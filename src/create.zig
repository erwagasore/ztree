const std = @import("std");
const node = @import("node.zig");

pub const Node    = node.Node;
pub const Element = node.Element;
pub const Attr    = node.Attr;

const Allocator = std.mem.Allocator;

// ── Leaf constructors (no allocation) ────────────────────────────────────────

/// Construct an Attr value. Useful when building a []const Attr slice at runtime.
/// Boolean attributes have a null value; presence in the slice is enough.
pub fn attr(key: []const u8, value: ?[]const u8) Attr {
    return .{ .key = key, .value = value };
}

/// Construct a text node. The renderer escapes its content.
pub fn text(content: []const u8) Node {
    return .{ .text = content };
}

/// Construct a raw node. The renderer passes content through as-is.
pub fn raw(content: []const u8) Node {
    return .{ .raw = content };
}

/// Empty node — an empty fragment. Useful as the else branch in conditionals.
pub fn none() Node {
    return .{ .fragment = &.{} };
}

// ── Element constructors (allocating) ────────────────────────────────────────

/// Build an element node.
///
/// `attrs` — accepts three forms:
///   **Struct literal** — field names become attribute keys.
///     Use @"name" for attribute names that are not valid Zig identifiers.
///     Use {} (void) or null for boolean attributes (rendered as key only).
///     Use if (cond) "value" else null for conditional attrs — null omits the attr.
///   **Tuple of Attr/?Attr** — for runtime keys or mixed static/dynamic attrs.
///     `.{ attr("href", url), if (ext) attr("target", "_blank") else null }`
///   **Slice** — `[]const Attr` or `[]const ?Attr` for fully dynamic attrs.
///
/// `children` — tuple literal whose items become child nodes.
///   Pass a []const Node slice when children are built in a loop.
///
///   try element(a, "a", .{ .class = "btn", .href = "/" }, .{ text("Home") })
///   try element(a, "div", .{ .@"hx-get" = url }, arena_kids)
///   try element(a, "input", .{ .type = "checkbox", .checked = {} }, .{})
///   try element(a, "li", .{ .@"aria-disabled" = if (off) "true" else null }, .{})
///   try element(a, "a", .{ attr("href", url), if (ext) attr("target", "_blank") else null }, .{})
///
pub fn element(a: Allocator, tag: []const u8, attrs: anytype, children: anytype) !Node {
    return .{ .element = .{
        .tag      = tag,
        .attrs    = try buildAttrs(a, attrs),
        .children = try buildChildren(a, children),
    } };
}

/// Build a void/self-closing element (no children).
///
///   try closedElement(a, "img", .{ .src = "/logo.png", .alt = "Logo" })
///   try closedElement(a, "br", .{})
///   try closedElement(a, "input", .{ .type = "text", .required = {} })
///
pub fn closedElement(a: Allocator, tag: []const u8, attrs: anytype) !Node {
    return .{ .element = .{
        .tag      = tag,
        .attrs    = try buildAttrs(a, attrs),
        .children = &.{},
        .closed   = true,
    } };
}

/// Build a fragment (children without a wrapping tag).
///
///   try fragment(a, .{ node1, node2, node3 })
///   try fragment(a, arena_slice)
///
pub fn fragment(a: Allocator, children: anytype) !Node {
    return .{ .fragment = try buildChildren(a, children) };
}

// ── Private builders ──────────────────────────────────────────────────────────

fn isOptionalAttrSlice(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer) return false;
    const child = info.pointer.child;
    if (child == ?Attr) return true; // []const ?Attr
    const ci = @typeInfo(child);
    return ci == .array and ci.array.child == ?Attr; // *const [N]?Attr
}

/// Convert attrs into a `[]const Attr` slice. Accepts:
///
///   - **Named struct literal** — field names become attr keys.
///     `.{ .class = "btn", .disabled = if (off) "true" else null }`
///
///   - **Tuple of `Attr` / `?Attr`** — each element is an attr value.
///     `.{ attr("class", "btn"), if (off) attr("disabled", null) else null }`
///
///   - **`[]const Attr`** — passthrough.
///
///   - **`[]const ?Attr`** — filters out nulls.
///
/// When optional values resolve to `null`, the allocated buffer may have
/// unused trailing capacity — harmless with arena allocators (recommended).
pub fn buildAttrs(a: Allocator, attrs: anytype) ![]const Attr {
    const T = @TypeOf(attrs);
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            if (s.fields.len == 0) return &.{};

            // Tuple of Attr/?Attr — collect values, skip nulls.
            // Bare null (@TypeOf(null)) is accepted for comptime-known
            // false conditions: `if (false) attr(...) else null`.
            if (s.is_tuple) {
                inline for (s.fields) |f| {
                    const valid = f.type == Attr or f.type == ?Attr or @typeInfo(f.type) == .null;
                    if (!valid) {
                        @compileError("tuple attrs must contain Attr or ?Attr values, got " ++ @typeName(f.type));
                    }
                }
                var count: usize = 0;
                inline for (s.fields) |f| {
                    const val = @field(attrs, f.name);
                    switch (@typeInfo(@TypeOf(val))) {
                        .null => {},
                        .optional => {
                            if (val != null) count += 1;
                        },
                        else => count += 1,
                    }
                }
                if (count == 0) return &.{};
                const buf = try a.alloc(Attr, count);
                var i: usize = 0;
                inline for (s.fields) |f| {
                    const val = @field(attrs, f.name);
                    switch (@typeInfo(@TypeOf(val))) {
                        .null => {},
                        .optional => {
                            if (val) |v| {
                                buf[i] = v;
                                i += 1;
                            }
                        },
                        else => {
                            buf[i] = val;
                            i += 1;
                        },
                    }
                }
                return buf;
            }

            // Named struct — field names become attr keys.
            const buf = try a.alloc(Attr, s.fields.len);
            var count: usize = 0;
            inline for (s.fields) |f| {
                const val = @field(attrs, f.name);
                switch (@typeInfo(@TypeOf(val))) {
                    .void, .null => {
                        buf[count] = .{ .key = f.name, .value = null };
                        count += 1;
                    },
                    .optional => {
                        if (val) |v| {
                            buf[count] = .{ .key = f.name, .value = @as([]const u8, v) };
                            count += 1;
                        }
                    },
                    else => {
                        buf[count] = .{ .key = f.name, .value = @as([]const u8, val) };
                        count += 1;
                    },
                }
            }
            return buf[0..count];
        },
        .pointer => {
            // []const ?Attr / *const [N]?Attr — skip nulls
            if (comptime isOptionalAttrSlice(T)) {
                const src: []const ?Attr = attrs;
                var count: usize = 0;
                for (src) |x| if (x != null) { count += 1; };
                if (count == 0) return &.{};
                const buf = try a.alloc(Attr, count);
                var i: usize = 0;
                for (src) |x| if (x) |v| { buf[i] = v; i += 1; };
                return buf;
            }
            return @as([]const Attr, attrs); // []const Attr / *const [N]Attr passthrough
        },
        else => @compileError("attrs must be an anonymous struct literal .{} or []const Attr"),
    }
}

fn buildChildren(a: Allocator, children: anytype) ![]const Node {
    const T = @TypeOf(children);
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            if (s.fields.len == 0) return &.{};
            const buf = try a.alloc(Node, s.fields.len);
            inline for (s.fields, 0..) |f, i| {
                buf[i] = @field(children, f.name);
            }
            return buf;
        },
        .pointer => return @as([]const Node, children), // []const Node / *const [N]Node passthrough
        else => @compileError("children must be a tuple literal .{} or []const Node"),
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

// -- text --

test "text stores content" {
    const n = text("hello");
    try testing.expectEqualStrings("hello", n.text);
}

test "text empty string" {
    try testing.expectEqualStrings("", text("").text);
}

// -- raw --

test "raw stores content" {
    try testing.expectEqualStrings("<br/>", raw("<br/>").raw);
}

// -- none --

test "none returns empty fragment" {
    const n = none();
    try testing.expectEqual(.fragment, std.meta.activeTag(n));
    try testing.expectEqual(0, n.fragment.len);
}

// -- closedElement --

test "closedElement no attrs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n = try closedElement(a, "br", .{});
    try testing.expectEqualStrings("br", n.element.tag);
    try testing.expectEqual(0, n.element.attrs.len);
    try testing.expectEqual(0, n.element.children.len);
}

test "closedElement with attrs struct" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n = try closedElement(a, "img", .{ .src = "photo.jpg", .alt = "photo" });
    try testing.expectEqualStrings("img", n.element.tag);
    try testing.expectEqual(2, n.element.attrs.len);
    try testing.expectEqualStrings("src",       n.element.attrs[0].key);
    try testing.expectEqualStrings("photo.jpg", n.element.attrs[0].value.?);
    try testing.expectEqualStrings("alt",       n.element.attrs[1].key);
    try testing.expectEqualStrings("photo",     n.element.attrs[1].value.?);
    try testing.expectEqual(0, n.element.children.len);
}

test "closedElement boolean attr with void" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const n = try closedElement(arena.allocator(), "input", .{ .type = "checkbox", .checked = {} });
    try testing.expectEqual(2, n.element.attrs.len);
    try testing.expectEqualStrings("checked", n.element.attrs[1].key);
    try testing.expectEqual(null, n.element.attrs[1].value);
}

test "closedElement boolean attr with null" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const n = try closedElement(arena.allocator(), "input", .{ .disabled = null });
    try testing.expectEqualStrings("disabled", n.element.attrs[0].key);
    try testing.expectEqual(null, n.element.attrs[0].value);
}

// -- element --

test "element empty attrs and children" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const n = try element(arena.allocator(), "div", .{}, .{});
    try testing.expectEqualStrings("div", n.element.tag);
    try testing.expectEqual(0, n.element.attrs.len);
    try testing.expectEqual(0, n.element.children.len);
}

test "element with attrs struct and children tuple" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n = try element(a, "a", .{ .class = "btn", .href = "/" }, .{ text("Home") });
    try testing.expectEqualStrings("a", n.element.tag);
    try testing.expectEqual(2, n.element.attrs.len);
    try testing.expectEqualStrings("class", n.element.attrs[0].key);
    try testing.expectEqualStrings("btn",   n.element.attrs[0].value.?);
    try testing.expectEqualStrings("href",  n.element.attrs[1].key);
    try testing.expectEqualStrings("/",     n.element.attrs[1].value.?);
    try testing.expectEqual(1, n.element.children.len);
    try testing.expectEqualStrings("Home", n.element.children[0].text);
}

test "element non-identifier attr name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const n = try element(arena.allocator(), "div", .{ .@"hx-get" = "/api", .@"aria-label" = "region" }, .{});
    try testing.expectEqualStrings("hx-get",    n.element.attrs[0].key);
    try testing.expectEqualStrings("aria-label", n.element.attrs[1].key);
}

test "element with []const Attr passthrough" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const my_attrs = try a.alloc(Attr, 1);
    my_attrs[0] = .{ .key = "id", .value = "root" };
    const n = try element(a, "div", my_attrs, .{});
    try testing.expectEqual(1, n.element.attrs.len);
    try testing.expectEqualStrings("id", n.element.attrs[0].key);
}

test "element with []const Node passthrough" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const items = try a.alloc(Node, 2);
    items[0] = text("a");
    items[1] = text("b");
    const n = try element(a, "ul", .{}, items);
    try testing.expectEqual(2, n.element.children.len);
    try testing.expectEqualStrings("a", n.element.children[0].text);
}

// -- fragment --

test "fragment from tuple" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const n = try fragment(arena.allocator(), .{ text("a"), text("b") });
    try testing.expectEqual(.fragment, std.meta.activeTag(n));
    try testing.expectEqual(2, n.fragment.len);
    try testing.expectEqualStrings("a", n.fragment[0].text);
}

test "fragment from slice" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const nodes = try a.alloc(Node, 3);
    nodes[0] = text("x");
    nodes[1] = text("y");
    nodes[2] = text("z");
    const n = try fragment(a, nodes);
    try testing.expectEqual(3, n.fragment.len);
}

test "fragment empty" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const n = try fragment(arena.allocator(), .{});
    try testing.expectEqual(0, n.fragment.len);
}

// -- optional struct attr values --

test "struct attr with optional value includes when non-null" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const n = try buildWithCond(arena.allocator(), true);
    try testing.expectEqual(2, n.element.attrs.len);
    try testing.expectEqualStrings("class", n.element.attrs[0].key);
    try testing.expectEqualStrings("aria-disabled", n.element.attrs[1].key);
    try testing.expectEqualStrings("true", n.element.attrs[1].value.?);
}

test "struct attr with optional value omits when null" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const n = try buildWithCond(arena.allocator(), false);
    try testing.expectEqual(1, n.element.attrs.len);
    try testing.expectEqualStrings("class", n.element.attrs[0].key);
}

/// Helper — keeps the condition runtime so Zig infers ?[]const u8, not @TypeOf(null).
fn buildWithCond(a: std.mem.Allocator, cond: bool) !Node {
    return element(a, "div", .{
        .class = "card",
        .@"aria-disabled" = if (cond) "true" else null,
    }, .{});
}

test "boolean attr still works with void and null" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const n = try closedElement(arena.allocator(), "input", .{
        .type = "checkbox",
        .checked = {},
        .disabled = null,
    });
    try testing.expectEqual(3, n.element.attrs.len);
    try testing.expectEqual(null, n.element.attrs[1].value);
    try testing.expectEqual(null, n.element.attrs[2].value);
}

// -- conditional ?Attr via if/else --

test "element with []const ?Attr skips nulls" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const checked = true;
    const disabled = false;
    const n = try closedElement(a, "input", &[_]?Attr{
        attr("type", "checkbox"),
        if (checked) attr("checked", null) else null,
        if (disabled) attr("disabled", null) else null,
    });
    try testing.expectEqual(2, n.element.attrs.len);
    try testing.expectEqualStrings("type",    n.element.attrs[0].key);
    try testing.expectEqualStrings("checked", n.element.attrs[1].key);
}

// -- tuple attrs --

test "tuple of Attr values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const n = try element(arena.allocator(), "a", .{
        attr("class", "btn"),
        attr("href", "/"),
    }, .{text("Home")});
    try testing.expectEqual(2, n.element.attrs.len);
    try testing.expectEqualStrings("class", n.element.attrs[0].key);
    try testing.expectEqualStrings("btn", n.element.attrs[0].value.?);
    try testing.expectEqualStrings("href", n.element.attrs[1].key);
    try testing.expectEqualStrings("/", n.element.attrs[1].value.?);
}

test "tuple of ?Attr skips nulls" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const checked = true;
    const disabled = false;
    const n = try closedElement(arena.allocator(), "input", .{
        attr("type", "checkbox"),
        if (checked) attr("checked", null) else null,
        if (disabled) attr("disabled", null) else null,
    });
    try testing.expectEqual(2, n.element.attrs.len);
    try testing.expectEqualStrings("type", n.element.attrs[0].key);
    try testing.expectEqualStrings("checked", n.element.attrs[1].key);
    try testing.expectEqual(null, n.element.attrs[1].value);
}

test "tuple with all nulls returns empty" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const show = false;
    const n = try element(arena.allocator(), "div", .{
        if (show) attr("class", "visible") else null,
    }, .{});
    try testing.expectEqual(0, n.element.attrs.len);
}

test "tuple with boolean attr" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const n = try closedElement(arena.allocator(), "input", .{
        attr("type", "text"),
        attr("required", null),
    });
    try testing.expectEqual(2, n.element.attrs.len);
    try testing.expectEqualStrings("required", n.element.attrs[1].key);
    try testing.expectEqual(null, n.element.attrs[1].value);
}

test "tuple with runtime key" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const key: []const u8 = "data-id";
    const val: []const u8 = "42";
    const n = try element(arena.allocator(), "div", .{
        attr("class", "item"),
        attr(key, val),
    }, .{});
    try testing.expectEqual(2, n.element.attrs.len);
    try testing.expectEqualStrings("data-id", n.element.attrs[1].key);
    try testing.expectEqualStrings("42", n.element.attrs[1].value.?);
}

test "tuple attrs work with TreeBuilder" {
    const tree_builder = @import("tree_builder.zig");
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = tree_builder.TreeBuilder.init(arena.allocator());

    const active = true;
    try b.open("div", .{
        attr("class", "card"),
        if (active) attr("data-active", "true") else null,
    });
    try b.close();

    const n = try b.finish();
    try testing.expectEqual(2, n.element.attrs.len);
    try testing.expectEqualStrings("class", n.element.attrs[0].key);
    try testing.expectEqualStrings("data-active", n.element.attrs[1].key);
}

// -- nested elements --

test "nested elements returned from a function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const section = try buildCard(a, "Alice", "/users/alice");
    try testing.expectEqualStrings("article", section.element.tag);
    const link = section.element.children[0];
    try testing.expectEqualStrings("a", link.element.tag);
    try testing.expectEqualStrings("/users/alice", link.element.attrs[0].value.?);
    try testing.expectEqualStrings("Alice", link.element.children[0].text);
}

fn buildCard(a: Allocator, name: []const u8, href: []const u8) !Node {
    return element(a, "article", .{ .class = "card" }, .{
        try element(a, "a", .{ .href = href }, .{ text(name) }),
    });
}

// -- dynamic children --

test "loop-built children via slice passthrough" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const data = [_][]const u8{ "one", "two", "three" };
    const items = try a.alloc(Node, data.len);
    for (data, 0..) |item, i| {
        items[i] = try element(a, "li", .{}, .{ text(item) });
    }

    const list = try element(a, "ul", .{ .class = "list" }, items);
    try testing.expectEqual(3, list.element.children.len);
    try testing.expectEqualStrings("one", list.element.children[0].element.children[0].text);
}

// -- comptime: leaf constructors only --

test "leaf constructors work at comptime" {
    comptime {
        const t = text("ct");
        if (!std.mem.eql(u8, t.text, "ct")) @compileError("text failed");

        const r = raw("<b>");
        if (!std.mem.eql(u8, r.raw, "<b>")) @compileError("raw failed");

        const n = none();
        if (n.fragment.len != 0) @compileError("none failed");
    }
}

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
/// `attrs` — anonymous struct literal whose field names become attribute keys.
///   Use @"name" for attribute names that are not valid Zig identifiers.
///   Use {} (void) or null for boolean attributes (rendered as key only).
///   Pass a []const Attr slice when attrs are built at runtime.
///
/// `children` — tuple literal whose items become child nodes.
///   Pass a []const Node slice when children are built in a loop.
///
///   try element(a, "a", .{ .class = "btn", .href = "/" }, .{ text("Home") })
///   try element(a, "div", .{ .@"hx-get" = url }, arena_kids)
///   try element(a, "input", .{ .type = "checkbox", .checked = {} }, .{})
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

fn buildAttrs(a: Allocator, attrs: anytype) ![]const Attr {
    const T = @TypeOf(attrs);
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            if (s.fields.len == 0) return &.{};
            const buf = try a.alloc(Attr, s.fields.len);
            inline for (s.fields, 0..) |f, i| {
                const val = @field(attrs, f.name);
                buf[i] = .{
                    .key   = f.name,
                    .value = switch (@typeInfo(@TypeOf(val))) {
                        .void, .null => null,
                        else         => @as([]const u8, val),
                    },
                };
            }
            return buf;
        },
        .pointer => return @as([]const Attr, attrs), // []const Attr / *const [N]Attr passthrough
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

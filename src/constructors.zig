const std = @import("std");
const Allocator = std.mem.Allocator;
const node = @import("node.zig");
pub const Node = node.Node;
pub const Element = node.Element;
pub const Attr = node.Attr;

/// Construct a text node. The renderer is responsible for escaping its content.
pub fn text(content: []const u8) Node {
    return .{ .text = content };
}

/// Construct a raw node. The renderer passes its content through as-is.
pub fn raw(content: []const u8) Node {
    return .{ .raw = content };
}

/// Construct an element with no children. Uses an empty static slice — no allocation.
pub fn elementVoid(tag: []const u8, attrs: []const Attr) Node {
    return .{ .element = .{
        .tag = tag,
        .attrs = attrs,
        .children = &.{},
    } };
}

/// Convenience for constructing an Attr. A null value represents a boolean attribute.
pub fn attr(key: []const u8, value: ?[]const u8) Attr {
    return .{ .key = key, .value = value };
}

/// Empty node. Returns an empty fragment. Useful as the `else` branch in conditionals.
pub fn none() Node {
    return .{ .fragment = &.{} };
}

/// Construct an element node with children.
///
/// `children` accepts a tuple of `Node` values or a `[]const Node` slice.
/// At comptime the tuple becomes a static array (allocator is unused).
/// At runtime the tuple is copied into an arena-allocated slice.
pub fn element(allocator: Allocator, tag: []const u8, attrs: []const Attr, children: anytype) !Node {
    const child_slice = try resolveChildren(allocator, children);
    return .{ .element = .{
        .tag = tag,
        .attrs = attrs,
        .children = child_slice,
    } };
}

/// Construct a fragment node (children without a wrapping tag).
///
/// `children` accepts a tuple of `Node` values or a `[]const Node` slice.
/// At comptime the tuple becomes a static array (allocator is unused).
/// At runtime the tuple is copied into an arena-allocated slice.
pub fn fragment(allocator: Allocator, children: anytype) !Node {
    const child_slice = try resolveChildren(allocator, children);
    return .{ .fragment = child_slice };
}

/// Resolve a children parameter (tuple or slice) into a `[]const Node`.
fn resolveChildren(allocator: Allocator, children: anytype) ![]const Node {
    const T = @TypeOf(children);

    // Already a slice — use as-is (caller owns the memory).
    if (T == []const Node) return children;

    const info = @typeInfo(T);
    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError("children must be a tuple of Node values or a []const Node slice");
    }

    const N = info.@"struct".fields.len;
    if (N == 0) return &.{};

    if (@inComptime()) {
        // Comptime: create a static array. Lives in the binary's constant data.
        const arr: [N]Node = children;
        return &arr;
    } else {
        // Runtime: copy into arena-allocated memory.
        const slice = try allocator.alloc(Node, N);
        inline for (0..N) |i| {
            slice[i] = children[i];
        }
        return slice;
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

// -- text --

test "text stores content correctly" {
    const n = text("hello");
    try testing.expectEqualStrings("hello", n.text);
}

test "text with empty string" {
    const n = text("");
    try testing.expectEqualStrings("", n.text);
}

// -- raw --

test "raw stores content correctly" {
    const n = raw("<br/>");
    try testing.expectEqualStrings("<br/>", n.raw);
}

test "raw with empty string" {
    const n = raw("");
    try testing.expectEqualStrings("", n.raw);
}

// -- attr --

test "attr with string value" {
    const a = attr("class", "main");
    try testing.expectEqualStrings("class", a.key);
    try testing.expectEqualStrings("main", a.value.?);
}

test "attr with null value (boolean attribute)" {
    const a = attr("disabled", null);
    try testing.expectEqualStrings("disabled", a.key);
    try testing.expectEqual(null, a.value);
}

// -- none --

test "none returns empty fragment" {
    const n = none();
    try testing.expectEqual(.fragment, std.meta.activeTag(n));
    try testing.expectEqual(0, n.fragment.len);
}

// -- elementVoid --

test "elementVoid has zero children" {
    const n = elementVoid("br", &.{});
    try testing.expectEqualStrings("br", n.element.tag);
    try testing.expectEqual(0, n.element.children.len);
    try testing.expectEqual(0, n.element.attrs.len);
}

test "elementVoid with attrs" {
    const attrs = [_]Attr{attr("src", "img.png")};
    const n = elementVoid("img", &attrs);
    try testing.expectEqualStrings("img", n.element.tag);
    try testing.expectEqual(1, n.element.attrs.len);
    try testing.expectEqual(0, n.element.children.len);
}

// -- element (runtime with arena) --

test "element with tag, attrs, and children" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n = try element(a, "div", &.{attr("id", "main")}, .{
        text("hello"),
    });
    try testing.expectEqualStrings("div", n.element.tag);
    try testing.expectEqual(1, n.element.attrs.len);
    try testing.expectEqualStrings("id", n.element.attrs[0].key);
    try testing.expectEqual(1, n.element.children.len);
    try testing.expectEqualStrings("hello", n.element.children[0].text);
}

test "element with no attrs (empty slice)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n = try element(a, "p", &.{}, .{text("content")});
    try testing.expectEqual(0, n.element.attrs.len);
    try testing.expectEqual(1, n.element.children.len);
}

test "element with no children (empty tuple)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n = try element(a, "div", &.{}, .{});
    try testing.expectEqual(0, n.element.children.len);
}

test "element with slice children" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const kids = [_]Node{ text("a"), text("b") };
    const n = try element(a, "ul", &.{}, @as([]const Node, &kids));
    try testing.expectEqual(2, n.element.children.len);
    try testing.expectEqualStrings("a", n.element.children[0].text);
    try testing.expectEqualStrings("b", n.element.children[1].text);
}

// -- fragment (runtime with arena) --

test "fragment with tuple of nodes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n = try fragment(a, .{ text("a"), text("b"), text("c") });
    try testing.expectEqual(.fragment, std.meta.activeTag(n));
    try testing.expectEqual(3, n.fragment.len);
    try testing.expectEqualStrings("b", n.fragment[1].text);
}

test "fragment with empty tuple" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n = try fragment(a, .{});
    try testing.expectEqual(0, n.fragment.len);
}

// -- nested elements (3+ levels deep) --

test "nested elements 3 levels deep" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const tree = try element(a, "html", &.{}, .{
        try element(a, "body", &.{}, .{
            try element(a, "div", &.{}, .{
                text("deep"),
            }),
        }),
    });

    const body = tree.element.children[0];
    try testing.expectEqualStrings("body", body.element.tag);
    const div = body.element.children[0];
    try testing.expectEqualStrings("div", div.element.tag);
    try testing.expectEqualStrings("deep", div.element.children[0].text);
}

// -- mixed node types --

test "mixed node types in one element" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const tree = try element(a, "div", &.{}, .{
        text("escaped text"),
        raw("<hr/>"),
        try fragment(a, .{text("in fragment")}),
        try element(a, "span", &.{}, .{text("child")}),
        elementVoid("br", &.{}),
    });

    try testing.expectEqual(5, tree.element.children.len);
    try testing.expectEqual(.text, std.meta.activeTag(tree.element.children[0]));
    try testing.expectEqual(.raw, std.meta.activeTag(tree.element.children[1]));
    try testing.expectEqual(.fragment, std.meta.activeTag(tree.element.children[2]));
    try testing.expectEqual(.element, std.meta.activeTag(tree.element.children[3]));
    try testing.expectEqual(.element, std.meta.activeTag(tree.element.children[4]));
}

// -- comptime: all non-allocating functions --

test "all non-allocating functions work at comptime" {
    comptime {
        const t = text("ct");
        if (!std.mem.eql(u8, t.text, "ct")) @compileError("text failed");

        const r = raw("<b>");
        if (!std.mem.eql(u8, r.raw, "<b>")) @compileError("raw failed");

        const a = attr("k", "v");
        if (!std.mem.eql(u8, a.key, "k")) @compileError("attr key failed");

        const n = none();
        if (n.fragment.len != 0) @compileError("none failed");

        const v = elementVoid("br", &.{});
        if (!std.mem.eql(u8, v.element.tag, "br")) @compileError("elementVoid failed");
    }
}

// -- comptime: element() and fragment() with undefined allocator --

test "element works at comptime with undefined allocator" {
    comptime {
        const tree = comptimeElementHelper() catch unreachable;
        if (!std.mem.eql(u8, tree.element.tag, "div")) @compileError("tag mismatch");
        if (tree.element.children.len != 2) @compileError("children count mismatch");
        if (!std.mem.eql(u8, tree.element.children[0].text, "hello")) @compileError("child 0 mismatch");
        if (!std.mem.eql(u8, tree.element.children[1].element.tag, "span")) @compileError("child 1 tag mismatch");
    }
}

fn comptimeElementHelper() !Node {
    return element(undefined, "div", &.{}, .{
        text("hello"),
        try element(undefined, "span", &.{}, .{
            text("world"),
        }),
    });
}

test "fragment works at comptime with undefined allocator" {
    comptime {
        const f = fragment(undefined, .{
            text("a"),
            text("b"),
        }) catch unreachable;
        if (f.fragment.len != 2) @compileError("fragment children count mismatch");
    }
}

// -- runtime: children survive return (no dangling pointers) --

fn buildComponent(allocator: Allocator) !Node {
    return element(allocator, "section", &.{}, .{
        text("line 1"),
        try element(allocator, "p", &.{}, .{
            text("line 2"),
        }),
    });
}

test "component function returning !Node at runtime — children survive return" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const section = try buildComponent(arena.allocator());
    try testing.expectEqualStrings("section", section.element.tag);
    try testing.expectEqual(2, section.element.children.len);
    try testing.expectEqualStrings("line 1", section.element.children[0].text);
    try testing.expectEqualStrings("p", section.element.children[1].element.tag);
    try testing.expectEqualStrings("line 2", section.element.children[1].element.children[0].text);
}

fn buildDeep(allocator: Allocator) !Node {
    return element(allocator, "l1", &.{}, .{
        try element(allocator, "l2", &.{}, .{
            try element(allocator, "l3", &.{}, .{
                text("leaf"),
            }),
        }),
    });
}

test "element works at runtime with arena — no dangling pointers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try buildDeep(arena.allocator());
    try testing.expectEqualStrings("l1", tree.element.tag);
    try testing.expectEqualStrings("l2", tree.element.children[0].element.tag);
    try testing.expectEqualStrings("l3", tree.element.children[0].element.children[0].element.tag);
    try testing.expectEqualStrings("leaf", tree.element.children[0].element.children[0].element.children[0].text);
}

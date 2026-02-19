const std = @import("std");
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

/// Construct a closed element with no children. Uses an empty static slice — no allocation.
pub fn closedElement(tag: []const u8, attrs: []const Attr) Node {
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
pub fn element(tag: []const u8, attrs: []const Attr, children: []const Node) Node {
    return .{ .element = .{
        .tag = tag,
        .attrs = attrs,
        .children = children,
    } };
}

/// Construct a fragment node (children without a wrapping tag).
pub fn fragment(children: []const Node) Node {
    return .{ .fragment = children };
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

// -- closedElement --

test "closedElement has zero children" {
    const n = closedElement("br", &.{});
    try testing.expectEqualStrings("br", n.element.tag);
    try testing.expectEqual(0, n.element.children.len);
    try testing.expectEqual(0, n.element.attrs.len);
}

test "closedElement with attrs" {
    const attrs = [_]Attr{attr("src", "img.png")};
    const n = closedElement("img", &attrs);
    try testing.expectEqualStrings("img", n.element.tag);
    try testing.expectEqual(1, n.element.attrs.len);
    try testing.expectEqual(0, n.element.children.len);
}

// -- element --

test "element with tag, attrs, and children" {
    const n = element("div", &.{attr("id", "main")}, &.{
        text("hello"),
    });
    try testing.expectEqualStrings("div", n.element.tag);
    try testing.expectEqual(1, n.element.attrs.len);
    try testing.expectEqualStrings("id", n.element.attrs[0].key);
    try testing.expectEqual(1, n.element.children.len);
    try testing.expectEqualStrings("hello", n.element.children[0].text);
}

test "element with no attrs (empty slice)" {
    const n = element("p", &.{}, &.{text("content")});
    try testing.expectEqual(0, n.element.attrs.len);
    try testing.expectEqual(1, n.element.children.len);
}

test "element with no children (empty slice)" {
    const n = element("div", &.{}, &.{});
    try testing.expectEqual(0, n.element.children.len);
}

test "element with slice children" {
    const kids = [_]Node{ text("a"), text("b") };
    const n = element("ul", &.{}, &kids);
    try testing.expectEqual(2, n.element.children.len);
    try testing.expectEqualStrings("a", n.element.children[0].text);
    try testing.expectEqualStrings("b", n.element.children[1].text);
}

// -- fragment --

test "fragment with nodes" {
    const n = fragment(&.{ text("a"), text("b"), text("c") });
    try testing.expectEqual(.fragment, std.meta.activeTag(n));
    try testing.expectEqual(3, n.fragment.len);
    try testing.expectEqualStrings("b", n.fragment[1].text);
}

test "fragment with empty slice" {
    const n = fragment(&.{});
    try testing.expectEqual(0, n.fragment.len);
}

// -- nested elements (3+ levels deep) --

test "nested elements 3 levels deep" {
    const tree = element("html", &.{}, &.{
        element("body", &.{}, &.{
            element("div", &.{}, &.{
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
    const tree = element("div", &.{}, &.{
        text("escaped text"),
        raw("<hr/>"),
        fragment(&.{text("in fragment")}),
        element("span", &.{}, &.{text("child")}),
        closedElement("br", &.{}),
    });

    try testing.expectEqual(5, tree.element.children.len);
    try testing.expectEqual(.text, std.meta.activeTag(tree.element.children[0]));
    try testing.expectEqual(.raw, std.meta.activeTag(tree.element.children[1]));
    try testing.expectEqual(.fragment, std.meta.activeTag(tree.element.children[2]));
    try testing.expectEqual(.element, std.meta.activeTag(tree.element.children[3]));
    try testing.expectEqual(.element, std.meta.activeTag(tree.element.children[4]));
}

// -- comptime: all functions work at comptime --

test "all functions work at comptime" {
    comptime {
        const t = text("ct");
        if (!std.mem.eql(u8, t.text, "ct")) @compileError("text failed");

        const r = raw("<b>");
        if (!std.mem.eql(u8, r.raw, "<b>")) @compileError("raw failed");

        const a = attr("k", "v");
        if (!std.mem.eql(u8, a.key, "k")) @compileError("attr key failed");

        const n = none();
        if (n.fragment.len != 0) @compileError("none failed");

        const v = closedElement("br", &.{});
        if (!std.mem.eql(u8, v.element.tag, "br")) @compileError("closedElement failed");

        const e = element("div", &.{}, &.{text("hello")});
        if (!std.mem.eql(u8, e.element.tag, "div")) @compileError("element failed");
        if (e.element.children.len != 1) @compileError("element children count");

        const f = fragment(&.{ text("a"), text("b") });
        if (f.fragment.len != 2) @compileError("fragment children count");
    }
}

test "nested tree at comptime" {
    comptime {
        const tree = element("div", &.{}, &.{
            text("hello"),
            element("span", &.{}, &.{
                text("world"),
            }),
        });
        if (!std.mem.eql(u8, tree.element.tag, "div")) @compileError("tag mismatch");
        if (tree.element.children.len != 2) @compileError("children count mismatch");
        if (!std.mem.eql(u8, tree.element.children[0].text, "hello")) @compileError("child 0 mismatch");
        if (!std.mem.eql(u8, tree.element.children[1].element.tag, "span")) @compileError("child 1 tag mismatch");
    }
}

// -- dynamic children with allocator --

test "dynamic children with arena allocator" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const data = [_][]const u8{ "one", "two", "three" };
    const items = try a.alloc(Node, data.len);
    for (data, 0..) |item, i| {
        const li_kids = try a.alloc(Node, 1);
        li_kids[0] = text(item);
        items[i] = element("li", &.{}, li_kids);
    }
    const list = element("ul", &.{}, items);

    try testing.expectEqualStrings("ul", list.element.tag);
    try testing.expectEqual(3, list.element.children.len);
    try testing.expectEqualStrings("li", list.element.children[0].element.tag);
    try testing.expectEqualStrings("one", list.element.children[0].element.children[0].text);
    try testing.expectEqualStrings("three", list.element.children[2].element.children[0].text);
}

// -- component function with dynamic children --

fn buildComponent(a: std.mem.Allocator) !Node {
    const p_kids = try a.alloc(Node, 1);
    p_kids[0] = text("line 2");
    const kids = try a.alloc(Node, 2);
    kids[0] = text("line 1");
    kids[1] = element("p", &.{}, p_kids);
    return element("section", &.{}, kids);
}

test "component function returning Node — children survive return" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const section = try buildComponent(arena.allocator());
    try testing.expectEqualStrings("section", section.element.tag);
    try testing.expectEqual(2, section.element.children.len);
    try testing.expectEqualStrings("line 1", section.element.children[0].text);
    try testing.expectEqualStrings("p", section.element.children[1].element.tag);
    try testing.expectEqualStrings("line 2", section.element.children[1].element.children[0].text);
}

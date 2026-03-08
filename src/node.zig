const std = @import("std");

pub const Attr = struct {
    key: []const u8,
    value: ?[]const u8, // null = boolean attribute (key only, no value)
};

pub const Element = struct {
    tag: []const u8,
    attrs: []const Attr,
    children: []const Node,
    /// True for void/self-closing elements created via `closedElement()`.
    /// When true, `renderWalk` calls `elementOpen` only — no children, no `elementClose`.
    closed: bool = false,

    /// Look up an attribute value by key. Returns the value if found,
    /// `null` if not present or if the attribute is boolean (has no value).
    pub fn getAttr(self: Element, key: []const u8) ?[]const u8 {
        for (self.attrs) |a| {
            if (std.mem.eql(u8, a.key, key)) return a.value;
        }
        return null;
    }

    /// Check whether an attribute is present (with or without a value).
    pub fn hasAttr(self: Element, key: []const u8) bool {
        for (self.attrs) |a| {
            if (std.mem.eql(u8, a.key, key)) return true;
        }
        return false;
    }
};

pub const Node = union(enum) {
    element: Element,
    text: []const u8, // content to be escaped by renderer
    raw: []const u8, // content passed through as-is
    fragment: []const Node, // children without a wrapping tag
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "Node.text holds content" {
    const n: Node = .{ .text = "hello" };
    try testing.expectEqualStrings("hello", n.text);
}

test "Node.raw holds content" {
    const n: Node = .{ .raw = "<br>" };
    try testing.expectEqualStrings("<br>", n.raw);
}

test "Node.element holds tag, attrs, and children" {
    const attrs = [_]Attr{.{ .key = "id", .value = "main" }};
    const children = [_]Node{.{ .text = "hi" }};
    const n: Node = .{ .element = .{
        .tag = "div",
        .attrs = &attrs,
        .children = &children,
    } };
    try testing.expectEqualStrings("div", n.element.tag);
    try testing.expectEqual(1, n.element.attrs.len);
    try testing.expectEqualStrings("id", n.element.attrs[0].key);
    try testing.expectEqual(1, n.element.children.len);
    try testing.expectEqualStrings("hi", n.element.children[0].text);
}

test "Node.fragment holds children" {
    const children = [_]Node{ .{ .text = "a" }, .{ .text = "b" } };
    const n: Node = .{ .fragment = &children };
    try testing.expectEqual(2, n.fragment.len);
    try testing.expectEqualStrings("a", n.fragment[0].text);
    try testing.expectEqualStrings("b", n.fragment[1].text);
}

test "Attr with null value is boolean attribute" {
    const a: Attr = .{ .key = "disabled", .value = null };
    try testing.expectEqualStrings("disabled", a.key);
    try testing.expectEqual(null, a.value);
}

test "Attr with string value" {
    const a: Attr = .{ .key = "class", .value = "container" };
    try testing.expectEqualStrings("class", a.key);
    try testing.expectEqualStrings("container", a.value.?);
}

test "Element.getAttr returns value for matching key" {
    const attrs = [_]Attr{
        .{ .key = "class", .value = "card" },
        .{ .key = "id", .value = "main" },
    };
    const el: Element = .{ .tag = "div", .attrs = &attrs, .children = &.{} };
    try testing.expectEqualStrings("card", el.getAttr("class").?);
    try testing.expectEqualStrings("main", el.getAttr("id").?);
}

test "Element.getAttr returns null for missing key" {
    const attrs = [_]Attr{.{ .key = "class", .value = "card" }};
    const el: Element = .{ .tag = "div", .attrs = &attrs, .children = &.{} };
    try testing.expectEqual(null, el.getAttr("id"));
}

test "Element.getAttr returns null for boolean attr" {
    const attrs = [_]Attr{.{ .key = "disabled", .value = null }};
    const el: Element = .{ .tag = "input", .attrs = &attrs, .children = &.{} };
    // Boolean attr has no value — getAttr returns null
    try testing.expectEqual(null, el.getAttr("disabled"));
}

test "Element.hasAttr finds value attr" {
    const attrs = [_]Attr{.{ .key = "href", .value = "/home" }};
    const el: Element = .{ .tag = "a", .attrs = &attrs, .children = &.{} };
    try testing.expect(el.hasAttr("href"));
    try testing.expect(!el.hasAttr("class"));
}

test "Element.hasAttr finds boolean attr" {
    const attrs = [_]Attr{.{ .key = "checked", .value = null }};
    const el: Element = .{ .tag = "input", .attrs = &attrs, .children = &.{} };
    // hasAttr returns true even for boolean attrs (where getAttr returns null)
    try testing.expect(el.hasAttr("checked"));
}

test "Element.getAttr and hasAttr on empty attrs" {
    const el: Element = .{ .tag = "br", .attrs = &.{}, .children = &.{} };
    try testing.expectEqual(null, el.getAttr("anything"));
    try testing.expect(!el.hasAttr("anything"));
}

test "Node union enum tag switching" {
    const nodes = [_]Node{
        .{ .text = "t" },
        .{ .raw = "r" },
        .{ .element = .{ .tag = "e", .attrs = &.{}, .children = &.{} } },
        .{ .fragment = &.{} },
    };

    try testing.expectEqual(.text, std.meta.activeTag(nodes[0]));
    try testing.expectEqual(.raw, std.meta.activeTag(nodes[1]));
    try testing.expectEqual(.element, std.meta.activeTag(nodes[2]));
    try testing.expectEqual(.fragment, std.meta.activeTag(nodes[3]));
}

const std = @import("std");
const node = @import("node.zig");

const Node = node.Node;
const Element = node.Element;

/// Returned by `elementOpen` to control tree traversal.
///
/// - `.@"continue"` — `renderWalk` recurses into children, then calls `elementClose`.
/// - `.skip_children` — `renderWalk` skips children and `elementClose`. The renderer
///   handled this element completely in `elementOpen`.
///
/// Closed elements (`el.closed == true`) always skip children and `elementClose`,
/// regardless of the returned action.
pub const WalkAction = enum { @"continue", skip_children };

/// Walk a node tree, dispatching to `renderer` callbacks.
///
/// The renderer must be a pointer to a struct with these methods:
///
///   fn elementOpen(self, el: Element) !WalkAction
///   fn elementClose(self, el: Element) !void
///   fn onText(self, content: []const u8) !void
///   fn onRaw(self, content: []const u8) !void
///
/// Fragment nodes are transparent — `renderWalk` recurses into their
/// children without calling any callback.
///
/// Closed elements (`el.closed == true`, created via `closedElement`) receive
/// only an `elementOpen` call — children are skipped and `elementClose` is
/// not called. Renderers can inspect `el.closed` to choose self-closing syntax.
///
/// When `elementOpen` returns `.skip_children`, `renderWalk` skips children and
/// does not call `elementClose`. This lets renderers handle complex elements
/// (tables, code blocks) entirely within `elementOpen` — extracting children
/// directly from the `Element` — while still getting free traversal for
/// simple wrapper elements that return `.@"continue"`.
///
/// Note: traversal is recursive. Extremely deep trees (thousands of levels)
/// may overflow the call stack.
///
/// Example:
///
///   var r = MyHtmlRenderer.init(allocator);
///   try renderWalk(&r, tree);
///
pub fn renderWalk(renderer: anytype, n: Node) @TypeOf(callRenderer(renderer, n)) {
    const R = @TypeOf(renderer);
    const info = @typeInfo(R);
    if (info != .pointer or info.pointer.size != .one) {
        @compileError("renderWalk expects a pointer to a renderer struct, got " ++ @typeName(R));
    }
    return callRenderer(renderer, n);
}

fn callRenderer(renderer: anytype, n: Node) !void {
    switch (n) {
        .text => |s| try renderer.onText(s),
        .raw => |s| try renderer.onRaw(s),
        .fragment => |children| {
            for (children) |child| try callRenderer(renderer, child);
        },
        .element => |el| {
            const action = try renderer.elementOpen(el);
            if (!el.closed and action == .@"continue") {
                for (el.children) |child| try callRenderer(renderer, child);
                try renderer.elementClose(el);
            }
        },
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

const testing = std.testing;
const Allocator = std.mem.Allocator;
const create = @import("create.zig");
const element = create.element;
const closedElement = create.closedElement;
const fragment = create.fragment;
const text = create.text;
const raw = create.raw;
const none = create.none;
const TraceRenderer = @import("test_util.zig").TraceRenderer;

/// Test renderer that returns `.skip_children` for a specific tag.
/// Used to verify that `renderWalk` respects `WalkAction.skip_children`.
const SkipRenderer = struct {
    buf: std.ArrayList(u8),
    gpa: Allocator,
    skip_tag: []const u8,

    fn init(gpa: Allocator, skip_tag: []const u8) SkipRenderer {
        return .{ .buf = .empty, .gpa = gpa, .skip_tag = skip_tag };
    }

    fn deinit(self: *SkipRenderer) void {
        self.buf.deinit(self.gpa);
    }

    fn result(self: *SkipRenderer) []const u8 {
        return self.buf.items;
    }

    fn append(self: *SkipRenderer, s: []const u8) !void {
        try self.buf.appendSlice(self.gpa, s);
    }

    pub fn elementOpen(self: *SkipRenderer, el: Element) !WalkAction {
        try self.append("<");
        try self.append(el.tag);
        try self.append(">");
        if (std.mem.eql(u8, el.tag, self.skip_tag)) {
            // Handle children manually — just count them
            try self.append("[");
            for (el.children, 0..) |_, i| {
                if (i > 0) try self.append(",");
                try self.append("_");
            }
            try self.append("]");
            return .skip_children;
        }
        return .@"continue";
    }

    pub fn elementClose(self: *SkipRenderer, el: Element) !void {
        try self.append("</");
        try self.append(el.tag);
        try self.append(">");
    }

    pub fn onText(self: *SkipRenderer, content: []const u8) !void {
        try self.append(content);
    }

    pub fn onRaw(self: *SkipRenderer, content: []const u8) !void {
        try self.append(content);
    }
};

test "renderWalk text node" {
    var r = TraceRenderer.init(testing.allocator);
    defer r.deinit();
    try renderWalk(&r, text("hello"));
    try testing.expectEqualStrings("hello", r.result());
}

test "renderWalk raw node" {
    var r = TraceRenderer.init(testing.allocator);
    defer r.deinit();
    try renderWalk(&r, raw("<br>"));
    try testing.expectEqualStrings("<br>", r.result());
}

test "renderWalk element with children" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const tree = try element(a, "div", .{ .class = "card" }, .{
        text("hello"),
    });

    var r = TraceRenderer.init(testing.allocator);
    defer r.deinit();
    try renderWalk(&r, tree);
    try testing.expectEqualStrings("<div class=\"card\">hello</div>", r.result());
}

test "renderWalk closed element calls open only" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try closedElement(arena.allocator(), "br", .{});

    var r = TraceRenderer.init(testing.allocator);
    defer r.deinit();
    try renderWalk(&r, tree);
    try testing.expectEqualStrings("<br>", r.result());
}

test "renderWalk fragment is transparent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const tree = try fragment(a, .{ text("a"), text("b"), text("c") });

    var r = TraceRenderer.init(testing.allocator);
    defer r.deinit();
    try renderWalk(&r, tree);
    try testing.expectEqualStrings("abc", r.result());
}

test "renderWalk none() produces nothing" {
    var r = TraceRenderer.init(testing.allocator);
    defer r.deinit();
    try renderWalk(&r, none());
    try testing.expectEqualStrings("", r.result());
}

test "renderWalk nested elements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const tree = try element(a, "ul", .{}, .{
        try element(a, "li", .{}, .{text("one")}),
        try element(a, "li", .{}, .{text("two")}),
    });

    var r = TraceRenderer.init(testing.allocator);
    defer r.deinit();
    try renderWalk(&r, tree);
    try testing.expectEqualStrings("<ul><li>one</li><li>two</li></ul>", r.result());
}

test "renderWalk boolean attr" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try closedElement(arena.allocator(), "input", .{ .type = "checkbox", .checked = {} });

    var r = TraceRenderer.init(testing.allocator);
    defer r.deinit();
    try renderWalk(&r, tree);
    try testing.expectEqualStrings("<input type=\"checkbox\" checked>", r.result());
}

test "renderWalk mixed content" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const tree = try element(a, "p", .{}, .{
        text("hello "),
        try element(a, "strong", .{}, .{text("world")}),
        raw("!"),
    });

    var r = TraceRenderer.init(testing.allocator);
    defer r.deinit();
    try renderWalk(&r, tree);
    try testing.expectEqualStrings("<p>hello <strong>world</strong>!</p>", r.result());
}

test "renderWalk skip_children skips children and elementClose" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Tree: <div><pre><code>hello</code></pre><p>after</p></div>
    const tree = try element(a, "div", .{}, .{
        try element(a, "pre", .{}, .{
            try element(a, "code", .{}, .{text("hello")}),
        }),
        try element(a, "p", .{}, .{text("after")}),
    });

    // Skip "pre" — renderer handles it in elementOpen, no recursion, no elementClose
    var r = SkipRenderer.init(testing.allocator, "pre");
    defer r.deinit();
    try renderWalk(&r, tree);
    // <pre> gets opened with [_] for its 1 child, no </pre>
    // <p> gets normal traversal
    try testing.expectEqualStrings("<div><pre>[_]<p>after</p></div>", r.result());
}

test "renderWalk skip_children on leaf element" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Element with no children — skip_children is a no-op but still suppresses elementClose
    const tree = try element(arena.allocator(), "pre", .{}, .{});

    var r = SkipRenderer.init(testing.allocator, "pre");
    defer r.deinit();
    try renderWalk(&r, tree);
    try testing.expectEqualStrings("<pre>[]", r.result());
}

test "renderWalk skip_children does not affect siblings" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two pre elements and a normal element — each pre is skipped independently
    const tree = try fragment(a, .{
        try element(a, "pre", .{}, .{text("a")}),
        try element(a, "div", .{}, .{text("b")}),
        try element(a, "pre", .{}, .{text("c")}),
    });

    var r = SkipRenderer.init(testing.allocator, "pre");
    defer r.deinit();
    try renderWalk(&r, tree);
    try testing.expectEqualStrings("<pre>[_]<div>b</div><pre>[_]", r.result());
}

test "renderWalk closed element ignores skip_children" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Closed element whose tag matches skip_tag — closed already skips,
    // so the WalkAction doesn't matter. No elementClose either way.
    const tree = try closedElement(arena.allocator(), "pre", .{});

    var r = SkipRenderer.init(testing.allocator, "pre");
    defer r.deinit();
    try renderWalk(&r, tree);
    // closed elements have no children, so [] is empty
    try testing.expectEqualStrings("<pre>[]", r.result());
}

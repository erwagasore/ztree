const std = @import("std");
const node = @import("node.zig");

const Node = node.Node;
const Element = node.Element;

/// Walk a node tree, dispatching to `renderer` callbacks.
///
/// The renderer must be a pointer to a struct with these methods:
///
///   fn elementOpen(self, el: Element) !void
///   fn elementClose(self, el: Element) !void
///   fn onText(self, content: []const u8) !void
///   fn onRaw(self, content: []const u8) !void
///
/// Fragment nodes are transparent — `renderWalk` recurses into their
/// children without calling any callback.
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
            try renderer.elementOpen(el);
            for (el.children) |child| try callRenderer(renderer, child);
            try renderer.elementClose(el);
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

/// Minimal test renderer that records callback invocations as a string.
const TraceRenderer = struct {
    buf: std.ArrayList(u8),
    gpa: Allocator,

    fn init(gpa: Allocator) TraceRenderer {
        return .{ .buf = .empty, .gpa = gpa };
    }

    fn deinit(self: *TraceRenderer) void {
        self.buf.deinit(self.gpa);
    }

    fn result(self: *TraceRenderer) []const u8 {
        return self.buf.items;
    }

    fn append(self: *TraceRenderer, s: []const u8) !void {
        try self.buf.appendSlice(self.gpa, s);
    }

    pub fn elementOpen(self: *TraceRenderer, el: Element) !void {
        try self.append("<");
        try self.append(el.tag);
        for (el.attrs) |a| {
            try self.append(" ");
            try self.append(a.key);
            if (a.value) |v| {
                try self.append("=\"");
                try self.append(v);
                try self.append("\"");
            }
        }
        try self.append(">");
    }

    pub fn elementClose(self: *TraceRenderer, el: Element) !void {
        try self.append("</");
        try self.append(el.tag);
        try self.append(">");
    }

    pub fn onText(self: *TraceRenderer, content: []const u8) !void {
        try self.append(content);
    }

    pub fn onRaw(self: *TraceRenderer, content: []const u8) !void {
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

test "renderWalk closed element calls open and close" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const tree = try closedElement(arena.allocator(), "br", .{});

    var r = TraceRenderer.init(testing.allocator);
    defer r.deinit();
    try renderWalk(&r, tree);
    try testing.expectEqualStrings("<br></br>", r.result());
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
    try testing.expectEqualStrings("<input type=\"checkbox\" checked></input>", r.result());
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

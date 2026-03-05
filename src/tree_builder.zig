const std = @import("std");
const create = @import("create.zig");
const node_mod = @import("node.zig");

const Node = node_mod.Node;
const Element = node_mod.Element;
const Attr = node_mod.Attr;
const Allocator = std.mem.Allocator;

/// Imperative tree builder — the producer-side counterpart to `renderWalk`.
///
/// Parsers call `open`, `close`, `text`, `raw`, and `closedElement` to emit
/// a stream of structural events. The builder assembles them into a `Node` tree.
///
/// Designed for arena allocators. The builder's scratch buffers and all tree
/// nodes are allocated via the provided allocator. With an arena, free
/// everything in one shot when the tree is no longer needed.
///
///   var b = TreeBuilder.init(arena.allocator());
///   defer b.deinit();
///
///   try b.open("h1", .{});
///   try b.text("Hello");
///   try b.close();
///
///   try b.open("p", .{});
///   try b.text("World");
///   try b.close();
///
///   const tree = try b.finish();
///
pub const TreeBuilder = struct {
    allocator: Allocator,

    /// Scratch buffer for nodes at the current nesting level.
    /// Nodes are moved to permanent allocations on `close()`.
    nodes: std.ArrayList(Node),

    /// Stack of open element frames.
    frames: std.ArrayList(Frame),

    const Frame = struct {
        tag: []const u8,
        attrs: []const Attr,
        children_start: usize,
    };

    /// Result of `popRaw` — the popped frame's metadata and finalized children.
    pub const PopResult = struct {
        tag: []const u8,
        attrs: []const Attr,
        children: []const Node,
    };

    /// Initialise a new builder. All allocations go through `allocator`.
    /// Arena recommended — the tree and scratch buffers share the allocator.
    pub fn init(allocator: Allocator) TreeBuilder {
        return .{
            .allocator = allocator,
            .nodes = .empty,
            .frames = .empty,
        };
    }

    /// Free the builder's scratch buffers. Does not free tree nodes — those
    /// are owned by the allocator (free via arena, or walk the tree manually).
    /// With an arena, calling deinit is optional.
    pub fn deinit(self: *TreeBuilder) void {
        self.nodes.deinit(self.allocator);
        self.frames.deinit(self.allocator);
    }

    /// Push a new element onto the stack. Children added after this call
    /// (via `text`, `raw`, `open`/`close`, `closedElement`) become children
    /// of this element until the matching `close()`.
    ///
    /// `attrs` accepts the same types as `element()`: struct literal,
    /// `[]const Attr`, or `[]const ?Attr`.
    pub fn open(self: *TreeBuilder, tag: []const u8, attrs: anytype) !void {
        try self.frames.append(self.allocator, .{
            .tag = tag,
            .attrs = try create.buildAttrs(self.allocator, attrs),
            .children_start = self.nodes.items.len,
        });
    }

    /// Pop the current element from the stack, finalise its children, and
    /// add it as a child of the parent element (or as a root node).
    ///
    /// Returns `error.ExtraClose` if no element is open.
    pub fn close(self: *TreeBuilder) !void {
        const frame = self.frames.pop() orelse return error.ExtraClose;
        const start = frame.children_start;
        const child_nodes = self.nodes.items[start..];

        var children: []const Node = &.{};
        if (child_nodes.len > 0) {
            const buf = try self.allocator.alloc(Node, child_nodes.len);
            @memcpy(buf, child_nodes);
            children = buf;
        }

        self.nodes.shrinkRetainingCapacity(start);

        try self.nodes.append(self.allocator, .{
            .element = .{
                .tag = frame.tag,
                .attrs = frame.attrs,
                .children = children,
            },
        });
    }

    /// Pop the current frame without emitting a node. Returns the frame's
    /// tag, attrs, and finalized children so the caller can inspect, transform,
    /// or discard them and manually emit via `text()`, `raw()`, `closedElement()`, etc.
    ///
    /// Use when a parser needs to intercept children at close time — e.g. collecting
    /// alt text from an image span's children, then emitting a `closedElement` with
    /// computed attrs instead of the normal element.
    ///
    /// Returns `error.ExtraClose` if no element is open.
    pub fn popRaw(self: *TreeBuilder) !PopResult {
        const frame = self.frames.pop() orelse return error.ExtraClose;
        const start = frame.children_start;
        const child_nodes = self.nodes.items[start..];

        var children: []const Node = &.{};
        if (child_nodes.len > 0) {
            const buf = try self.allocator.alloc(Node, child_nodes.len);
            @memcpy(buf, child_nodes);
            children = buf;
        }

        self.nodes.shrinkRetainingCapacity(start);

        return .{
            .tag = frame.tag,
            .attrs = frame.attrs,
            .children = children,
        };
    }

    /// Append a text node. The renderer escapes its content.
    pub fn text(self: *TreeBuilder, content: []const u8) !void {
        try self.nodes.append(self.allocator, .{ .text = content });
    }

    /// Append a raw node. The renderer passes content through as-is.
    pub fn raw(self: *TreeBuilder, content: []const u8) !void {
        try self.nodes.append(self.allocator, .{ .raw = content });
    }

    /// Append a void/self-closing element (no children).
    ///
    /// `attrs` accepts the same types as `open()`.
    pub fn closedElement(self: *TreeBuilder, tag: []const u8, attrs: anytype) !void {
        try self.nodes.append(self.allocator, .{
            .element = .{
                .tag = tag,
                .attrs = try create.buildAttrs(self.allocator, attrs),
                .children = &.{},
            },
        });
    }

    /// Finalise the tree and return the root node.
    ///
    /// - Zero root nodes → empty fragment (`none()`).
    /// - One root node → that node directly.
    /// - Multiple root nodes → fragment wrapping all roots.
    ///
    /// Returns `error.UnclosedElement` if any `open()` calls have no
    /// matching `close()`.
    pub fn finish(self: *TreeBuilder) !Node {
        if (self.frames.items.len != 0) return error.UnclosedElement;

        return switch (self.nodes.items.len) {
            0 => .{ .fragment = &.{} },
            1 => self.nodes.items[0],
            else => {
                const buf = try self.allocator.alloc(Node, self.nodes.items.len);
                @memcpy(buf, self.nodes.items);
                return .{ .fragment = buf };
            },
        };
    }

    /// Current nesting depth (number of unclosed `open()` calls).
    pub fn depth(self: *const TreeBuilder) usize {
        return self.frames.items.len;
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

const testing = std.testing;
const renderWalk = @import("render.zig").renderWalk;

// -- finish edge cases --

test "finish empty builder returns none" {
    var b = TreeBuilder.init(testing.allocator);
    defer b.deinit();
    const n = try b.finish();
    try testing.expectEqual(.fragment, std.meta.activeTag(n));
    try testing.expectEqual(0, n.fragment.len);
}

test "finish single text node unwraps" {
    var b = TreeBuilder.init(testing.allocator);
    defer b.deinit();
    try b.text("hello");
    const n = try b.finish();
    try testing.expectEqualStrings("hello", n.text);
}

test "finish single raw node unwraps" {
    var b = TreeBuilder.init(testing.allocator);
    defer b.deinit();
    try b.raw("<br>");
    const n = try b.finish();
    try testing.expectEqualStrings("<br>", n.raw);
}

test "finish multiple roots wraps in fragment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());
    try b.text("a");
    try b.text("b");
    try b.text("c");
    const n = try b.finish();
    try testing.expectEqual(.fragment, std.meta.activeTag(n));
    try testing.expectEqual(3, n.fragment.len);
    try testing.expectEqualStrings("a", n.fragment[0].text);
    try testing.expectEqualStrings("b", n.fragment[1].text);
    try testing.expectEqualStrings("c", n.fragment[2].text);
}

// -- closedElement --

test "closedElement no attrs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());
    try b.closedElement("br", .{});
    const n = try b.finish();
    try testing.expectEqualStrings("br", n.element.tag);
    try testing.expectEqual(0, n.element.attrs.len);
    try testing.expectEqual(0, n.element.children.len);
}

test "closedElement with struct attrs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());
    try b.closedElement("img", .{ .src = "photo.jpg", .alt = "A photo" });
    const n = try b.finish();
    try testing.expectEqualStrings("img", n.element.tag);
    try testing.expectEqual(2, n.element.attrs.len);
    try testing.expectEqualStrings("src", n.element.attrs[0].key);
    try testing.expectEqualStrings("photo.jpg", n.element.attrs[0].value.?);
    try testing.expectEqualStrings("alt", n.element.attrs[1].key);
    try testing.expectEqualStrings("A photo", n.element.attrs[1].value.?);
}

// -- open / close --

test "element with no children" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());
    try b.open("div", .{});
    try b.close();
    const n = try b.finish();
    try testing.expectEqualStrings("div", n.element.tag);
    try testing.expectEqual(0, n.element.children.len);
}

test "element with text child" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());
    try b.open("p", .{});
    try b.text("hello");
    try b.close();
    const n = try b.finish();
    try testing.expectEqualStrings("p", n.element.tag);
    try testing.expectEqual(1, n.element.children.len);
    try testing.expectEqualStrings("hello", n.element.children[0].text);
}

test "element with struct attrs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());
    try b.open("div", .{ .class = "card", .id = "main" });
    try b.close();
    const n = try b.finish();
    try testing.expectEqual(2, n.element.attrs.len);
    try testing.expectEqualStrings("class", n.element.attrs[0].key);
    try testing.expectEqualStrings("card", n.element.attrs[0].value.?);
    try testing.expectEqualStrings("id", n.element.attrs[1].key);
    try testing.expectEqualStrings("main", n.element.attrs[1].value.?);
}

test "element with runtime []const Attr" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var b = TreeBuilder.init(a);
    const attrs = try a.alloc(Attr, 1);
    attrs[0] = .{ .key = "href", .value = "/home" };
    try b.open("a", attrs);
    try b.text("Home");
    try b.close();
    const n = try b.finish();
    try testing.expectEqual(1, n.element.attrs.len);
    try testing.expectEqualStrings("href", n.element.attrs[0].key);
}

test "element with boolean attr" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());
    try b.open("input", .{ .type = "checkbox", .checked = {} });
    try b.close();
    const n = try b.finish();
    try testing.expectEqual(2, n.element.attrs.len);
    try testing.expectEqualStrings("checked", n.element.attrs[1].key);
    try testing.expectEqual(null, n.element.attrs[1].value);
}

// -- nesting --

test "nested elements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());

    try b.open("ul", .{});
    try b.open("li", .{});
    try b.text("one");
    try b.close();
    try b.open("li", .{});
    try b.text("two");
    try b.close();
    try b.close();

    const n = try b.finish();
    try testing.expectEqualStrings("ul", n.element.tag);
    try testing.expectEqual(2, n.element.children.len);

    const li1 = n.element.children[0];
    try testing.expectEqualStrings("li", li1.element.tag);
    try testing.expectEqualStrings("one", li1.element.children[0].text);

    const li2 = n.element.children[1];
    try testing.expectEqualStrings("li", li2.element.tag);
    try testing.expectEqualStrings("two", li2.element.children[0].text);
}

test "deep nesting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());

    try b.open("div", .{});
    try b.open("section", .{});
    try b.open("p", .{});
    try b.open("strong", .{});
    try b.text("deep");
    try b.close(); // strong
    try b.close(); // p
    try b.close(); // section
    try b.close(); // div

    const n = try b.finish();
    const deep_text = n.element // div
        .children[0].element // section
        .children[0].element // p
        .children[0].element // strong
        .children[0].text;
    try testing.expectEqualStrings("deep", deep_text);
}

test "mixed content" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());

    try b.open("p", .{});
    try b.text("hello ");
    try b.open("strong", .{});
    try b.text("world");
    try b.close();
    try b.raw("!");
    try b.close();

    const n = try b.finish();
    try testing.expectEqual(3, n.element.children.len);
    try testing.expectEqualStrings("hello ", n.element.children[0].text);
    try testing.expectEqualStrings("strong", n.element.children[1].element.tag);
    try testing.expectEqualStrings("!", n.element.children[2].raw);
}

test "closedElement as child" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());

    try b.open("p", .{});
    try b.text("line one");
    try b.closedElement("br", .{});
    try b.text("line two");
    try b.close();

    const n = try b.finish();
    try testing.expectEqual(3, n.element.children.len);
    try testing.expectEqualStrings("line one", n.element.children[0].text);
    try testing.expectEqualStrings("br", n.element.children[1].element.tag);
    try testing.expectEqual(0, n.element.children[1].element.children.len);
    try testing.expectEqualStrings("line two", n.element.children[2].text);
}

// -- depth --

test "depth tracks nesting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());

    try testing.expectEqual(0, b.depth());
    try b.open("div", .{});
    try testing.expectEqual(1, b.depth());
    try b.open("p", .{});
    try testing.expectEqual(2, b.depth());
    try b.close();
    try testing.expectEqual(1, b.depth());
    try b.close();
    try testing.expectEqual(0, b.depth());
}

// -- error cases --

test "close without open returns ExtraClose" {
    var b = TreeBuilder.init(testing.allocator);
    defer b.deinit();
    try testing.expectError(error.ExtraClose, b.close());
}

test "finish with unclosed element returns UnclosedElement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());
    try b.open("div", .{});
    try testing.expectError(error.UnclosedElement, b.finish());
}

test "finish with deeply unclosed elements returns UnclosedElement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());
    try b.open("div", .{});
    try b.open("p", .{});
    try b.text("orphan");
    try testing.expectError(error.UnclosedElement, b.finish());
}

// -- popRaw --

test "popRaw returns frame data without emitting node" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());

    try b.open("span", .{ .class = "img" });
    try b.text("alt text here");
    const f = try b.popRaw();

    // Frame data is returned
    try testing.expectEqualStrings("span", f.tag);
    try testing.expectEqual(1, f.attrs.len);
    try testing.expectEqualStrings("class", f.attrs[0].key);
    try testing.expectEqual(1, f.children.len);
    try testing.expectEqualStrings("alt text here", f.children[0].text);

    // Nothing was emitted — builder is empty
    try testing.expectEqual(0, b.depth());
    const n = try b.finish();
    try testing.expectEqual(.fragment, std.meta.activeTag(n));
    try testing.expectEqual(0, n.fragment.len);
}

test "popRaw then emit transformed node" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var b = TreeBuilder.init(a);

    // Simulate: parser opens an img span, adds alt text children,
    // then intercepts at close to emit a closed <img> instead.
    try b.open("div", .{});

    try b.open("span", .{ .src = "photo.jpg" });
    try b.text("A photo");
    const f = try b.popRaw();

    // Extract src from original attrs
    const src = for (f.attrs) |attr| {
        if (std.mem.eql(u8, attr.key, "src")) break attr.value orelse "";
    } else "";

    // Extract alt from children
    var alt: []const u8 = "";
    if (f.children.len > 0) {
        if (f.children[0] == .text) alt = f.children[0].text;
    }

    // Emit a closed img element with computed attrs
    const attrs = try a.alloc(Attr, 2);
    attrs[0] = .{ .key = "src", .value = src };
    attrs[1] = .{ .key = "alt", .value = alt };
    try b.closedElement("img", attrs);

    try b.close(); // div

    const n = try b.finish();
    try testing.expectEqualStrings("div", n.element.tag);
    try testing.expectEqual(1, n.element.children.len);

    const img = n.element.children[0].element;
    try testing.expectEqualStrings("img", img.tag);
    try testing.expectEqual(0, img.children.len);
    try testing.expectEqual(2, img.attrs.len);
    try testing.expectEqualStrings("src", img.attrs[0].key);
    try testing.expectEqualStrings("photo.jpg", img.attrs[0].value.?);
    try testing.expectEqualStrings("alt", img.attrs[1].key);
    try testing.expectEqualStrings("A photo", img.attrs[1].value.?);
}

test "popRaw with no children returns empty slice" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());

    try b.open("span", .{});
    const f = try b.popRaw();

    try testing.expectEqualStrings("span", f.tag);
    try testing.expectEqual(0, f.attrs.len);
    try testing.expectEqual(0, f.children.len);
}

test "popRaw without open returns ExtraClose" {
    var b = TreeBuilder.init(testing.allocator);
    defer b.deinit();
    try testing.expectError(error.ExtraClose, b.popRaw());
}

test "popRaw preserves parent frame" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var b = TreeBuilder.init(arena.allocator());

    try b.open("div", .{});
    try b.text("before");

    try b.open("span", .{});
    try b.text("inner");
    _ = try b.popRaw(); // discard the span

    try b.text("after");
    try b.close(); // div

    const n = try b.finish();
    try testing.expectEqualStrings("div", n.element.tag);
    try testing.expectEqual(2, n.element.children.len);
    try testing.expectEqualStrings("before", n.element.children[0].text);
    try testing.expectEqualStrings("after", n.element.children[1].text);
}

// -- round-trip: TreeBuilder output matches declarative API via renderWalk --

/// Minimal renderer that records callbacks as a string (same as render.zig tests).
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

fn renderToString(gpa: Allocator, n: Node) ![]const u8 {
    var r = TraceRenderer.init(gpa);
    errdefer r.deinit();
    try renderWalk(&r, n);
    return r.buf.toOwnedSlice(gpa);
}

test "round-trip: TreeBuilder matches declarative element()" {
    // Build the same tree two ways and compare rendered output.
    //
    // Target tree:
    //   <ul class="list">
    //     <li>one</li>
    //     <li><strong>two</strong></li>
    //   </ul>
    //

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // -- Declarative --
    const declarative = try create.element(a, "ul", .{ .class = "list" }, .{
        try create.element(a, "li", .{}, .{create.text("one")}),
        try create.element(a, "li", .{}, .{
            try create.element(a, "strong", .{}, .{create.text("two")}),
        }),
    });

    // -- TreeBuilder --
    var b = TreeBuilder.init(a);

    try b.open("ul", .{ .class = "list" });
    try b.open("li", .{});
    try b.text("one");
    try b.close();
    try b.open("li", .{});
    try b.open("strong", .{});
    try b.text("two");
    try b.close(); // strong
    try b.close(); // li
    try b.close(); // ul

    const built = try b.finish();

    // Render both and compare
    const decl_html = try renderToString(testing.allocator, declarative);
    defer testing.allocator.free(decl_html);
    const built_html = try renderToString(testing.allocator, built);
    defer testing.allocator.free(built_html);

    try testing.expectEqualStrings(decl_html, built_html);
    try testing.expectEqualStrings(
        "<ul class=\"list\"><li>one</li><li><strong>two</strong></li></ul>",
        built_html,
    );
}

test "round-trip: mixed content with closedElement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Declarative
    const declarative = try create.element(a, "p", .{}, .{
        create.text("hello "),
        try create.element(a, "strong", .{}, .{create.text("world")}),
        try create.closedElement(a, "br", .{}),
        create.raw("&amp;"),
    });

    // TreeBuilder
    var b = TreeBuilder.init(a);
    try b.open("p", .{});
    try b.text("hello ");
    try b.open("strong", .{});
    try b.text("world");
    try b.close();
    try b.closedElement("br", .{});
    try b.raw("&amp;");
    try b.close();
    const built = try b.finish();

    const decl_html = try renderToString(testing.allocator, declarative);
    defer testing.allocator.free(decl_html);
    const built_html = try renderToString(testing.allocator, built);
    defer testing.allocator.free(built_html);

    try testing.expectEqualStrings(decl_html, built_html);
}

test "round-trip: document with attrs and nesting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Declarative
    const declarative = try create.element(a, "html", .{ .lang = "en" }, .{
        try create.element(a, "head", .{}, .{
            try create.element(a, "title", .{}, .{create.text("Test")}),
            try create.closedElement(a, "meta", .{ .charset = "utf-8" }),
        }),
        try create.element(a, "body", .{}, .{
            try create.element(a, "h1", .{}, .{create.text("Hello")}),
        }),
    });

    // TreeBuilder
    var b = TreeBuilder.init(a);
    try b.open("html", .{ .lang = "en" });
    try b.open("head", .{});
    try b.open("title", .{});
    try b.text("Test");
    try b.close();
    try b.closedElement("meta", .{ .charset = "utf-8" });
    try b.close(); // head
    try b.open("body", .{});
    try b.open("h1", .{});
    try b.text("Hello");
    try b.close(); // h1
    try b.close(); // body
    try b.close(); // html
    const built = try b.finish();

    const decl_html = try renderToString(testing.allocator, declarative);
    defer testing.allocator.free(decl_html);
    const built_html = try renderToString(testing.allocator, built);
    defer testing.allocator.free(built_html);

    try testing.expectEqualStrings(decl_html, built_html);
    try testing.expectEqualStrings(
        "<html lang=\"en\"><head><title>Test</title><meta charset=\"utf-8\"></meta></head><body><h1>Hello</h1></body></html>",
        built_html,
    );
}

# ztree

Format-agnostic document tree library for Zig. Zero dependencies beyond `std`.

ztree provides types and construction functions for building document trees.
It has no opinions about HTML, Markdown, JSON, or any specific format.
Renderer packages walk the tree and produce output:

- [ztree-html](https://github.com/erwagasore/ztree-html) — HTML renderer
- [ztree-md](https://github.com/erwagasore/ztree-md) — GFM Markdown renderer
- [ztree-parse-md](https://github.com/erwagasore/ztree-parse-md) — Markdown parser → ztree tree

## Install

Add ztree to your `build.zig.zon`:

```bash
zig fetch --save git+https://github.com/erwagasore/ztree.git#main
```

Then in your `build.zig`, add the dependency to your module:

```zig
const ztree_dep = b.dependency("ztree", .{
    .target = target,
    .optimize = optimize,
});
my_module.addImport("ztree", ztree_dep.module("ztree"));
```

Import it:

```zig
const ztree = @import("ztree");
```

## Quick example

```zig
const std = @import("std");
const ztree = @import("ztree");
const html = @import("ztree-html");

const element = ztree.element;
const closedElement = ztree.closedElement;
const text = ztree.text;
const none = ztree.none;
const cls = ztree.cls;

fn page(a: std.mem.Allocator, logged_in: bool) !ztree.Node {
    return element(a, "html", .{ .lang = "en" }, .{
        try element(a, "head", .{}, .{
            try element(a, "title", .{}, .{text("My Site")}),
            try closedElement(a, "meta", .{ .charset = "utf-8" }),
        }),
        try element(a, "body", .{}, .{
            try element(a, "nav", .{ .class = "topnav" }, .{
                try element(a, "a", .{ .href = "/", .class = "nav-link" }, .{text("Home")}),
                if (logged_in)
                    try element(a, "a", .{ .href = "/profile" }, .{text("Profile")})
                else
                    none(),
            }),
            try element(a, "main", .{}, .{
                try element(a, "h1", .{}, .{text("Welcome")}),
                try element(a, "p", .{}, .{
                    text("This is a "),
                    try element(a, "strong", .{}, .{text("format-agnostic")}),
                    text(" document tree."),
                }),
            }),
        }),
    });
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const tree = try page(a, true);

    // Render to HTML — ztree-html walks the tree, writes output
    var buf: std.ArrayList(u8) = .empty;
    try html.render(tree, buf.writer(a));
}
```

This builds an in-memory tree. Renderers walk the tree and decide the format:

**ztree-html** → `<h1>Welcome</h1><p>This is a <strong>format-agnostic</strong> document tree.</p>`

**ztree-md** → `# Welcome\n\nThis is a **format-agnostic** document tree.`

---

## API

### Types

#### `Node`

Tagged union representing any node in a document tree.

```zig
const Node = union(enum) {
    element: Element,       // an element with tag, attributes, and children
    text: []const u8,       // content to be escaped by the renderer
    raw: []const u8,        // content passed through as-is by the renderer
    fragment: []const Node, // children without a wrapping tag
};
```

#### `Element`

A named element with attributes and children.

```zig
const Element = struct {
    tag: []const u8,
    attrs: []const Attr,
    children: []const Node,
};
```

#### `Attr`

A key-value attribute. A `null` value represents a boolean attribute (key only, no value).

```zig
const Attr = struct {
    key: []const u8,
    value: ?[]const u8,
};
```

---

### Construction functions

`element`, `closedElement`, and `fragment` take an `Allocator` and return `!Node`.
Leaf constructors (`text`, `raw`, `none`, `attr`) are pure and need no allocator.

#### `element`

```zig
fn element(a: Allocator, tag: []const u8, attrs: anytype, children: anytype) !Node
```

Build an element node. Attrs can be a struct literal or a `[]const Attr` slice.
Children can be a tuple or a `[]const Node` slice.

```zig
// Struct attrs — field names become attribute keys
try element(a, "div", .{ .class = "card", .id = "main" }, .{
    try element(a, "h2", .{}, .{text("Title")}),
    try element(a, "p", .{}, .{text("Body")}),
})

// Boolean attrs with void
try closedElement(a, "input", .{ .type = "checkbox", .checked = {} })

// Non-identifier attr names with @""
try element(a, "div", .{ .@"hx-get" = "/api", .@"aria-label" = "panel" }, .{})

// Conditional attrs — null omits the attribute
try element(a, "li", .{
    .class = "item",
    .@"aria-disabled" = if (disabled) "true" else null,
}, .{text(label)})

// Runtime attrs via []const Attr or []const ?Attr slice
try element(a, "a", &[_]?Attr{
    attr("href", url),
    if (external) attr("target", "_blank") else null,
}, .{text("Link")})
```

#### `closedElement`

```zig
fn closedElement(a: Allocator, tag: []const u8, attrs: anytype) !Node
```

Build a void/self-closing element (no children).

```zig
try closedElement(a, "img", .{ .src = "photo.jpg", .alt = "A photo" })
try closedElement(a, "br", .{})
```

#### `fragment`

```zig
fn fragment(a: Allocator, children: anytype) !Node
```

Build a fragment — children without a wrapping tag. Renderers treat
fragments as transparent.

```zig
try fragment(a, .{
    try element(a, "h1", .{}, .{text("Title")}),
    try element(a, "p", .{}, .{text("Subtitle")}),
})
```

#### `text`

```zig
fn text(content: []const u8) Node
```

Construct a text node. The **renderer** escapes its content.

#### `raw`

```zig
fn raw(content: []const u8) Node
```

Construct a raw node. The renderer passes content through **without escaping**.

#### `attr`

```zig
fn attr(key: []const u8, value: ?[]const u8) Attr
```

Construct an attribute. Pass `null` for a boolean attribute. Used when
building `[]const Attr` or `[]const ?Attr` slices at runtime.

#### `cls`

```zig
fn cls(a: Allocator, parts: []const ?[]const u8) ![]const u8
```

Join non-null class name parts with spaces. Useful for conditional classes.

```zig
try cls(a, &.{ "btn", if (primary) "btn-primary" else null, if (active) "active" else null })
// → "btn btn-primary active"  or  "btn"  or  "btn active"  etc.
```

#### `none`

```zig
fn none() Node
```

Returns an empty fragment. Useful as the `else` branch in conditionals.

```zig
if (show_nav) try navbar(a) else none()
```

#### `renderWalk`

```zig
fn renderWalk(renderer: anytype, node: Node) !void
```

Walk a tree, calling `elementOpen`, `elementClose`, `onText`, `onRaw` on the
renderer. Fragments are transparent. Used by format libraries internally —
end users call the format library's render function instead.

---

## Dynamic content

For runtime values, children and attrs must outlive the function scope.
Use an arena allocator — allocate everything, use the tree, free in one shot:

```zig
fn navBar(a: Allocator, items: []const NavItem, active: []const u8) !Node {
    const links = try a.alloc(Node, items.len);
    for (items, 0..) |item, i| {
        links[i] = try element(a, "a", .{
            .href = item.href,
            .class = try cls(a, &.{
                "nav-link",
                if (std.mem.eql(u8, item.href, active)) "active" else null,
            }),
        }, .{text(item.label)});
    }
    return element(a, "nav", .{ .class = "navbar" }, links);
}
```

## Structure

See [AGENTS.md](AGENTS.md#repo-map) for the full repo map.

## License

MIT

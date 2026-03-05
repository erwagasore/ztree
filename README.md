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

const element = ztree.element;
const closedElement = ztree.closedElement;
const text = ztree.text;
const raw = ztree.raw;
const none = ztree.none;

// A function is a component — takes data, returns a Node.
fn navBar(a: std.mem.Allocator, user: ?[]const u8) !ztree.Node {
    return element(a, "nav", .{ .class = "topnav" }, .{
        try element(a, "a", .{ .href = "/" }, .{text("Home")}),
        if (user != null)
            try element(a, "a", .{ .href = "/profile" }, .{text("Profile")})
        else
            none(),
    });
}

fn page(a: std.mem.Allocator, user: ?[]const u8) !ztree.Node {
    return element(a, "html", .{ .lang = "en" }, .{
        try element(a, "head", .{}, .{
            try element(a, "title", .{}, .{text("My Site")}),
            try closedElement(a, "meta", .{ .charset = "utf-8" }),
        }),
        try element(a, "body", .{}, .{
            // composable — just call the function
            try navBar(a, user),
            try element(a, "main", .{}, .{
                try element(a, "h1", .{}, .{text("Welcome")}),
                try element(a, "p", .{}, .{
                    text("Built with "),
                    try element(a, "strong", .{}, .{text("ztree")}),
                }),
                // optional attr — null omits it entirely
                try closedElement(a, "img", .{
                    .src = "hero.jpg",
                    .alt = "Hero",
                    .loading = if (user != null) "eager" else null,
                }),
                // boolean attr — void value, no ="..."
                try closedElement(a, "input", .{
                    .type = "email",
                    .required = {},
                }),
                // raw content — passed through without escaping
                raw("<!-- analytics -->"),
            }),
        }),
    });
}
```

One tree, multiple outputs. Renderer packages walk the tree and decide the format:

**ztree-html**
```html
<html lang="en"><head><title>My Site</title><meta charset="utf-8"></head>
<body><nav class="topnav"><a href="/">Home</a><a href="/profile">Profile</a></nav>
<main><h1>Welcome</h1><p>Built with <strong>ztree</strong></p>
<img src="hero.jpg" alt="Hero" loading="eager"><input type="email" required>
<!-- analytics --></main></body></html>
```

**ztree-md**
```md
# Welcome

Built with **ztree**

![Hero](hero.jpg)
```

**ztree-json**
```json
{"tag":"html","attrs":{"lang":"en"},"children":[...]}
```

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

#### `TreeBuilder`

Imperative tree builder — the producer-side counterpart to `renderWalk`.
Parsers call `open`, `close`, `text`, `raw`, and `closedElement` to emit
a stream of structural events. The builder assembles them into a `Node` tree.

```zig
var b = ztree.TreeBuilder.init(arena.allocator());
defer b.deinit();

try b.open("h1", .{});
try b.text("Hello");
try b.close();

try b.open("p", .{});
try b.text("World");
try b.close();

const tree = try b.finish();
```

`renderWalk` decomposes a tree into events (consumer side).
`TreeBuilder` composes events into a tree (producer side).

```
renderWalk: Tree → events → format  (renderer implements callbacks)
TreeBuilder: format → events → Tree  (parser calls methods)
```

Methods:

| Method | Description |
|--------|-------------|
| `init(allocator)` | Create a builder. Arena recommended. |
| `deinit()` | Free scratch buffers (optional with arena). |
| `open(tag, attrs)` | Push element. `attrs` accepts struct literal, `[]const Attr`, or `[]const ?Attr`. |
| `close()` | Pop element, finalise children. Returns `error.ExtraClose` if nothing is open. |
| `text(content)` | Append text node (escaped by renderer). |
| `raw(content)` | Append raw node (passed through as-is). |
| `closedElement(tag, attrs)` | Append void element (no children). |
| `finish()` | Return root node. Returns `error.UnclosedElement` if elements remain open. |
| `depth()` | Current nesting depth. |

Finish behaviour:
- Zero root nodes → empty fragment (`none()`).
- One root node → that node directly.
- Multiple root nodes → fragment wrapping all roots.

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
            .class = if (std.mem.eql(u8, item.href, active)) "nav-link active" else "nav-link",
        }, .{text(item.label)});
    }
    return element(a, "nav", .{ .class = "navbar" }, links);
}
```

## Structure

See [AGENTS.md](AGENTS.md#repo-map) for the full repo map.

## License

MIT

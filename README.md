# ztree

Format-agnostic document tree library for Zig. Zero dependencies beyond `std`.

ztree provides types and construction functions for building document trees.
It has no opinions about HTML, Markdown, JSON, or any specific format.
Renderer packages (e.g. `ztree-html`, `ztree-md`, `ztree-json`) walk the tree
and produce output.

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
const ztree = @import("ztree");
const element = ztree.element;
const closedElement = ztree.closedElement;
const fragment = ztree.fragment;
const text = ztree.text;
const raw = ztree.raw;
const attr = ztree.attr;
const none = ztree.none;

const logged_in = true;

const page = element("html", &.{attr("lang", "en")}, &.{
    element("head", &.{}, &.{
        element("title", &.{}, &.{text("My Site")}),
        closedElement("meta", &.{attr("charset", "utf-8")}),
    }),
    element("body", &.{}, &.{
        element("nav", &.{attr("class", "topnav")}, &.{
            element("a", &.{attr("href", "/")}, &.{text("Home")}),
            if (logged_in)
                element("a", &.{attr("href", "/profile")}, &.{text("Profile")})
            else
                none(),
        }),
        element("main", &.{}, &.{
            element("h1", &.{}, &.{text("Welcome")}),
            element("article", &.{attr("class", "post")}, &.{
                element("p", &.{}, &.{
                    text("This is a "),
                    element("strong", &.{}, &.{text("format-agnostic")}),
                    text(" document tree."),
                }),
                raw("<!-- rendered from ztree -->"),
                closedElement("hr", &.{}),
            }),
        }),
        fragment(&.{
            element("script", &.{attr("src", "app.js")}, &.{}),
            element("script", &.{attr("src", "analytics.js")}, &.{}),
        }),
    }),
});
```

This builds an in-memory tree. ztree has no opinions about output —
renderers walk the tree and decide the format:

**ztree-html**
```html
<html lang="en">
  <head>
    <title>My Site</title>
    <meta charset="utf-8">
  </head>
  <body>
    <nav class="topnav">
      <a href="/">Home</a>
      <a href="/profile">Profile</a>
    </nav>
    <main>
      <h1>Welcome</h1>
      <article class="post">
        <p>This is a <strong>format-agnostic</strong> document tree.</p>
        <!-- rendered from ztree -->
        <hr>
      </article>
    </main>
    <script src="app.js"></script>
    <script src="analytics.js"></script>
  </body>
</html>
```

**ztree-md**
```md
# Welcome

This is a **format-agnostic** document tree.
```

**ztree-json**
```json
{"tag":"html","attrs":{"lang":"en"},"children":[{"tag":"head","children":["My Site"]}, ...]}
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

A key-value attribute. A `null` value represents a boolean attribute (key
only, no value).

```zig
const Attr = struct {
    key: []const u8,
    value: ?[]const u8,
};
```

---

### Construction functions

All construction functions are **pure** — data in, `Node` out, no side
effects, no allocator. They all work at **comptime**.

#### `element`

```zig
fn element(tag: []const u8, attrs: []const Attr, children: []const Node) Node
```

Construct an element node with a tag, attributes, and children.

```zig
const card = element("div", &.{attr("class", "card")}, &.{
    element("h2", &.{}, &.{text("Title")}),
    element("p", &.{}, &.{text("Body")}),
});
```

#### `closedElement`

```zig
fn closedElement(tag: []const u8, attrs: []const Attr) Node
```

Construct a self-closing element with no children. Uses an empty static
slice internally — no allocation.

```zig
const img = closedElement("img", &.{
    attr("src", "photo.jpg"),
    attr("alt", "A photo"),
});

const br = closedElement("br", &.{});
```

#### `text`

```zig
fn text(content: []const u8) Node
```

Construct a text node. The **renderer** is responsible for escaping its
content (e.g. `<` → `&lt;` in HTML). ztree stores it as-is.

```zig
const greeting = text("Hello, world!");
```

#### `raw`

```zig
fn raw(content: []const u8) Node
```

Construct a raw node. The renderer passes its content through **without
escaping**. Use this for pre-escaped content or inline markup.

```zig
const icon = raw("<svg>...</svg>");
```

#### `fragment`

```zig
fn fragment(children: []const Node) Node
```

Construct a fragment — a list of children without a wrapping tag. Renderers
treat fragments as transparent: they recurse into the children directly.

```zig
const header_content = fragment(&.{
    element("h1", &.{}, &.{text("Title")}),
    element("p", &.{}, &.{text("Subtitle")}),
});
```

#### `attr`

```zig
fn attr(key: []const u8, value: ?[]const u8) Attr
```

Construct an attribute. Pass `null` for a boolean attribute (key only).

```zig
attr("class", "main")    // class="main"
attr("disabled", null)   // disabled
```

#### `none`

```zig
fn none() Node
```

Returns an empty fragment. Useful as the `else` branch in conditionals.

```zig
element("div", &.{}, &.{
    if (show_nav) nav_bar else none(),
    main_content,
});
```

---

## Children lifetime

Anonymous array literals (`&.{ ... }`) with comptime-known values live in
static memory — no allocation needed:

```zig
// Static tree — all values known at comptime:
const static_page = element("div", &.{}, &.{
    element("h1", &.{}, &.{text("Hello")}),
    closedElement("hr", &.{}),
});
```

For runtime values, or when returning a `Node` from a function, children
slices must be allocated so they outlive the scope. An arena allocator is the
simplest approach — allocate everything, use the tree, free in one shot:

```zig
fn profileCard(a: std.mem.Allocator, user: User) !ztree.Node {
    const kids = try a.alloc(ztree.Node, 2);
    kids[0] = element("h2", &.{}, &.{text(user.name)});
    kids[1] = closedElement("img", &.{attr("src", user.avatar)});
    return element("div", &.{attr("class", "card")}, kids);
}
```

Any allocator works — the arena is a convenience, not a requirement.

---

## Comptime

All construction functions work at comptime. Static trees are embedded in
the binary at zero runtime cost:

```zig
const layout = comptime element("html", &.{}, &.{
    element("head", &.{}, &.{
        element("title", &.{}, &.{text("My Site")}),
    }),
    element("body", &.{}, &.{
        element("h1", &.{}, &.{text("Welcome")}),
    }),
});
```

## License

MIT

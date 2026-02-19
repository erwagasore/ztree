# ztree

Format-agnostic document tree library for Zig.

## Quickstart

```bash
# Clone
git clone git@github.com:erwagasore/ztree.git
cd ztree

# Build
zig build

# Test
zig build test
```

### Usage

Add `ztree` as a dependency in your `build.zig.zon`, then import it:

```zig
const ztree = @import("ztree");

// Build a tree — no allocator needed for static content
const tree = ztree.element("div", &.{ztree.attr("class", "container")}, &.{
    ztree.text("Hello, "),
    ztree.element("strong", &.{}, &.{
        ztree.text("world"),
    }),
});
```

This produces the following in-memory tree:

```
Node.element
 tag: "div"
 attrs: [class="container"]
 children:
 ├── Node.text "Hello, "
 └── Node.element
      tag: "strong"
      children:
      └── Node.text "world"
```

ztree builds the tree — renderers produce the output. Each renderer walks the
tree and decides the format:

**ztree-html**
```html
<div class="container">Hello, <strong>world</strong></div>
```

**ztree-md**
```md
Hello, **world**
```

**ztree-json**
```json
{"tag":"div","attrs":{"class":"container"},"children":["Hello, ",{"tag":"strong","children":["world"]}]}
```

## Structure

See [AGENTS.md](AGENTS.md#repo-map) for the full repo map.

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

## Structure

See [AGENTS.md](AGENTS.md#repo-map) for the full repo map.

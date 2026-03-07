# Changelog

All notable changes to this project will be documented in this file.

## [0.8.0] — 2026-03-06

### Features

- **`TreeBuilder.addNode(node)`** — append a pre-built `Node` into the builder at the current nesting level. Enables injecting nodes from sub-parsers, caches, or externally constructed trees.

### Other

- Deduplicate `close()` and `popRaw()` via shared private `popFrame()` method, eliminating repeated frame-popping logic.

## [0.7.0] — 2026-03-06

### Breaking Changes

- **`Element` gains `closed: bool` field** — void/self-closing elements created via `closedElement()` now have `closed = true`. `renderWalk` calls `elementOpen` only for closed elements — `elementClose` is no longer called. Renderers that relied on receiving both callbacks for void elements must be updated.

### Features

- **`TreeBuilder.Error`** — named error set (`ExtraClose`, `UnclosedElement`) for use in downstream function signatures.
- **`TreeBuilder.reset()`** — clear all state while retaining allocated capacity, enabling builder reuse without a deinit/init cycle.

### Other

- `TraceRenderer` moved to dedicated `test_util.zig`, eliminating duplication across test modules.
- `isOptionalAttrSlice` made private — was unnecessarily `pub`.
- `root.zig` added to build test list (was missing).
- Improved doc comments on `buildAttrs`, `renderWalk`, and `attr`.

## [0.6.0] — 2026-03-05

### Features

- Add `TreeBuilder.popRaw()` — pops the current frame without emitting a node, returning a `PopResult` with the tag, attrs, and finalized children. Enables parsers to intercept and transform children at close time (e.g. collecting alt text from image span children) without coupling to TreeBuilder internals.

## [0.5.0] — 2026-03-05

### Features

- Add `TreeBuilder` — imperative tree builder for parser authors. Producer-side counterpart to `renderWalk`: parsers call `open`/`close`/`text`/`raw`/`closedElement` to emit structural events, and the builder assembles them into a `Node` tree. Includes `depth()` for nesting introspection and structural error detection (`ExtraClose`, `UnclosedElement`).

## [0.4.0] — 2026-03-05

### Breaking Changes

- Remove `cls()` from the public API. CSS class joining is format-specific; use a simple ternary or move the helper to `ztree-html`.

### Other

- Rewrite README quickstart: composable `navBar` component, optional attrs, boolean attrs, raw content, HTML/MD/JSON output samples.
- Update AGENTS.md: repo map, core principles, rejected alternatives, and code examples for v0.2 API.

## [0.3.0] — 2026-03-05

### Features

- Add `renderWalk` — generic tree walker that dispatches to duck-typed renderer callbacks (`elementOpen`, `elementClose`, `onText`, `onRaw`). Fragments are transparent.

### Other

- Remove examples directory (examples belong in format library repos, not the core lib).
- Rewrite README for v0.2 API: struct attrs, `cls()`, optional attrs, `renderWalk`, ecosystem links to ztree-html, ztree-md, ztree-parse-md.

## [0.2.0] — 2026-03-05

### Breaking Changes

- `element()`, `closedElement()`, and `fragment()` now take an `Allocator` and accept `anytype` for attrs and children — struct literals, tuples, and slices all work. Return type is `!Node`.

### Features

- Struct literal attrs: `.{ .class = "btn", .href = "/" }` — field names become attr keys, `{}` or `null` for boolean attrs.
- Optional struct attrs: `.{ .style = if (cond) "value" else null }` — null omits the attr entirely.
- `cls()` helper: joins non-null class name parts with spaces — `try cls(a, &.{ "btn", if (active) "active" else null })`.
- `[]const ?Attr` slice support: `buildAttrs` filters out nulls, enabling `if (cond) attr("key", "val") else null` in attr slices.
- Runnable examples: `examples/profile.zig` and `examples/storefront.zig` demonstrating nested elements, dynamic content, and conditional attrs.

### Fixes

- Export `attr()` constructor from public API.
- Fix pointer passthrough coercion in `buildAttrs`.

### Other

- Remove DESIGN.md.
- Add complete API reference and renderer output examples to README.

## [0.1.0] — 2026-02-19

### Breaking Changes

- Simplify construction API: `element()` and `fragment()` now take `[]const Node` instead of `anytype`, are infallible (`Node`, not `!Node`), and require no allocator.
- Rename `constructors.zig` → `create.zig`.
- Rename `elementVoid` → `closedElement`.

### Features

- Core types: `Node` tagged union, `Element`, `Attr` structs.
- Construction functions: `element()`, `closedElement()`, `fragment()`, `text()`, `raw()`, `attr()`, `none()`.
- Full comptime support — all construction functions work at compile time with no special code paths.
- Arena-based dynamic children for runtime content (database rows, loops).

### Other

- Project documentation: AGENTS.md with design principles, rejected alternatives, and children lifetime rules.
- DESIGN.md implementation checklist for all four phases.
- MIT licence, build.zig.zon package manifest.

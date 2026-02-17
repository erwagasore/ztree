# ztree (core) — Implementation Checklist

Format-agnostic document tree library for Zig. The foundation that every format library depends on.

---

## Overview

ztree provides:
- A `Node` tagged union representing any document structure
- Free functions to construct trees (`element`, `fragment`, `text`, `raw`, `elementVoid`, `attr`, `none`)
- Tree traversal and transformation utilities
- Render helpers for format module authors, including a callback-based tree walker (learned from goldmark)

It has zero opinions about HTML, Markdown, JSON, or any specific format. Format modules depend on ztree and add typed helpers + renderers.

### Prior Art

- **typed-html (Rust):** `VNode` enum (Text, UnsafeText, Element) — validates our `Node` tagged union design.
- **goldmark (Go):** Per-node-kind renderer registration via callbacks — adopted as `renderWalk` with duck-typed `anytype` renderer.
- **elem-go (Go):** Attrs as separate argument from children — adopted: attrs and children are distinct parameters on `element()`.

---

## Types

### Node

```
Node = union(enum) {
    element: Element,
    text: []const u8,       // content to be escaped by renderer
    raw: []const u8,        // content passed through as-is
    fragment: []const Node, // children without a wrapping tag
}
```

### Element

```
Element = struct {
    tag: []const u8,
    attrs: []const Attr,
    children: []const Node,
}
```

### Attr

```
Attr = struct {
    key: []const u8,
    value: ?[]const u8,     // null = boolean attribute (key only, no value)
}
```

---

## Phase 1: Types and Construction Functions

Define the core types and free functions for building trees.

### Design Decisions

**No Builder struct.** An earlier design wrapped an `Allocator` in a `Builder` struct. This was dropped because idiomatic Zig passes allocators explicitly to each function that needs one — the same pattern used throughout `std`. Free functions with an `allocator` parameter make every allocation site visible and eliminate a type.

**No `if_` helper.** An earlier design included `if_(condition, node) Node`. This was dropped because native Zig `if`/`else` is strictly more powerful — it handles optionals with payload capture, is familiar to every Zig developer, and adds zero API surface:

```
// Native Zig if — handles booleans, optionals, payload capture:
try element(allocator, "div", &.{}, .{
    if (user) |u| try profileCard(allocator, u) else none(),
    if (show_sidebar) sidebar else none(),
})
```

**No `map_` helper.** An earlier design included `map_(allocator, T, items, renderFn) !Node`. This was dropped because Zig has no closures — the render function can only use its single argument. The moment you need an allocator, an index, or any context, you need a `for` loop anyway. Idiomatic Zig:

```
// List rendering — explicit for loop:
const items = try allocator.alloc(Node, data.len);
for (data, 0..) |item, i| {
    items[i] = try renderItem(allocator, item);
}
const list = try element(allocator, "ul", &.{}, items);
```

### Critical Zig Constraint: Children Lifetime

**Tested and confirmed:** Tuples passed to functions live on the callee's stack. Returning a `Node` with children pointing to a local tuple causes **segfaults at runtime** (dangling pointer). This was verified with Zig 0.15.2.

**Solution:** `element()` and `fragment()` take an `Allocator` parameter and branch on `@inComptime()`:
- **Comptime:** `const arr: [N]Node = children; return .{ .children = &arr };` — static storage, allocator is `undefined` and never accessed.
- **Runtime:** `const slice = try allocator.alloc(Node, N); ...` — arena allocation.

### Construction Functions

All functions are free functions in `src/constructors.zig`.

**Functions that allocate** (take `Allocator`, return `!Node`):

| Function | Signature | Description |
|----------|-----------|-------------|
| `element` | `(allocator: Allocator, tag: []const u8, attrs: []const Attr, children: anytype) !Node` | Element node with children. Allocates children array at runtime. |
| `fragment` | `(allocator: Allocator, children: anytype) !Node` | Fragment node (children without wrapper). Allocates children array at runtime. |

**Functions that don't allocate** (no `Allocator`, return `Node` or `Attr`):

| Function | Signature | Description |
|----------|-----------|-------------|
| `text` | `(content: []const u8) Node` | Text node. Renderer escapes it. |
| `raw` | `(content: []const u8) Node` | Raw node. Renderer passes it through. |
| `elementVoid` | `(tag: []const u8, attrs: []const Attr) Node` | Element with no children. Empty static slice — no allocation. |
| `attr` | `(key: []const u8, value: ?[]const u8) Attr` | Convenience for constructing an `Attr`. |
| `none` | `() Node` | Empty node. Returns `Node{ .fragment = &.{} }`. Useful as `else` branch. |

### Children Handling

The `children` parameter on `element()` and `fragment()` accepts:
- A tuple of `Node` values: `.{ node1, node2, node3 }`
- A slice: `[]const Node`

At comptime, tuples become static arrays. At runtime, tuples are copied into arena-allocated slices. Slices are used as-is (caller owns the memory).

### Checklist

- [ ] Define `Node` union type in `src/node.zig`
- [ ] Define `Element` struct in `src/node.zig`
- [ ] Define `Attr` struct in `src/node.zig`
- [ ] Implement `element()` in `src/constructors.zig` — @inComptime branch, tuple-to-slice conversion
- [ ] Implement `fragment()` in `src/constructors.zig` — @inComptime branch, tuple-to-slice conversion
- [ ] Implement `text()` — returns `Node{ .text = content }`
- [ ] Implement `raw()` — returns `Node{ .raw = content }`
- [ ] Implement `elementVoid()` — constructs element with `&.{}` children
- [ ] Implement `attr()` — returns `Attr{ .key, .value }`
- [ ] Implement `none()` — returns `Node{ .fragment = &.{} }`
- [ ] Test: `text()` stores content correctly
- [ ] Test: `raw()` stores content correctly
- [ ] Test: `fragment()` with tuple of nodes
- [ ] Test: `fragment()` with empty tuple
- [ ] Test: `element()` with tag, attrs, and children
- [ ] Test: `element()` with no attrs (empty slice)
- [ ] Test: `element()` with no children (empty tuple)
- [ ] Test: `elementVoid()` has zero children
- [ ] Test: `attr()` with string value
- [ ] Test: `attr()` with null value (boolean attribute)
- [ ] Test: `none()` returns empty fragment
- [ ] Test: nested elements — 3+ levels deep
- [ ] Test: mixed node types — element containing text, raw, fragment, and child elements
- [ ] Test: all non-allocating functions work at comptime
- [ ] Test: `element()` works at comptime with `undefined` allocator (static children)
- [ ] Test: `element()` works at runtime with arena (no dangling pointers)
- [ ] Test: component function returning `!Node` at runtime — children survive return

---

## Phase 2: Tree Utilities

Functions for inspecting and traversing trees. All operate on `Node` and are format-agnostic.

### Read-Only Utilities

| Function | Signature | Description |
|----------|-----------|-------------|
| `isEmpty` | `(node: Node) bool` | True if node has no meaningful content. Empty text, empty fragment, element with no children and empty tag. |
| `countNodes` | `(node: Node) usize` | Total number of nodes in the tree (including the root). |
| `depth` | `(node: Node) usize` | Maximum nesting depth. A leaf is depth 1. |
| `children` | `(node: Node) []const Node` | Direct children of a node. Text/raw return empty. Fragment returns its items. Element returns its children. |
| `hasTag` | `(node: Node, tag: []const u8) bool` | True if node is an element with the given tag. |
| `getAttr` | `(node: Node, key: []const u8) ?[]const u8` | Get attribute value by key. Returns null if node is not an element or attr not found. |

### Traversal

| Function | Signature | Description |
|----------|-----------|-------------|
| `walk` | `(node: Node, callback: fn(Node) void) void` | Depth-first pre-order traversal. Calls callback for every node. |
| `walkDepth` | `(node: Node, callback: fn(Node, usize) void) void` | Same as walk but callback receives current depth. |
| `find` | `(node: Node, predicate: fn(Node) bool) ?Node` | Return first node matching predicate (depth-first). |
| `findAll` | `(allocator: Allocator, node: Node, predicate: fn(Node) bool) ![]Node` | Collect all matching nodes. |
| `findByTag` | `(node: Node, tag: []const u8) ?Node` | Shorthand for find with tag check. |

### Transformation

| Function | Signature | Description |
|----------|-----------|-------------|
| `map` | `(allocator: Allocator, node: Node, transform: fn(Node) Node) !Node` | Return new tree with transform applied to every node. |
| `filter` | `(allocator: Allocator, node: Node, predicate: fn(Node) bool) !Node` | Return new tree with non-matching nodes removed. |
| `append` | `(allocator: Allocator, parent: Node, child: Node) !Node` | Return new node with child appended to parent's children. Parent must be element or fragment. |
| `prepend` | `(allocator: Allocator, parent: Node, child: Node) !Node` | Return new node with child prepended. |
| `setAttr` | `(allocator: Allocator, node: Node, key: []const u8, value: ?[]const u8) !Node` | Return new element with attribute added/updated. |
| `removeAttr` | `(allocator: Allocator, node: Node, key: []const u8) !Node` | Return new element with attribute removed. |

Note: transformations return **new** trees. Nodes are immutable once created.

### Checklist

- [ ] Implement `isEmpty()`
- [ ] Implement `countNodes()` — recursive count
- [ ] Implement `depth()` — recursive max depth
- [ ] Implement `children()` — direct children accessor
- [ ] Implement `hasTag()`
- [ ] Implement `getAttr()`
- [ ] Test: `isEmpty` on empty text, empty fragment, element with no children
- [ ] Test: `isEmpty` returns false for non-empty nodes
- [ ] Test: `countNodes` on single node (returns 1)
- [ ] Test: `countNodes` on nested tree
- [ ] Test: `countNodes` on fragment with multiple children
- [ ] Test: `depth` on leaf node (returns 1)
- [ ] Test: `depth` on nested tree (returns correct max)
- [ ] Test: `children` on element returns its children
- [ ] Test: `children` on text returns empty
- [ ] Test: `children` on fragment returns its items
- [ ] Test: `hasTag` matches correctly
- [ ] Test: `hasTag` returns false for non-element
- [ ] Test: `getAttr` finds attribute by key
- [ ] Test: `getAttr` returns null for missing key
- [ ] Test: `getAttr` returns null for non-element node
- [ ] Implement `walk()` — depth-first pre-order
- [ ] Implement `walkDepth()`
- [ ] Implement `find()`
- [ ] Implement `findAll()`
- [ ] Implement `findByTag()`
- [ ] Test: `walk` visits all nodes in correct order
- [ ] Test: `walk` on single node
- [ ] Test: `walkDepth` reports correct depth values
- [ ] Test: `find` returns first match
- [ ] Test: `find` returns null when no match
- [ ] Test: `findAll` collects all matches
- [ ] Test: `findAll` returns empty slice when no match
- [ ] Test: `findByTag` finds correct element
- [ ] Implement `map()` — returns transformed tree
- [ ] Implement `filter()` — returns filtered tree
- [ ] Implement `append()`
- [ ] Implement `prepend()`
- [ ] Implement `setAttr()`
- [ ] Implement `removeAttr()`
- [ ] Test: `map` transforms all nodes
- [ ] Test: `map` preserves tree structure
- [ ] Test: `filter` removes matching nodes
- [ ] Test: `filter` preserves non-matching subtrees
- [ ] Test: `append` adds child to element
- [ ] Test: `append` adds child to fragment
- [ ] Test: `prepend` adds child at start
- [ ] Test: `setAttr` adds new attribute
- [ ] Test: `setAttr` updates existing attribute
- [ ] Test: `removeAttr` removes attribute
- [ ] Test: `removeAttr` on missing key returns unchanged node
- [ ] Test: all read-only utilities work at comptime
- [ ] Test: transformation functions work with arena allocator

---

## Phase 3: Render Helpers

Shared utilities for format module authors building renderers. These are NOT renderers themselves — they are building blocks.

### Escape Writer

All write functions take `*std.io.Writer` — the Zig 0.15.2 concrete Writer type (not `anytype`). The old `GenericWriter` and `anytype` writer patterns are deprecated in std.

| Function | Signature | Description |
|----------|-----------|-------------|
| `writeEscaped` | `(writer: *Writer, content: []const u8, comptime escapeFn: fn(u8) ?[]const u8) Writer.Error!void` | Write content to writer, replacing characters based on escape function. `escapeFn` is `comptime` for optimization (switch inlined at compile time). |
| `writeRaw` | `(writer: *Writer, content: []const u8) Writer.Error!void` | Write content to writer without any escaping. Convenience wrapper. |
| `comptimeEscape` | `(comptime content: []const u8, comptime escapeFn: fn(u8) ?[]const u8) []const u8` | Comptime version. Returns escaped string at compile time. |

### Attr Rendering

| Function | Signature | Description |
|----------|-----------|-------------|
| `writeAttr` | `(writer: *Writer, a: Attr, comptime escapeFn: fn(u8) ?[]const u8) Writer.Error!void` | Write a single attribute: ` key="escaped_value"` or ` key` for boolean. |
| `writeAttrs` | `(writer: *Writer, attrs: []const Attr, comptime escapeFn: fn(u8) ?[]const u8) Writer.Error!void` | Write all attributes in order. |

### Duck-Typed Renderer (learned from goldmark, adapted to Zig idioms)

| Function | Signature | Description |
|----------|-----------|-------------|
| `renderWalk` | `(node: Node, renderer: anytype) !void` | Generic tree walker with duck-typed renderer. |

The renderer is `anytype` — any struct that has these methods:

```
elementOpen(tag: []const u8, attrs: []const Attr) !void
elementClose(tag: []const u8) !void
onText(content: []const u8) !void
onRaw(content: []const u8) !void
```

This is the same pattern as `std.sort.insertionContext(a, b, context)` — the context must have `lessThan()` and `swap()` methods. No function pointer struct needed. Zig's comptime duck-typing resolves method calls at compile time.

Benefits:
- Format modules define a renderer struct (e.g., `HtmlRenderer`) with these methods and a `*Writer` field.
- Tree traversal is written once in ztree. Format modules only implement the four callbacks.
- Fragment nodes are transparent — `renderWalk` recurses into children without calling any callback.
- Renderers can carry state (indentation depth, current context, etc.) because they're structs, not function pointers.
- Users can create custom renderers by defining their own struct with the four methods.

### Checklist

- [ ] Implement `writeEscaped()` — byte-by-byte with comptime escape function, writes to `*Writer`
- [ ] Implement `writeRaw()` — passthrough to `*Writer`
- [ ] Implement `comptimeEscape()` — comptime string escaping
- [ ] Implement `writeAttr()` — single attribute rendering to `*Writer`
- [ ] Implement `writeAttrs()` — multiple attribute rendering to `*Writer`
- [ ] Implement `renderWalk()` — generic tree walker with duck-typed `anytype` renderer
- [ ] Test: `writeEscaped` with escape function that replaces `<` → `&lt;`
- [ ] Test: `writeEscaped` with no replacements needed
- [ ] Test: `writeEscaped` with empty string
- [ ] Test: `writeEscaped` with `*Writer.fixed()` buffer
- [ ] Test: `writeRaw` passes through all content
- [ ] Test: `comptimeEscape` at comptime
- [ ] Test: `writeAttr` with string value
- [ ] Test: `writeAttr` with null value (boolean)
- [ ] Test: `writeAttr` escapes value content
- [ ] Test: `writeAttrs` with multiple attrs
- [ ] Test: `writeAttrs` with empty slice
- [ ] Test: `renderWalk` with mock renderer struct — visits element open/close in correct order
- [ ] Test: `renderWalk` with mock renderer — visits text and raw nodes
- [ ] Test: `renderWalk` — fragment is transparent (no open/close, just children)
- [ ] Test: `renderWalk` — nested elements, correct traversal order
- [ ] Test: `renderWalk` — void element (elementVoid — open, no close, no children)
- [ ] Test: `renderWalk` with TWO different mock renderers on the same tree (validates format agnosticism)

---

## Phase 4: Comptime Validation

Ensure everything works at compile time. This is critical — comptime is a core feature, not an afterthought.

### What Must Work at Comptime

- All non-allocating functions: `text()`, `raw()`, `elementVoid()`, `attr()`, `none()`
- `element(undefined, ...)` and `fragment(undefined, ...)` — `@inComptime()` branch uses static arrays, allocator is never accessed
- All read-only utilities: `isEmpty()`, `countNodes()`, `depth()`, `children()`, `hasTag()`, `getAttr()`
- Traversal: `walk()`, `find()` (when callback is comptime-known)
- Escape: `comptimeEscape()`
- Building a full tree at comptime — component functions called at comptime with `catch unreachable`

### What Only Works at Runtime

- `findAll()`, `map()`, `filter()`, `append()`, `prepend()`, `setAttr()`, `removeAttr()` — these allocate and need a runtime allocator
- `writeEscaped()`, `writeRaw()`, `writeAttr()`, `writeAttrs()` — these write to `*std.io.Writer` (runtime only)

### Checklist

- [ ] Verify: `text()` callable at comptime
- [ ] Verify: `raw()` callable at comptime
- [ ] Verify: `element(undefined, ...)` callable at comptime with tuple children
- [ ] Verify: `fragment(undefined, ...)` callable at comptime with tuple
- [ ] Verify: `elementVoid()` callable at comptime
- [ ] Verify: `attr()` callable at comptime
- [ ] Verify: `none()` callable at comptime
- [ ] Verify: nested tree construction at comptime (5+ levels, using `catch unreachable`)
- [ ] Verify: `isEmpty()` at comptime
- [ ] Verify: `countNodes()` at comptime
- [ ] Verify: `depth()` at comptime
- [ ] Verify: `children()` at comptime
- [ ] Verify: `hasTag()` at comptime
- [ ] Verify: `getAttr()` at comptime
- [ ] Verify: `walk()` at comptime with comptime callback
- [ ] Verify: `find()` at comptime with comptime predicate
- [ ] Verify: `comptimeEscape()` produces correct string at comptime
- [ ] Verify: comptime tree assigned to `const` has zero runtime cost
- [ ] Test: a complex comptime tree (layout with nav, main, footer, nested lists) is correctly structured

---

## File Structure

```
ztree/
├── build.zig
├── build.zig.zon
├── src/
│   ├── root.zig            # Public API — re-exports everything
│   ├── node.zig            # Node, Element, Attr type definitions
│   ├── constructors.zig    # element(), fragment(), text(), raw(), elementVoid(), attr(), none()
│   ├── walk.zig            # isEmpty, countNodes, depth, children, hasTag, getAttr,
│   │                       # walk, walkDepth, find, findAll, findByTag
│   ├── transform.zig       # map, filter, append, prepend, setAttr, removeAttr
│   └── render.zig          # writeEscaped, writeRaw, comptimeEscape,
│                           # writeAttr, writeAttrs, renderWalk (duck-typed)
└── README.md
```

---

## Public API Surface (root.zig)

Everything the user imports from `@import("ztree")`:

### Types
- `Node`
- `Element`
- `Attr`

### Construction Functions
- `element` — element node with children (takes `Allocator`)
- `fragment` — fragment node with children (takes `Allocator`)
- `text` — text node (no allocator)
- `raw` — raw node (no allocator)
- `elementVoid` — element with no children (no allocator)
- `attr` — attribute constructor (no allocator)
- `none` — empty node (no allocator)

### Read-Only Utilities
- `isEmpty`
- `countNodes`
- `depth`
- `children`
- `hasTag`
- `getAttr`

### Traversal
- `walk`
- `walkDepth`
- `find`
- `findAll`
- `findByTag`

### Transformation
- `map`
- `filter`
- `append`
- `prepend`
- `setAttr`
- `removeAttr`

### Render Helpers (take *std.io.Writer)
- `writeEscaped`
- `writeRaw`
- `comptimeEscape`
- `writeAttr`
- `writeAttrs`
- `renderWalk` — duck-typed `anytype` renderer

---

## Definition of Done

ztree core is done when:

- [ ] All types compile and work at both comptime and runtime
- [ ] All construction functions implemented and tested (`element`, `fragment`, `text`, `raw`, `elementVoid`, `attr`, `none`)
- [ ] `element()` and `fragment()` work at comptime (with `undefined` allocator) and runtime (with arena)
- [ ] Children lifetime verified: component functions returning `!Node` at runtime — no dangling pointers
- [ ] All read-only utilities implemented and tested
- [ ] All traversal functions implemented and tested
- [ ] All transformation functions implemented and tested
- [ ] All render helpers use `*std.io.Writer` and are tested
- [ ] `renderWalk` with duck-typed renderer tested with two different mock renderers
- [ ] All comptime verification tests pass
- [ ] README documents every public function with usage examples
- [ ] `build.zig.zon` is valid and the package is importable by other projects
- [ ] Zero dependencies beyond `std`

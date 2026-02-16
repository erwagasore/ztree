# ztree (core) — Implementation Checklist

Format-agnostic document tree library for Zig. The foundation that every format library depends on.

---

## Overview

ztree provides:
- A `Node` tagged union representing any document structure
- Builder functions to construct trees
- Control flow helpers for conditional and list rendering (learned from gomponents)
- Tree traversal and transformation utilities
- Render helpers for format module authors, including a callback-based tree walker (learned from goldmark)

It has zero opinions about HTML, Markdown, JSON, or any specific format. Format modules depend on ztree and add typed helpers + renderers.

### Prior Art

- **gomponents (Go):** `If()`, `Map()`, `Group` helpers for control flow. Opaque `Node` interface. We adopt the helpers but keep an inspectable tree.
- **typed-html (Rust):** `VNode` enum (Text, UnsafeText, Element) — nearly identical to our `Node`. Validates our type design.
- **goldmark (Go):** Per-node-kind renderer registration via callbacks. Clean AST/renderer separation. We adopt `renderWalk` with duck-typed `anytype` renderer.
- **elem-go (Go):** Attrs as separate argument from children. `map[string]string` for attrs. Validates our decision to keep attrs separate and use a typed struct in format modules.

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

## Phase 1: Types and Builder

Define the core types, the Builder struct, and free functions.

### Critical Zig Constraint: Children Lifetime

**Tested and confirmed:** Tuples passed to functions live on the callee's stack. Returning a `Node` with children pointing to a local tuple causes **segfaults at runtime** (dangling pointer). This was verified with Zig 0.15.2.

**Solution:** The `Builder` struct carries an `Allocator`. At runtime, `element()` and `fragment()` allocate children arrays via the arena. At comptime (detected via `@inComptime()`), children arrays become static constants — no allocator needed.

Functions that don't create children arrays (`text`, `raw`, `none`, `elementVoid`, `attr`, `if_`) are free functions returning `Node` directly (not `!Node`).

### Builder Struct

```
Builder = struct {
    allocator: Allocator,

    fn init(allocator: Allocator) Builder
    fn element(self, tag: []const u8, attrs: []const Attr, children: anytype) !Node
    fn fragment(self, children: anytype) !Node
}
```

`element()` and `fragment()` branch on `@inComptime()`:
- **Comptime:** `const arr: [N]Node = children; return .{ .children = &arr };` — static storage.
- **Runtime:** `const slice = try self.allocator.alloc(Node, N); ...` — arena allocation.

At comptime, callers use `Builder.init(undefined)` — the allocator field is never accessed.

### Free Functions (no allocator, return Node not !Node)

| Function | Signature | Description |
|----------|-----------|-------------|
| `text` | `(content: []const u8) Node` | Text node. Renderer escapes it. |
| `raw` | `(content: []const u8) Node` | Raw node. Renderer passes it through. |
| `elementVoid` | `(tag: []const u8, attrs: []const Attr) Node` | Element with no children. Empty static slice — no allocation. |
| `attr` | `(key: []const u8, value: ?[]const u8) Attr` | Convenience for constructing an `Attr`. |
| `none` | `() Node` | Empty node. Returns `Node{ .fragment = &.{} }`. Useful as else branch. |
| `if_` | `(condition: bool, node: Node) Node` | Returns `node` when true, `none()` when false. Eagerly evaluated. |

### Children Handling

The `children` parameter on `Builder.element()` and `Builder.fragment()` accepts:
- A tuple of `Node` values: `.{ node1, node2, node3 }`
- A slice: `[]const Node`

At comptime, tuples become static arrays. At runtime, tuples are copied into arena-allocated slices. Slices are used as-is (caller owns the memory).

### Checklist

- [ ] Define `Node` union type in `src/node.zig`
- [ ] Define `Element` struct in `src/node.zig`
- [ ] Define `Attr` struct in `src/node.zig`
- [ ] Implement `Builder` struct in `src/builders.zig`
- [ ] Implement `Builder.init()` — stores allocator
- [ ] Implement `Builder.element()` — @inComptime branch, tuple-to-slice conversion
- [ ] Implement `Builder.fragment()` — @inComptime branch, tuple-to-slice conversion
- [ ] Implement `text()` — returns `Node{ .text = content }`
- [ ] Implement `raw()` — returns `Node{ .raw = content }`
- [ ] Implement `elementVoid()` — constructs element with `&.{}` children
- [ ] Implement `attr()` — returns `Attr{ .key, .value }`
- [ ] Implement `none()` — returns `Node{ .fragment = &.{} }`
- [ ] Implement `if_()` — returns node or none based on condition
- [ ] Test: `text()` stores content correctly
- [ ] Test: `raw()` stores content correctly
- [ ] Test: `Builder.fragment()` with tuple of nodes
- [ ] Test: `Builder.fragment()` with empty tuple
- [ ] Test: `Builder.element()` with tag, attrs, and children
- [ ] Test: `Builder.element()` with no attrs (empty slice)
- [ ] Test: `Builder.element()` with no children (empty tuple)
- [ ] Test: `elementVoid()` has zero children
- [ ] Test: `attr()` with string value
- [ ] Test: `attr()` with null value (boolean attribute)
- [ ] Test: `none()` returns empty fragment
- [ ] Test: `if_` with true condition returns the node
- [ ] Test: `if_` with false condition returns none
- [ ] Test: nested elements — 3+ levels deep
- [ ] Test: mixed node types — element containing text, raw, fragment, and child elements
- [ ] Test: all free functions work at comptime
- [ ] Test: `Builder.init(undefined)` works at comptime
- [ ] Test: `Builder.element()` works at comptime (static children)
- [ ] Test: `Builder.element()` works at runtime with arena (no dangling pointers)
- [ ] Test: component function returning `!Node` at runtime — children survive return

---

## Phase 2: Control Flow Helpers

Learned from gomponents: `Map` and conditional helpers are indispensable for real-world usage. These are format-agnostic and belong in the core.

**`iff()` was dropped.** Zig has no closures — `fn() Node` cannot capture surrounding scope variables. Native Zig `if` expressions are more powerful, support payload capture, and are idiomatic:

```
// Native Zig if — preferred, handles optionals:
h.div(.{}, .{
    if (user) |u| try profileCard(b, u) else ztree.none(),
})

// if_ — convenience for simple booleans:
h.div(.{}, .{
    ztree.if_(show_sidebar, sidebar),
})
```

### Builder.map_

| Function | Signature | Description |
|----------|-----------|-------------|
| `Builder.map_` | `(self, comptime T: type, items: []const T, comptime renderFn: fn (T) Node) !Node` | Maps a slice to a fragment. Each item transformed via `renderFn`. Allocates children array. |

`renderFn` is `comptime fn(T) Node` — covers the common case (no context needed). For cases requiring builder access or other context, use a `for` loop:

```
// Simple mapping (use map_):
try b.map_([]const u8, &names, renderName)

// Complex mapping (use for loop):
const items = try arena.alloc(Node, data.len);
for (data, 0..) |item, i| {
    items[i] = try renderItem(b, item);
}
const list = try h.ul(.{}, items);
```

`none()` and `if_()` were moved to Phase 1 (free functions, no allocator needed).

### Checklist

- [ ] Implement `Builder.map_()` — maps slice through comptime function, returns fragment
- [ ] Test: `map_` with empty slice returns empty fragment
- [ ] Test: `map_` with items returns fragment with correct children
- [ ] Test: `map_` preserves order
- [ ] Test: `map_` composes inside element children

---

## Phase 3: Tree Utilities

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

## Phase 4: Render Helpers

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

## Phase 5: Comptime Validation

Ensure everything works at compile time. This is critical — comptime is a core feature, not an afterthought.

### What Must Work at Comptime

- All free functions: `text()`, `raw()`, `elementVoid()`, `attr()`, `none()`, `if_()`
- `Builder.init(undefined)` — allocator never accessed at comptime
- `Builder.element()` and `Builder.fragment()` — `@inComptime()` branch uses static arrays
- All read-only utilities: `isEmpty()`, `countNodes()`, `depth()`, `children()`, `hasTag()`, `getAttr()`
- Traversal: `walk()`, `find()` (when callback is comptime-known)
- Escape: `comptimeEscape()`
- Building a full tree at comptime — component functions called at comptime with `catch unreachable`

### What Only Works at Runtime

- `findAll()`, `map()`, `filter()`, `append()`, `prepend()`, `setAttr()`, `removeAttr()` — these allocate and need a runtime allocator
- `Builder.map_()` — allocates a children slice, needs a runtime allocator
- `writeEscaped()`, `writeRaw()`, `writeAttr()`, `writeAttrs()` — these write to `*std.io.Writer` (runtime only)

### Checklist

- [ ] Verify: `text()` callable at comptime
- [ ] Verify: `raw()` callable at comptime
- [ ] Verify: `Builder.init(undefined)` at comptime
- [ ] Verify: `Builder.fragment()` callable at comptime with tuple
- [ ] Verify: `Builder.element()` callable at comptime with tuple children
- [ ] Verify: `elementVoid()` callable at comptime
- [ ] Verify: `attr()` callable at comptime
- [ ] Verify: `none()` callable at comptime
- [ ] Verify: `if_()` callable at comptime
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
│   ├── builders.zig        # Builder struct, text(), raw(), elementVoid(), attr(), none(), if_()
│   ├── helpers.zig         # Builder.map_() — control flow helpers needing allocator
│   ├── walk.zig            # isEmpty, countNodes, depth, children, hasTag, getAttr,
│   │                       # walk, walkDepth, find, findAll, findByTag
│   ├── transform.zig       # map, filter, append, prepend, setAttr, removeAttr
│   └── render.zig          # writeEscaped, writeRaw, comptimeEscape,
│                           # writeAttr, writeAttrs, renderWalk (duck-typed)
├── tests/
│   ├── node_test.zig       # Type construction tests
│   ├── builders_test.zig   # Builder function tests
│   ├── helpers_test.zig    # Control flow helper tests
│   ├── walk_test.zig       # Read-only utility and traversal tests
│   ├── transform_test.zig  # Transformation function tests
│   ├── render_test.zig     # Render helper tests
│   └── comptime_test.zig   # All comptime verification tests
└── README.md
```

---

## Public API Surface (root.zig)

Everything the user imports from `@import("ztree")`:

### Types
- `Node`
- `Element`
- `Attr`

### Builder
- `Builder` — struct with `init`, `element`, `fragment`, `map_` methods

### Free Functions (no allocator)
- `text`
- `raw`
- `elementVoid`
- `attr`
- `none`
- `if_`

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
- [ ] Builder struct works: `init`, `element`, `fragment`, `map_` — comptime and runtime
- [ ] All free functions implemented and tested (`text`, `raw`, `none`, `elementVoid`, `attr`, `if_`)
- [ ] Children lifetime verified: component functions returning `!Node` at runtime — no dangling pointers
- [ ] All read-only utilities implemented and tested
- [ ] All traversal functions implemented and tested
- [ ] All transformation functions implemented and tested
- [ ] All render helpers use `*std.io.Writer` and are tested
- [ ] `renderWalk` with duck-typed renderer tested with two different mock renderers
- [ ] All comptime verification tests pass (Builder.init(undefined) at comptime)
- [ ] README documents every public function with usage examples
- [ ] `build.zig.zon` is valid and the package is importable by other projects
- [ ] Zero dependencies beyond `std`

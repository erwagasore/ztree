# AGENTS — ztree

Operating rules for humans + AI.

## Workflow

- Never commit to `main`/`master`.
- Always start on a new branch.
- Only push after the user approves.
- Merge via PR.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/).

- fix → patch
- feat → minor
- feat! / BREAKING CHANGE → major
- chore, docs, refactor, test, ci, style, perf → no version change

## Releases

- Semantic versioning.
- Versions derived from Conventional Commits.
- Release performed locally via `/create-release` (no CI required).
- Manifest (if present) is source of truth.
- Tags: vX.Y.Z

## Repo map

- `LICENSE` — MIT licence
- `.gitignore` — Zig build artefacts exclusions
- `build.zig` — Zig build configuration (library + tests)
- `build.zig.zon` — Zig package manifest
- `src/` — library source
  - `root.zig` — public API re-exporting all modules
  - `node.zig` — `Node`, `Element` (with `getAttr`/`hasAttr`), `Attr` type definitions
  - `create.zig` — construction functions: `element()`, `closedElement()`, `fragment()`, `text()`, `raw()`, `attr()`, `none()`; `buildAttrs` with struct literal, tuple, `?Attr` slice, and optional value support
  - `render.zig` — `WalkAction`, `renderWalk()` generic tree walker, `Walker`/`walker()` type-erased re-entrant walker for format library authors (consumer side)
  - `tree_builder.zig` — `TreeBuilder` imperative tree builder for parser authors (producer side)
  - `test_util.zig` — shared test utilities (`TraceRenderer`)
- `docs/` — project documentation

## Merge strategy

- Prefer squash merge.
- PR title must be a valid Conventional Commit.

## Definition of done

- Works locally.
- Tests updated if behaviour changed.
- CHANGELOG updated when user-facing.
- No secrets committed.

## Orientation

- **Entry point**: `src/root.zig` — public API re-exporting all modules.
- **Domain**: format-agnostic document tree library for Zig. Provides `Node`/`Element`/`Attr` types, construction functions, tree traversal via `renderWalk` (consumer side), and imperative tree construction via `TreeBuilder` (producer side).
- **Language**: Zig (0.15.x). Zero dependencies beyond `std`.
- **Examples**: see format library repos (ztree-html, ztree-md) for usage examples.

## Design principles

### Prior art

- **typed-html (Rust):** `VNode` enum (Text, UnsafeText, Element) — validates our `Node` tagged union design.
- **goldmark (Go):** Per-node-kind renderer registration via callbacks — adopted as `renderWalk` with duck-typed `anytype` renderer (same pattern as `std.sort.insertionContext` where the context must have `lessThan()` and `swap()` methods).
- **elem-go (Go):** Attrs as separate argument from children — adopted: attrs and children are distinct parameters on `element()`.

### Core principles

- **Explicit allocation, ergonomic construction.** `element()`, `closedElement()`, and `fragment()` take an `Allocator` to convert struct attrs and tuple children into slices. Same pattern as `std.fmt.allocPrint` — the caller owns the allocator, arena recommended. Leaf constructors (`text`, `raw`, `none`, `attr`) are pure and need no allocator. Trade-off: we gave up comptime tree construction (v0.1) for struct attrs (`.{ .class = "card" }`) and tuple children (`.{text("hi")}`).
- **One way to do a thing.** No aliases, no overloads, no convenience wrappers that duplicate functionality. Follows Zig's design philosophy.
- **Functions are components.** A function that takes data and returns `!Node` is a component. No traits, no registration, no framework — just call the function inside the tree. Composability comes from the language, not the library.
- **Duck-typed renderer.** `renderWalk` accepts `anytype` — any struct with `elementOpen` (returns `WalkAction`), `elementClose`, `onText`, `onRaw` methods. Tree traversal is written once in ztree; format modules only implement the four callbacks. `elementOpen` returns `.@"continue"` for simple wrappers (free traversal) or `.skip_children` to handle an element entirely in `elementOpen` (no child recursion, no `elementClose` call). Renderers carry state (indentation, context) because they're structs, not function pointers. Fragment nodes are transparent — `renderWalk` recurses into children without calling any callback.
- **Type-erased re-entrant walker.** `Walker`/`walker()` let `.skip_children` handlers walk subtrees back through the same rendering pipeline. The function pointer boundary (`fn(*anyopaque, Node) anyerror!void`) breaks Zig's error-set inference cycle that otherwise forces `anyerror` annotations on renderer methods. Simple renderers ignore it; complex ones (e.g. Markdown list rendering) store a `Walker` field and call `self.walker.walk(child)`.
- **Symmetric producer/consumer.** `renderWalk` (consumer) decomposes a tree into events. `TreeBuilder` (producer) composes events into a tree. Every renderer reuses `renderWalk`; every parser reuses `TreeBuilder`. Format-specific knowledge stays in format libraries.

### Rejected alternatives

These were considered and intentionally dropped. Don't re-propose without new evidence.

- **Builder struct.** Wrapping an `Allocator` in a `Builder` struct hides allocation and adds a type. Idiomatic Zig passes allocators explicitly. Dropped.
- **`if_` helper.** `if_(condition, node) Node` is strictly weaker than native Zig `if`/`else`, which handles optionals with payload capture. Use `if (user) |u| profileCard(u) else none()`. Dropped.
- **`map_` helper.** `map_(allocator, T, items, renderFn) !Node` breaks the moment you need an allocator, an index, or any context — Zig has no closures. Use an explicit `for` loop. Dropped.
- **`cls()` helper.** `cls(a, &.{"btn", if (active) "active" else null})` joins class parts. Shorter than ternary only with 3+ conditional parts — rare in practice. CSS class joining is format-specific; belongs in `ztree-html` if anywhere, not the core lib. Dropped.

### Children lifetime

Construction functions allocate slices for attrs and children via the provided allocator. An arena is the natural fit — allocate everything, use the tree, free in one shot.

For dynamic children (loops, database rows), allocate the slice yourself and pass it as children:

```zig
fn profileCard(a: Allocator, user: User) !Node {
    return element(a, "div", .{ .class = "card" }, .{
        try element(a, "h2", .{}, .{text(user.name)}),
        try closedElement(a, "img", .{ .src = user.avatar }),
    });
}

fn userList(a: Allocator, users: []const User) !Node {
    const cards = try a.alloc(Node, users.len);
    for (users, 0..) |user, i| {
        cards[i] = try profileCard(a, user);
    }
    return element(a, "div", .{ .class = "users" }, cards);
}
```

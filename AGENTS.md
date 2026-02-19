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

- `DESIGN.md` — implementation checklist covering types, construction functions, tree utilities, render helpers, and comptime validation
- `LICENSE` — MIT licence
- `.gitignore` — Zig build artefacts exclusions
- `build.zig` — Zig build configuration
- `build.zig.zon` — Zig package manifest
- `src/` — library source
  - `root.zig` — public API re-exporting all modules
  - `node.zig` — `Node`, `Element`, `Attr` type definitions
  - `create.zig` — construction functions: `element()`, `closedElement()`, `fragment()`, `text()`, `raw()`, `attr()`, `none()`
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
- **Domain**: format-agnostic document tree library for Zig. Provides `Node`/`Element`/`Attr` types, construction functions, tree traversal/transformation utilities, and render helpers for format module authors.
- **Language**: Zig (0.15.x). Zero dependencies beyond `std`.

## Design principles

### Prior art

- **typed-html (Rust):** `VNode` enum (Text, UnsafeText, Element) — validates our `Node` tagged union design.
- **goldmark (Go):** Per-node-kind renderer registration via callbacks — adopted as `renderWalk` with duck-typed `anytype` renderer (same pattern as `std.sort.insertionContext` where the context must have `lessThan()` and `swap()` methods).
- **elem-go (Go):** Attrs as separate argument from children — adopted: attrs and children are distinct parameters on `element()`.

### Core principles

- **Pure functions, caller-managed allocation.** All construction functions are pure — data in, `Node` out, no side effects, no allocator. When the caller has dynamic content (database rows, user input), they allocate the children slice themselves and pass it in. Same pattern as `std.fmt`: `comptimePrint` needs no allocator, `allocPrint` takes one at the call site. Functions that don't allocate don't take an allocator.
- **One way to do a thing.** No aliases, no overloads, no convenience wrappers that duplicate functionality. Follows Zig's design philosophy.
- **Comptime for free.** Because construction functions are infallible and take no allocator, they work at comptime with no special code paths. Static trees are embedded in the binary at zero runtime cost.
- **Duck-typed renderer.** `renderWalk` accepts `anytype` — any struct with `elementOpen`, `elementClose`, `onText`, `onRaw` methods. Tree traversal is written once in ztree; format modules only implement the four callbacks. Renderers carry state (indentation, context) because they're structs, not function pointers. Fragment nodes are transparent — `renderWalk` recurses into children without calling any callback.

### Rejected alternatives

These were considered and intentionally dropped. Don't re-propose without new evidence.

- **Builder struct.** Wrapping an `Allocator` in a `Builder` struct hides allocation and adds a type. Idiomatic Zig passes allocators explicitly. Dropped.
- **`if_` helper.** `if_(condition, node) Node` is strictly weaker than native Zig `if`/`else`, which handles optionals with payload capture. Use `if (user) |u| profileCard(u) else none()`. Dropped.
- **`map_` helper.** `map_(allocator, T, items, renderFn) !Node` breaks the moment you need an allocator, an index, or any context — Zig has no closures. Use an explicit `for` loop. Dropped.
- **Tuple children (`anytype`).** Accepting both tuples and slices for `children` required `resolveChildren` with `@inComptime()` branching, `inline for`, and an allocator on `element()`/`fragment()`. Dropped in favour of `[]const Node` only — one input type, infallible functions, consistent with how `attrs` works.

### Children lifetime

Anonymous array literals (`&.{ ... }`) with comptime-known values live in static memory. For runtime values, or when returning a `Node` from a function, children slices must be arena-allocated to avoid dangling pointers:

```zig
// Static tree — no allocation needed, children are comptime-known:
const page = element("div", &.{}, &.{
    element("h1", &.{}, &.{ text("Hello") }),
    closedElement("hr", &.{}),
});

// Component function — arena-allocate children that must outlive the scope:
fn profileCard(a: Allocator, user: User) !Node {
    const kids = try a.alloc(Node, 2);
    kids[0] = element("h2", &.{}, &.{ text(user.name) });
    kids[1] = closedElement("img", &.{attr("src", user.avatar)});
    return element("div", &.{attr("class", "card")}, kids);
}
```

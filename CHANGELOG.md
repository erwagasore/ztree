# Changelog

All notable changes to this project will be documented in this file.

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

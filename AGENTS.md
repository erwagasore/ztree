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

- `DESIGN.md` — full implementation checklist covering types, builder, helpers, tree utilities, render helpers, and comptime validation
- `LICENSE` — MIT licence
- `.gitignore` — Zig build artefacts exclusions
- `src/` — library source (planned: `root.zig`, `node.zig`, `builders.zig`, `helpers.zig`, `walk.zig`, `transform.zig`, `render.zig`)
- `tests/` — test suite (planned: per-module tests + `comptime_test.zig`)
- `build.zig` — Zig build configuration (planned)
- `build.zig.zon` — Zig package manifest (planned)

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
- **Domain**: format-agnostic document tree library for Zig. Provides `Node`/`Element`/`Attr` types, builder functions, tree traversal/transformation utilities, and render helpers for format module authors.
- **Language**: Zig (0.15.x). Zero dependencies beyond `std`.

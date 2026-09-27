# Agent guide

`rbxm-kit` is a standalone Lune toolkit for creating, inspecting, checking, and
diffing Roblox `.rbxm` models outside Studio. It is not part of any game build:
game repositories commit the `.rbxm` files it produces, never these scripts.

## Layout

| Path | Contents |
| --- | --- |
| `src/build.luau` | Declarative instance construction (`Build.new`, `Build.part`, `Build.model`). |
| `src/place.luau` | Relative placement over world-space bounds (`onTopOf`, `against`, `grid`, `ring`, `lookAt`). |
| `src/check.luau` | Offline checks: overlaps, unanchored parts, extent and part budgets. |
| `src/model_io.luau` | Read and write models and places, resolving Git LFS pointers. |
| `src/properties.luau` | Which properties are surfaced by diffs and dumps. |
| `src/kit.luau` | Entry point for recipes. |
| `bin/` | Commands: `inspect`, `scripts`, `check`, `diff`, `textconv`, `install_diff`. |
| `recipes/` | Optional saved generator scripts, one model per recipe. |
| `tests/run.luau` | The kit's own tests. |

## Working rules

- Run `mise run test` after changing anything in `src` or `bin`.
- Commands take paths relative to the caller's working directory, so they can be
  run from a game repository as `lune run <rbxm-kit>/bin/<command> ...`.
- Recipes take the output path as their first argument and write nothing else.
  A recipe runs `Check.run` and refuses to write a model that fails it.
- Position geometry with `Place` helpers rather than hand-computed coordinates.
- Use `Place.lookAt`, not `CFrame.lookAt`: Lune 0.10.5 returns a reversed look
  vector when facing along the Z axis.
- `Position` is not a stored property under Lune. `Build` translates it into a
  `CFrame`; read positions through `part.CFrame.Position`.
- `Place` bounds are axis-aligned. Relative placement is exact for axis-aligned
  geometry and uses the outer box for rotated parts.
- Checks are heuristics, not physics. Report which checks ran and leave visual
  and gameplay verification to a human playtest.
- Never execute scripts stored in a model. Commands read `Source` as text only.

## Commits

- Use concise, lowercase, imperative titles without Conventional Commit prefixes
  or trailing punctuation. Omit commit bodies unless requested.

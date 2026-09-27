# Agent guide

`rbxm-kit` is a standalone Lune toolkit for creating, inspecting, checking, and
diffing Roblox `.rbxm` models outside Studio. It is not part of any game build:
game repositories commit the `.rbxm` files it produces, never these scripts.

It ships as a public repository with standalone binaries on GitHub releases.
Game repositories install a pinned version through mise:
`"github:okeanskiy/rbxm-kit" = "<version>"`.

## Layout

| Path | Contents |
| --- | --- |
| `src/build.luau` | Declarative instance construction (`Build.new`, `Build.part`, `Build.model`). |
| `src/place.luau` | Relative placement over world-space bounds (`onTopOf`, `against`, `grid`, `ring`, `lookAt`). |
| `src/check.luau` | Offline checks: overlaps, unanchored parts, extent and part budgets. |
| `src/model_io.luau` | Read and write models and places, resolving Git LFS pointers. |
| `src/properties.luau` | Which properties are surfaced by diffs and dumps. |
| `src/kit.luau` | Entry point for recipes. |
| `src/commands/` | One module per CLI command, each returning `function(args)`. |
| `bin/rbxm-kit.luau` | The CLI entry point and command dispatcher. |
| `tools/bundle.luau`, `tools/build.luau` | Flatten the CLI into one file and compile it with `lune build`. |
| `recipes/` | Optional saved generator scripts, one model per recipe. |
| `tests/run.luau` | The kit's own tests. |

## Working rules

- Run `mise run test` after changing anything in `src` or `bin`.
- Commands take paths relative to the caller's working directory. From source,
  run `lune run bin/rbxm-kit <command> ...`; released, run `rbxm-kit <command> ...`.
- `lune build` embeds only its input file, so the CLI and everything it reaches
  must use string-literal relative requires that `tools/bundle.luau` can inline.
  The binary test in `tests/run.luau` fails if bundling breaks.
- Releasing: bump `VERSION` in `bin/rbxm-kit.luau`, commit, and push a matching
  `v<version>` tag. `.github/workflows/release.yml` refuses a mismatched tag.
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

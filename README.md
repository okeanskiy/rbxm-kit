# rbxm-kit

Build, check, inspect, and diff Roblox `.rbxm` models outside Studio.

rbxm-kit is a [Lune](https://lune-org.github.io/docs) toolkit for projects whose
Roblox instances live in the filesystem, such as fully managed Rojo projects. It
never executes scripts stored in a model; script source is only read as text.

- **`rbxm-kit` CLI**: inspect a model, check it for mistakes, summarize the
  changes between two versions, and render it as text so `git diff` is readable.
- **Library and recipes**: build models from code with declarative instance
  construction and relative placement, then write them out as `.rbxm` files.

## Install

rbxm-kit ships as a standalone binary for Windows, Linux, and macOS on the
[releases page](https://github.com/okeanskiy/rbxm-kit/releases). With
[mise](https://mise.jdx.dev/), pin it in your project's `mise.toml`:

```toml
[tools]
"github:okeanskiy/rbxm-kit" = "0.1.1"
```

Then run `mise install`. Without mise, download the archive for your platform
from a release and put `rbxm-kit` on your `PATH`.

## Commands

| Command | Purpose |
| --- | --- |
| `rbxm-kit inspect <model>` | Print the instance hierarchy and counts per class. |
| `rbxm-kit scripts <model> [--full]` | Print the source of every script in a model. |
| `rbxm-kit check <model> [options]` | Report overlapping parts, unanchored parts, and budget overruns. |
| `rbxm-kit diff <before> <after> [--full]` | Summarize hierarchy, property, tag, attribute, and script changes. |
| `rbxm-kit diff --git <before-ref> <after-ref> <path>` | The same, for one file at two Git revisions. |
| `rbxm-kit textconv <model>` | Render a model as stable text, for Git's diff driver. |
| `rbxm-kit install-diff <repo> [--command ...]` | Configure a repository to diff models as text. |

Every command accepts `--help`. Commands read `.rbxm`, `.rbxmx`, `.rbxl`, and
`.rbxlx` files, and resolve Git LFS pointers from the local LFS store.

### Checking models

```sh
rbxm-kit check src/Workspace/Map/Pavilion.rbxm
rbxm-kit check build.rbxl --max-extent 512 --max-parts 5000
```

`check` exits non-zero when it finds issues, so it can run in CI. It works on
axis-aligned bounding boxes: parts that touch or share a face are fine, while
parts that sink into each other are reported. Pass `--tolerance <studs>` to
allow shallow overlaps, or `--allow-unanchored` for models with physics. Checks
are heuristics, not a physics simulation, so a playtest remains the final word.

## Readable model diffs in Git

`.rbxm` files are binary, and are often stored in Git LFS, so Git normally shows
only "Binary files differ" or an LFS pointer. rbxm-kit can act as a Git diff
driver so `git diff`, `git show`, and `git log -p` print the model as text:

```diff
-      .Material = Enum.Material.WoodPlanks
+      .Material = Enum.Material.Slate
-      .Size = 16, 1, 16
+      .Size = 18, 1, 18
+    Part "Lantern"
+      .Material = Enum.Material.Neon
+        PointLight "PointLight"
+          .Range = 18
```

This changes how models are displayed, not how they are stored: LFS keeps
storing them as before.

1. Route model files to the driver in your tracked `.gitattributes`:

   ```gitattributes
   *.rbxm filter=lfs diff=rbxm merge=lfs -text
   *.rbxl filter=lfs diff=rbxm merge=lfs -text
   ```

2. Configure each clone once. This writes to the clone's local Git config, not
   a tracked file, so every contributor runs it themselves:

   ```sh
   rbxm-kit install-diff .
   ```

   If your project pins rbxm-kit with mise, register the pinned version instead,
   ideally from a mise task so contributors run a single command:

   ```toml
   [tasks."setup:rbxm-diff"]
   run = "rbxm-kit install-diff . --command mise exec -- rbxm-kit textconv"
   ```

   `--command` takes every remaining argument, so it needs no quoting.

Rerun `install-diff` after upgrading rbxm-kit; it also clears Git's cached
renderings. Clones that skip this step see the same diffs as before. GitHub's
web interface does not run local diff drivers.

## Building models from code

Recipes are Lune scripts that build a model with the library in `src/` and write
it to a `.rbxm` file. The model is what gets committed to a game repository; the
recipe stays with the kit so the model can be regenerated or tweaked later.

```luau
local Kit = require("../src/kit")
local Build, Place, Check, ModelIo = Kit.Build, Kit.Place, Kit.Check, Kit.ModelIo
local Vector3 = Kit.Vector3

local floor = Build.part({ Name = "Floor", Size = Vector3.new(14, 1, 14) })
Place.moveTo(floor, Vector3.new(0, 0.5, 0))

local crate = Build.part({ Name = "Crate", Size = Vector3.new(2, 2, 2) })
Place.onTopOf(crate, floor)

local model = Build.model("Storage", { floor, crate }, { Tags = { "Storage" } })
assert(#Check.run({ model }) == 0, "model failed its checks")
ModelIo.write("out/storage.rbxm", { model })
```

| Module | Provides |
| --- | --- |
| `Build` | `new(className, props, children)`, plus `part`, `wedge`, `model`, and `folder` with sensible defaults. `Attributes` and `Tags` props set attributes and tags; `Position` sets a part's CFrame position. |
| `Place` | Placement relative to world-space bounds: `onTopOf`, `against(side, gap)`, `moveTo`, `moveBy`, `offset`, `grid`, `ring`, `lookAt`, `snap`. |
| `Check` | `run(roots, options)` returns overlap, anchoring, extent, and budget issues. |
| `ModelIo` | `read` and `write` for models and places, Git revision reads, and LFS pointer resolution. |

Recipes run from a clone of this repository:

```sh
lune run recipes/example_shelter out/example_shelter.rbxm
```

Relative placement is exact for axis-aligned geometry and uses the outer
bounding box for rotated parts.

## Lune caveats

- Use `Place.lookAt` instead of `CFrame.lookAt`. In Lune 0.10.5,
  `CFrame.lookAt` returns a reversed look vector when facing along the Z axis.
- `Position` and `Orientation` are not stored properties outside the engine.
  `Build` translates `Position` into a CFrame; read positions with
  `part.CFrame.Position`.
- Engine methods such as `PivotTo` are unavailable, so `Place` moves models by
  moving their parts.

## Development

Tools are pinned in `mise.toml`.

```sh
mise install
mise run test          # the kit's tests, including a standalone binary build
mise run format        # format with StyLua
lune run bin/rbxm-kit  # run the CLI from source
lune run tools/build   # build a standalone binary into out/build/
```

`lune build` embeds only its input file, so `tools/bundle.luau` first inlines
every module the CLI requires. Keep requires as string-literal relative paths so
the bundler can follow them.

To release, bump `VERSION` in `bin/rbxm-kit.luau`, commit, and push a matching
tag such as `v0.1.2`. The release workflow tests, builds every platform, and
publishes the archives with checksums. It refuses a tag that does not match
`VERSION`.

# Terrain prototype

Baseline proving the stack end to end: the Animosis Engine fork + Terrain3D +
a fixed-extent region, plus the dedicated terrain workspace.

## Open it

```
"S:\Animosis Studio\engine\animosis-engine\bin\animosis.windows.editor.x86_64.exe" ^
  --path "S:\Animosis Studio\Animosis Studio\projects\terrain-proto" --editor
```

Click the **Terrain** tab. The workspace covers the entire editor — menu bar,
tab strip, docks and bottom panel. **Exit** (top right) or **Escape** returns
to the engine.

## Dependency — not in git

`addons/terrain_3d/` is ~51 MB of prebuilt binaries and is deliberately
gitignored. Binaries that size never leave a git history once committed.

| | |
|---|---|
| Version | **v1.0.2-stable** |
| Licence | MIT |
| Source | https://github.com/TokisanGames/Terrain3D |
| Download | https://github.com/TokisanGames/Terrain3D/releases/download/v1.0.2-stable/Terrain3D_v1.0.2-stable.zip |

Extract the archive's `addons/` directory into this project root. Only
`addons/` is needed; the bundled `demo/` is not used.

`compatibility_minimum = 4.4`, so it loads against the 4.7.2 fork.

## Layout

| Path | |
|---|---|
| `Main.tscn` | Region root + Terrain3D + sun + environment |
| `Region.gd` | The authored region: fixed extent, own origin, seeded generation |
| `addons/animosis_terrain/` | The dedicated workspace (ours) |
| `addons/terrain_3d/` | Terrain3D (upstream, gitignored) |

## Region

Select the `Main` node and tick **Generate** in the inspector, or run the
project to build and print a verification report.

Defaults: **4096 m** extent, **2 m** vertex spacing, 2048² samples, seed
`20260924`. Builds in ~6 s and produces roughly 65–205 m of relief.

Regions have their own local origin and tile via `grid_coord`, which feeds the
noise domain in world space so neighbours meet without a seam. Nothing ever
approaches the ~8 km where float32 stops resolving centimetres, which is why
the engine fork needs no `precision=double` build.

Generation is deterministic — same seed and tile produce identical heights on
any machine. Verified by running twice and comparing the sampled transect.

## Known constraints

- **Terrain3D cannot run headless.** It allocates GPU texture arrays on the
  first property write and crashes against the dummy driver. It also cannot be
  driven from a `--script` SceneTree hook, which runs before the rendering
  server exists — generation must happen in a normal scene lifecycle. Headless
  CI therefore cannot test geometry, only the semantic layer.
- **Generation is GDScript**, ~6 s for 4.2 M samples. Fine for authoring, too
  slow for runtime streaming. That loop moves to C++ in the fork when it matters.
- **The workspace viewport is a placeholder.** Nothing renders in it yet.

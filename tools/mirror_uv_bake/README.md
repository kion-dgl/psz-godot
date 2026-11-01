# Independent Godot mirror-UV proof of concept

## Plan and acceptance gates

1. Reuse the Three.js Valley path approved by Kion and the asymmetric card;
   export the exact source/baked triangles, texture, transforms and provenance.
2. Build an independent Godot project, with no game autoloads, downloads, saves
   or modifications to stage configs. Compare source shader vs StandardMaterial3D
   using linked cameras, lighting, filtering and image differences.
3. Resolve mixed mirror/repeat sampling entirely in assets. Reflect the texture
   along mirrored axes, then map the folded UV into the first half of each
   expanded axis. Both axes can use ordinary REPEAT. The reflected half supplies
   the correct neighboring texels at folds, including the texture boundary.
   Cost: 2× pixels for one mirrored axis, 4× for two. Assess memory/deduplication
   and alternatives before using this as a production strategy.
4. Test fixture invariants and native material resources headlessly; run an
   actual rendered comparison with native lighting, plus automated screenshots.
5. Kion reviews the independent scene. Only then plan representative stage,
   object, transparent and animated cases. No mass port is part of this step.

The candidate has no ShaderMaterial or custom shader hooks. The left-hand
reference alone uses the old fold-and-half-texel shader approach. Textures and
UVs are prepared once from fixture data, never altered to simulate lighting.

**Status:** Steps 1–4 are implemented and verified. Step 5, Kion’s Godot
scene review, is the next gate before expanding coverage or porting assets.

## Run and inspect

From the repository root:

```sh
tools/mirror_uv_bake/run.sh            # standalone interactive comparison
tools/mirror_uv_bake/run.sh --test     # headless seeded tests
tools/mirror_uv_bake/run.sh --verify   # rendered checks, screenshots, then quit
```

The wrapper finds Godot on PATH or in the normal macOS application folders;
otherwise set `GODOT_BIN`. Open `project.godot` in Godot to inspect the project.
It intentionally does not load the main game's project or asset pack.

Drag either view to orbit, scroll to zoom, move the light-angle slider, toggle
native lighting and mipmaps, or select the asymmetric card. The default is
linear filtering without mipmaps. The right view always uses StandardMaterial3D.
The left reference intentionally retains the existing half-texel mirror shader.
Both views render at 640×640 with the same camera, lighting and no MSAA.

Save native-only scene produces `output/<sample>-native.tscn` and
`output/<sample>-native.res`: a script-free scene and ordinary ArrayMesh
containing StandardMaterial3D and its reflected texture. The scene includes
the current camera, light and environment and runs without any lab script
or custom shader. The resource can also be assigned to a MeshInstance3D.
Screenshots and `--verify` reports also go in `output/` (gitignored). Override
with `--output /absolute/path` if desired.

## Fixture regeneration

In the Three.js lab, choose the default Valley path and click **Download Godot
fixture**; save it as `fixtures/stage.json`. Switch to the asymmetric card and
save `fixtures/synthetic.json`. Each contains the same normalized static
snapshot shown in the browser, the original texture with its upload orientation
accounted for, authored scale/offset, source identity and baked triangles.
These small fixtures are self-contained; the proof needs no network or original
GLB installation. They are not production replacement stage assets.

The adapter reconstructs Godot clockwise triangles, builds reflected texture
periods, maps folded UVs into their first half, and attaches standard resources.
It does not rerun UV subdivision in GDScript. That remains the tested shared
Three.js operation. This avoids two independently evolving bake algorithms.

## Verification and observed results

Godot 4.5.1, Apple M5, Compatibility renderer, 2026-10-31:

- Seeded headless suite: 4,000 random and exact-boundary bilinear samples match
  the original mirror shader's sampling; atlas dimensions, silhouette bounds,
  vertex counts, native material/no next-pass and saved-resource roundtrip pass.
- Valley: 16 → 48 triangles; 64×64 → 128×64 texture (2× pixels).
- Card: 2 → 114 triangles; 128×128 → 256×256 texture (4× pixels).
- Unlit linear comparison: Valley max error 1/255, foreground mean 0.0442/255;
  card max error 2/255, foreground mean 0.0043/255.
- Lit linear comparison: foreground means 0.5756/255 (Valley) and 0.2559/255
  (card). StandardMaterial3D and the simple reference shader have small native
  shading differences. Exact shader pixel identity is not the purpose of
  moving to Godot's native material implementation.
- Native lighting changes the image substantially; the rendered probe also
  moves the directional light and requires a measurable native response.
- Mipmaps remain diagnostic: Valley foreground mean differences are about
  1.99/255 unlit and 2.41/255 lit versus the old shader. The folded reference
  has discontinuous UV derivatives, and atlas mip generation differs from the
  source texture's mip chain. Do not claim exact mip equivalence from this POC.

`--verify` fails if no-mip foreground mean exceeds 1/255, a sample renders fewer
than 100 foreground pixels, native lighting/direction does not change the
image, or the candidate ceases to be a plain native material. It saves all
mipmap observations but does not grade those as exact-parity tests. These
thresholds describe this fixture probe, not a universal art acceptance rule.

The isolated seeded suite and real-render probe are the two verification
layers for this tool. Gameplay scripts, quests and scenes are unchanged, so
this does not substitute for the later game's integration tests or playtests.

## Next gate

Review this native Godot scene before scaling out. Then select representative
mixed-axis, both-axis, alpha, vertex-color and animated materials; decide where
clamping alone suffices and where reflected textures are worth the memory cost.
Deduplicate by source texture and wrap settings, validate mip/alpha behavior,
and define bake provenance and runtime migration checks before a batch port.
City/free-roam/trap grades and owner assessment dates stay unchanged.

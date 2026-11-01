# Mirror UV bake — issue 381 prototype

Open `/psz-godot/tools/mirror-bake/` (Tools → Mirror UV Bake).
Run `npm run dev` from the repository root. To use extracted local assets
instead of the CDN, run `VITE_ASSETS_BASE='' npm run dev`.

The two views share a camera and use ordinary Three.js materials. The left
uses hardware mirrored-repeat. The right subdivides at integer UV boundaries,
folds alternating tiles, resets the texture transform and clamps mirrored axes.
No custom shader, half-texel UV shrink or texture modification is used.
Non-mirrored axes still repeat.

The Valley preset uses the `1_pass1` surface from `s01a_ga1_m.glb`, with the
committed `s01_0_pass1.png#1` settings (U ×2, U mirror, V repeat). It explicitly
captures a static rest pose, drops skin attributes, normalizes the model for
viewing, and uses that same snapshot for both sides. This is not a production
animation exporter. The asymmetric card makes alternating directions and
seams easier to inspect; its triangles cross negative and positive tiles.

## Compare

1. Start with linear filtering without mipmaps. Zoom in on a path edge or a
   letter on the test card. Orbiting either side moves both views.
2. Toggle wireframe to inspect the new triangles. Turn native lighting off/on
   and change the light angle. Both sides use the same material parameters.
3. Measure pixel difference: two 512×512 offscreen renders from the same
   camera, no MSAA, report mean RGB error, maximum error and fraction of all
   pixels with any RGB channel differing by more than 2/255. Background pixels
   are included; this is diagnostic, not a pass/fail fidelity grade.
4. Repeat with nearest filtering and mipmaps, mixed mirror/repeat axes,
   fractional scales, negative scales and offsets. Mipmap differences are not
   hidden or corrected by a custom shader.
5. Download the baked GLB for inspection. It contains the normalized static
   sample, standard material, sampler modes and versioned bake metadata. It
   does not replace a game asset or publish an asset pack.

## Algorithm and guardrails

`foldBake.ts` clips each indexed or non-indexed triangle at each mirror fold.
It carries barycentric weights through clipping, interpolates all vertex
attributes from the original triangle, and preserves material groups/winding.
UV-degenerate triangles are retained. Inputs are not modified. The output has
baked scale/offset and explicit metadata; accidentally baking it again fails.
Skinned/morph inputs and excessive subdivision fail explicitly. Start each bake
from an original static source. The lab's rest-pose capture is an explicit
adapter, not general deformation support.

Run `npm test -- web/src/mirror-bake/foldBake.test.ts`. Tests check interior
sampling (not only vertex UVs), area/winding, attributes, negative/fractional
transforms, mixed axes, exact fold boundaries, groups, deterministic output,
input immutability and unsupported-input guards.

## Rollout gates

- Godot has one texture-repeat flag, whereas this prototype uses per-axis
  clamp/repeat. The independent Godot proof in `tools/mirror_uv_bake` now
  tests reflected texture periods plus remapped UVs with ordinary repeat.
  This costs extra texture pixels and still needs owner review before rollout.
  GLB sampler export alone does not solve this.
- Validate mip filtering, alpha, vertex tint, native lighting, shared textures,
  additional UV/map channels and animation cases before a batch conversion.
- Production export must preserve original world transforms, skeletons where
  applicable and asset provenance. This lab normalizes a static sample.
- Update runtime material selection only after a baked asset is positively
  identified, so scale/offset and mirror wrapping are not applied twice.
- Keep source assets recoverable; do not flip the global mirror configuration
  to repeat as a shortcut. No Godot runtime or shipped asset changes are made
  by this prototype. City/free-roam/trap scorecard grades remain unchanged.

Initial software-WebGL check (2026-10-31), default native lighting, linear
filter/no mips, default camera: Valley 16 → 48 triangles, mean error 0.0050/255,
0.051% of pixels >2; test card 2 → 114 triangles, mean error 0.0404/255,
0.907% >2. These are observations, not portable thresholds or a human playtest.

## Godot handoff

Download Godot fixture exports the exact source and baked triangles with their
texture and settings. The independent Godot project consumes those snapshots;
see `tools/mirror_uv_bake/README.md` for its plan, launch and validation commands.

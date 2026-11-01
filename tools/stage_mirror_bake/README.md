# Native mirror materials across field stages (#381)

The Valley-approved bake now runs through the normal field loader for all eight
field areas. Original GLBs and global texture-fix rows remain unchanged.
Generated resources use `StandardMaterial3D`, continuous transformed UVs divided
by two on mirrored axes, and reflected-period textures with ordinary repeat.
There is no subdivision, per-frame UV conversion, or mirror shader on migrated
surfaces. The runtime checks source/settings identities and falls back to the
original material path when a resource is missing or stale.

## Coverage

| Area | Converted rooms | Converted surfaces |
| --- | ---: | ---: |
| Valley | 37 | 39 |
| Wetlands | 19 | 37 |
| Snowfield | 19 | 52 |
| Makara | 38 | 49 |
| Paru | 38 | 60 |
| Arca | 38 | 134 |
| Shrine | 39 | 119 |
| Tower | 27 | 117 |
| Total | 255 | 607 |

305 conventional stage GLBs were surveyed. 50 need no conversion under this
policy. The manifest explicitly records 19 mirror surfaces in city source
scenes (a separate pipeline, including the local Coliseum work) and 13 Tower
`bakedBlend` glass/light-effect surfaces that retain their existing treatment.
Animated, hidden, mixed-clamp and morph inputs are outside this static batch.
This is not a claim that every stage/effect shader has been removed.

84 shared reflected textures occupy 8,964,804 decoded bytes, including imported
mip levels. Source mip availability, opacity, cutout/blend mode, material names,
packed geometry, skin arrays, RGB tint and area lighting policy are retained.
The original-color metadata used by Snowfield's later lighting pass is carried
into the variants. Existing teal emission-mask processing reflects its raw-pixel
mask to match a baked texture's period.

## Commands

Run from the repository root, using Godot 4.5.1:

```sh
tools/stage_mirror_bake/run.sh bake
tools/stage_mirror_bake/run.sh audit
tools/stage_mirror_bake/run.sh render
tools/stage_mirror_bake/run.sh smoke
tools/stage_mirror_bake/run.sh review
tools/stage_mirror_bake/run.sh play ozette
```

Play accepts `gurhacia`, `ozette`, `rioh`, `makara`, `paru`, `arca`, `dark`, or
`tower`. It starts a normal expedition with a temporary starter character,
without autopilot, under a separate application/save name. Tools use local
assets rather than mounting the deployed pack. The old Valley viewer and audit
remain available as scoped wrappers; the old bake command rebuilds the unified
manifest to avoid dropping other areas.

## Verification and review

- All 35,822 audit checks pass. The all-stage audit covers source channels, UV transforms, alpha, lighting color
  metadata, material settings, missing/stale asset rejection, repeated material
  application, and the native emission-mask path.
- 340 outputs (manifest, meshes and textures) were byte-identical on a repeated
  bake. Superseded generated textures were moved under ignored `archive/`.
- 128 rendered comparisons cover all 32 converted area variants, full rooms and
  isolated mirror surfaces, with base-level and source mip filtering. All load
  and base-level comparison gates pass; worst base-level foreground mean error
  is 0.477/255. Production mip differences are measured separately: maximum
  foreground mean is 2.474/255 in the isolated Arca boss-room view. Continuous
  native UVs and the folded shader have different mip derivatives; these are
  not pixel-identical mipmapped outputs.
- The real field-controller smoke enters 37 generated sections across eight
  areas and verifies expected native variants load. This is entry coverage,
  not a complete route, combat or boss playthrough. Native and disabled runs
  both show existing null-material and deferred-lambda cleanup errors; the
  rapid headless teardown also reports resource leaks.
- Full game suite: 14,304 passes, 104 failures, with exactly the same failure
  labels as the pre-rollout baseline. Code-health reports the same existing
  RNG duplication, dead camera helper and oversized functions. No debt
  baselines were raised.

Valley free-roam appearance has owner approval. Other areas need gameplay
review. Generated resources live in ignored asset folders; the tracked
`data/stage_configs/stage-mirror-bakes.json` describes them. Standalone export
presets exclude these assets so they ship through the asset pack. PR #769 publishes a pack assembled from the verified previously deployed
pack plus exactly 339 generated resources; the packed-resource audit also
passes all 35,822 checks. The PR updates the asset manifest and index. Release
versions and fidelity grades remain unchanged; application release/merge still
requires green CI.

> Historical pre-migration audit. For the implemented roster migration and current requirements, see [Character VRM policy](character-vrm-policy.md). Arbitrary external-avatar retargeting remains future work.

# Player GLB → VRM migration audit

Inspected 2026-11-05 for #776, alongside the merge preparation for PR #766.
This is an investigation and proposed rollout, not an implemented migration.

## Finding

The existing roster is a good candidate for a batch converter: all 56 models share
one named skeletal hierarchy. A complete migration also needs a Godot avatar
adapter and a retargeting strategy. PR #766 proves PSO animation baking onto a
specific VRoid rig; it does not convert the original PSZ player models or supply
a general VRM runtime loader.

## Measured inventory

- 14 classes × 4 model/head variants = 56 player GLBs (`pc_000`–`pc_133`).
- 2,520 external appearance PNGs: 45 per model variation.
- All 56 have the same 12 joint names and parent relationships. Joint ordering
  differs (29 ordered lists), so conversion must map by name, never fixed index.
- No morph targets found in these models. No nonpositive node scales found.
- All 56 GLBs lack bound textures; the game supplies the chosen PNG at runtime.
- `assets/player/animations/` contains 39 GLB libraries and 867 animation entries.
  This is a file inventory, not 867 unique or player-only motions.
- `addons/` currently contains the joystick addon, not a VRM importer.

Inventory came from parsing the GLB JSON chunks, skins, nodes, meshes, materials,
and animation lists directly, rather than relying only on import-script comments.

## Rig conversion

Target VRM **1.0**. VRM uses a GLB container with required humanoid mapping and
metadata. Renaming `.glb` to `.vrm` does not add those requirements.

| Current bone | Proposed humanoid role |
|---|---|
| `000_Root` | Preserve as non-humanoid scene/motion root |
| `010_Hip` | hips |
| `020_Spine` | spine |
| `090_Head` | head |
| `030_LArm01`, `040_LArm02` | leftUpperArm, leftLowerArm |
| `060_RArm01`, `070_RArm02` | rightUpperArm, rightLowerArm |
| `100_LLeg01`, `110_LLeg02` | leftUpperLeg, leftLowerLeg |
| `120_RLeg01`, `130_RLeg02` | rightUpperLeg, rightLowerLeg |

The required left/right **hands and feet are missing** as separate nodes. Add
wrist/ankle bones using measured landmarks for each body profile. The original
hierarchy has 11 candidate humanoid bones plus its separate root; four additions
can supply VRM 1.0's 15 required roles. Chest, neck, fingers, toes, and expressions
are optional in VRM 1.0 and need not block the first conversion.

Start by preserving original bone names, rest transforms, mesh, and skinning.
VRM maps semantic roles to node indices; it does not require renaming every bone.
Adding unweighted endpoint nodes can preserve current playback, but by itself
will not make hand/foot rotations deform the mesh. For general humanoid motion,
validate wrist/ankle positions, allocate appropriate vertex weights, and test
external hand/foot rotations. Do not duplicate the lower-arm/lower-leg node into
two humanoid roles: mappings must be unique.

Generate valid VRM metadata, preserve source attribution and actual usage terms,
and embed a default appearance texture so the file looks correct outside PSZ.
Keep alternate colors in the existing appearance system initially: 56 model
files, not 2,520 separate avatars. Preserve the current unlit/pixel-art material
look; MToon effects and facial expressions are optional later features.

## Godot integration

- `scripts/autoloads/player_config.gd` selects a `.glb` plus a texture from class
  and saved appearance. Introduce an avatar/profile resolver while preserving
  existing save fields and fallback behavior.
- `scripts/3d/player/player.gd::_swap_model` loads an imported PackedScene.
  Pre-imported shipped avatars and user-selected external `.vrm` files require
  different loading paths. Runtime loading must work in exported builds, not
  only in the editor.
- `_remap_animation` currently changes skeleton paths, not bone semantics or rest
  poses. Preserve this fast path for original rigs; add a humanoid/rest-pose
  adapter for arbitrary VRM rigs.
- `_anim_lib_cache` keys on animation GLB and skeleton name. Retargeted results
  must also distinguish the target rig/rest-pose profile.
- Weapon sockets are hard-coded to `070_RArm02` / `040_LArm02` with local grip
  offsets. Resolve left/right hand semantics plus per-rig grip transforms, and
  preserve dual-wield mirroring. Do not simply attach existing offsets unchanged
  to a new wrist bone.
- Mags use a fixed player-relative shoulder offset. Make its visual anchor
  profile-aware for avatars with different proportions.
- Dodge playback strips `000_Root` translation because movement is driven by the
  gameplay curve. Retargeting must preserve this separation to avoid double
  movement and snapping. Preserve clip names, timing windows, playback speeds,
  attack events, and recovery behavior across both animation genders and weapon
  families.
- Preserve gameplay collision independently from cosmetic avatar dimensions;
  changing a model must not silently change combat reach or player clearance.

Evaluate a pinned version of V-Sekai's `godot-vrm` with Godot 4.5.1 and the project's
Compatibility renderer. It documents VRM 1.0 import/export and humanoid retargeting.
Its README lists VRM Animation (`VRMC_vrm_animation`) support as future work, so
keep the existing separate animation libraries for the first implementation.
Test shipped imports and external-file imports on exported target platforms.

## Rollout and acceptance

1. Convert `pc_000` end to end. Validate required metadata/bones, embedded texture,
   skin bind matrices, orientation, scale, and appearance in two independent viewers.
2. Load it as the actual player. Verify idle/run/dodge, a full combo, damage,
   knockdown/get-up, techniques, weapon grips, mag, shadows, and character preview.
3. Validate one female and one CAST body, then one of every class. Check foot
   contact and weapon alignment before assuming one set of landmarks fits all.
4. Batch-generate all 56 variants reproducibly. Audit all 45 appearance choices
   per variant, animation track resolution, bind-pose equivalence, and bounds.
5. Test an unrelated VRM 1.0 avatar through the same player adapter. This is the
   key acceptance test for swapping/modding; loading converted PSZ models alone
   does not prove arbitrary avatar compatibility.
6. Publish converted assets through the existing pack/CDN process, update asset
   references and manifests, and document one complete custom-avatar swap.
   Keep #776 open until this pipeline and the roster migration are complete.

Recommended first implementation: one original HUmar model (class id `humar`,
`pc_000`) plus one external VRM running the same gameplay animations. That proves
the converter and integration separately before multiplying work across the roster.

## Sources

- Local inventory: `assets/player/`, `scripts/tools/import_player_models.py`,
  `scripts/autoloads/player_config.gd`, and `scripts/3d/player/player.gd`.
- [PR #766](https://github.com/kion-dgl/psz-godot/pull/766): viewer and per-model
  retarget bake, including inverse-bind rest reconstruction and manual offsets.
- [VRM 1.0 overview](https://github.com/vrm-c/vrm-specification/blob/master/specification/VRMC_vrm-1.0/README.md)
- [VRM 1.0 required/optional bones](https://github.com/vrm-c/vrm-specification/blob/master/specification/VRMC_vrm-1.0/humanoid.md)
- [Godot VRM importer/exporter](https://github.com/V-Sekai/godot-vrm)

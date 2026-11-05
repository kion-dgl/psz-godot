# Character model policy and migration guide

## Required format

Every newly added human or humanoid character must use **VRM 1.0** as its runtime model. This includes playable humans, newmans, CASTs, humanoid NPCs, and future mod avatars. A renamed `.glb` is not VRM: the file must contain a valid `VRMC_vrm` 1.0 extension, required humanoid bones, usable materials and correct metadata.

All 14 playable classes and their four variants now resolve to `.vrm` through `PlayerConfig`. Gameplay, creation previews and selection previews use the same `PlayerAvatar` loader. There is no production player GLB fallback. Original GLBs remain source/conversion fixtures; animation-library GLBs remain supported. Non-humanoid monsters, props, weapons and stages do not need VRM.

Existing NPC models are transitional exceptions recorded in `scripts/tools/vrm/legacy_npc_glbs.json`. Remove each exception when its migration lands. Do not add exceptions for new human characters. Existing animation libraries in that list are not character-model exemptions. CI rejects new literal player/NPC GLB references in production scripts, scenes and data; review must also check dynamically constructed paths and humanoids placed outside those directories.

## Runtime contract: what works today

The portable file is a +Z-facing, metre-scale T-pose with grounded soles, 15 required humanoid roles, weighted hands/feet and an embedded default texture. PSZ appearance textures remain separate and apply through the existing customization system (including HUmarl's skin-tone remap). Materials retain their per-surface double-sided settings.

Current gameplay supports the versioned **`pszLegacyRig/1`** compatibility profile in `extras.pszLegacyRig`. It contains original rest nodes, position accessor, inverse-bind accessor, model identifier and source SHA-256. The loader restores the native bind convention in memory; it does not change the portable file. This preserves existing animation tracks, weapon sockets, mags, movement and combat code. The current converted rig has 16 bones: the 12 original bones plus hands and feet.

The loader is for trusted, validated built-in assets. It rejects missing files, non-VRM paths and unsupported profiles. It is not a general external-avatar importer, a security boundary, or a complete VRM feature implementation. MToon, expressions, spring bones, arbitrary skeleton retargeting and mod discovery are not implemented here.

## Convert the playable roster

With original source models and textures present locally:

```sh
python3 -m venv /tmp/psz-vrm-tools
/tmp/psz-vrm-tools/bin/pip install -r scripts/tools/vrm/requirements.txt
/tmp/psz-vrm-tools/bin/python scripts/tools/vrm/convert_players.py
npm ci --prefix scripts/tools/vrm
npm run validate --prefix scripts/tools/vrm -- --all
/tmp/psz-vrm-tools/bin/python scripts/tools/vrm/verify_conversion.py
python3 scripts/tools/vrm/check_policy.py --assets
python3 scripts/tools/run_humar_vrm_poc.py --headless --all
```

Outputs are `assets/player/pc_XXX/pc_XXX.vrm` and `assets/player/vrm_conversion_report.json`. Outputs are generated assets, not committed source. Conversion is deterministic for identical inputs/tool versions. The historical `convert_humar.py` contains the shared conversion functions; `convert_players.py` orchestrates the full roster. Do not run a publishing command just to convert or validate.

The converter requires one skin, a shared rigid-weight vertex stream across the mesh surfaces, and the expected PSZ named hierarchy. It finds joints by name, not joint ordering. The original playable rigs share dimensions; endpoint placement uses local limb-axis offsets (hand 0.28 m, foot 0.40 m) and distal-vertex thresholds (0.27 / 0.38 m). These are conversion settings, not universal humanoid proportions. Do not reuse them blindly on another skeleton or blended weights.

## Validate and inspect

The independent Node check runs Khronos glTF validation plus three-vrm parsing, verifies required roles and outward horizontal arms, grounded geometry and embedded PNG, and rotates each added hand/foot to verify weighted deformation. Node texture decoding is stubbed; Godot renders the actual embedded texture for visual review.

The all-roster Godot probe creates original-GLB test fixtures and production VRM players, exercises every gender-matching animation library through the production remapper, and compares the original 12 bone poses at four timestamps. It also checks starter weapon/mag attachment and a non-default appearance, then switches through all 14 weapon types, checking both hands where applicable, weapon socket transforms, attack startup, animation and timing. This is animation equivalence, not a claim of exhaustive interactive combat testing.

```sh
# Animated original/VRM comparison; choose clips in the window.
python3 scripts/tools/run_humar_vrm_poc.py --class-id humarl --variation 2
# Portable T-pose, bypassing native compatibility restoration.
python3 scripts/tools/run_humar_vrm_poc.py --class-id racast --portable
# Four gallery pages, one per variation (0–3).
python3 scripts/tools/run_humar_vrm_poc.py --gallery --variation 0
# Normal game, with isolated test saves.
python3 scripts/tools/run_humar_vrm_poc.py --game
```

The launcher uses separate `psz-humar-vrm-poc` saves. `--godot` selects an executable; `--screenshot /absolute/file.png` captures comparison/gallery output. Inspect front/back, hair and clothing surfaces, feet, wrists, weapon sockets and mag placement. In combat, check attacks, techniques, dodge, damage, death and equipment changes with melee/ranged/technique weapons and both animation genders. Exercise character creation/selection and appearance changes as well.

## Port another existing humanoid

Port an existing NPC when replacing or substantially reworking its model, when making it playable/mod-selectable, or in a dedicated NPC migration. Do not mix unrelated NPC conversion into a gameplay fix.

1. Inventory its skeleton, rest axes, scale, weights, surfaces, texture dependencies, animation sources and attachment points. Record its existing exception and runtime loaders.
2. If it matches the native PSZ rig, supply its source model/texture to the conversion functions, give it a stable identifier, and verify the endpoint offsets. For another rig, author a proper VRM in a DCC exporter; do not fabricate a native profile to bypass compatibility checks.
3. Validate the portable humanoid in an independent VRM loader and inspect deformation, textures and proportions. Metadata must describe the actual author and permissions; retain original asset rights.
4. Provide a supported animation adapter. Native-rig assets can use `pszLegacyRig/1`; other rigs require the canonical-humanoid retargeting work below. NPC loaders currently still load their legacy GLBs, so migrate the relevant city/field/companion loader explicitly to the shared avatar interface.
5. Compare old/new idles, walk/run, action clips and attachments. Exercise the actual NPC scene. Remove its model GLB exception only after that path uses VRM.
6. Add the validated asset to the asset distribution pipeline, verify it in the exported pack, and remove old runtime model references. Keep source files available for reproducible conversion.

## Foundation for moddable characters

This migration gives us a standard portable humanoid asset and a single player-avatar loading boundary. Keep character identity/class/stats/appearance in save data separate from the visual asset; changing an avatar must not change combat rules.

The next implementation should add a data-only avatar registry with stable namespaced IDs (for example `author:avatar`), display name, VRM path, format/profile version, author/license metadata and optional supported appearance presets. Save the avatar ID, with a defined missing-mod fallback to a built-in VRM. Validate paths and resource limits before loading; never load arbitrary scripts from an avatar package.

Before enabling user-selected external VRMs, implement and test a second animation adapter that maps PSZ animation to canonical VRM humanoid roles, handles rest-pose/proportion differences and root motion, and derives weapon sockets from hands and mag placement from an explicit attachment profile. Define collision/gameplay dimensions independently of visual size. Add validation for malformed files, external resource access, excessive geometry/textures and unsupported required extensions. Test on substantially different humanoid proportions, not only these converted PSZ models.

Do not advertise arbitrary VRM mods as working until that adapter, registry, safe loading, attachment rules and missing-mod behavior exist. Preserve the native adapter as a versioned compatibility option rather than requiring mod authors to copy PSZ bone names.

## Packaging and merge gate

Raw `.vrm` files require explicit inclusion in Godot exports; `Asset Pack` includes `assets/player/*.vrm`. Both asset publishers run the local coverage/profile preflight. R2 synchronization recognizes the VRM binary MIME type. Full independent validation and Godot probes must also run before release; the asset-free CI policy check alone cannot prove proprietary assets render.

**Do not merge the migration until all 56 playable models are generated, independently validated, reviewed in Godot, included in the tested distribution pack, and the character policy/guidance is committed with the loader changes.** Publish the approved asset pack/tree and update the release's asset reference before deploying code that requires these files. Existing published packs predate this migration. No asset upload or deployment is performed by the conversion commands.

## Migration verification record

Local validation on 2026-11-05, Godot 4.5.1:

- 56 models recognized by three-vrm; glTF validator reports zero errors/warnings. All four weighted endpoints deform each model.
- 56 native skinning comparisons at eight arbitrary poses, preserving surface sidedness; all 2,520 appearance textures present.
- 868 gender-matching model/library combinations, 21,476 clip instances, 1,030,848 matching original bone poses.
- 14 weapon types on each of 56 avatars: attachment/socket, equipment refresh and attack-start checks pass.
- Four portable gallery pages rendered and inspected, covering all variants.
- Exported asset pack mounted in an empty project: all 56 raw VRM entries match conversion hashes.
- Existing main suite: 14,694 passed, zero failed. Code-health/orphan checks have no new findings.

Automated runtime checks do not replace final interactive combat review. Asset publication, release-manifest update and merge are intentionally outstanding.

To independently verify an exported pack, run Godot from an empty project directory (containing only `project.godot` with `config_version=5`) and pass the absolute verifier script and pack paths:

```sh
godot --headless --path /tmp/empty-project --script /absolute/repo/scripts/tools/vrm/verify_pack.gd -- /absolute/assets.pck
```

Using an empty project prevents local loose VRMs from masking missing pack entries.

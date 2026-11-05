# Valley native-mirror rollout (#381)

The pipeline is now shared with `tools/stage_mirror_bake`. This viewer/audit
remains Valley-scoped; `bake` rebuilds the unified all-field manifest. Valley
free-roam appearance has owner approval. The results below record the original
Valley rollout; see the shared tool README for current coverage.

Scope: static mirror materials in Valley A/B/E/Z. Source GLBs, collisions,
animations, global texture fixes and other areas stay unchanged.

The reflected texture period approved in the Godot proof permits a simpler
production UV map: `(source_uv * repeat + offset) / period`, where period is
2 on mirror axes and 1 otherwise. Repeat sampling supplies the alternating
orientation, so no triangle splitting or skin interpolation is needed.

The normative behavior is `/engineering/#mirrored-repeat-porting`. Before
implementation, acceptance is pinned to:

- Seeded bilinear samples including negative/fractional UVs match mirror wrap.
- Generated surfaces keep topology, normals, RGB tint, bones and weights;
  only UVs and ignored vertex alpha change.
- Static mirror variants use StandardMaterial3D and respect field shading.
- Animated/hidden/effect rows are skipped. Other materials remain unchanged.
- Exact source mesh signatures and current fix rows gate runtime loading;
  missing/stale variants leave the original scene intact.
- All locally available Valley stages are audited after the real material
  pass; representative full rooms are rendered before pack publication.

Generated resources live under each stage's ignored `lndmd/mirror-bake/`.
Shared reflected textures live under `valley_a/native_mirror/lndmd/`.
The tracked manifest identifies their inputs and output paths. Production
publication remains a separate step after reviewing the converted Valley.

## Commands

Run from the repository root with Godot 4.5.1 installed:

```sh
tools/valley_mirror_bake/run.sh bake
tools/valley_mirror_bake/run.sh audit
tools/valley_mirror_bake/run.sh render
tools/valley_mirror_bake/run.sh review
```

The wrapper uses an application name separate from the game to protect the
normal user save. `GODOT_BIN` can select a particular engine executable. It
shares the repository's imported resources; original Valley assets must be
present locally. The review tool uses the real field material/lighting
selection pass, with linked cameras and a choice of all 37 converted rooms.
"Mirrored surfaces only" isolates the migrated surfaces; "Light all surfaces"
is a diagnostic override, not a change to the game's greenery-only light list.
Screenshots and `render-report.json` go in `output/` (ignored).

## Runtime and resource integrity

`MeshUtils.apply_field_materials` installs variants only for a manifest-listed
source scene. The loader verifies the source mesh's positions, indices, UVs,
colors, skin arrays, material identities, decoded texture pixels and current
fix rows. The loaded variant must also carry matching source/settings metadata.
The whole stage is prepared before replacing any mesh. A missing, stale or
older pack falls back to the original shader path. No texture generation or UV
conversion occurs in the gameplay loop. Set `PSZ_NATIVE_MIRROR_DISABLE=1` for a
legacy-path diagnostic run.

The offline baker copies Godot's packed surface buffers and changes only UV
floats and vertex alpha. This avoids an extra lossy decode/re-encode of normal
and tangent data. It rejects compressed UV layouts rather than interpreting
them as floats. The normal-generation pass matches the field's existing
`SmoothNormals.ensure(..., 2)` behavior. Material names, geometry topology,
bones, weights, transforms, other UV channels and surface LODs are retained.

Shared texture resources are keyed by pixels, dimensions, mipmap availability, mirror axes and
bake version. Three reflected textures cover all Valley candidates. The source
images and GLBs remain recoverable and the global authoring configuration is
not rewritten. Generated asset paths are excluded from standalone native
binaries alongside the source Valley art; they belong in the asset pack.

## Local rollout results (2026-10-31)

- 38 source stages surveyed: 37 converted, boss arena `s01z_na1` unchanged.
- 39 migrated surfaces: 19 dirt paths, 18 bridges, 2 carts.
- 3 shared textures: path/cart 64×64 → 128×64; bridge 64×64 → 128×128.
- Reflected textures total 131,072 decoded bytes without mipmaps; generated
  meshes/textures add about 1.8 MB on disk. No triangle growth.
- Two consecutive bakes produced byte-identical manifest and resource outputs.
- All 4,158 audit checks pass. The seeded unit test covers 1,536 UV samples. The all-stage audit checks
  topology, exact packed channel preservation, native material/shading policy,
  no double transforms, settings mismatch and missing/stale assets.
- The rendered probe covers five representative rooms (A path, A cart,
  B bridges and E transition), both full-room and isolated views, with/without
  mipmaps. Linear-filter comparisons differ by at most one 8-bit level.
- Production preserves the source textures' disabled mipmaps. The viewer can
  generate mipmaps for both sides as an explicit diagnostic. Continuous UVs
  and the old folded shader have different derivatives, so those diagnostic
  comparisons are recorded without requiring exact parity.
- Full game suite: 14,304 passes, 104 failures; the baseline runner has the
  same 104 failure labels. No new failure labels from this work.
- Real Valley free-roam autopilot, seed 381: native variants load through
  several rooms. Both native and disabled/legacy runs stop at the same
  pre-existing missing `AreaWarp_goal_pad` in section A cell (2,4). This is
  not a successful end-to-end gameplay pass.
- The existing code-health gate also reports baseline findings in field RNG,
  player camera and field-population/test functions; none is in the new bake
  helpers. No debt baselines were increased.

## Review and release boundary

This is a local Valley conversion, ready for room-by-room review. It has not
updated the deployed pack or `assets_manifest.json`. After review, build and
publish the full asset pack through the normal workflow and update its
manifest/tree. CI and the existing route/test blockers still need resolution
before claiming a completely green release. Other areas, animated surfaces,
traps and effects are outside this batch. The Free roam scorecard records the
pending area-wide playtest; its grade and assessment date are unchanged.

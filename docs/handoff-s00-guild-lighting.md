# Handoff — s00e_sa2 guild counter: the DS lighting architecture (#656)

Date: 2026-09-26 · Branch: `feature/s00-guild-lighting` · everything pushed.

## Where this stands

The walk lab is reverted to **c18324ba** — the build kion walked and called
"already really close": REAL per-light dynamic shadows (walk between two
lights → two shadows from each direction) over the sto shadow-only catcher.
Its one known defect: the floor renders as a black-ish veil wherever the
light field is weak. The revert commit restores
`scripts/tools/counter_walktest.gd` and `data/stage_configs/city-lights/s00e_sa2.json`
(ambient 0.5) bit-for-bit; `scripts/utils/mesh_utils.gd` was already at that
state. Smoke-verified after revert.

Run it: `godot --path . scenes/tools/counter_walktest.tscn` (boots straight
into the DS bake). Web lab: `cd web && npm run dev` → `/#/city-lab`.

## The objective (kion's words)

Vertex colors (the DS bake) on the stage, unaffected by light. Characters
lit by the placed lights. Dynamic shadows cast by the placed lights — NOT a
sun — onto the floor, which otherwise shows the bake verbatim ("the floor
mesh transparent, just apply the dynamic shadow — this is already working
in valley A with the sun; in this case it's lights").

## What is settled (do not re-derive)

The project renders with **gl_compatibility**. Every engine-shadow path to
"transparent floor + N per-light shadows" is measured or derived dead:

1. **MUL catcher** (valley's `make_shadow_catcher`, white multiply-blend):
   under multiply blending, pool visibility and shadow visibility are the
   SAME term. Valley A works only because its sun is directional — uniform,
   so the lit catcher clamps to ×1 everywhere and no pool can exist.
2. **shadow_to_opacity (sto)** — the StandardMaterial3D FLAG no-ops on
   compatibility; the SHADER `render_mode shadow_to_opacity` works. The
   formula (from `drivers/gles3/shaders/scene.glsl` in godot source):
   per light `alpha = min(alpha, clamp(1.0 - attenuation, 0.0, 1.0))`, then
   after lighting `alpha = min(alpha, clamp(length(ambient_light)))`.
   Consequences, all verified numerically (`scripts/tools/shadow_probe.gd`
   is the probe; prints sampled luminance):
   - The veil = `1 − strongest attenuated light` at the pixel — FALLOFF
     drives it (lit catcher sampled 74/217 under an e2, 161/217 under an
     e40; clean floor reference 217). This is the reverted rig's black floor.
   - Ambient is a shared cap: it bounds BOTH the max veil and the max
     shadow depth. 0.5 → worst floor ~25% of bake; 0.28 → ~60% but weaker
     shadows. One dial, zero-sum.
   - Fill lights erase shadows (a fill's `1−a=0` verdict wins the min
     everywhere — measured tie at 154≈153).
3. **Twin omnis** (hot catcher-only copies via light_cull_mask render
   layers): the gles3 omni attenuation `(1−(d/r)⁴)²/d` collapses to ~0 near
   the range edge, so no energy clears the floor to the edge; longer ranges
   re-trip the zero-sum (a second light ≥1 erases shadows).
4. **light() custom shader**: ATTENUATION there carries neither falloff nor
   shadow (measured flat 217) — no shadow access.
5. **Swinging directional** (one shadow-caster aimed from the dominant
   placed light): mechanically verified (real silhouette, floor clamp ×1)
   but kion rejected the read — "the shadow unnaturally rotates around".

## The open thread: the projector rig (8def749b)

The last attempt before the revert — real per-light shadows with a
transparent floor by construction, no engine shadow path at all:

- One SubViewport per placed light; camera AT the light aimed at the actor
  (actors-only render layer 8; player meshes join it after spawn), 256px,
  `transparent_bg`, rendering the actor silhouette.
- The catcher is an UNSHADED composite (`PROJECTOR_SHADER` in the walktest):
  projects each silhouette through the same camera's view/projection,
  weights `20·energy/d²` (in range, above actor), max-composited,
  `SHADOW_MAX_ALPHA 0.55`.
- Debug evidence it WORKS (all reproducible):
  - `PSZ_WALK_DUMP=/tmp/vp0.png` → texture holds a clean silhouette
    (6731 solid-alpha px of 65k).
  - Projection math printed: player's feet project to uv (0.50, 0.49) of
    the plaza light's shadow camera — dead center.
  - `PSZ_WALK_CATCHER_DEBUG=1` → red overlay: strong red exactly under the
    character.
  - `PSZ_WALK_TELEPORT="0.1,-9.0,128.0" PSZ_WALK_SHOT=/tmp/x.png` →
    medium-dark human shadow on the anti-light side, floor pure bake.
- **Unresolved**: kion walked it live twice and reported "no shadow" both
  times, contradicting all smoke evidence. Next step if resumed: run it
  live on kion's screen WITH the catcher debug on and reconcile — candidates
  are something live-vs-smoke (window focus/DPI?), or the read (at spawn the
  e40 is directly overhead → shadow straight under the body, hidden by it;
  walk to the sconce cluster z 98–141).

To resurrect: `git show 8def749b:scripts/tools/counter_walktest.gd`.

## The reverted rig's tuning map (c18324ba, current state)

- `,` `.` ambient live (P prints paste-ready sidecar): the shared cap above.
- `[` `]` omni energy scale; M toggles all omni shadows; B A/Bs the whole
  bake mode; R reload; ESC quit.
- Env: `PSZ_WALK_BAKE=0` (boot lit look), `PSZ_WALK_SHADOWS=0` (diff
  control), `PSZ_WALK_SHOT` (screenshot smoke at frame 45).
- Sidecar: `data/stage_configs/city-lights/s00e_sa2.json` — kion's 8-light
  authored rig (2×e40 plaza/warp, 5×e2 sconces r15, e5 lantern r11 — its
  pos y −12.6 is BELOW the floor, worth re-authoring), ambient 0.5.

## Remaining scope (untouched)

- Port the approved look into `city_counter_controller` production
  (`scripts/3d/city/city_counter_controller.gd` calls `_add_authored_lights`
  via `CityAreaBase`; the bake/shadow half is lab-only so far).
- Mirror the DS mode in the web labs (`web/src/city-lab/`,
  `web/src/city-walk-mock/` — they currently model the lit look).
- Office / underground / market sidecars (controllers don't call
  `_add_authored_lights` yet); market UV surgery's isolated islands
  (set02 190 / wall03 35 faces) need source data or re-authoring.

## Dev-assets note (gitignored, machine-local)

The worktree needs `assets/stages/city_e/s00e_sa2{lndmd}` GLBs, the whole
`assets/player/` tree, and `web/.env.local` copied in + `godot --headless
--import` run once — see the main checkout at
`/Users/kion/projects/psz-godot` or the server worktree for sources.

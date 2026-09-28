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

## IN THE GAME (2026-09-27) — counter + market ship the certified rig

CityAreaBase._apply_ds_bake_look(stage_node_name): the locked recipe as a
production helper — make_unlit stage, stage never casts, the sto catcher
on FloorCollision. city_counter_controller calls it after its trimesh
floor ("Counter"); city_market_controller now loads its own sidecar
(s00e_sa1.json — 7 lights on the wetlands envelope at the shops, mid-room,
entrance, north wall, underground door; legacy row as fallback) and calls
it after its box floor ("Market"). Boot-smoked clean; the market light
positions are first-draft (authored from the NPC/geometry coordinates) —
tune by report or port the lab's live keys next.

## SETTLED (2026-09-27) — the sto rig certified, lights authored

Kion's eyes certified the c18324ba rig reproduced on the current tree
(PSZ_WALK_STO=1): player reacting to every light, dynamic shadows
everywhere including the between-feet contact under a light. The
brightness problem was authoring, not rig: the e40/att1 lights flooded
the hall and no global scale could fix the ratios. Re-authored to the
wetlands envelope and TUNED LIVE BY KION (P read-out, final):
ambient 0.5 · sconces/ceiling e0.3 att2.0 r12 at head height · plaza
pillar + warp door e1.25 att2.0 r12 LOWERED to y −4.5/−7.0 (high lights
can't cast readable floor shadows — inverse-square at 6+ units of
height has nothing to subtract; chest/head-height lights read, the
wetlands post-lantern convention) · lantern e0.5 above floor. Sidecar
updated in-tree. Remaining: the catcher/black-floor look is still the
open aesthetic call (this rig ships it); the scene-direct floor
receiver variants (FLOOR_LIT/geom, FLAT, BAKE, PROJECTOR modes) all
remain in the lab as the follow-up options.

## CATCHER_EMISSION — the dial that breaks the zero-sum (evening)

Kion's read: the shadow shows where the catcher is visible; make the
catcher INVISIBLE except the shadow. The blocker was the ambient
zero-sum (ambient hides the veil AND shallows shadows). The third dial:
EMISSION on the multiply catcher — an UNLIT additive term, so
ambient + emission ≈ 1 pins the multiplier at x1 outside pools (no
veil, no coverage seams) while shadows keep their full pool-depth.
PSZ_WALK_CATCHER_EMISSION (default 0.85), live via - / =, in the P
readout as catcherEmission. Station-verified: floor mean 54 (ambient
0.1, no emission) → 124 (emission 0.85) ≈ bake-natural, pools 157,
one clear shadow, no visible mesh or seams. Tune trio: , . ambient
(shadow floor) · [ ] pools (shadow depth) · - = emission (mesh
invisibility). Tuning must run with shadows ARMED (the compat omni
path differs otherwise).

## The corrected conclusion (same day, evening) — the catcher pattern WORKS with point lights

Kion's call: the pattern repeated across the lighting PRs — visible stage
baked and light-immune, the COLLISION MESH the invisible shadow receiver.
The earlier "blend_mul never receives omni shadows on compat" verdict was
a **saturation artifact**: at ambient 0.5 with full-strength e40s the
multiply catcher pins to ×1 everywhere and shadows have nothing to
subtract from. At kion's tuning (ambient 0.1, pools ×0.25 —
PSZ_WALK_AMBIENT / PSZ_WALK_POOLS boot overrides added) the MUL catcher
shows the player's shadow, verified 4-for-4 by station shots + the new
in-boot A/B (PSZ_WALK_AB: same station, shadows flipped in code, one
settle, second shot — two-boot diffs drown in animation noise).

Also measured: on compat, toggling omni shadow_enabled changes the omni's
whole contribution to the catcher (the off-state floor reads ~6× darker
than shadowed-on at the same energies) — the shadow pass is a different
light path, not just occlusion. Tuning must happen with shadows ARMED.

Launch: `PSZ_WALK_FLOOR_LIT=0 PSZ_WALK_AMBIENT=0.1 PSZ_WALK_POOLS=0.25
godot --path . scenes/tools/counter_walktest.tscn`. The FLOOR_LIT and
geom modes remain as alternatives; the catcher rig is kion's pattern.

## BAKE_FLOOR — the "transparent hull" (kion's close-to-done ask)

True transparency stays the measured dead end (blend_mul never samples
omni shadows; shadow_to_opacity's alpha is the veil), so the receiver
stays OPAQUE and instead LOOKS transparent: PSZ_WALK_BAKE_FLOOR=1 (with
FLOOR_LIT=0) captures the UNSHADED stage floor once — top-down ortho
SubViewport, thin vertical slice so walls only print their base strip,
player hidden — and prints it on the collision shell via world-XZ UVs
(MeshUtils.make_baked_floor). The floor shows the actual baked
tiles/inlays at the real world positions, pools and the omnis' shadow
maps playing on top; verified: dead-strip station shows the bake + one
shadow, the sconce pair shows TWO shadows, no seams/mirroring. Kion's
tuning read-out from the flat-floor walk (P): ambient 0.1, pools ×0.25
(sconces 0.5 / plaza 10) — the candidate sidecar values.

## FLAT_FLOOR — kion's flat-color proposal, verified (latest)

Kion found mid-floor strips the surface list can never cover (the stage's
floor is split across more materials than ground01/groud01/doorset) and
proposed the c18324ba architecture with a flat color instead of the black
veil. `PSZ_WALK_FLOOR_LIT=0 PSZ_WALK_FLAT_FLOOR=1` (or "r,g,b"): the
collision shell as an OPAQUE flat-color per-pixel floor
(MeshUtils.make_flat_floor) — total walk-surface coverage by construction,
pools + the omnis' shadow maps everywhere (opaque receiver = the only kind
compat omni shadows land on), bake kept on walls/props. Station-verified
at the dead center strip (now fully responsive, shadow reads), the office
door, the sconce pair, and spawn (compact zenith shadow, NO hot spot —
the flat albedo absorbs the e40); 144.9 fps / 0 slow frames with all 8
omnis casting — the cheapest rig yet. The trade: the floor reads as the
flat color, not the baked texture — the aesthetic call kion is testing.

## Resumed 2026-09-26 (later) — the rig that satisfies kion's conditions: FLOOR_LIT

Kion's conditions (verbatim): no sun; lights in the scene; baked lighting on
the city; the city mesh must not interact with the lights; the character
lit by them; the character with dynamic shadows. The c18324ba sto rig had
the shadow behavior right but SHOWED the catcher as a black floor mesh.

**The answer is the ozette contract on the floor surfaces only**
(`PSZ_WALK_FLOOR_LIT="ground01_COLOR_0,groud01_COLOR_0.001"` in the lab):
the stage goes unlit bake as before, then the two floor surfaces flip
per-pixel WITH the vertex bake as albedo — the authored omnis pool on the
floor, and their shadow maps land: measured one medium-dark shadow at a
single sconce, TWO opposite shadows between the sconce pair, a compact one
under the spawn plaza light, bake visible everywhere, warm pools at the
lamps, and NO catcher mesh at all (the visual floor IS the receiver —
nothing to hide).

Engine fact measured along the way (worth keeping): on gl_compatibility,
**dual-paraboloid omni shadow maps do not reach blend_mul receivers** — the
valley MUL catcher took a shadow-casting directional (sun probe: clear
1.5–2-body shadow) but nothing from the casting omnis; a blend_mul shader
fared the same. blend_mix receivers take them (c18324ba's sto catcher
showed omni shadows; shadow_to_opacity's veil was the problem, not
reception). Opaque per-pixel receivers take them (the wetlands ground, and
now the city floor). So: omni shadows ⇒ opaque receiver, full stop.

Post-confirm fixes (kion's live walk, same day): the "no shadow next to
the principal's office" strip was the **doorset_COLOR_0 floor** — an
unlisted surface can neither pool nor shadow; doorset joined the default
FLOOR_LIT list (ground01/groud01/doorset, env-overridable, "0" disables)
and the doorway now shows pools + a medium-dark shadow. The HUD carries
its own key legend now (", ." ambient, "[ ]" pools, M shadows, B bake) —
the values update live as pressed. Ambient guidance: don't zero it — the
wetlands reference is 0.35, and unlit surfaces keep only ambient, so 0
blacks out exactly the pockets being investigated.

Perf (kion's live walk flagged chop; measured 2026-09-26, PSZ_WALK_FPS):
the rig holds vsync 120 fps / 0 slow frames with all 8 omnis casting; the
chop was the SHOT_EVERY capture reel's sync readback (94–95 fps, exactly
2 >50ms hitches per second at EVERY=60) — leave the reel off when judging
framerate. Kion's live confirmation: two shadows between the sconces,
positions and behavior correct; the office/spawn stretch reads shadowless
(zenith plaza light geometry + the intensity/ambient tuning below).

Tuning territory (not rig work): the plaza e40 blows a hot spot on the
floor-lit surface at spawn (energies were authored for actors; `[ ]`
scales them live, P prints the tuned sidecar); ambient 0.5 with `,` `.`.
The lantern L5 still sits below the floor (y −12.6) and throws nothing.

To run: `PSZ_WALK_FLOOR_LIT="ground01_COLOR_0,groud01_COLOR_0.001" godot
--path . scenes/tools/counter_walktest.tscn` — plus the station walk
(`PSZ_WALK_STATIONS`), live HUD, and `PSZ_WALK_SHOT_EVERY` reel from the
morning's instrumentation, all still in place. Everything uncommitted in
the worktree for review. Next: port the FLOOR_LIT mode into
`city_counter_controller` (flip the floor surfaces in the DS-bake path,
arm the omni shadows), mirror in the web labs, then the office/underground/
market sidecars.

## Resumed 2026-09-26 — reconciled: the rig works, "no shadow" was the read

The projector rig is back in the working tree (from 8def749b) plus
instrumentation; **uncommitted, review `git diff` first.** Verdict from a
6-station walk (`PSZ_WALK_STATIONS`, new): the projection, compositing, and
per-light weights are all correct — visible shadows confirmed by screenshot
+ catcher-debug red at three stations, including the two-shadows case
between the east sconce pair (≈ x 13.5, z 108: both e2s at w=0.55, shadows
in opposite diagonals). No live-vs-smoke mechanism exists: the catcher is
world-space, the shadow viewports are 256px fixed, nothing reads window
state.

Why live read as "no shadow":

1. **Spawn has no visible shadow by geometry.** The only in-range strong
   light at spawn is the plaza e40 (L3) — almost exactly overhead, so its
   full-weight shadow lands directly under the body. The warp e40 is 60+
   units away, forever out of its r15. The handoff's z=128 smoke was the
   same story: a ~0.9-unit nub pointing at the camera, occluded by the body.
2. **The readable shadows live away from spawn**: the east sconce pair
   (two-shadow spot) and near L6 at z≈99–101 (one character-length shadow).
   Sconce shadows are e2-driven — faint (w≤0.13) past ~8 units, gone at 15.
3. **Key trap**: M toggles the projector weights here (in the sto rig it
   toggled engine shadows) — pressing M "to make sure" blanks the shadows;
   B drops back to the lit look. The new HUD line ("shadows on | (x, z)
   top: P2 Light 3 w=0.55 d=10.3") makes both self-diagnosing, and
   `PSZ_WALK_SHOT_EVERY=30 PSZ_WALK_SHOT_DIR=/tmp/reel` records exactly
   what the live window showed.

Hardening added while in there: `look_at` colinear guard (walking dead
under a center-line light — L3/L6/L8 all sit at x≈0.06 — errored and FROZE
that projector; dead-under-L6 now runs clean at w=0.55);
`PSZ_WALK_STATIONS` + the per-light verdict table printed per station;
`PSZ_WALK_CAM_ROT` (the default follow offset lands inside the east wall
at wall-side stations); the live HUD read; the live capture reel.

Next: kion walks it live with the HUD on (start at the east sconces, not
spawn). Authoring decisions now quantified — lantern L5 sits below the
floor (y −12.6, throws nothing); shadow ceiling is SHADOW_MAX_ALPHA 0.55;
if spawn should show a shadow that's sidecar work (un-zenith L3 or a low
sconce), not rig work. Then the Phase-2 port into
`city_counter_controller` and the web labs.

## #669 RESOLVED (2026-09-27, evening) — the game never flipped a single surface

The in-game rig booted pure bake: lights armed (the dump said
`shadows=true` 8-for-8), floor "flipped" — and nothing landed. The
boot-path delta the issue suspected was real but mundane:

1. **The geom gate's walk height was garbage on this stage.**
   `floor_top(FloorCollision)` reads the collision AABB TOP, and the
   counter's floor GLB is a whole-room shell (walls and all, y −21.5..
   +14.7 — the kaidan). walk_y = **+14.7** against the −10.7 floor → the
   ±1.5 centroid gate rejected EVERY surface. Zero flips. The lab never
   hit this because kion's certified run booted with the NAME list; the
   geom gate was "the equivalent" nobody A/B'd.
2. **The certified name list never covered the hall walkway either.** A
   color-coded station render (each surface a flat unique color, shot
   from the live game camera pose) showed the floor pixels under the
   player's feet are `groud01_COLOR_0` — the list had `.001`, a different
   (northern) surface. The hall floor is a material mosaic (groud01,
   mizu, Material__80, ...) — kion's live read: "shadows appear and
   vanish depending on the material", then the call: **"you can just use
   the full mesh."**
3. **The city player was unlit.** The player GLB imports UNSHADED; the
   field's spawn contract (`SmoothNormals.ensure` + `make_lit`, #646)
   never ran city-side — the omnis lit the floor but not the actor.

The fix (`_apply_ds_floor_lit(stage, surfaces)`): the wetlands
`lit_surfaces` convention — a per-stage surface list, "*" = the whole
stage per-pixel with the vertex bake as albedo. The counter passes
`["*"]`; the geom gate stays as the no-list fallback for flat box floors
(the market A/B). A boot print (`DS floor-lit on Counter: 28 surface(s)
by wildcard`) makes zero-flip impossible to miss again. Kion certified
live, twice, from the running game window.

Probes that settled it (all in CityAreaBase, PSZ_CITY_DUMP companions):
`PSZ_CITY_SPAWN="x,y,z"` boots the player at a station (the in-game
PSZ_WALK_TELEPORT), the dump prints the settled player pos + mesh feet,
the camera pose, and the top underfoot surface HITS with shading mode
(the raycast that named groud01). macOS throttles occluded windows, so
a dump boot sets `always_on_top` (the labs' station lesson).

## MARKET #670 (2026-09-27) — the corrected MUL-catcher contract (measured)

WALKED AND CONFIRMED BY KION in the live window ("perfect, this is
exactly what i was going for") — the floor shows its bake verbatim with
only the sun's shadow on top.

The market catcher plane work corrected a settled-fact premise above: the
compat renderer's transparent pass blends in **FLOAT — there is no ×1
clamp**. "Uniform directional saturates the catcher to ×1" was wrong;
valley A works because its total is 0.9·cos60° + ambient 0.4 ≈ **0.85 —
under 1 everywhere**, so the multiply is a near-invisible uniform ×0.85.
Measured on the market, in-game (`PSZ_CITY_DUMP`, three boots):

- e6 sun: catcher lit ≈ ×3.4 → **white sheet** over the bake (the shadow
  still reads through it — the catcher IS receiving the shadow maps).
- e0.9 + ambient 0.5 + the 7 shop omnis: still ≈ ×1.4 near lights →
  still white. Point pools always push past 1 inside their falloff.
- rig off (`PSZ_MARKET_CATCHER=none`): floor shows its bake verbatim,
  no shadow — the plane was the only whitener; the stage mesh is fine.

The shipping contract (`city_market_controller._apply_market_rig`): stage
pure bake (unlit), catcher plane at y+0.03 riding CATCHER_LAYER with every
OmniLight3D culled off it (`light_cull_mask &= ~CATCHER_LAYER`), ambient
0.5 + ONE uniform sun e0.8 @ −55° ≈ ×0.96 — just under 1, invisible —
shadowed regions fall to the ambient share (×0.5, valley's depth ratio).
`MarketSun` also had to move: the compat shadow pass anchors at the LIGHT
NODE, and the origin is outside the plaza (z 5..75) — no shadow map
covered the room until `place_light_inside_room` put the eye inside
(#648's valley lesson, now applied city-side). Floor-lit A/B:
`PSZ_MARKET_CATCHER=floor_lit`; raw stage: `=none`.

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

class_name FieldSlotTable
extends RefCounted

## Field time slots (#655 phase 1) — the authored time-of-day + weather table.
## Spec: /states/field-time-slots. The game ships NO free-running day/night
## cycle: each field area pins exactly one authored slot (its identity time),
## applied once at cell entry. The snowfield's locked #646 night rig is the
## template row; areas whose identity issue (#648–#654, #657) hasn't authored
## a slot yet carry interim day rows that preserve pre-#655 behavior.
##
## Row fields (all optional except hour):
##   hour          float  pinned clock hour; fractional picks a stable lerped
##                        palette between phase presets (e.g. 5.5 pre-dawn)
##   weather       String rides the row (#609 unification): "", "snow", …
##   sun_energy    float  DirectionalLight3D energy override
##   sun_color     Color  DirectionalLight3D color override (the phase preset
##                        ships warm daylight; overcast rows desaturate it
##                        toward neutral-cool, #649)
##   ambient_energy float ambient energy override
##   ambient_color Color  ambient color override (same overcast use)
##   sky_top_color Color  ProceduralSkyMaterial overrides — the visible sky
##   sky_horizon_color Color band under the preset, for moods whose sky must
##                        read through (overcast gray; no effect where the
##                        stage's baked panorama hides the sky)
##   moon_energy   float  moonlight energy override (moon becomes visible)
##   moon_pitch    float  moonlight elevation in degrees (rotation.x; the
##                        hour-lerped preset parks it at grazing angles —
##                        −26° at 5.5 — whose long shadows read against the
##                        moon's own look; rows that stand on moon shadows
##                        pin their own elevation)
##   moon_shadows  bool   moonlight casts real shadows (also skips the player
##                        blob shadow — blob + moon shadow reads double)
##   sun_shadows   bool   the sun casts real shadows (day rigs, #648; the
##                        phase preset ships them off — the row re-arms them).
##                        Same blob-shadow skip as moon_shadows
##   sun_pitch     float  sun elevation in degrees (rotation.x; the DAY band
##                        parks every hour at −45° — rows that want a noon
##                        or afternoon character pin their own elevation)
##   sun_origin    [x, y, z] hang the sun AT a world position, aimed at the
##                        origin (the stage art's baked sun spot — the
##                        wetlands' rainbow maker, #649; overrides the
##                        preset pitch/yaw and sets the compat shadow-eye
##                        position if shadows ever re-arm)
##   bake_mix      float COLOR_0 → white blend (0..1); presence implies the
##                        white-strategy material pass (neutralize + per-pixel)
##   tonemap_white float  tonemap white point override
##   fog_density   float  dark edge-haze rows (#653 follow-up): exponential
##                        fog whose near-black albedo (fog_color, default
##                        0.03,0.03,0.06) dissolves the room's far edges
##                        into the dark — clouds at the boundary instead of
##                        hard walls against unmodeled space
##   fog_color     Color  the fog's albedo (rides the dark read)
##   fog_height    float  with fog_height_density: the height fog's y line —
##                        a NEGATIVE density piles fog above it (the shrine
##                        B/Z ceiling cloud bank burying a white skybox
##                        through open roofs), positive pools it below
##                        (ground fog)
##   fog_height_density float the height fog's density sign and magnitude
##   geometry_casts_shadows bool map geometry casts shadows (default off — the
##                        bake is the look); a rig that stands on real moon
##                        shadows (s03b, #659) turns it on
##   sun_eye_pull  [float, float] shadow-eye offset as fractions of the
##                        panorama box [x, z], applied after panorama
##                        placement — slides the compat shadow frustum off
##                        the rim so edge scenery stops casting (#648)
##   lit_surfaces Array  material names that DO receive the rig while the
##                        rest of the stage keeps its bake — the "cheat"
##                        strategy (#648 valley): greenery lights, hard
##                        surfaces don't (every prop class read bright and
##                        out of place against the bake). A "*" entry is the
##                        wildcard (#649 wetlands): the WHOLE stage receives
##                        per-pixel, bake kept as albedo — real light pools
##                        on the ground. Needs no bake_mix; run after the
##                        field material pass so special-shader surfaces
##                        (waterfalls) are skipped
##   stage_light_layer bool the lit stage ALSO joins its private visual
##                        layer (#653, the floor/actor split): "stage"-
##                        targeted placed lights (<stage>_effects.json
##                        entries with "targets": "stage") are masked to
##                        that layer alone — hot low floor pools the
##                        actors/props/catcher physically cannot see, while
##                        ordinary lights keep reaching everything
##   shadow_catcher bool the collision shell renders as the shadow receiver
##                        — white, multiply-blended, at the walk height:
##                        the actors' dynamic shadows multiply onto the
##                        bake while lit ground multiplies by ~1 (#648)
##   post_lights   String material name whose surface geometry marks light
##                        posts: the pass clusters that surface's vertices
##                        on the XZ grid (one cluster per post) and drops an
##                        OmniLight3D at each post head — actors/props read
##                        the pools, the post itself keeps its bake (#649)
##   lit_props     bool  field GameElements (boxes, fences, drops, NPCs)
##                        receive the rig (SmoothNormals + per-pixel, their
##                        own load path). Default off — pre-#649 fields keep
##                        the baked props look
##   lightning     bool  the storm strobes — a scene-level cool directional
##                        flashing random multi-pulse strokes (the wetlands'
##                        dark turn + boss downpour, #649)
##   signature     String the area's ambient-life effect key (the shrine's
##                        rising motes, #653) — built by the WeatherController's
##                        signature builders and attached to the player like
##                        weather, but NOT weather: it spawns indoors by
##                        design, because the indoor gate exists for
##                        precipitation, not for the area's identity
##
## Keys resolve most-specific-first: exact stage_id → variant prefix (first
## 4 chars — "s03a"/"s03b", tower floor styles) → area_id → DEFAULT. The
## s03b row and the wetlands turn (s02b_ga1 + the s02z downpour, #649) are
## the variant slots so far (#657: the B caves split off the snowfield
## night while s03a stages keep the area row).

const DEFAULT_SLOT := {"hour": 10.0}

const SLOTS := {
	# ── per-stage exceptions (most specific) ──
	# The coliseum debug arena is deliberately noon (kion); other s00 stages day.
	"s00a_nr2": {"hour": 12.0},

	# ── per-variant rows (#657: the first) ──
	# Snowfield B caves — pre-dawn under a blanket moon. LOCKED from the
	# in-field walk-lab read-out (2026-09-14): sun 0, ambient a faint 0.05
	# floor, moon 0.6 at −55° elevation with real shadows and geometry
	# casting (models/rocks shadow each other by position — the "implied
	# moon position" of the original art), COLOR_0 0.75 toward white so a
	# breath of the blue bake survives under the moon. Open-ceiling caves
	# snow (the 5 enclosed stages stay weather-skipped via INDOOR_STAGES);
	# anchors (pools / mushrooms / kinoko spores) are the local accents.
	"s03b": {
		"hour": 5.5,
		"sun_energy": 0.0,
		"ambient_energy": 0.05,
		"moon_energy": 0.6,
		"moon_pitch": -55.0,
		"moon_shadows": true,
		"bake_mix": 0.75,
		"geometry_casts_shadows": true,
		"weather": "snow",
	},

	# ── per-area identity slots ──
	# Valley day — the #648 "cheat" rig (kion art-direction calls, 2026-09-21):
	# the stage KEEPS its authored bake — pure baked vertex color, no bake_mix,
	# no white-strategy pass — and the dynamic sun lights only what the bake
	# could not account for: player + enemies (their own spawn paths) and the
	# lit_surfaces greenery/props. The player's DYNAMIC shadow lands via the
	# shadow_catcher: the collision shell (the walkable surface, exactly)
	# renders as a white multiply-blended receiver — shadows multiply onto
	# the bake, lit ground multiplies by ~1 — so the unwalkable low ground
	# keeps its intentional baked darkness ("you can't walk there") and no
	# lit/unlit floor boundary exists. sun_shadows arms the rig (blob
	# skipped); no geometry casting — only the actors cast, so no rim drama;
	# the panorama shadow-eye placement still runs. Blowing sand drift.
	# sun_pitch −60 is the actor-lighting character (DAY band parks −45).
	# lit_surfaces is GREENERY ONLY. Every hard-surface "prop" eventually
	# read bright and out of place against the baked world and came off:
	# deco1 (ground decals), oas* (oasis terrain), and the bridge/rail/toro
	# class (bri2 was the final read-out, 2026-09-22 — its mirror shader
	# stays the LIT variant under the keep-list, sunning the bridge against
	# baked rock). Plants blend because they're organic and soft; stone and
	# lumber don't. The toro lanterns keep their warm placed-light pools
	# without being lit themselves.
	"gurhacia": {
		"hour": 10.0,
		"sun_energy": 0.9,
		"ambient_energy": 0.4,
		"sun_pitch": -60.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"weather": "sand",
		"lit_surfaces": [
			"1_reaf1", "1_reaf2", "1_reaf3", "1_reaf4", "1_reaf5",
		],
	},

	# ── the wetlands weather arc (#649, kion 2026-09-23) ──
	# A (area row): the APPROVED pre-transition look, verbatim — the whole
	# stage on the receive path (lit_surfaces "*": ambient owns the bake,
	# dark-moody), sun off, the yellow-orange lantern pools painting the
	# pathway and casting the actors' swinging shadows onto the lit
	# ground. E is the transition: the rain breaks and a faint warm sun
	# peeks through the valley contract (unlit bake + catcher floor).
	# B continues the transition — EXCEPT s02b_ga1, the dark turn
	# (wildcard-lit again, sun off, the heavy rain, lightning) on the
	# road into Z, where the octopus boss waits in the same downpour.
	"ozette": {
		"hour": 10.0,
		"sun_energy": 0.0,
		"ambient_energy": 0.35,
		"ambient_color": Color(0.70, 0.75, 0.82),
		"sky_top_color": Color(0.42, 0.47, 0.53),
		"sky_horizon_color": Color(0.58, 0.62, 0.66),
		"weather": "drizzle",
		"lit_surfaces": ["*"],
		"post_lights": "0_light",
		"lit_props": true,
	},
	"s02e": {
		"hour": 10.0,
		"sun_energy": 0.1,
		"sun_color": Color(1.0, 0.94, 0.82),
		"sun_origin": [15.8, 14.7, -55.6],
		"sun_pitch": -49.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"ambient_energy": 0.3,
		"ambient_color": Color(0.70, 0.75, 0.82),
		"sky_top_color": Color(0.42, 0.47, 0.53),
		"sky_horizon_color": Color(0.58, 0.62, 0.66),
		"weather": "drizzle",
		"lit_surfaces": [],
		"lit_props": true,
	},
	# B carries the transition's look.
	"s02b": {
		"hour": 10.0,
		"sun_energy": 0.1,
		"sun_color": Color(1.0, 0.94, 0.82),
		"sun_origin": [15.8, 14.7, -55.6],
		"sun_pitch": -49.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"ambient_energy": 0.3,
		"ambient_color": Color(0.70, 0.75, 0.82),
		"sky_top_color": Color(0.42, 0.47, 0.53),
		"sky_horizon_color": Color(0.58, 0.62, 0.66),
		"weather": "drizzle",
		"lit_surfaces": [],
		"lit_props": true,
	},
	# The turn: b_ga1 goes dark and rainy on the road into Z (kion). The
	# WHOLE stage joins the receive path (lit_surfaces "*"): an unlit bake
	# can't be darkened, and with the sun off the catcher already holds
	# the floor at ambient — full-bright baked edges (water, walls, the
	# painted sky) read stupidly bright against it (kion read-outs).
	"s02b_ga1": {
		"hour": 10.0,
		"sun_energy": 0.0,
		"ambient_energy": 0.3,
		"ambient_color": Color(0.70, 0.75, 0.82),
		"sky_top_color": Color(0.42, 0.47, 0.53),
		"sky_horizon_color": Color(0.58, 0.62, 0.66),
		"weather": "rain",
		"lit_surfaces": ["*"],
		"shadow_catcher": true,
		"lit_props": true,
		"lightning": true,
	},
	# The octopus boss waits in the same dark downpour.
	"s02z": {
		"hour": 10.0,
		"sun_energy": 0.0,
		"ambient_energy": 0.3,
		"ambient_color": Color(0.70, 0.75, 0.82),
		"sky_top_color": Color(0.42, 0.47, 0.53),
		"sky_horizon_color": Color(0.58, 0.62, 0.66),
		"weather": "rain",
		"lit_surfaces": [],
		"shadow_catcher": true,
		"lit_props": true,
		"lightning": true,
	},
	# Snowfield night — the #646 lock, verbatim: sun off, bright ambient so the
	# white-albedo snow reads, moon 0.35 as the shadow source, bake quarter-
	# mixed for depth. Lantern pools punch through via ×12 spore-light energy.
	"rioh": {
		"hour": 22.0,
		"weather": "snow",
		"sun_energy": 0.0,
		"ambient_energy": 1.5,
		"moon_energy": 0.35,
		"moon_shadows": true,
		"bake_mix": 0.25,
	},
	"makara": {"hour": 10.0},     # B/E/Z baseline pending separate #650 review
	# #650: sparse red leaf fall indoors; entrance retains its separate baseline.
	"s04a": {"hour": 10.0, "signature": "makara_leaves", "lit_surfaces": []},
	"s04a_sa1": {"hour": 10.0},
	# Freestanding pillar rooms, directions read from each room's baked shadows.
	# Explicit empty lit_surfaces also selects the unlit mirror-wrap shader
	# for exit stairs (otherwise global illumination paints them gray).
	# Stage surfaces stay unshaded. Only actors cast onto the multiply receiver;
	# no second set of pillar shadows, crystal lights, or texture changes.
	"s04a_ib1": {
		"hour": 10.0,
		"sun_origin": [-40.0, 30.0, 14.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_ic1": {
		"hour": 10.0,
		"sun_origin": [-40.0, 30.0, 14.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_ic3": {
		"hour": 10.0,
		"sun_origin": [-40.0, 30.0, 14.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_lb1": {
		"hour": 10.0,
		"sun_origin": [-40.0, 30.0, -14.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_lc1": {
		"hour": 10.0,
		"sun_origin": [-40.0, 30.0, 14.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_lc2": {
		"hour": 10.0,
		"sun_origin": [-40.0, 30.0, 10.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_nc2": {
		"hour": 10.0,
		"sun_origin": [-14.0, 30.0, -40.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_tc3": {
		"hour": 10.0,
		"sun_origin": [-14.0, 30.0, -40.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},

	# #650 rooms without tall pillars: XZ bearings follow the broad baked
	# floor highlights in overhead previews; lb3 uses the user's (3.9, -6.3).
	# sun_origin aims toward the room origin, sun_pitch fixes the elevation.
	# The source is a directional proxy: no extra light pool over the bake.
	"s04a_ga1": {
		"hour": 10.0,
		"sun_origin": [-5.5, 30.0, -14.5],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_ib2": {
		"hour": 10.0,
		"sun_origin": [8.0, 30.0, 1.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_lb3": {
		"hour": 10.0,
		"sun_origin": [3.9, 30.0, -6.3],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.18,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_na1": {
		"hour": 10.0,
		"sun_origin": [0.0, 30.0, -5.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_nb2": {
		"hour": 10.0,
		"sun_origin": [-9.0, 30.0, -5.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_tb3": {
		"hour": 10.0,
		"sun_origin": [3.0, 30.0, -2.5],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_td1": {
		"hour": 10.0,
		"sun_origin": [-7.0, 30.0, 5.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_td2": {
		"hour": 10.0,
		"sun_origin": [0.0, 30.0, -3.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},
	"s04a_xb2": {
		"hour": 10.0,
		"sun_origin": [-8.0, 30.0, -10.0],
		"sun_pitch": -35.0,
		"sun_energy": 0.3,
		"sun_color": Color(1.0, 1.0, 1.0),
		"ambient_energy": 0.5,
		"ambient_color": Color(1.0, 1.0, 1.0),
		"moon_energy": 0.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "makara_leaves",
		"lit_surfaces": [],
	},

	# ── the Forgotten City ambient↔sun ladder (#651, kion 2026-09-28) ──
	# Valley-A lineage: the stage KEEPS its authored bake (no bake_mix) and
	# the rig lights only what the bake could not — actors, the greenery
	# keep-list, and the player shadow via the catcher. The variants differ
	# in nothing but the ambient/sun balance: A and Z ambient-led under a
	# faint sun (deep-forest shade), E the sun-led transition into the area,
	# B the balanced middle. Keep-list: 1_reaf1–5 — the leaf class across
	# every variant, the valley greenery precedent verbatim — plus tuta1
	# (B vines) and kusa1 (Z grass) as the organic walk-lab candidates;
	# trees, panorama, water/mist and every hard surface keep the bake.
	# Starting values pre-lock; the walk-lab P read-out owns the numbers.
	"paru": {
		"hour": 10.0,
		"sun_energy": 0.25,
		"ambient_energy": 0.55,
		"sun_pitch": -60.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"lit_surfaces": [
			"1_reaf1", "1_reaf2", "1_reaf3", "1_reaf4", "1_reaf5",
			"1_tuta1", "1_kusa1",
		],
	},
	# E — the transition: less ambient, a stronger, higher sun.
	"s05e": {
		"hour": 10.0,
		"sun_energy": 1.0,
		"ambient_energy": 0.25,
		"sun_pitch": -50.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"lit_surfaces": [
			"1_reaf1", "1_reaf2", "1_reaf3", "1_reaf4", "1_reaf5",
			"1_tuta1", "1_kusa1",
		],
	},
	# B — the balanced middle between the two.
	"s05b": {
		"hour": 10.0,
		"sun_energy": 0.6,
		"ambient_energy": 0.4,
		"sun_pitch": -55.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"lit_surfaces": [
			"1_reaf1", "1_reaf2", "1_reaf3", "1_reaf4", "1_reaf5",
			"1_tuta1", "1_kusa1",
		],
	},
	# ── the Moon Facility variants (#652, kion 2026-09-30) ──
	# Valley-A lineage with the stage's own twist: the facility is the one
	# area whose bake IS the look — kion's call was to keep it untouched (no
	# bake_mix, no lit_surfaces — the row's silence is the contract that the
	# sun can never light the stage) and let the rig own only what the bake
	# could not: the actors, and the player's shadow on the catcher floor.
	# A is the pristine lobby: low ambient fill, a weak sun whose whole job
	# is the shadow (kion: "just enough of a shadow") — the window rooms
	# (ic1/ic3/lc1/lc2/nc2/tc3, the moon through the glass) read right
	# already and just ride the row. B is the industrial dark kion calls his
	# favorite: barely any sun, and the composition is the COLORED fixture
	# pools — authored omnis per room (the <stage>_effects.json "light"
	# channel, #636) that reach only the actors, the stage being unlit.
	# E (transition) and Z (boss) ride the area row between the two.
	# FIRST DRAFT values (seeded from the s02e/s02b ladder — sun 0.1 +
	# ambient 0.3 under the catcher); the walk-lab P read-out owns the
	# numbers, and the B accents land with their effects files.
	"s06a": {
		"hour": 10.0,
		"sun_energy": 0.3,
		"ambient_energy": 0.35,
		"sun_pitch": -60.0,
		"sun_shadows": true,
		"shadow_catcher": true,
	},
	"s06b": {
		"hour": 10.0,
		"sun_energy": 0.1,
		"ambient_energy": 0.25,
		"sun_pitch": -60.0,
		"sun_shadows": true,
		"shadow_catcher": true,
	},
	"arca": {
		"hour": 10.0,
		"sun_energy": 0.2,
		"ambient_energy": 0.3,
		"sun_pitch": -60.0,
		"sun_shadows": true,
		"shadow_catcher": true,
	},
	# ── the Dark Shrine pin (#653, kion 2026-10-01; locked + fogged
	#    2026-10-02) ──
	# The arca contract again — the rows' silence keeps the stage unlit, the
	# bake IS the look — but pinned to the NIGHT preset's base (a near-black
	# sky where any peeks through, the preset moon zeroed: kion's rig is a
	# low sun whose only job is the minimum floor shadow). kion's first walk
	# read the 0.20 ambient as TOO DARK — the lock landed at 0.90 — then the
	# edge fog dimmed the read a little, and the SECOND lock (s07a_ga1,
	# 2026-10-02) is 1.30: just light enough to make out the floor
	# texture's detail, fog at 0.040 untouched (B scaled to keep the
	# ladder). The follow-up also asked for the dark edge fog (the far
	# walls dissolve into the dark instead of ending hard against
	# unmodeled space) and a subtle swirl in the motes. The area's identity is the SIGNATURE motes rising from the
	# ground — white on A, black on B (the Falz dark-castle side) — which
	# ride the `signature` knob, not `weather`, so they spawn indoors by
	# design. Sparse candle/urn accents land per-room as effects lights.
	# Reference-room prototype: preserve the floor bake, light actors overhead.
	"s07e_ia1": {
		"hour": 22.0,
		"sun_energy": 0.0,
		"moon_energy": 0.0,
		"ambient_energy": 0.35,
		"ambient_color": Color(0.55, 0.5, 0.6),
		"lit_surfaces": ["1_ayuka2", "1_ayukas", "1_kaidan"],
		"signature": "red_motes",
		"fog_density": 0.04,
		"fog_color": Color(0.03, 0.02, 0.04),
	},
	"s07a_ga1": {
		"hour": 22.0,
		"sun_energy": 0.0,
		"sun_color": Color(0.7, 0.75, 0.9),
		"ambient_energy": 0.35,
		"ambient_color": Color(0.55, 0.55, 0.65),
		"moon_energy": 0.0,
		"sun_pitch": -85.0,
		"sun_shadows": false,
		"shadow_catcher": false,
		"lit_surfaces": ["1_ayuka2", "1_ayukas", "1_kaidan", "1_kage"],
		"signature": "white_motes",
		"fog_density": 0.04,
		"fog_color": Color(0.03, 0.03, 0.06),
	},
	"s07a": {
		"hour": 22.0,
		"sun_energy": 0.1,
		"sun_color": Color(0.7, 0.75, 0.9),
		"ambient_energy": 1.3,
		"ambient_color": Color(0.55, 0.55, 0.65),
		"moon_energy": 0.0,
		"sun_pitch": -60.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "white_motes",
		"fog_density": 0.04,
		"fog_color": Color(0.03, 0.03, 0.06),
	},
	"s07b": {
		"hour": 22.0,
		# THE PIVOT (kion 2026-10-03, completed on the fourth walk): ambient
		# waaay down (their read-out: 0.05), NO sun, NO catcher — the MUL
		# catcher was crushing the lit floor to its ambient share (the
		# "barely lit" read). The stage rides the receive path (lit_surfaces
		# "*") so the pools paint the actual floor; the floor painters hang
		# at y 0.5 (targets "stage", the actors never see them), one casting
		# all-objects light at y 2.5 gives the actors their key AND their
		# real omni shadows on the lit ground. Composition: the middle of
		# the room lit, the edges falling into the fog.
		"sun_energy": 0.0,
		"ambient_energy": 0.05,
		"ambient_color": Color(0.55, 0.55, 0.65),
		"moon_energy": 0.0,
		"lit_surfaces": ["*"],
		"stage_light_layer": true,
		"signature": "black_motes",
		"fog_density": 0.18,
		"fog_color": Color(0.02, 0.02, 0.04),
		# CAMOUFLAGE, not mood (kion 2026-10-03, the s07b_ walkthrough): the
		# B stages are bright OPEN-AIR courtyards — no ceiling geometry, a
		# white sky above, low-res edge textures that read fine on the DS
		# screen and fall apart at Godot scale. The fog is concealment: near-
		# black clouds drowning the openness (0.18 eats everything past a
		# few units), the negative height density piling them overhead where
		# the ceiling should be, and tonemap_white 3.0 dims the too-light
		# bake (the field default is 6.0) while the 1000-mote storm fills
		# the air.
		"fog_height": 5.0,
		"fog_height_density": -0.7,
		"tonemap_white": 3.0,
	},
	# The boss arenas (two — na1 and na2): the B rig's black motes.
	"s07z": {
		"hour": 22.0,
		"sun_energy": 0.1,
		"sun_color": Color(0.7, 0.75, 0.9),
		"ambient_energy": 0.95,
		"ambient_color": Color(0.55, 0.55, 0.65),
		"moon_energy": 0.0,
		"sun_pitch": -60.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"signature": "black_motes",
		"fog_density": 0.18,
		"fog_color": Color(0.02, 0.02, 0.04),
		"fog_height": 5.0,
		"fog_height_density": -0.7,
		"tonemap_white": 3.0,
	},
	# The area row — s07e_ia1 (the transition) and the fallback: the rig
	# without the motes first draft (the transition may want its own mood
	# after it's walked).
	"dark": {
		"hour": 22.0,
		"sun_energy": 0.1,
		"sun_color": Color(0.7, 0.75, 0.9),
		"ambient_energy": 1.3,
		"ambient_color": Color(0.55, 0.55, 0.65),
		"moon_energy": 0.0,
		"sun_pitch": -60.0,
		"sun_shadows": true,
		"shadow_catcher": true,
		"fog_density": 0.04,
		"fog_color": Color(0.03, 0.03, 0.06),
	},
	"tower":  {"hour": 10.0},     # interim; #654 authors fixed-hour floors
	"city":   {"hour": 10.0},     # s00 field stages (city scenes carry no clock)
}


## Resolve the slot for a cell: stage-level rows beat variant-prefix rows beat
## the area row. Returns a row with "hour" always present. The table parameter
## exists so the unit test can exercise the ladder with synthetic rows.
static func slot_for(area_id: String, stage_id: String, table: Dictionary = SLOTS) -> Dictionary:
	if table.has(stage_id):
		return (table[stage_id] as Dictionary).duplicate()
	if stage_id.length() >= 4 and table.has(stage_id.substr(0, 4)):
		return (table[stage_id.substr(0, 4)] as Dictionary).duplicate()
	if table.has(area_id):
		return (table[area_id] as Dictionary).duplicate()
	return DEFAULT_SLOT.duplicate()


## Weather precedence (#655): a quest-authored session weather key overrides
## the row; otherwise the row's weather applies; indoor stages never spawn.
static func resolve_weather(session_weather: String, slot: Dictionary) -> String:
	if not session_weather.is_empty():
		return session_weather
	return str(slot.get("weather", ""))

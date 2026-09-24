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
	# The settled overcast look rides the area row — A/E/B all wear it
	# (the peeking-sun transition values were tuned ON the E stage): faint
	# warm sun at the baked spot, dark-moody ambient, the light drizzle,
	# lantern pools, the catcher floor. The turn is s02b_ga1: dark and
	# rainy overcast again (sun off, the heavy rain) on the road into Z,
	# where the octopus boss waits in the same downpour. The stage keeps
	# its bake everywhere (empty lit list — the sun never lights the
	# stage); lit_props brings boxes/fences/drops/NPCs onto the receive
	# path. The b/e/z stages ship no 0_light surface, so the dark rows
	# carry no post_lights (the blob returns there — no shadow source).
	"ozette": {
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
		"post_lights": "0_light",
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
	"makara": {"hour": 10.0},     # interim; #650 authors torch-dark
	"paru":   {"hour": 10.0},     # interim; #651 establishes the identity
	"arca":   {"hour": 10.0},     # interim; #652 authors fixture lights
	"dark":   {"hour": 10.0},     # interim; #653 authors the dark-interior pin
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

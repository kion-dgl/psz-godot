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
##   ambient_energy float ambient energy override
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
##                        strategy (#648 valley): greenery + props light,
##                        architecture stays authored. Needs no bake_mix;
##                        run after the field material pass so special-
##                        shader surfaces (waterfalls) are skipped
##   shadow_catcher bool the collision shell renders as the shadow receiver
##                        — white, multiply-blended, at the walk height:
##                        the actors' dynamic shadows multiply onto the
##                        bake while lit ground multiplies by ~1 (#648)
##
## Keys resolve most-specific-first: exact stage_id → variant prefix (first
## 4 chars — "s03a"/"s03b", tower floor styles) → area_id → DEFAULT. The s03b
## row is the variant slot so far (#657: the B caves split off the snowfield
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
	# lit_surfaces is DELIBERATELY sparse — only certain greenery/props —
	# because not every stage material imports unlit: 1_flo1/1_view1/
	# 1_rock1/1_step2 arrive SHADED, which is why the cheat rig also runs
	# the force-unlit pass (the MeshBasic guarantee) over everything not
	# listed. oas* stays OUT pending a look (suspected oasis terrain, and
	# the lit low ground in the 2026-09-21 screenshot read exactly like it).
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
			"1_deco1", "1_toro", "1_rail1", "1_bri2", "1_bri3",
		],
	},

	"ozette":   {"hour": 10.0},   # interim; #649 authors the overcast mood
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

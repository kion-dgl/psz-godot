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
##   moon_shadows  bool   moonlight casts real shadows (also skips the player
##                        blob shadow — blob + moon shadow reads double)
##   bake_mix      float COLOR_0 → white blend (0..1); presence implies the
##                        white-strategy material pass (neutralize + per-pixel)
##   tonemap_white float  tonemap white point override
##
## Keys resolve most-specific-first: exact stage_id → variant prefix (first
## 4 chars — "s03a"/"s03b", tower floor styles) → area_id → DEFAULT. The
## variant rung ships no rows yet; #657's s03b early-morning caves will be the
## first.

const DEFAULT_SLOT := {"hour": 10.0}

const SLOTS := {
	# ── per-stage exceptions (most specific) ──
	# The coliseum debug arena is deliberately noon (kion); other s00 stages day.
	"s00a_nr2": {"hour": 12.0},

	# ── per-area identity slots ──
	"gurhacia": {"hour": 10.0},   # Valley day — #648 tunes the balance
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
## exists so the unit test can exercise the ladder with synthetic rows — the
## shipped table carries no variant rows until #657.
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

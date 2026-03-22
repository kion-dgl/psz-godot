extends Node
## MagManager — handles mag feeding, leveling, and evolution.
## Ported from psz-sketch/src/systems/mag-feeder + mag-evolutions

const _RU = preload("res://scripts/utils/resource_utils.gd")

signal mag_fed(item_id: String, stat_changes: Dictionary)
signal mag_leveled_up(new_level: int)
signal mag_evolved(old_form: String, new_form: String)

const MAX_SYNC := 120
const MAX_IQ := 200
const STATS_PER_LEVEL := 5

## Feed effects per consumable item
const FEED_EFFECTS := {
	"monomate":      {"power": 1, "guard": 0, "hit": 0, "mind": 0, "sync": 5},
	"dimate":        {"power": 2, "guard": 0, "hit": 0, "mind": 0, "sync": 10},
	"trimate":       {"power": 3, "guard": 0, "hit": 0, "mind": 0, "sync": 15},
	"monofluid":     {"power": 0, "guard": 0, "hit": 0, "mind": 1, "sync": 5},
	"difluid":       {"power": 0, "guard": 0, "hit": 0, "mind": 2, "sync": 10},
	"trifluid":      {"power": 0, "guard": 0, "hit": 0, "mind": 3, "sync": 15},
	"antidote":      {"power": 0, "guard": 1, "hit": 0, "mind": 0, "sync": 3},
	"antiparalysis": {"power": 0, "guard": 1, "hit": 0, "mind": 0, "sync": 3},
	"sol_atomizer":  {"power": 0, "guard": 0, "hit": 2, "mind": 0, "sync": 8},
	"moon_atomizer": {"power": 1, "guard": 1, "hit": 1, "mind": 1, "sync": 10},
	"star_atomizer": {"power": 2, "guard": 2, "hit": 2, "mind": 2, "sync": 20},
	"debug_mag_power": {"power": 50, "guard": 0, "hit": 0, "mind": 0, "sync": 0},
	"debug_mag_guard": {"power": 0, "guard": 50, "hit": 0, "mind": 0, "sync": 0},
	"debug_mag_hit": {"power": 0, "guard": 0, "hit": 50, "mind": 0, "sync": 0},
	"debug_mag_mind": {"power": 0, "guard": 0, "hit": 0, "mind": 50, "sync": 0},
}

## Mag form_id → GLB model path mapping
## wmaa=Power, wmab=Guard, wmac=Hit, wmad=Mind, wmae=Rare; number=stage
const MAG_MODEL_MAP := {
	# Stage 1
	"mag": "res://assets/mags/wmaa1_1_1.glb",
	# Stage 2 (primary stat)
	"yul": "res://assets/mags/wmaa2_1_1.glb",   # Power
	"aio": "res://assets/mags/wmab2_1_1.glb",   # Guard
	"yth": "res://assets/mags/wmac2_1_1.glb",   # Hit
	"ingh": "res://assets/mags/wmad2_1_1.glb",  # Mind
	# Stage 3
	"othel": "res://assets/mags/wmaa3_1_1.glb",  # Power
	"thohn": "res://assets/mags/wmaa3_2_1.glb",  # Power alt
	"aiolo": "res://assets/mags/wmab3_1_1.glb",  # Guard
	"maray": "res://assets/mags/wmab3_2_1.glb",  # Guard alt
	"peoth": "res://assets/mags/wmac3_1_1.glb",  # Hit
	"teroo": "res://assets/mags/wmac3_2_1.glb",  # Hit alt
	"deegh": "res://assets/mags/wmad3_1_1.glb",  # Mind
	"niid": "res://assets/mags/wmad3_2_1.glb",   # Mind alt
	# Stage 4
	"urado": "res://assets/mags/wmaa4_1_1.glb",  # Power
	"wyn": "res://assets/mags/wmaa4_2_1.glb",    # Power
	"chato": "res://assets/mags/wmab4_1_1.glb",  # Power
	"beork": "res://assets/mags/wmab4_2_1.glb",  # Guard
	"larg": "res://assets/mags/wmab4_3_1.glb",   # Guard
	"tyrna": "res://assets/mags/wmac4_1_1.glb",  # Guard
	"ansul": "res://assets/mags/wmac4_2_1.glb",  # Hit
	"hagal": "res://assets/mags/wmac4_3_1.glb",  # Hit
	"sig": "res://assets/mags/wmad4_1_1.glb",    # Hit
	"feo": "res://assets/mags/wmad4_2_1.glb",    # Mind
	# Rare
	"toppi": "res://assets/mags/wmae5_1_1.glb",
	"femini": "res://assets/mags/wmae5_2_1.glb",
	"lassi": "res://assets/mags/wmae5_3_1.glb",
	"rappy": "res://assets/mags/wmae5_4_1.glb",
	"puyo": "res://assets/mags/wmae5_5_1.glb",
	"soniti": "res://assets/mags/wmae5_6_1.glb",
	"radam": "res://assets/mags/wmae5_7_1.glb",
	"arkharz": "res://assets/mags/wmae5_8_1.glb",
}

## All mag form data keyed by id, loaded from .tres files
var _mag_forms: Dictionary = {}


func _ready() -> void:
	_load_mag_forms()


func _load_mag_forms() -> void:
	for path in _RU.list_resources("res://data/mags/"):
		var mag_data = load(path)
		if mag_data:
			_mag_forms[mag_data.id] = mag_data
	print("[MagManager] Loaded %d mag forms" % _mag_forms.size())


## Get a mag form definition by id
func get_mag_form(form_id: String):
	return _mag_forms.get(form_id, null)


## Get all mag forms
func get_all_mag_forms() -> Dictionary:
	return _mag_forms


## Create a new mag instance (default state)
func create_mag() -> Dictionary:
	return {
		"form_id": "mag",
		"stats": {"power": 0, "guard": 0, "hit": 0, "mind": 0},
		"sync": 0,
		"iq": 0,
		"personality": "playful",
	}


## Calculate mag level from stats
func get_level(mag_state: Dictionary) -> int:
	var stats: Dictionary = mag_state.get("stats", {})
	var total: int = int(stats.get("power", 0)) + int(stats.get("guard", 0)) + int(stats.get("hit", 0)) + int(stats.get("mind", 0))
	return int(total / STATS_PER_LEVEL)


## Feed an item to the mag. Returns result dict.
func feed_mag(mag_state: Dictionary, item_id: String) -> Dictionary:
	if not FEED_EFFECTS.has(item_id):
		return {"success": false, "message": "Can't feed %s to mag." % item_id}

	var effects: Dictionary = FEED_EFFECTS[item_id]
	var stats: Dictionary = mag_state.get("stats", {})
	var level_before: int = get_level(mag_state)
	var form_before: String = mag_state.get("form_id", "mag")

	# Apply stat changes
	stats["power"] = int(stats.get("power", 0)) + int(effects.get("power", 0))
	stats["guard"] = int(stats.get("guard", 0)) + int(effects.get("guard", 0))
	stats["hit"] = int(stats.get("hit", 0)) + int(effects.get("hit", 0))
	stats["mind"] = int(stats.get("mind", 0)) + int(effects.get("mind", 0))
	mag_state["stats"] = stats

	# Apply sync (capped at MAX_SYNC)
	mag_state["sync"] = mini(int(mag_state.get("sync", 0)) + int(effects.get("sync", 0)), MAX_SYNC)

	# Increase IQ (capped at MAX_IQ)
	mag_state["iq"] = mini(int(mag_state.get("iq", 0)) + 1, MAX_IQ)

	var level_after: int = get_level(mag_state)
	var leveled_up: bool = level_after > level_before

	# Check for evolution
	var new_form_id: String = determine_form(mag_state)
	var evolved: bool = new_form_id != form_before
	mag_state["form_id"] = new_form_id

	if leveled_up:
		mag_leveled_up.emit(level_after)
	if evolved:
		mag_evolved.emit(form_before, new_form_id)

	var stat_changes := {
		"power": int(effects.get("power", 0)),
		"guard": int(effects.get("guard", 0)),
		"hit": int(effects.get("hit", 0)),
		"mind": int(effects.get("mind", 0)),
	}
	mag_fed.emit(item_id, stat_changes)

	var result := {
		"success": true,
		"message": "Fed %s to mag." % item_id,
		"level_before": level_before,
		"level_after": level_after,
		"form_before": form_before,
		"form_after": new_form_id,
		"leveled_up": leveled_up,
		"evolved": evolved,
		"stat_changes": stat_changes,
	}
	return result


## Determine which form a mag should be based on its stats
func determine_form(mag_state: Dictionary) -> String:
	var stats: Dictionary = mag_state.get("stats", {})
	var level: int = get_level(mag_state)

	if level < 10:
		return "mag"

	var primary: String = _get_highest_stat(stats)
	var secondary: String = _get_second_highest_stat(stats, primary)

	# Stage 4: Level 60+, requires dual stats (secondary > 0)
	if level >= 60:
		var sec_val: int = int(stats.get(secondary, 0))
		if sec_val > 0:
			for form_id in _mag_forms:
				var form = _mag_forms[form_id]
				if form.stage == "4" and form.evolution_requirement.get("type", "") == "stat":
					if form.evolution_requirement.get("primary", "") == primary.capitalize() and \
					   form.evolution_requirement.get("secondary", "") == secondary.capitalize():
						return form_id

	# Stage 3: Level 30+, primary stat
	if level >= 30:
		for form_id in _mag_forms:
			var form = _mag_forms[form_id]
			if form.stage == "3" and form.evolution_requirement.get("type", "") == "stat":
				if form.evolution_requirement.get("primary", "") == primary.capitalize():
					if not form.evolution_requirement.has("secondary"):
						return form_id

	# Stage 2: Level 10+, primary stat
	for form_id in _mag_forms:
		var form = _mag_forms[form_id]
		if form.stage == "2" and form.evolution_requirement.get("type", "") == "stat":
			if form.evolution_requirement.get("primary", "") == primary.capitalize():
				return form_id

	return "mag"


## Get the highest stat name
func _get_highest_stat(stats: Dictionary) -> String:
	var best_key := "power"
	var best_val: int = int(stats.get("power", 0))
	for key in ["guard", "hit", "mind"]:
		var val: int = int(stats.get(key, 0))
		if val > best_val:
			best_val = val
			best_key = key
	return best_key


## Get the second highest stat name (excluding primary)
func _get_second_highest_stat(stats: Dictionary, exclude: String) -> String:
	var best_key := ""
	var best_val: int = -1
	for key in ["power", "guard", "hit", "mind"]:
		if key == exclude:
			continue
		var val: int = int(stats.get(key, 0))
		if val > best_val:
			best_val = val
			best_key = key
	return best_key


## Get stat bonuses a mag provides to the character (each mag stat point = 2 character stat points)
func get_stat_bonuses(mag_state: Dictionary) -> Dictionary:
	var stats: Dictionary = mag_state.get("stats", {})
	return {
		"attack": int(stats.get("power", 0)) * 2,
		"defense": int(stats.get("guard", 0)) * 2,
		"accuracy": int(stats.get("hit", 0)) * 2,
		"technique": int(stats.get("mind", 0)) * 2,
	}


## Get the GLB model path for a mag form
func get_model_path(form_id: String) -> String:
	return MAG_MODEL_MAP.get(form_id, MAG_MODEL_MAP.get("mag", ""))


## Check if an item can be fed to a mag
func can_feed(item_id: String) -> bool:
	return FEED_EFFECTS.has(item_id)


## Check if an item ID (or instance ID) refers to a mag
func is_mag(item_id: String) -> bool:
	var base_id: String = Inventory.get_base_id(item_id)
	return _mag_forms.has(base_id)


## Get mag state from a character dict
func get_mag_state(character: Dictionary, mag_id: String) -> Dictionary:
	return character.get("mag_states", {}).get(mag_id, {})


## Add a new mag to a character's inventory + mag_states. Returns instance ID.
func add_mag_to_character(character: Dictionary, base_id: String) -> String:
	var inst_id: String = Inventory.add_weapon(base_id)
	if inst_id.is_empty():
		return ""
	if not character.has("mag_states"):
		character["mag_states"] = {}
	character["mag_states"][inst_id] = create_mag()
	return inst_id


## Get display name for a mag (form name + level)
func get_mag_display_name(character: Dictionary, mag_id: String) -> String:
	var state: Dictionary = get_mag_state(character, mag_id)
	if state.is_empty():
		var form = get_mag_form(Inventory.get_base_id(mag_id))
		if form:
			return form.name
		return mag_id
	var form = get_mag_form(state.get("form_id", "mag"))
	var form_name: String = form.name if form else "Mag"
	var level: int = get_level(state)
	return "%s Lv.%d" % [form_name, level]

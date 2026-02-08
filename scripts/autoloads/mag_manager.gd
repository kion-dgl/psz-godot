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


## Check if an item can be fed to a mag
func can_feed(item_id: String) -> bool:
	return FEED_EFFECTS.has(item_id)

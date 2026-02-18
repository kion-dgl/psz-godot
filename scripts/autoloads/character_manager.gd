extends Node
## CharacterManager — manages character slots, creation, deletion, and experience.
## Ported from psz-sketch/src/api/character.ts

const MAX_SLOTS := 4
const MAX_LEVEL := 100
const STARTING_MESETA := 500

signal character_created(slot: int)
signal character_deleted(slot: int)
signal active_character_changed(slot: int)
signal level_up(new_level: int)

## 4 character slots, each is a Dictionary or null
var _characters: Array = [null, null, null, null]
var _active_slot: int = -1


func _ready() -> void:
	pass


## Create a new character in the given slot
func create_character(slot: int, class_id: String, char_name: String, appearance: Dictionary = {}) -> Dictionary:
	if slot < 0 or slot >= MAX_SLOTS:
		push_warning("[CharacterManager] Invalid slot: ", slot)
		return {}
	if _characters[slot] != null:
		push_warning("[CharacterManager] Slot already occupied: ", slot)
		return {}

	var class_data = ClassRegistry.get_class_data(class_id)
	if class_data == null:
		push_warning("[CharacterManager] Unknown class: ", class_id)
		return {}

	var stats: Dictionary = class_data.get_stats_at_level(1)

	# Determine starter weapon from class type
	var starter_weapon: String = "saber"
	match class_data.type:
		"Ranger":
			starter_weapon = "handgun"
		"Force":
			starter_weapon = "rod"

	var character: Dictionary = {
		"name": char_name,
		"class_id": class_id,
		"level": 1,
		"experience": 0,
		"meseta": STARTING_MESETA,
		"hp": stats.get("hp", 100),
		"max_hp": stats.get("hp", 100),
		"pp": stats.get("pp", 50),
		"max_pp": stats.get("pp", 50),
		"materials_used": 0,
		"appearance": {
			"variation_index": int(appearance.get("variation_index", 0)),
			"body_color_index": int(appearance.get("body_color_index", 0)),
			"hair_color_index": int(appearance.get("hair_color_index", 0)),
			"skin_tone_index": int(appearance.get("skin_tone_index", 0)),
		},
		"equipment": {
			"weapon": starter_weapon,
			"frame": "normal_frame",
			"mag": "mag",
			"unit1": "",
			"unit2": "",
			"unit3": "",
			"unit4": "",
		},
		"inventory": {
			starter_weapon: 1,
			"normal_frame": 1,
			"mag": 1,
			"monomate": 5,
			"monofluid": 5,
		},
		"techniques": {},
		"weapon_grinds": {},
		"unidentified_weapons": [],
		"material_bonuses": {},
		"combat_buffs": {},
		"completed_missions": [],
		"storage": [],
		"created_at": Time.get_unix_time_from_system(),
	}

	_characters[slot] = character
	character_created.emit(slot)

	print("[CharacterManager] Created %s (%s) in slot %d" % [char_name, class_id, slot])
	return character


## Get character data for a slot (or null if empty)
func get_character(slot: int):
	if slot < 0 or slot >= MAX_SLOTS:
		return null
	return _characters[slot]


## Get the active character data
func get_active_character():
	if _active_slot < 0 or _active_slot >= MAX_SLOTS:
		return null
	return _characters[_active_slot]


## Set the active character slot (swaps inventory)
func set_active_slot(slot: int) -> void:
	if slot < 0 or slot >= MAX_SLOTS or _characters[slot] == null:
		return
	# Save outgoing character's data
	if _active_slot >= 0 and _active_slot < MAX_SLOTS and _characters[_active_slot] != null:
		_characters[_active_slot]["inventory"] = Inventory._items.duplicate()
		_characters[_active_slot]["completed_missions"] = GameState.completed_missions.duplicate()
	_active_slot = slot
	# Load incoming character's data
	Inventory._items = _characters[slot].get("inventory", {}).duplicate()
	GameState.completed_missions = _characters[slot].get("completed_missions", []).duplicate()
	active_character_changed.emit(slot)
	_sync_to_game_state()


## Get all characters (array of 4, with nulls for empty slots)
func get_all_characters() -> Array:
	return _characters.duplicate()


## Delete a character from a slot
func delete_character(slot: int) -> void:
	if slot < 0 or slot >= MAX_SLOTS:
		return
	if _characters[slot] == null:
		return
	_characters[slot] = null
	if _active_slot == slot:
		_active_slot = -1
		Inventory.clear_inventory()
	character_deleted.emit(slot)


## Add experience to the active character. Returns {leveled_up: bool, new_level: int}
func add_experience(amount: int) -> Dictionary:
	var character = get_active_character()
	if character == null:
		return {"leveled_up": false, "new_level": 0}

	character["experience"] = int(character["experience"]) + amount
	var old_level: int = character["level"]
	var new_level := _calculate_level(int(character["experience"]))
	var leveled_up := new_level > old_level

	if leveled_up:
		character["level"] = new_level
		var class_data = ClassRegistry.get_class_data(character["class_id"])
		if class_data:
			var stats: Dictionary = class_data.get_stats_at_level(new_level)
			character["max_hp"] = stats.get("hp", character["max_hp"])
			character["max_pp"] = stats.get("pp", character["max_pp"])
			character["hp"] = character["max_hp"]
			character["pp"] = character["max_pp"]
		level_up.emit(new_level)
		_sync_to_game_state()

	return {"leveled_up": leveled_up, "new_level": new_level}


## Get stats at a specific level for a class
func get_stats_at_level(class_id: String, level: int) -> Dictionary:
	var class_data = ClassRegistry.get_class_data(class_id)
	if class_data == null:
		return {}
	return class_data.get_stats_at_level(level)


## Get experience progress for active character
func get_exp_progress() -> Dictionary:
	var character = get_active_character()
	if character == null:
		return {"current": 0, "needed": 0, "percent": 0.0}

	var level: int = character["level"]
	var total_exp: int = character["experience"]
	var exp_table = _get_exp_table()
	if exp_table == null:
		return {"current": total_exp, "needed": 100, "percent": 0.0}

	var current_level_exp: int = exp_table.get_exp_for_level(level)
	var next_level_exp: int = exp_table.get_exp_to_next(level)
	var progress: int = total_exp - current_level_exp
	var percent := 0.0
	if next_level_exp > 0:
		percent = clampf(float(progress) / float(next_level_exp), 0.0, 1.0)

	return {"current": progress, "needed": next_level_exp, "percent": percent}


## Get the active slot index
func get_active_slot() -> int:
	return _active_slot


## Load characters from save data
func load_from_save(data: Array) -> void:
	for i in range(mini(data.size(), MAX_SLOTS)):
		_characters[i] = data[i]
		# Ensure inventory key exists for old saves
		if _characters[i] != null and not _characters[i].has("inventory"):
			_characters[i]["inventory"] = {}


## Get save data
func get_save_data() -> Array:
	return _characters.duplicate(true)


## Sync current runtime state to active character dict (call before saving)
func sync_inventory_to_active() -> void:
	if _active_slot >= 0 and _active_slot < MAX_SLOTS and _characters[_active_slot] != null:
		_characters[_active_slot]["inventory"] = Inventory._items.duplicate()
		_characters[_active_slot]["completed_missions"] = GameState.completed_missions.duplicate()


## Migrate v3 global completed_missions to all existing characters
func migrate_global_missions(missions_data: Array) -> void:
	for i in range(MAX_SLOTS):
		if _characters[i] != null and _characters[i].get("completed_missions", []).is_empty():
			_characters[i]["completed_missions"] = missions_data.duplicate()


## Migrate v2 global inventory to all existing characters
func migrate_global_inventory(inv_data: Dictionary) -> void:
	for i in range(MAX_SLOTS):
		if _characters[i] != null and _characters[i].get("inventory", {}).is_empty():
			_characters[i]["inventory"] = inv_data.duplicate()


## Heal the active character
func heal_character(hp_amount: int, pp_amount: int = 0) -> void:
	var character = get_active_character()
	if character == null:
		return
	character["hp"] = mini(int(character["hp"]) + hp_amount, int(character["max_hp"]))
	if pp_amount > 0:
		character["pp"] = mini(int(character["pp"]) + pp_amount, int(character["max_pp"]))
	_sync_to_game_state()


func _calculate_level(total_exp: int) -> int:
	var exp_table = _get_exp_table()
	if exp_table:
		return exp_table.get_level_for_exp(total_exp)
	# Fallback: simple formula
	return mini(int(sqrt(float(total_exp) / 50.0)) + 1, MAX_LEVEL)


func _get_exp_table():
	var path := "res://data/experience_table.tres"
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _sync_to_game_state() -> void:
	var character = get_active_character()
	if character == null:
		return
	GameState.set_max_hp(int(character["max_hp"]))
	GameState.set_hp(int(character["hp"]))
	GameState.set_max_mp(int(character["max_pp"]))
	GameState.set_mp(int(character["pp"]))
	GameState.meseta = int(character["meseta"])

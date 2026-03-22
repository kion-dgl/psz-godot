extends Node
## SaveManager — handles game persistence via JSON at user://save_data.json

const SAVE_PATH := "user://save_data.json"

signal game_saved()
signal game_loaded()


func _ready() -> void:
	load_game()


## Save all game data to disk
func save_game() -> void:
	# Sync current inventory into active character's data
	CharacterManager.sync_inventory_to_active()

	var save_data := {
		"version": 5,
		"characters": CharacterManager.get_save_data(),
		"shared_storage": GameState.shared_storage.duplicate(),
		"stored_meseta": GameState.stored_meseta,
		"timestamp": Time.get_unix_time_from_system(),
	}

	var json_str := JSON.stringify(save_data, "  ")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[SaveManager] Could not open save file for writing: ", SAVE_PATH)
		return

	file.store_string(json_str)
	file.close()
	print("[SaveManager] Game saved")
	game_saved.emit()


## Load game data from disk
func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[SaveManager] No save file found, starting fresh")
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("[SaveManager] Could not open save file for reading")
		return

	var json_str: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_str)
	if error != OK:
		push_warning("[SaveManager] Failed to parse save file: ", json.get_error_message())
		return

	var save_data: Dictionary = json.data
	if not save_data is Dictionary:
		push_warning("[SaveManager] Save data is not a dictionary")
		return

	# Load characters
	var characters: Array = save_data.get("characters", [])
	CharacterManager.load_from_save(characters)

	# Migrate v2 global inventory to per-character
	var version := int(save_data.get("version", 0))
	if version < 3 and save_data.has("inventory"):
		var inv_data: Dictionary = save_data.get("inventory", {})
		CharacterManager.migrate_global_inventory(inv_data)

	# Migrate v3 global completed_missions to per-character
	if version < 4 and save_data.has("completed_missions"):
		var missions_data: Array = save_data.get("completed_missions", [])
		CharacterManager.migrate_global_missions(missions_data)

	# Migrate v4 weapon_elements to weapon_stats with new photon IDs
	if version < 5:
		_migrate_v4_to_v5(characters)

	# Load shared storage
	GameState.shared_storage = save_data.get("shared_storage", []).duplicate()
	GameState.stored_meseta = int(save_data.get("stored_meseta", 0))

	print("[SaveManager] Game loaded (version %d)" % int(save_data.get("version", 0)))
	game_loaded.emit()


## Auto-save (called on key events)
func auto_save() -> void:
	save_game()


## Check if a save file exists
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Delete the save file
func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("[SaveManager] Save file deleted")


## Migrate v4 saves: map old photon IDs to new ones and create weapon_stats
func _migrate_v4_to_v5(characters: Array) -> void:
	var photon_map := {
		"fire_photon": "ban_photon",
		"ice_photon": "ray_photon",
		"poison_photon": "gra_photon",
		"shock_photon": "zon_photon",
		"devil_photon": "megi_photon",
	}
	var element_map := {
		"ban_photon": "fire",
		"ray_photon": "ice",
		"zon_photon": "lightning",
		"megi_photon": "dark",
		"gra_photon": "light",
	}

	for character in characters:
		if character == null:
			continue
		if not character.has("weapon_stats"):
			character["weapon_stats"] = {}

		var weapon_elements: Dictionary = character.get("weapon_elements", {})
		var new_elements: Dictionary = {}
		for weapon_id in weapon_elements:
			var old_photon: String = str(weapon_elements[weapon_id])
			var new_photon: String = photon_map.get(old_photon, old_photon)
			new_elements[weapon_id] = new_photon

			# Create weapon_stats entry if it doesn't exist
			if not character["weapon_stats"].has(weapon_id):
				var element: String = element_map.get(new_photon, "")
				character["weapon_stats"][weapon_id] = {
					"photon_id": new_photon,
					"element": element,
					"element_level": 1,
					"native_pct": 0,
					"beast_pct": 0,
					"machine_pct": 0,
					"dark_pct": 0,
					"hit_pct": 0,
				}

		character["weapon_elements"] = new_elements
	print("[SaveManager] Migrated v4→v5: weapon_elements → weapon_stats")

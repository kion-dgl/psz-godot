extends Node
## SaveManager — handles game persistence via JSON at user://save_data.json

const SAVE_PATH := "user://save_data.json"

signal game_saved()
signal game_loaded()


func _ready() -> void:
	load_game()


## Save all game data to disk
func save_game() -> void:
	var save_data := {
		"version": 1,
		"characters": CharacterManager.get_save_data(),
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

	var json_str := file.get_as_text()
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

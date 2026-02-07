extends Node
## Autoload that provides access to all ModifierData resources by ID.

const MODIFIERS_PATH = "res://data/modifiers/"

var _modifiers: Dictionary = {}

signal modifiers_loaded()


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_modifiers.clear()
	var dir = DirAccess.open(MODIFIERS_PATH)
	if dir == null:
		push_warning("[ModifierRegistry] Could not open directory: ", MODIFIERS_PATH)
		modifiers_loaded.emit()
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res = load(MODIFIERS_PATH + file_name)
			if res and not res.id.is_empty():
				_modifiers[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
	print("[ModifierRegistry] Loaded ", _modifiers.size(), " modifiers")
	modifiers_loaded.emit()


func get_modifier(id: String):
	return _modifiers.get(id, null)


func get_all_modifiers() -> Array:
	return _modifiers.values()

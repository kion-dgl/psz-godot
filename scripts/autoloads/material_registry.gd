extends Node
## Autoload that provides access to all MaterialData resources by ID.

const MATERIALS_PATH = "res://data/materials/"

var _materials: Dictionary = {}

signal materials_loaded()


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_materials.clear()
	var dir = DirAccess.open(MATERIALS_PATH)
	if dir == null:
		push_warning("[MaterialRegistry] Could not open directory: ", MATERIALS_PATH)
		materials_loaded.emit()
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res = load(MATERIALS_PATH + file_name)
			if res and not res.id.is_empty():
				_materials[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
	print("[MaterialRegistry] Loaded ", _materials.size(), " materials")
	materials_loaded.emit()


func get_material(id: String):
	return _materials.get(id, null)


func get_all_materials() -> Array:
	return _materials.values()


func get_all_material_ids() -> Array:
	return _materials.keys()

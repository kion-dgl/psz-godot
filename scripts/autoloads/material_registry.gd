extends Node
## Autoload that provides access to all MaterialData resources by ID.

const _RU = preload("res://scripts/utils/resource_utils.gd")
const MATERIALS_PATH = "res://data/materials/"

var _materials: Dictionary = {}

signal materials_loaded()


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_materials.clear()
	for path in _RU.list_resources(MATERIALS_PATH):
		var res = load(path)
		if res and not res.id.is_empty():
			_materials[res.id] = res
	print("[MaterialRegistry] Loaded ", _materials.size(), " materials")
	materials_loaded.emit()


func get_material(id: String):
	return _materials.get(id, null)


func get_all_materials() -> Array:
	return _materials.values()


func get_all_material_ids() -> Array:
	return _materials.keys()

extends Node
## Autoload that provides access to all MaterialData resources by ID.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const MATERIALS_PATH = "res://data/materials/"

var _materials: Dictionary = {}

signal materials_loaded()


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_RH.load_dir(MATERIALS_PATH, _materials, "MaterialRegistry", "materials")
	materials_loaded.emit()


func get_material(id: String):
	return _materials.get(id, null)


func get_all_materials() -> Array:
	return _materials.values()


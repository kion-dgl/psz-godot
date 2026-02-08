extends Node
## Autoload that provides access to all ModifierData resources by ID.

const _RU = preload("res://scripts/utils/resource_utils.gd")
const MODIFIERS_PATH = "res://data/modifiers/"

var _modifiers: Dictionary = {}

signal modifiers_loaded()


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_modifiers.clear()
	for path in _RU.list_resources(MODIFIERS_PATH):
		var res = load(path)
		if res and not res.id.is_empty():
			_modifiers[res.id] = res
	print("[ModifierRegistry] Loaded ", _modifiers.size(), " modifiers")
	modifiers_loaded.emit()


func get_modifier(id: String):
	return _modifiers.get(id, null)


func get_all_modifiers() -> Array:
	return _modifiers.values()

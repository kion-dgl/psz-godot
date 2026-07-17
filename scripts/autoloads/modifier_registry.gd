extends Node
## Autoload that provides access to all ModifierData resources by ID.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const MODIFIERS_PATH = "res://data/modifiers/"

var _modifiers: Dictionary = {}


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_RH.load_dir(MODIFIERS_PATH, _modifiers, "ModifierRegistry", "modifiers")


func get_modifier(id: String):
	return _modifiers.get(id, null)


func get_all_modifiers() -> Array:
	return _modifiers.values()

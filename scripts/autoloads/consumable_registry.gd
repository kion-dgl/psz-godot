extends Node
## Autoload that provides access to all ConsumableData resources by ID.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const CONSUMABLES_PATH = "res://data/consumables/"

var _consumables: Dictionary = {}


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_RH.load_dir(CONSUMABLES_PATH, _consumables, "ConsumableRegistry", "consumables")


func get_consumable(id: String):
	return _consumables.get(id, null)


func get_all_consumables() -> Array:
	return _consumables.values()


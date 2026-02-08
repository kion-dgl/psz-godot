extends Node
## Autoload that provides access to all ConsumableData resources by ID.

const _RU = preload("res://scripts/utils/resource_utils.gd")
const CONSUMABLES_PATH = "res://data/consumables/"

var _consumables: Dictionary = {}

signal consumables_loaded()


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_consumables.clear()
	for path in _RU.list_resources(CONSUMABLES_PATH):
		var res = load(path)
		if res and not res.id.is_empty():
			_consumables[res.id] = res
	print("[ConsumableRegistry] Loaded ", _consumables.size(), " consumables")
	consumables_loaded.emit()


func get_consumable(id: String):
	return _consumables.get(id, null)


func has_consumable(id: String) -> bool:
	return _consumables.has(id)


func get_all_consumables() -> Array:
	return _consumables.values()


func get_consumable_count() -> int:
	return _consumables.size()

extends Node
## Autoload that provides access to all UnitData resources by ID.

const _RU = preload("res://scripts/utils/resource_utils.gd")
const UNITS_PATH = "res://data/units/"
var _units: Dictionary = {}
signal units_loaded()

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_units.clear()
	for path in _RU.list_resources(UNITS_PATH):
		var res = load(path)
		if res and not res.id.is_empty():
			_units[res.id] = res
	print("[UnitRegistry] Loaded ", _units.size(), " units")
	units_loaded.emit()

func get_unit(id: String):
	return _units.get(id, null)

func get_all_units() -> Array:
	return _units.values()

func get_units_by_category(category: String) -> Array:
	var result: Array = []
	for unit in _units.values():
		if unit.category == category:
			result.append(unit)
	return result

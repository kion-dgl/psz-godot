extends Node
## Autoload that provides access to all UnitData resources by ID.

const UNITS_PATH = "res://data/units/"
var _units: Dictionary = {}
signal units_loaded()

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_units.clear()
	var dir = DirAccess.open(UNITS_PATH)
	if dir == null:
		units_loaded.emit()
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res = load(UNITS_PATH + file_name)
			if res and not res.id.is_empty():
				_units[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
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

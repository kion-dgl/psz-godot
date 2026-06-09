extends Node
## Autoload that provides access to all UnitData resources by ID.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const UNITS_PATH = "res://data/units/"
var _units: Dictionary = {}
signal units_loaded()

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_RH.load_dir(UNITS_PATH, _units, "UnitRegistry", "units")
	units_loaded.emit()

func get_unit(id: String):
	return _units.get(id, null)

func get_all_units() -> Array:
	return _units.values()

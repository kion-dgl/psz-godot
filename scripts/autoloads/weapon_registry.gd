extends Node
## Autoload that provides access to all WeaponData resources by ID.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const WEAPONS_PATH = "res://data/weapons/"

var _weapons: Dictionary = {}

signal weapons_loaded()


func _ready() -> void:
	_load_all_weapons()


func _load_all_weapons() -> void:
	_RH.load_dir(WEAPONS_PATH, _weapons, "WeaponRegistry", "weapons")
	weapons_loaded.emit()


func get_weapon(weapon_id: String):
	var result = _weapons.get(weapon_id, null)
	if result != null:
		return result
	# Strip instance suffix (e.g., "ein_saber#2" → "ein_saber")
	var idx: int = weapon_id.rfind("#")
	if idx >= 0:
		return _weapons.get(weapon_id.substr(0, idx), null)
	return null


func get_all_weapon_ids() -> Array:
	return _weapons.keys()


func get_weapon_count() -> int:
	return _weapons.size()

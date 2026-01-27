extends Node
## Autoload that provides access to all WeaponData resources by ID.

const WEAPONS_PATH = "res://data/weapons/"

var _weapons: Dictionary = {}

signal weapons_loaded()


func _ready() -> void:
	_load_all_weapons()


func _load_all_weapons() -> void:
	_weapons.clear()

	var dir = DirAccess.open(WEAPONS_PATH)
	if dir == null:
		push_warning("[WeaponRegistry] Could not open weapons directory: ", WEAPONS_PATH)
		weapons_loaded.emit()
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var full_path = WEAPONS_PATH + file_name
			var weapon = load(full_path)
			if weapon and not weapon.id.is_empty():
				_weapons[weapon.id] = weapon
		file_name = dir.get_next()

	dir.list_dir_end()
	print("[WeaponRegistry] Loaded ", _weapons.size(), " weapons")
	weapons_loaded.emit()


func get_weapon(weapon_id: String):
	return _weapons.get(weapon_id, null)


func has_weapon(weapon_id: String) -> bool:
	return _weapons.has(weapon_id)


func get_weapons_by_type(weapon_type: int) -> Array:
	var result: Array = []
	for weapon in _weapons.values():
		if weapon.weapon_type == weapon_type:
			result.append(weapon)
	return result


func get_all_weapon_ids() -> Array:
	return _weapons.keys()


func get_weapon_count() -> int:
	return _weapons.size()

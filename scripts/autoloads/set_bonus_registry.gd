extends Node
## Autoload that provides access to all SetBonusData resources by ID.

const _RU = preload("res://scripts/utils/resource_utils.gd")
const SET_BONUSES_PATH = "res://data/set_bonuses/"

var _set_bonuses: Dictionary = {}

signal set_bonuses_loaded()


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_set_bonuses.clear()
	for path in _RU.list_resources(SET_BONUSES_PATH):
		var res = load(path)
		if res and not res.id.is_empty():
			_set_bonuses[res.id] = res
	print("[SetBonusRegistry] Loaded ", _set_bonuses.size(), " set bonuses")
	set_bonuses_loaded.emit()


func get_set_bonus(id: String):
	return _set_bonuses.get(id, null)


func get_all_set_bonuses() -> Array:
	return _set_bonuses.values()


## Check if equipped armor+weapon have a set bonus. Returns bonus dict or empty.
func get_set_bonus_for_equipment(armor_name: String, weapon_name: String) -> Dictionary:
	for bonus in _set_bonuses.values():
		if bonus.armor == armor_name and weapon_name in bonus.weapons:
			return bonus.bonuses.duplicate()
	return {}

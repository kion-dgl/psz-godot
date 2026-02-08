extends Node
## Autoload that provides access to all ArmorData resources by ID.

const _RU = preload("res://scripts/utils/resource_utils.gd")
const ARMORS_PATH = "res://data/armors/"

var _armors: Dictionary = {}

signal armors_loaded()


func _ready() -> void:
	_load_all_armors()


func _load_all_armors() -> void:
	_armors.clear()
	for path in _RU.list_resources(ARMORS_PATH):
		var armor = load(path)
		if armor and not armor.id.is_empty():
			_armors[armor.id] = armor
	print("[ArmorRegistry] Loaded ", _armors.size(), " armors")
	armors_loaded.emit()


func get_armor(armor_id: String):
	return _armors.get(armor_id, null)


func has_armor(armor_id: String) -> bool:
	return _armors.has(armor_id)


func get_armors_by_type(armor_type: int) -> Array:
	var result: Array = []
	for armor in _armors.values():
		if armor.type == armor_type:
			result.append(armor)
	return result


func get_all_armor_ids() -> Array:
	return _armors.keys()


func get_armor_count() -> int:
	return _armors.size()

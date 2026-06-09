extends Node
## Autoload that provides access to all ArmorData resources by ID.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const ARMORS_PATH = "res://data/armors/"

var _armors: Dictionary = {}

signal armors_loaded()


func _ready() -> void:
	_load_all_armors()


func _load_all_armors() -> void:
	_RH.load_dir(ARMORS_PATH, _armors, "ArmorRegistry", "armors")
	armors_loaded.emit()


func get_armor(armor_id: String):
	return _armors.get(armor_id, null)


func has_armor(armor_id: String) -> bool:
	return _armors.has(armor_id)


func get_armor_count() -> int:
	return _armors.size()

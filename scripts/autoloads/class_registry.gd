extends Node
## Autoload that provides access to all ClassData resources by ID.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const CLASSES_PATH = "res://data/classes/"

var _classes: Dictionary = {}


func _ready() -> void:
	_load_all_classes()


func _load_all_classes() -> void:
	if _RH.load_dir(CLASSES_PATH, _classes, "ClassRegistry", "classes") == 0:
		push_warning("[ClassRegistry] Could not load any classes from: ", CLASSES_PATH)


func get_class_data(class_id: String):
	return _classes.get(class_id, null)


func get_all_classes() -> Array:
	return _classes.values()


func get_class_count() -> int:
	return _classes.size()

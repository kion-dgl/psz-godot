extends Node
## Autoload that provides access to all ClassData resources by ID.

const _RU = preload("res://scripts/utils/resource_utils.gd")
const CLASSES_PATH = "res://data/classes/"

var _classes: Dictionary = {}

signal classes_loaded()


func _ready() -> void:
	_load_all_classes()


func _load_all_classes() -> void:
	_classes.clear()
	for path in _RU.list_resources(CLASSES_PATH):
		var class_res = load(path)
		if class_res and not class_res.id.is_empty():
			_classes[class_res.id] = class_res
	if _classes.is_empty():
		push_warning("[ClassRegistry] Could not load any classes from: ", CLASSES_PATH)
	print("[ClassRegistry] Loaded ", _classes.size(), " classes")
	classes_loaded.emit()


func get_class_data(class_id: String):
	return _classes.get(class_id, null)


func has_class(class_id: String) -> bool:
	return _classes.has(class_id)


func get_all_classes() -> Array:
	return _classes.values()


func get_all_class_ids() -> Array:
	return _classes.keys()


func get_classes_by_type(type: String) -> Array:
	var result: Array = []
	for cls in _classes.values():
		if cls.type == type:
			result.append(cls)
	return result


func get_class_count() -> int:
	return _classes.size()

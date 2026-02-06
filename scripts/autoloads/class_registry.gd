extends Node
## Autoload that provides access to all ClassData resources by ID.

const CLASSES_PATH = "res://data/classes/"

var _classes: Dictionary = {}

signal classes_loaded()


func _ready() -> void:
	_load_all_classes()


func _load_all_classes() -> void:
	_classes.clear()
	var dir = DirAccess.open(CLASSES_PATH)
	if dir == null:
		push_warning("[ClassRegistry] Could not open classes directory: ", CLASSES_PATH)
		classes_loaded.emit()
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var full_path = CLASSES_PATH + file_name
			var class_res = load(full_path)
			if class_res and not class_res.id.is_empty():
				_classes[class_res.id] = class_res
		file_name = dir.get_next()
	dir.list_dir_end()
	print("[ClassRegistry] Loaded ", _classes.size(), " classes")
	classes_loaded.emit()


func get_class(class_id: String):
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

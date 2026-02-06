extends Node
## Autoload that provides access to all ConsumableData resources by ID.

const CONSUMABLES_PATH = "res://data/consumables/"

var _consumables: Dictionary = {}

signal consumables_loaded()


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_consumables.clear()
	var dir = DirAccess.open(CONSUMABLES_PATH)
	if dir == null:
		push_warning("[ConsumableRegistry] Could not open directory: ", CONSUMABLES_PATH)
		consumables_loaded.emit()
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res = load(CONSUMABLES_PATH + file_name)
			if res and not res.id.is_empty():
				_consumables[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
	print("[ConsumableRegistry] Loaded ", _consumables.size(), " consumables")
	consumables_loaded.emit()


func get_consumable(id: String):
	return _consumables.get(id, null)


func has_consumable(id: String) -> bool:
	return _consumables.has(id)


func get_all_consumables() -> Array:
	return _consumables.values()


func get_consumable_count() -> int:
	return _consumables.size()

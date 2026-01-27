extends Node
## Autoload that provides access to all ItemData resources by ID.
## Loads all .tres files from data/items/ on startup.

const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const ITEMS_PATH = "res://data/items/"

## Dictionary of item_id -> ItemData
var _items: Dictionary = {}

## Signal emitted when all items are loaded
signal items_loaded()


func _ready() -> void:
	_load_all_items()


## Load all ItemData resources from the items directory
func _load_all_items() -> void:
	_items.clear()

	var dir = DirAccess.open(ITEMS_PATH)
	if dir == null:
		push_warning("[ItemRegistry] Could not open items directory: ", ITEMS_PATH)
		items_loaded.emit()
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var full_path = ITEMS_PATH + file_name
			var item = load(full_path)
			if item and not item.id.is_empty():
				_items[item.id] = item
				print("[ItemRegistry] Loaded: ", item.id, " (", item.name, ")")
			else:
				push_warning("[ItemRegistry] Invalid item at: ", full_path)
		file_name = dir.get_next()

	dir.list_dir_end()
	print("[ItemRegistry] Loaded ", _items.size(), " items")
	items_loaded.emit()


## Get an item by its ID, returns null if not found
func get_item(item_id: String):
	return _items.get(item_id, null)


## Check if an item exists
func has_item(item_id: String) -> bool:
	return _items.has(item_id)


## Get all items of a specific type
func get_items_by_type(type: int) -> Array:
	var result: Array = []
	for item in _items.values():
		if item.type == type:
			result.append(item)
	return result


## Get all item IDs
func get_all_item_ids() -> Array:
	return _items.keys()


## Get total number of registered items
func get_item_count() -> int:
	return _items.size()


## Reload all items (useful for development)
func reload_items() -> void:
	_load_all_items()

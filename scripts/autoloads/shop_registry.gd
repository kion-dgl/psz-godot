extends Node
## Autoload that provides access to all ShopData resources by ID.

const SHOPS_PATH = "res://data/shops/"

var _shops: Dictionary = {}

signal shops_loaded()


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_shops.clear()
	var dir = DirAccess.open(SHOPS_PATH)
	if dir == null:
		push_warning("[ShopRegistry] Could not open directory: ", SHOPS_PATH)
		shops_loaded.emit()
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res = load(SHOPS_PATH + file_name)
			if res and not res.id.is_empty():
				_shops[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
	print("[ShopRegistry] Loaded ", _shops.size(), " shops")
	shops_loaded.emit()


func get_shop(id: String):
	return _shops.get(id, null)


func get_all_shops() -> Array:
	return _shops.values()

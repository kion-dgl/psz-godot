extends Node
## Autoload that provides access to all ShopData resources by ID.

const _RU = preload("res://scripts/utils/resource_utils.gd")
const SHOPS_PATH = "res://data/shops/"

var _shops: Dictionary = {}

signal shops_loaded()


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_shops.clear()
	for path in _RU.list_resources(SHOPS_PATH):
		var res = load(path)
		if res and not res.id.is_empty():
			_shops[res.id] = res
	print("[ShopRegistry] Loaded ", _shops.size(), " shops")
	shops_loaded.emit()


func get_shop(id: String):
	return _shops.get(id, null)


func get_all_shops() -> Array:
	return _shops.values()

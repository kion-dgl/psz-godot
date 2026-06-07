extends Node
## Autoload that provides access to all ShopData resources by ID.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const SHOPS_PATH = "res://data/shops/"

var _shops: Dictionary = {}

signal shops_loaded()


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	_RH.load_dir(SHOPS_PATH, _shops, "ShopRegistry", "shops")
	shops_loaded.emit()


func get_shop(id: String):
	return _shops.get(id, null)


func get_all_shops() -> Array:
	return _shops.values()

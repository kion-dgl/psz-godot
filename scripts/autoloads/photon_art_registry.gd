extends Node
## Autoload that provides access to all PhotonArtData resources by ID.

const _RU = preload("res://scripts/utils/resource_utils.gd")
const ARTS_PATH = "res://data/photon_arts/"
var _arts: Dictionary = {}
signal arts_loaded()

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_arts.clear()
	for path in _RU.list_resources(ARTS_PATH):
		var res = load(path)
		if res and not res.id.is_empty():
			_arts[res.id] = res
	print("[PhotonArtRegistry] Loaded ", _arts.size(), " photon arts")
	arts_loaded.emit()

func get_art(id: String):
	return _arts.get(id, null)

func get_all_arts() -> Array:
	return _arts.values()

func get_arts_by_weapon_type(weapon_type: String) -> Array:
	var result: Array = []
	for art in _arts.values():
		if art.weapon_type == weapon_type:
			result.append(art)
	return result

func get_arts_by_class(class_type: String) -> Array:
	var result: Array = []
	for art in _arts.values():
		if art.class_type == class_type:
			result.append(art)
	return result

extends Node
## Autoload that provides access to all PhotonArtData resources by ID.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const ARTS_PATH = "res://data/photon_arts/"
var _arts: Dictionary = {}
signal arts_loaded()

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_RH.load_dir(ARTS_PATH, _arts, "PhotonArtRegistry", "photon arts")
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

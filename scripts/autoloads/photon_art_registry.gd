extends Node
## Autoload that provides access to all PhotonArtData resources by ID.

const ARTS_PATH = "res://data/photon_arts/"
var _arts: Dictionary = {}
signal arts_loaded()

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_arts.clear()
	var dir = DirAccess.open(ARTS_PATH)
	if dir == null:
		arts_loaded.emit()
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res = load(ARTS_PATH + file_name)
			if res and not res.id.is_empty():
				_arts[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
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

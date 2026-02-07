extends Node
## Autoload that provides access to DropTableData resources.

const DROPS_PATH = "res://data/drop_tables/"
var _drops: Dictionary = {}
signal drops_loaded()

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_drops.clear()
	var dir = DirAccess.open(DROPS_PATH)
	if dir == null:
		drops_loaded.emit()
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res = load(DROPS_PATH + file_name)
			if res and not res.id.is_empty():
				_drops[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
	print("[DropRegistry] Loaded ", _drops.size(), " drop tables")
	drops_loaded.emit()

func get_drop_table(difficulty: String):
	return _drops.get(difficulty, null)

func get_enemy_drops(difficulty: String, area: String, enemy_name: String) -> Array:
	var table = get_drop_table(difficulty)
	if table == null:
		return []
	var area_data: Dictionary = table.area_drops.get(area, {})
	return area_data.get(enemy_name, [])

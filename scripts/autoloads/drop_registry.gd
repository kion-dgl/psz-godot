extends Node
## Autoload that provides access to DropTableData resources.

const _RH = preload("res://scripts/utils/registry_helper.gd")
const DROPS_PATH = "res://data/drop_tables/"
var _drops: Dictionary = {}
signal drops_loaded()

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_RH.load_dir(DROPS_PATH, _drops, "DropRegistry", "drop tables")
	drops_loaded.emit()

func get_drop_table(difficulty: String):
	return _drops.get(difficulty, null)

func get_enemy_drops(difficulty: String, area: String, enemy_name: String) -> Array:
	var table = get_drop_table(difficulty)
	if table == null:
		return []
	var area_data: Dictionary = table.area_drops.get(area, {})
	return area_data.get(enemy_name, [])

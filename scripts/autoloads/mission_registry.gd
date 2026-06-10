extends Node
## Autoload that provides access to MissionData.

const _RU = preload("res://scripts/utils/resource_utils.gd")
const MISSIONS_PATH = "res://data/missions/"

var _missions: Dictionary = {}

signal data_loaded()

func _ready() -> void:
	_load_dir(MISSIONS_PATH, _missions, "MissionRegistry:missions")
	data_loaded.emit()

func _load_dir(path: String, dict: Dictionary, label: String) -> void:
	for res_path in _RU.list_resources(path):
		var res = load(res_path)
		if res and not res.id.is_empty():
			dict[res.id] = res
	print("[%s] Loaded %d" % [label, dict.size()])

func get_mission(id: String):
	return _missions.get(id, null)

func get_all_missions() -> Array:
	return _missions.values()

func get_main_missions() -> Array:
	var result: Array = []
	for mission in _missions.values():
		if mission.is_main:
			result.append(mission)
	return result

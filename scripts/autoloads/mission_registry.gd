extends Node
## Autoload that provides access to MissionData, QuestAreaData, and QuestDefinitionData.

const MISSIONS_PATH = "res://data/missions/"
const QUEST_AREAS_PATH = "res://data/quest_areas/"
const QUEST_DEFS_PATH = "res://data/quest_definitions/"

var _missions: Dictionary = {}
var _quest_areas: Dictionary = {}
var _quest_defs: Dictionary = {}

signal data_loaded()

func _ready() -> void:
	_load_dir(MISSIONS_PATH, _missions, "MissionRegistry:missions")
	_load_dir(QUEST_AREAS_PATH, _quest_areas, "MissionRegistry:quest_areas")
	_load_dir(QUEST_DEFS_PATH, _quest_defs, "MissionRegistry:quest_defs")
	data_loaded.emit()

func _load_dir(path: String, dict: Dictionary, label: String) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res = load(path + file_name)
			if res and not res.id.is_empty():
				dict[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
	print("[%s] Loaded %d" % [label, dict.size()])

func get_mission(id: String):
	return _missions.get(id, null)

func get_all_missions() -> Array:
	return _missions.values()

func get_quest_area(id: String):
	return _quest_areas.get(id, null)

func get_all_quest_areas() -> Array:
	return _quest_areas.values()

func get_quest_definition(id: String):
	return _quest_defs.get(id, null)

func get_all_quest_definitions() -> Array:
	return _quest_defs.values()

func get_main_missions() -> Array:
	var result: Array = []
	for mission in _missions.values():
		if mission.is_main:
			result.append(mission)
	return result

extends Node
## SessionManager — manages field/mission sessions, stage/wave progression.
## Ported from psz-sketch/src/api/location.ts

signal session_started(data: Dictionary)
signal stage_advanced(stage: int)
signal wave_advanced(wave: int)
signal session_ended()

const MAX_STAGES := 3
const MAX_WAVES := 3

var _session: Dictionary = {}
var _location: String = "city"


## Enter a field area
func enter_field(area_id: String, difficulty: String) -> Dictionary:
	_session = {
		"type": "field",
		"area_id": area_id,
		"difficulty": difficulty,
		"stage": 1,
		"wave": 1,
		"total_exp": 0,
		"total_meseta": 0,
		"items_collected": [],
	}
	_location = "field"
	session_started.emit(_session)
	return _session


## Enter a mission
func enter_mission(mission_id: String, difficulty: String) -> Dictionary:
	# Look up area from mission data and convert to spawner area_id
	var area_id := "gurhacia"
	var mission = MissionRegistry.get_mission(mission_id)
	if mission:
		area_id = _area_name_to_id(mission.area)
	_session = {
		"type": "mission",
		"mission_id": mission_id,
		"area_id": area_id,
		"difficulty": difficulty,
		"stage": 1,
		"wave": 1,
		"total_exp": 0,
		"total_meseta": 0,
		"items_collected": [],
	}
	_location = "field"
	session_started.emit(_session)
	return _session


## Convert display area name to spawner area_id
func _area_name_to_id(area_name: String) -> String:
	var mapping := {
		"Gurhacia Valley": "gurhacia",
		"Rioh Snowfield": "rioh",
		"Ozette Wetland": "ozette",
		"Oblivion City Paru": "paru",
		"Makura Ruins": "makara", "Makara Ruins": "makara",
		"Arca Plant": "arca",
		"Dark Shrine": "dark",
		"Eternal Tower": "dark",
	}
	return mapping.get(area_name, "gurhacia")


## Advance to next wave. Returns true if there's a next wave, false if stage complete.
func next_wave() -> bool:
	if _session.is_empty():
		return false
	var wave: int = int(_session.get("wave", 1))
	if wave < MAX_WAVES:
		_session["wave"] = wave + 1
		wave_advanced.emit(int(_session["wave"]))
		return true
	return false


## Advance to next stage. Returns true if there's a next stage, false if session complete.
func next_stage() -> bool:
	if _session.is_empty():
		return false
	var stage: int = int(_session.get("stage", 1))
	if stage < MAX_STAGES:
		_session["stage"] = stage + 1
		_session["wave"] = 1
		stage_advanced.emit(int(_session["stage"]))
		return true
	return false


## Add rewards to running session totals
func add_rewards(exp_amount: int, meseta: int) -> void:
	_session["total_exp"] = int(_session.get("total_exp", 0)) + exp_amount
	_session["total_meseta"] = int(_session.get("total_meseta", 0)) + meseta


## Return to city and end session
func return_to_city() -> Dictionary:
	var summary: Dictionary = _session.duplicate()
	_session.clear()
	_location = "city"
	session_ended.emit()
	return summary


## Get current session data
func get_session() -> Dictionary:
	return _session


## Get current location
func get_location() -> String:
	return _location


## Check if a session is active
func has_active_session() -> bool:
	return not _session.is_empty()

extends Node
## MapManager - Handles map loading, transitions, and spawn points
## Complete Valley configuration ported from psz-sketch valleyConfig.ts

signal map_changed(map_id: String)
signal transition_started(from_map: String, to_map: String)

# Current map state
var current_map_id: String = ""
var current_map_scene: Node3D = null

# Map scene paths
const MAP_PATH_PREFIX := "res://assets/stages/"

# Spawn point data structure
class SpawnPoint:
	var position: Vector3
	var rotation: float
	var label: String
	var is_default: bool

	func _init(pos: Vector3, rot: float, lbl: String = "", default: bool = false) -> void:
		position = pos
		rotation = rot
		label = lbl
		is_default = default

# Trigger data structure
class TriggerData:
	var position: Vector3
	var rotation: float
	var size: Vector3

	func _init(pos: Vector3, rot: float = 0.0, sz: Vector3 = Vector3(4, 3, 4)) -> void:
		position = pos
		rotation = rot
		size = sz

# Map configuration
class MapConfig:
	var spawn_points: Array[SpawnPoint]
	var triggers: Array[TriggerData]

	func _init() -> void:
		spawn_points = []
		triggers = []

	func get_default_spawn() -> SpawnPoint:
		for sp in spawn_points:
			if sp.is_default:
				return sp
		if spawn_points.size() > 0:
			return spawn_points[0]
		return SpawnPoint.new(Vector3(0, 1, 0), 0.0)

	func get_spawn(index: int) -> SpawnPoint:
		if index >= 0 and index < spawn_points.size():
			return spawn_points[index]
		return get_default_spawn()

# Valley stage configurations
var valley_config: Dictionary = {}

# Map routing - defines which maps connect to which
# Key: "from_map:trigger_index", Value: { "map": "target_map", "spawn": spawn_index }
var map_routes: Dictionary = {}


func _ready() -> void:
	_init_valley_config()
	_init_map_routes()


func _init_valley_config() -> void:
	var cfg: MapConfig

	# ==================== VALLEY ROUTE A ====================

	# s01a_sa1 - Start area (1-gate: south)
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-2, 1, 24), PI, "south", true))
	cfg.triggers.append(TriggerData.new(Vector3(-2, 1, 29), PI))
	valley_config["s01a_sa1"] = cfg

	# s01a_ga1 - Entry stage
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-6.3, 1, 23.47), PI, "south", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(1.9, 1, -23.88), 0.0, "north", false))
	cfg.triggers.append(TriggerData.new(Vector3(1.85, 1, -27.28)))
	cfg.triggers.append(TriggerData.new(Vector3(-6.1, 1, 28.27)))
	valley_config["s01a_ga1"] = cfg

	# s01a_ib1 - Intermediate B1
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-17.3, 1, -22.28), 0.0, "north", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(14.2, 1, 21.97), PI, "south", false))
	cfg.triggers.append(TriggerData.new(Vector3(-17.15, 1, -25.78)))
	cfg.triggers.append(TriggerData.new(Vector3(14.25, 1, 26.42)))
	valley_config["s01a_ib1"] = cfg

	# s01a_ib2 - Intermediate B2
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(11.8, 1, 22.42), PI, "south", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-17.3, 1, -22.93), 0.0, "north", false))
	cfg.triggers.append(TriggerData.new(Vector3(-17.15, 1, -26.63)))
	cfg.triggers.append(TriggerData.new(Vector3(11.8, 1, 27.02)))
	valley_config["s01a_ib2"] = cfg

	# s01a_ic1 - Intermediate C1
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-13.6, 1, -23.23), 0.0, "north", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(11.05, 1, 14.42), 3.927, "east", false))
	cfg.triggers.append(TriggerData.new(Vector3(-13.4, 1, -26.23)))
	cfg.triggers.append(TriggerData.new(Vector3(15.65, 1, 16.47), 3.927))
	valley_config["s01a_ic1"] = cfg

	# s01a_ic3 - Intermediate C3
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-19.05, 1, -17.43), 0.0, "north", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(18.95, 1, 22.37), PI, "south", false))
	cfg.triggers.append(TriggerData.new(Vector3(-18.85, 1, -20.88)))
	cfg.triggers.append(TriggerData.new(Vector3(19.05, 1, 26.87)))
	valley_config["s01a_ic3"] = cfg

	# s01a_lb1 - Large B1
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-17.2, 1, -22.28), 0.0, "north", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(30.05, 1, -11.18), 4.7124, "east", false))
	cfg.triggers.append(TriggerData.new(Vector3(-17.05, 1, -25.98)))
	cfg.triggers.append(TriggerData.new(Vector3(34.6, 1, -14.98), 2.3562))
	valley_config["s01a_lb1"] = cfg

	# s01a_lb3 - Large B3
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-6.2, 1, -27.28), 0.0, "north", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(21.75, 1, 12.02), 4.7124, "east", false))
	cfg.triggers.append(TriggerData.new(Vector3(-6.2, 1, -30.53)))
	cfg.triggers.append(TriggerData.new(Vector3(26.15, 1, 11.67), 1.5708))
	valley_config["s01a_lb3"] = cfg

	# s01a_lc1 - Large C1
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-13.35, 1, -23.23), 0.0, "north", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(18.6, 1, 13.47), 4.7124, "east", false))
	cfg.triggers.append(TriggerData.new(Vector3(-13.45, 1, -26.43)))
	cfg.triggers.append(TriggerData.new(Vector3(23.05, 1, 13.42), 1.5708))
	valley_config["s01a_lc1"] = cfg

	# s01a_lc2 - Large C2
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(28.85, 1, -10.43), 4.7124, "west", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(14.1, 1, -25.43), 0.0, "north", false))
	cfg.triggers.append(TriggerData.new(Vector3(32.85, 1, -10.53), 4.7124))
	cfg.triggers.append(TriggerData.new(Vector3(13.75, 1, -28.63)))
	valley_config["s01a_lc2"] = cfg

	# s01a_na1 - Narrow A1 (boss area entrance, 1-gate: south)
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(19, 1, 17.12), PI, "south", true))
	cfg.triggers.append(TriggerData.new(Vector3(19.1, 1, 21.87)))
	valley_config["s01a_na1"] = cfg

	# s01a_nb2 - Narrow B2 (dead-end, 1-gate: south)
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(17, 1, 24), PI, "south", true))
	cfg.triggers.append(TriggerData.new(Vector3(17, 1, 29), PI))
	valley_config["s01a_nb2"] = cfg

	# s01a_nc2 - Narrow C2 (dead-end, 1-gate: south)
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-14, 1, 24), PI, "south", true))
	cfg.triggers.append(TriggerData.new(Vector3(-14, 1, 29), PI))
	valley_config["s01a_nc2"] = cfg

	# s01a_td1 - T-shaped D1 (3-gate: east, south, west)
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(24, 1, 1), -PI / 2, "east", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-14, 1, 24), PI, "south", false))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-24, 1, -16), PI / 2, "west", false))
	cfg.triggers.append(TriggerData.new(Vector3(29, 1, 1), -PI / 2))
	cfg.triggers.append(TriggerData.new(Vector3(-14, 1, 29), PI))
	cfg.triggers.append(TriggerData.new(Vector3(-29, 1, -16), PI / 2))
	valley_config["s01a_td1"] = cfg

	# s01a_td2 - T-shaped D2 (3-gate: east, west, south)
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(24, 1, 6.5), -PI / 2, "east", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-24, 1, -0.5), PI / 2, "west", false))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-14.5, 1, 24), PI, "south", false))
	cfg.triggers.append(TriggerData.new(Vector3(29, 1, 6.5), -PI / 2))
	cfg.triggers.append(TriggerData.new(Vector3(-29, 1, -0.5), PI / 2))
	cfg.triggers.append(TriggerData.new(Vector3(-14.5, 1, 29), PI))
	valley_config["s01a_td2"] = cfg

	# s01a_tb3 - T-shaped B3
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-21.05, 1, -11.88), 1.5708, "west", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(24.6, 1, 8.52), 4.7124, "east", false))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(6, 1, 26.92), PI, "south", false))
	cfg.triggers.append(TriggerData.new(Vector3(6.2, 1, 31.02)))
	cfg.triggers.append(TriggerData.new(Vector3(29.2, 1, 8.17), 4.7124))
	cfg.triggers.append(TriggerData.new(Vector3(-25.7, 1, -12.23), 1.5708))
	valley_config["s01a_tb3"] = cfg

	# s01a_tc3 - T-shaped C3
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(29.1, 1, -16.93), 4.7124, "west", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(18.95, 1, 23.37), PI, "south", false))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-28, 1, 5.92), 1.5708, "east", false))
	cfg.triggers.append(TriggerData.new(Vector3(19.1, 1, 27.97)))
	cfg.triggers.append(TriggerData.new(Vector3(-31.35, 1, 5.47), 1.5708))
	cfg.triggers.append(TriggerData.new(Vector3(33.3, 1, -16.78), 4.7124))
	valley_config["s01a_tc3"] = cfg

	# s01a_xb2 - Crossroad B2
	cfg = MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-16.95, 1, -23.08), 0.0, "north", true))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(-33.25, 1, 15.82), 1.5708, "west", false))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(11.9, 1, 23.42), PI, "south", false))
	cfg.spawn_points.append(SpawnPoint.new(Vector3(31.8, 1, -4.18), 4.7124, "east", false))
	cfg.triggers.append(TriggerData.new(Vector3(-16.7, 1, -26.98)))
	cfg.triggers.append(TriggerData.new(Vector3(-36.75, 1, 16.02), 1.5708))
	cfg.triggers.append(TriggerData.new(Vector3(12, 1, 27.22)))
	cfg.triggers.append(TriggerData.new(Vector3(35.45, 1, -5.08), 4.7124))
	valley_config["s01a_xb2"] = cfg


func _init_map_routes() -> void:
	# Valley Route A - Main progression path
	# ga1 → ib1 → ic1 → lb1 → lc1 → na1 (boss)

	# ga1: trigger 0 → ib1, trigger 1 → exit (lobby)
	map_routes["s01a_ga1:0"] = { "map": "s01a_ib1", "spawn": 1 }
	# map_routes["s01a_ga1:1"] = exit to lobby

	# ib1: trigger 0 → ic1, trigger 1 → ga1
	map_routes["s01a_ib1:0"] = { "map": "s01a_ic1", "spawn": 1 }
	map_routes["s01a_ib1:1"] = { "map": "s01a_ga1", "spawn": 1 }

	# ib2: trigger 0 → ic3, trigger 1 → ib1
	map_routes["s01a_ib2:0"] = { "map": "s01a_ic3", "spawn": 1 }
	map_routes["s01a_ib2:1"] = { "map": "s01a_ib1", "spawn": 1 }

	# ic1: trigger 0 → lb1, trigger 1 → ib1
	map_routes["s01a_ic1:0"] = { "map": "s01a_lb1", "spawn": 1 }
	map_routes["s01a_ic1:1"] = { "map": "s01a_ib1", "spawn": 0 }

	# ic3: trigger 0 → lb3, trigger 1 → ib2
	map_routes["s01a_ic3:0"] = { "map": "s01a_lb3", "spawn": 1 }
	map_routes["s01a_ic3:1"] = { "map": "s01a_ib2", "spawn": 0 }

	# lb1: trigger 0 → lc1, trigger 1 → ic1
	map_routes["s01a_lb1:0"] = { "map": "s01a_lc1", "spawn": 1 }
	map_routes["s01a_lb1:1"] = { "map": "s01a_ic1", "spawn": 0 }

	# lb3: trigger 0 → tb3, trigger 1 → ic3
	map_routes["s01a_lb3:0"] = { "map": "s01a_tb3", "spawn": 2 }
	map_routes["s01a_lb3:1"] = { "map": "s01a_ic3", "spawn": 0 }

	# lc1: trigger 0 → na1, trigger 1 → lb1
	map_routes["s01a_lc1:0"] = { "map": "s01a_na1", "spawn": 0 }
	map_routes["s01a_lc1:1"] = { "map": "s01a_lb1", "spawn": 0 }

	# lc2: trigger 0 → tc3, trigger 1 → xb2
	map_routes["s01a_lc2:0"] = { "map": "s01a_tc3", "spawn": 2 }
	map_routes["s01a_lc2:1"] = { "map": "s01a_xb2", "spawn": 3 }

	# na1: trigger 0 → lc1 (back from boss area)
	map_routes["s01a_na1:0"] = { "map": "s01a_lc1", "spawn": 0 }

	# tb3: trigger 0 → xb2, trigger 1 → tc3, trigger 2 → lb3
	map_routes["s01a_tb3:0"] = { "map": "s01a_xb2", "spawn": 2 }
	map_routes["s01a_tb3:1"] = { "map": "s01a_tc3", "spawn": 0 }
	map_routes["s01a_tb3:2"] = { "map": "s01a_lb3", "spawn": 0 }

	# tc3: trigger 0 → xb2, trigger 1 → lc2, trigger 2 → tb3
	map_routes["s01a_tc3:0"] = { "map": "s01a_xb2", "spawn": 2 }
	map_routes["s01a_tc3:1"] = { "map": "s01a_lc2", "spawn": 0 }
	map_routes["s01a_tc3:2"] = { "map": "s01a_tb3", "spawn": 1 }

	# xb2: 4-way crossroad
	map_routes["s01a_xb2:0"] = { "map": "s01a_ib2", "spawn": 1 }
	map_routes["s01a_xb2:1"] = { "map": "s01a_tc3", "spawn": 1 }
	map_routes["s01a_xb2:2"] = { "map": "s01a_tb3", "spawn": 0 }
	map_routes["s01a_xb2:3"] = { "map": "s01a_lc2", "spawn": 1 }


func get_map_config(map_id: String) -> MapConfig:
	if valley_config.has(map_id):
		return valley_config[map_id]
	# Return default config
	var cfg := MapConfig.new()
	cfg.spawn_points.append(SpawnPoint.new(Vector3(0, 1, 0), 0.0, "default", true))
	return cfg


func get_route(map_id: String, trigger_index: int) -> Dictionary:
	var key := "%s:%d" % [map_id, trigger_index]
	if map_routes.has(key):
		return map_routes[key]
	return {}


func get_trigger_count(map_id: String) -> int:
	var cfg := get_map_config(map_id)
	return cfg.triggers.size()


func get_trigger_data(map_id: String, trigger_index: int) -> TriggerData:
	var cfg := get_map_config(map_id)
	if trigger_index >= 0 and trigger_index < cfg.triggers.size():
		return cfg.triggers[trigger_index]
	return null


## Get list of gate edge names for a stage (e.g. ["north", "south"])
func get_gate_edges(stage_id: String) -> Array[String]:
	var cfg: MapConfig = valley_config.get(stage_id)
	if cfg == null:
		return []
	var edges: Array[String] = []
	for sp in cfg.spawn_points:
		if not sp.label.is_empty() and sp.label not in edges:
			edges.append(sp.label)
	return edges


## Get spawn point by label (gate edge name)
func get_spawn_by_label(stage_id: String, label: String) -> SpawnPoint:
	var cfg: MapConfig = valley_config.get(stage_id)
	if cfg == null:
		return null
	for sp in cfg.spawn_points:
		if sp.label == label:
			return sp
	return null


## Get trigger by index matching a spawn label
func get_trigger_for_label(stage_id: String, label: String) -> TriggerData:
	var cfg: MapConfig = valley_config.get(stage_id)
	if cfg == null:
		return null
	for i in range(cfg.spawn_points.size()):
		if cfg.spawn_points[i].label == label:
			if i < cfg.triggers.size():
				return cfg.triggers[i]
	return null

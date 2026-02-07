extends Node
## CityState — persists player position/rotation across push_scene/pop_scene
## transitions and between area loads within the 3D city hub.

var _position: Variant = null  # Vector3 or null
var _rotation: float = 0.0
var _area: String = ""
var _spawn_key: String = ""  # e.g. "counter-exit", "warp-exit"


func save_player_state(pos: Vector3, rot: float, area: String) -> void:
	_position = pos
	_rotation = rot
	_area = area


func get_player_position() -> Variant:
	return _position


func get_player_rotation() -> float:
	return _rotation


func get_area() -> String:
	return _area


func set_spawn_key(key: String) -> void:
	_spawn_key = key


func get_spawn_key() -> String:
	return _spawn_key


func clear() -> void:
	_position = null
	_rotation = 0.0
	_area = ""
	_spawn_key = ""

extends Node3D
## Third-person orbit camera controller.
## Left/Right arrows orbit horizontally at fixed radius. Home re-centers behind player.
## Player movement is camera-relative (handled in player.gd via get_viewport().get_camera_3d()).

# Camera settings
@export var distance: float = 6.0
@export var height: float = 3.0
@export var rotation_speed: float = 0.05

# Target to follow
@export var target_path: NodePath
var target: Node3D

# Camera rotation state (horizontal orbit angle)
var camera_rotation: float = 0.0

# Node references
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	if target_path:
		target = get_node_or_null(target_path)

	# Detach Camera3D from parent hierarchy so we control its world position directly.
	# This prevents the Camera3D's local transform from stacking on top of our positioning.
	camera.set_as_top_level(true)

	if target:
		_update_camera_position()


func _process(_delta: float) -> void:
	if Input.is_action_pressed("camera_left"):
		camera_rotation -= rotation_speed
	if Input.is_action_pressed("camera_right"):
		camera_rotation += rotation_speed

	if Input.is_action_just_pressed("camera_center"):
		_center_behind_player()

	if target and camera:
		_update_camera_position()


func _update_camera_position() -> void:
	if not target:
		return

	var target_pos := target.global_position
	var look_at_pos := Vector3(target_pos.x, target_pos.y + 1.0, target_pos.z)

	# Fixed-radius orbit: camera always exactly 'distance' away horizontally, 'height' above
	var cam_pos := Vector3(
		target_pos.x + sin(camera_rotation) * distance,
		target_pos.y + height,
		target_pos.z + cos(camera_rotation) * distance,
	)

	camera.global_position = cam_pos
	camera.look_at(look_at_pos)


func _center_behind_player() -> void:
	if not target:
		return
	# "Behind" = camera offset opposite to player's facing direction.
	# Player moves in (sin(player_rot), 0, cos(player_rot)).
	# Camera at player_rot + PI is on the opposite side, looking at the player's back.
	var player_rot: float = target.get("player_rotation") if target.get("player_rotation") != null else 0.0
	camera_rotation = player_rot + PI


func set_target(new_target: Node3D) -> void:
	target = new_target


func get_camera_rotation() -> float:
	return camera_rotation


func set_camera_rotation(new_rotation: float) -> void:
	camera_rotation = new_rotation

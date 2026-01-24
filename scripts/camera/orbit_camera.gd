extends Node3D
## Third-person orbit camera controller
## Ported from psz-sketch CameraController.tsx

# Camera settings
@export var distance: float = 6.0
@export var height: float = 3.0
@export var rotation_speed: float = 0.05
@export var follow_smoothness: float = 0.1

# Target to follow (set externally or find by path)
@export var target_path: NodePath
var target: Node3D

# Camera rotation state
var camera_rotation: float = 0.0

# Node references
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	# Find target if path is set
	if target_path:
		target = get_node_or_null(target_path)

	# Snap camera to target position immediately
	if target:
		_snap_to_target()


func _process(_delta: float) -> void:
	# Handle camera rotation input
	if Input.is_action_pressed("camera_left"):
		camera_rotation -= rotation_speed
	if Input.is_action_pressed("camera_right"):
		camera_rotation += rotation_speed

	# Update camera position if we have a target
	if target and camera:
		_update_camera_position()


func _update_camera_position() -> void:
	if not target:
		return

	# Get target position
	var target_pos := target.global_position

	# Calculate camera offset based on rotation
	var offset_x := sin(camera_rotation) * distance
	var offset_z := cos(camera_rotation) * distance

	# Desired camera position
	var desired_pos := Vector3(
		target_pos.x + offset_x,
		target_pos.y + height,
		target_pos.z + offset_z
	)

	# Smoothly move camera to desired position
	global_position = global_position.lerp(desired_pos, follow_smoothness)

	# Look at target (slightly above ground level)
	var look_target := Vector3(target_pos.x, target_pos.y + 1.0, target_pos.z)
	camera.look_at(look_target)


func set_target(new_target: Node3D) -> void:
	target = new_target


func get_camera_rotation() -> float:
	return camera_rotation


func set_camera_rotation(new_rotation: float) -> void:
	camera_rotation = new_rotation


func _snap_to_target() -> void:
	if not target:
		return

	var target_pos := target.global_position
	var offset_x := sin(camera_rotation) * distance
	var offset_z := cos(camera_rotation) * distance

	global_position = Vector3(
		target_pos.x + offset_x,
		target_pos.y + height,
		target_pos.z + offset_z
	)

	if camera:
		var look_target := Vector3(target_pos.x, target_pos.y + 1.0, target_pos.z)
		camera.look_at(look_target)

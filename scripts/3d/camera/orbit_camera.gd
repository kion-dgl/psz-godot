extends Node3D
## Third-person orbit camera controller.
## Left/Right arrows or mouse drag orbit horizontally at fixed radius.
## Right stick Y tilts the camera up/down (added 2026-05-08 for parity
## with most modern third-person controllers).
## Home re-centers behind player and resets pitch.
## Player movement is camera-relative (handled in player.gd via get_viewport().get_camera_3d()).

# Camera settings
@export var distance: float = 4.5
@export var height: float = 1.9
@export var rotation_speed: float = 0.05
@export var mouse_sensitivity: float = 0.005
## Min/max pitch as offset from the default look angle (which is set by
## `height` + `distance`). Clamping a touch under ±90° avoids gimbal-lock
## flips when looking straight up/down at the player.
@export var min_pitch_offset: float = -PI * 0.35
@export var max_pitch_offset: float = PI * 0.35

# Target to follow
@export var target_path: NodePath
var target: Node3D

# Camera rotation state (horizontal orbit angle)
var camera_rotation: float = 0.0
# Pitch *offset* from the default look angle (atan2(height, distance)).
# Positive tilts the camera up (more sky), negative tilts down (more ground).
var camera_pitch: float = 0.0

# Mouse drag state
var _mouse_dragging := false

# Set false to pause camera rotation (e.g. gate nudge mode)
var input_enabled := true

# Vertical follow smoothing (#538). The player's Y picks up a per-step sawtooth
# descending stairs (no step-down snap, so it walks off each edge and re-grounds);
# hard-assigning the camera Y every frame passed that 1:1 into the view as shake.
# Damp ONLY the follow Y — horizontal orbit stays instant — and snap on a large
# jump so the camera doesn't slide across a warp/respawn.
const CAM_Y_SMOOTH_TAU: float = 0.12   # seconds; larger = smoother but laggier
const CAM_Y_SNAP_DIST: float = 3.0     # gap beyond which we snap instead of damp
var _follow_y: float = 0.0
var _follow_y_valid: bool = false

# Node references
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	if target_path:
		target = get_node_or_null(target_path)

	# Detach Camera3D from parent hierarchy so we control its world position directly.
	# This prevents the Camera3D's local transform from stacking on top of our positioning.
	camera.set_as_top_level(true)

	if target:
		_update_camera_position(0.0)


func _process(delta: float) -> void:
	if input_enabled and not PsoStartMenu.is_open():
		var dir: float = 1.0 if InputConfig.invert_camera_x else -1.0
		if Input.is_action_pressed("camera_left"):
			camera_rotation -= rotation_speed * dir
		if Input.is_action_pressed("camera_right"):
			camera_rotation += rotation_speed * dir
		# Y-axis tilt is opt-in — gated on InputConfig.enable_camera_y so
		# the right-stick Y resting noise doesn't accidentally pitch the
		# camera for players who haven't opted in.
		if InputConfig.enable_camera_y:
			if Input.is_action_pressed("camera_up"):
				camera_pitch = clamp(camera_pitch + rotation_speed, min_pitch_offset, max_pitch_offset)
			if Input.is_action_pressed("camera_down"):
				camera_pitch = clamp(camera_pitch - rotation_speed, min_pitch_offset, max_pitch_offset)
		if Input.is_action_just_pressed("camera_lock"):
			_center_behind_player()

	if target and camera:
		_update_camera_position(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_dragging = mb.pressed
			# Capture mouse while dragging for smooth movement
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_dragging else Input.MOUSE_MODE_VISIBLE
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mouse_dragging = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_dragging else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and _mouse_dragging:
		var motion := event as InputEventMouseMotion
		camera_rotation += motion.relative.x * mouse_sensitivity


func _update_camera_position(delta: float) -> void:
	if not target:
		return

	var target_pos := target.global_position

	# Damp only the vertical follow (#538): absorbs the stair-descent Y sawtooth
	# so it doesn't shake the view, while x/z track the player instantly. First
	# frame (and large jumps, via the helper) snap so there's no startup slide.
	if not _follow_y_valid:
		_follow_y = target_pos.y
		_follow_y_valid = true
	else:
		_follow_y = _damp_follow_y(_follow_y, target_pos.y, delta)

	var look_at_pos := Vector3(target_pos.x, _follow_y + 1.0, target_pos.z)

	# Sphere-orbit: derive a single radius + base pitch from the
	# exported `distance`/`height` so pitch=0 reproduces the original
	# fixed-circle behavior, then user `camera_pitch` rotates around the
	# horizontal axis. Final pitch is clamped to the exported offsets,
	# additionally bounded under ±~88° as a safety net so the camera can
	# never flip through the look target even with user-edited offsets.
	const _SAFETY_PITCH: float = PI * 0.49
	var radius: float = sqrt(distance * distance + height * height)
	var base_pitch: float = atan2(height, distance)
	var min_pitch: float = max(base_pitch + min_pitch_offset, -_SAFETY_PITCH)
	var max_pitch: float = min(base_pitch + max_pitch_offset, _SAFETY_PITCH)
	var pitch: float = clamp(base_pitch + camera_pitch, min_pitch, max_pitch)
	var horiz: float = cos(pitch) * radius
	var vert: float = sin(pitch) * radius

	var cam_pos := Vector3(
		target_pos.x + sin(camera_rotation) * horiz,
		_follow_y + vert,
		target_pos.z + cos(camera_rotation) * horiz,
	)

	camera.global_position = cam_pos
	camera.look_at(look_at_pos)


## Frame-rate-independent exponential damping of the follow Y toward target_y.
## Snaps (returns target_y) when delta is non-positive or the gap exceeds
## CAM_Y_SNAP_DIST, so a warp/respawn doesn't slide and a settled frame is exact.
static func _damp_follow_y(current: float, target_y: float, delta: float) -> float:
	if delta <= 0.0 or absf(target_y - current) > CAM_Y_SNAP_DIST:
		return target_y
	return lerp(current, target_y, 1.0 - exp(-delta / CAM_Y_SMOOTH_TAU))


func _center_behind_player() -> void:
	if not target:
		return
	# "Behind" = camera offset opposite to player's facing direction.
	# Player moves in (sin(player_rot), 0, cos(player_rot)).
	# Camera at player_rot + PI is on the opposite side, looking at the player's back.
	var player_rot: float = target.get("player_rotation") if target.get("player_rotation") != null else 0.0
	camera_rotation = player_rot + PI
	# Recenter pitch too — same intent as horizontal: snap to default.
	camera_pitch = 0.0


func set_target(new_target: Node3D) -> void:
	target = new_target


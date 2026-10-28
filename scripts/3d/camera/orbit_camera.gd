extends Node3D
## Original world camera (spec /mechanics/camera) — the PSZ Mini's camera
## slot 1 model, ported from the decomp's verified world_camera.c: fixed
## elevation, look point easing to the player at 50%/frame, fixed-rate manual
## rotate, Δ/8 recenter ease, and a running-only follow swing whose rate is
## proportional to the player's per-frame displacement. No pitch control —
## the mouse orbit and player pitch of the old authored model are retired.
##
## Heading state is `camera_rotation` (radians; the original wraps at 65536
## angle units = TAU). Player movement is camera-relative (player.gd reads the
## viewport camera basis).

# Original constants: angle circle 65536, Q12 positions (4096 = 1 u), 30 fps tick.
const PITCH: float = TAU * 2048.0 / 65536.0            # fixed elevation 11.25°
const RADIUS: float = 5.0                              # 20480 Q12, also the max
const LOOK_HEIGHT: float = 1.5                         # 6144 Q12 above the player
const MANUAL_RATE: float = TAU * 768.0 / 65536.0 * 30.0  # 768 units/frame ≈ 126.6°/s
const RECENTER_SNAP: float = TAU * 256.0 / 65536.0     # snap band 1.40625°
const RECENTER_EASE_PER_TICK: float = 1.0 / 8.0        # Δ/8 per 30 fps frame
const RECENTER_RELEASE_TICKS: float = 10.0             # input can release after 10 frames
const FOLLOW_COEFF: float = 2048.0 * TAU / 65536.0     # rad of swing per unit displaced (step = disp/2 in angle units)
const FOLLOW_LIMIT_COEFF: float = 4096.0 * TAU / 65536.0  # rad-equivalent of the displacement gate
const TARGET_EASE_PER_TICK: float = 0.5                # look point closes 50%/frame
const FOV_DEG: float = 44.0                            # ROM projection: cot(fovy/2) = 10141/4096

# Target to follow
@export var target_path: NodePath
var target: Node3D

# Camera heading (radians, TAU wrap)
var camera_rotation: float = 0.0

# Recenter mode: 0 = manual/follow, 1 = easing to desired_heading behind the
# player (the ROM's mode 1). _recenter_time accumulates 30 fps ticks.
var _recenter_mode := false
var _desired_heading: float = 0.0
var _recenter_time: float = 0.0

# Soft-follow look point (XZ) and the last anchor it eases toward; also drives
# the follow-swing displacement (per-frame player movement, the ROM's
# follow_limit).
var _look_xz := Vector2.ZERO
var _anchor_xz := Vector2.ZERO
var _anchor_valid := false

# Set false to pause camera input (e.g. gate nudge mode)
var input_enabled := true

# While true the orbit does NOT drive the camera — used by the diegetic shop
# view, which tweens the camera to a fixed pose in front of the shopkeeper and
# needs the orbit to stop overwriting it. See begin_shop_focus / end_shop_focus.
var _shop_focus := false

# Vertical follow smoothing (#538). The player's Y picks up a per-step sawtooth
# descending stairs (no step-down snap, so it walks off each edge and re-grounds);
# hard-assigning the camera Y every frame passed that 1:1 into the view as shake.
# Damp ONLY the follow Y — horizontal easing is the original 50%/frame look-point
# rule — and snap on a large jump so the camera doesn't slide across a warp/respawn.
const CAM_Y_SMOOTH_TAU: float = 0.12   # seconds; larger = smoother but laggier
const CAM_Y_SNAP_DIST: float = 3.0     # gap beyond which we snap instead of damp
# Horizontal look-point snap (the ROM's place() semantics): the original's
# rooms are continuous so its 50%/frame easing never sees a jump, but our
# stage model teleports the player between rooms — snap the eased look point
# when the anchor leaps, so the camera doesn't sweep across the stage.
const CAM_XZ_SNAP_DIST: float = 5.0
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
	camera.fov = FOV_DEG

	if target:
		_snap_to_target()
		_update_camera_position(0.0)


func set_target(new_target: Node3D) -> void:
	target = new_target
	_anchor_valid = false
	_snap_to_target()


## Initial placement (ROM pszm_world_camera_init + place): heading behind the
## player, look point and anchor exactly on the player.
func _snap_to_target() -> void:
	if not target:
		return
	var facing: float = target.get("player_rotation") if target.get("player_rotation") != null else 0.0
	camera_rotation = wrapf(facing + PI, 0.0, TAU)
	_desired_heading = camera_rotation
	_follow_y_valid = false


func _process(delta: float) -> void:
	# Shop view owns the camera pose while focused; don't fight its tween.
	if _shop_focus:
		return
	if input_enabled and not PsoStartMenu.is_open():
		_step_heading(delta)
	else:
		# Input locked (ROM flags&2): no rotation behaviors, but the recenter
		# ease still runs in the original when already in mode 1 — mirror that.
		if _recenter_mode:
			_step_recenter(delta, false)

	if target and camera:
		_update_camera_position(delta)


func _step_heading(delta: float) -> void:
	var manual := false
	var dir: float = 1.0 if InputConfig.invert_camera_x else -1.0
	if Input.is_action_pressed("camera_left"):
		camera_rotation = wrapf(camera_rotation - MANUAL_RATE * delta * dir, 0.0, TAU)
		manual = true
	if Input.is_action_pressed("camera_right"):
		camera_rotation = wrapf(camera_rotation + MANUAL_RATE * delta * dir, 0.0, TAU)
		manual = true
	var recenter_held := Input.is_action_pressed("camera_lock")
	if Input.is_action_just_pressed("camera_lock"):
		_begin_recenter()
	if _recenter_mode:
		_step_recenter(delta, manual or recenter_held or _movement_held())
	elif recenter_held and not manual:
		# Holding the recenter input keeps easing toward the (refreshed)
		# behind-facing heading and suppresses the follow swing (ROM mode-0
		# "L held without X" branch).
		_refresh_desired_heading()
		_ease_toward_desired(delta)
	else:
		_step_follow_swing()


func _begin_recenter() -> void:
	_refresh_desired_heading()
	_recenter_mode = true
	_recenter_time = 0.0


func _refresh_desired_heading() -> void:
	if target:
		var facing: float = target.get("player_rotation") if target.get("player_rotation") != null else 0.0
		_desired_heading = wrapf(facing + PI, 0.0, TAU)


func _step_recenter(delta: float, has_release_input: bool) -> void:
	# The ease refreshes its target while the recenter input is held.
	if Input.is_action_pressed("camera_lock"):
		_refresh_desired_heading()
	_ease_toward_desired(delta)
	_recenter_time += delta * 30.0
	if _recenter_time > RECENTER_RELEASE_TICKS and has_release_input:
		_recenter_mode = false


func _ease_toward_desired(delta: float) -> void:
	var d := wrapf(_desired_heading - camera_rotation, -PI, PI)
	if absf(d) <= RECENTER_SNAP:
		camera_rotation = _desired_heading
		_recenter_mode = false
		return
	camera_rotation = wrapf(camera_rotation + d * RECENTER_EASE_PER_TICK * delta * 30.0, 0.0, TAU)


func _step_follow_swing() -> void:
	# ROM: the follow flag is set only in the running state; the swing chases
	# steering + 180° at half the per-frame player displacement (in angle
	# units — the original reads the fresh position in camera_follow before
	# update consumes it), snapping when the gap is within the displacement
	# gate. A player standing exactly opposite (Δ = 180°) does not move the
	# camera (the ambiguity guard).
	if not target or not _anchor_valid:
		return
	if not ("current_state" in target) or target.current_state != 2:  # PlayerState.RUNNING
		return
	var anchor_now := Vector2(target.global_position.x, target.global_position.z)
	var displacement := anchor_now.distance_to(_anchor_xz)
	var follow_yaw: float = target.get_camera_follow_yaw() if target.has_method("get_camera_follow_yaw") else 0.0
	var wanted := wrapf(follow_yaw + PI, 0.0, TAU)
	var d := wrapf(wanted - camera_rotation, -PI, PI)
	if absf(absf(d) - PI) < 0.0001:
		return  # exactly opposite — the ROM's ambiguity guard
	var limit := displacement * FOLLOW_LIMIT_COEFF
	if limit <= 0.0 or absf(d) <= limit:
		camera_rotation = wanted
	elif d > 0.0:
		camera_rotation = wrapf(camera_rotation + displacement * FOLLOW_COEFF, 0.0, TAU)
	else:
		camera_rotation = wrapf(camera_rotation - displacement * FOLLOW_COEFF, 0.0, TAU)


func _movement_held() -> bool:
	return Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_backward") \
		or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")


func _update_camera_position(delta: float) -> void:
	if not target:
		return

	var target_pos := target.global_position
	var anchor := Vector2(target_pos.x, target_pos.z)

	# Damp only the vertical follow (#538): absorbs the stair-descent Y sawtooth
	# so it doesn't shake the view, while x/z use the original 50%/frame
	# look-point easing. First frame (and large jumps, via the helper) snap.
	if not _follow_y_valid:
		_follow_y = target_pos.y
		_follow_y_valid = true
	else:
		_follow_y = _damp_follow_y(_follow_y, target_pos.y, delta)

	if not _anchor_valid:
		_look_xz = anchor
		_anchor_valid = true
	elif delta > 0.0:
		if _look_xz.distance_to(anchor) > CAM_XZ_SNAP_DIST:
			_look_xz = anchor
		else:
			var alpha: float = 1.0 - pow(1.0 - TARGET_EASE_PER_TICK, delta * 30.0)
			_look_xz = _look_xz.lerp(anchor, alpha)
	_anchor_xz = anchor

	# Original geometry (ROM wraps at Q12; the float port omits the sub-cm
	# double-add of the look point inside the eye's pre-shift sum): a fixed
	# elevation ring around the eased look point, above the player.
	var look := Vector3(_look_xz.x, _follow_y + LOOK_HEIGHT, _look_xz.y)
	var ring: float = RADIUS * cos(PITCH)
	var cam_pos := Vector3(
		look.x + sin(camera_rotation) * ring,
		_follow_y + LOOK_HEIGHT + RADIUS * sin(PITCH),
		look.z + cos(camera_rotation) * ring,
	)

	camera.global_position = cam_pos
	camera.look_at(look)


## Frame-rate-independent exponential damping of the follow Y toward target_y.
## Snaps (returns target_y) when delta is non-positive or the gap exceeds
## CAM_Y_SNAP_DIST, so a warp/respawn doesn't slide and a settled frame is exact.
static func _damp_follow_y(current: float, target_y: float, delta: float) -> float:
	if delta <= 0.0 or absf(target_y - current) > CAM_Y_SNAP_DIST:
		return target_y
	return lerpf(current, target_y, 1.0 - exp(-delta / CAM_Y_SMOOTH_TAU))


## Stop the orbit from driving the camera so the shop view can pose it directly.
func begin_shop_focus() -> void:
	_shop_focus = true
	input_enabled = false


## Resume normal follow. Invalidate the follow-Y so it snaps cleanly rather than
## sliding from the shop pose on the first frame back.
func end_shop_focus() -> void:
	_shop_focus = false
	input_enabled = true
	_follow_y_valid = false
	_anchor_valid = false


## The camera transform the orbit would use right now — the tween-back target
## when a shop closes. Mirrors _update_camera_position without the Y damping.
func get_follow_transform() -> Transform3D:
	if not target:
		return camera.global_transform
	var target_pos := target.global_position
	var fy: float = _follow_y if _follow_y_valid else target_pos.y
	var look := Vector3(target_pos.x, fy + LOOK_HEIGHT, target_pos.z)
	var ring: float = RADIUS * cos(PITCH)
	var cam_pos := Vector3(
		look.x + sin(camera_rotation) * ring,
		fy + LOOK_HEIGHT + RADIUS * sin(PITCH),
		look.z + cos(camera_rotation) * ring,
	)
	return Transform3D(Basis(), cam_pos).looking_at(look, Vector3.UP)

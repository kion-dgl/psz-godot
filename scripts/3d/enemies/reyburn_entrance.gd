class_name ReyburnEntrance extends RefCounted
## Brief authored presentation from the playtest observation, not retail timing.
const FLY_END := 1.6
const LAND_END := 2.6
const END := 4.5
const LANDING_DISTANCE := 27.0
var elapsed := 0.0
var _started := false
var _player: Node3D
var _camera: Camera3D
var _previous_camera: Camera3D
var _landing := Vector3.ZERO
var _forward := Vector3.FORWARD
var _right := Vector3.RIGHT
var _layer := 0
var _mask := 0
var _phase := -1

func tick(boss, delta: float) -> bool:
	if not _started:
		var player: Node3D = boss._find_player()
		if not is_instance_valid(player): return false
		_begin(boss, player)
	# Stage loading/fade time does not consume the visible introduction.
	if SceneManager._transitioning or PsoStartMenu.is_open(): return false
	var before := elapsed
	elapsed = minf(elapsed + delta, END)
	var phase := 0 if elapsed < FLY_END else 1 if elapsed < LAND_END else 2
	if phase != _phase:
		_phase = phase
		boss.play_action([18, 8, 1][phase], {0:-1} if phase == 0 else {})
	var rate := 1.0 if phase == 0 else (55.0 / 30.0) / (LAND_END - FLY_END) if phase == 1 else (115.0 / 30.0) / (END - LAND_END)
	boss.clock.advance((elapsed - before) * rate)
	boss._sync_pose()
	if phase == 0:
		var progress := elapsed / FLY_END
		var angle := TAU * progress
		# Start overhead, circle once and approach the landing facing the player.
		var center := _landing - _right * 12.0
		boss.global_position = center + _right * cos(angle) * 12.0 + _forward * sin(angle) * 12.0 + Vector3.UP * 9.0
		var tangent := -_right * sin(angle) + _forward * cos(angle)
		var yaw := atan2(tangent.x, tangent.z)
		boss.rotation.y = lerp_angle(yaw, atan2(_forward.x, _forward.z), smoothstep(0.65, 1.0, progress))
	elif phase == 1:
		var progress := smoothstep(FLY_END, LAND_END, elapsed)
		boss.global_position = (_landing + Vector3.UP * 9.0).lerp(_landing, progress)
		boss.rotation.y = atan2(_forward.x, _forward.z)
	else:
		boss.global_position = _landing
		boss.rotation.y = atan2(_forward.x, _forward.z)
	# Stay at the usual shoulder distance; only the view follows the dragon.
	_camera.global_position = _player.global_position + _forward * 4.5 + Vector3.UP * 1.9
	_camera.look_at(boss.global_position + Vector3.UP * 2.5)
	if before < 0.35:
		_player.move_and_collide(-_forward * minf(delta, 0.35 - before) * 3.0)
		_player.play_animation(_player._walk_anim, true)
	elif before < 0.35 + delta:
		_player.play_animation(_player._anim_prefix + "_wait", true)
	if elapsed < END: return false
	finish(boss)
	return true

func _begin(boss, player: Node3D) -> void:
	_started = true
	_player = player
	boss.target = player
	_landing = boss.global_position
	_forward = (_player.global_position - _landing) * Vector3(1,0,1)
	_forward = _forward.normalized() if _forward.length_squared() > 0.01 else Vector3.FORWARD
	_landing = _choose_landing(boss, _player.global_position, _landing, _forward)
	_forward = ((_player.global_position - _landing) * Vector3(1,0,1)).normalized()
	_right = _forward.cross(Vector3.UP)
	_layer = boss.collision_layer
	_mask = boss.collision_mask
	boss.collision_layer = 0
	boss.collision_mask = 0
	boss._home = _landing
	boss._ground_height = _landing.y
	boss._initialized_position = true
	_player._drop_charge()
	_player.transition_to(_player.PlayerState.CUTSCENE)
	_player.player_rotation = atan2(-_forward.x, -_forward.z)
	_previous_camera = boss.get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	boss.get_parent().add_child(_camera)
	_camera.global_position = _player.global_position + _forward * 4.5 + Vector3.UP * 1.9
	_camera.fov = 50.0
	_camera.look_at(_landing + Vector3.UP * 5.0)
	_camera.make_current()
	boss.global_position = _landing + Vector3.UP * 9.0
	boss.rotation.y = atan2(_forward.x, _forward.z)
	boss.play_action(18, {0:-1})
	_phase = 0

func finish(boss) -> void:
	if _started:
		boss.global_position = _landing
		boss.rotation.y = atan2(_forward.x, _forward.z)
		boss.collision_layer = _layer
		boss.collision_mask = _mask
		if is_instance_valid(_player) and _player.current_state == _player.PlayerState.CUTSCENE:
			_player.transition_to(_player.PlayerState.IDLE)
	if is_instance_valid(_camera):
		if _camera.current and is_instance_valid(_previous_camera) and _previous_camera.is_inside_tree():
			var rig := _previous_camera.get_parent()
			if rig.has_method("_center_behind_player"): rig._center_behind_player()
			_previous_camera.make_current()
		_camera.queue_free()
	_started = false

func _choose_landing(boss, player_pos: Vector3, original: Vector3, toward_player: Vector3) -> Vector3:
	if Vector2(original.x-player_pos.x, original.z-player_pos.z).length() >= LANDING_DISTANCE:
		return original
	# Prefer directly ahead of the player, then nearby headings with floor under
	# the entire body. Never push the spawn out over the arena edge for spacing.
	for angle in [0.0, PI/8, -PI/8, PI/4, -PI/4, PI/2, -PI/2, PI]:
		var candidate := player_pos - toward_player.rotated(Vector3.UP, angle) * LANDING_DISTANCE
		candidate.y = original.y
		var supported := true
		for offset in [Vector3.ZERO, Vector3(4,0,0), Vector3(-4,0,0), Vector3(0,0,4), Vector3(0,0,-4)]:
			if not boss._has_floor_at(candidate + offset): supported = false
		if supported: return candidate
	return original

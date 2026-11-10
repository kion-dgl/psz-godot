extends RefCounted
## Opt-in Ranger control slice (#775). OrbitCamera owns the view; Player owns locomotion.
const WEAPONS := [WeaponData.WeaponType.HANDGUN, WeaponData.WeaponType.RIFLE, WeaponData.WeaponType.MECH_GUN]
var active := false
var blocked_until_release := false
var blend := 0.0
var orbit: Node3D
var reticle: Control
var _mouse_owned := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _clip_speed := 1.0

func setup(camera_rig: Node3D) -> void:
	orbit = camera_rig
	if OS.get_environment("PSZ_AIM_PROTOTYPE") != "1": return
	if not InputMap.has_action("combat_aim"):
		InputMap.add_action("combat_aim", 0.3)
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("combat_aim", mouse)
		var trigger := InputEventJoypadMotion.new()
		trigger.axis = JOY_AXIS_TRIGGER_LEFT
		trigger.axis_value = 1.0
		InputMap.action_add_event("combat_aim", trigger)
	# Dedicated keyboard dodge for this opt-in fixture; menus still own Space.
	var dodge_key := InputEventKey.new()
	dodge_key.physical_keycode = KEY_SPACE
	if not InputMap.action_has_event("dodge", dodge_key): InputMap.action_add_event("dodge", dodge_key)
	var layer := CanvasLayer.new()
	orbit.add_child(layer)
	reticle = preload("res://scripts/3d/ui/aim_reticle.gd").new()
	layer.add_child(reticle)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.hide()

func eligible() -> bool:
	var p = orbit.target
	return OS.get_environment("PSZ_AIM_PROTOTYPE") == "1" and is_instance_valid(p) and p.has_method("_get_equipped_weapon_type") and not p._is_in_city() and p._get_equipped_weapon_type() in WEAPONS

func allowed() -> bool:
	if not eligible(): return false
	var p = orbit.target
	return orbit.input_enabled and not orbit._shop_focus and not GameState.is_gameplay_blocked() and not p._is_defeated and GameState.hp > 0 and p.current_state != p.PlayerState.CUTSCENE

func update(delta: float) -> void:
	if not InputMap.has_action("combat_aim"): return
	if is_instance_valid(orbit.target) and "combat_aim" in orbit.target: orbit.target.combat_aim = self
	var held := Input.is_action_pressed("combat_aim")
	var was_active := active
	update_hold(held, allowed())
	if was_active and not active: restore_locomotion()
	blend = move_toward(blend, 1.0 if active else 0.0, delta / 0.15)
	if is_instance_valid(reticle): reticle.visible = active
	if not active:
		release_mouse()
		return
	var direction := 1.0 if InputConfig.invert_camera_x else -1.0
	orbit.camera_rotation += Input.get_axis("camera_left", "camera_right") * orbit.rotation_speed * direction * delta * 60.0
	orbit.camera_pitch = clampf(orbit.camera_pitch + Input.get_axis("camera_down", "camera_up") * orbit.rotation_speed * delta * 60.0, orbit.min_pitch_offset, orbit.max_pitch_offset)

func restore_locomotion() -> void:
	var p = orbit.target
	if is_instance_valid(p) and p.current_state in [p.PlayerState.IDLE, p.PlayerState.WALKING, p.PlayerState.RUNNING]:
		p.transition_to(p.current_state)

func update_hold(held: bool, can_aim: bool) -> void:
	if not held: blocked_until_release = false
	elif not can_aim: blocked_until_release = true
	active = held and can_aim and not blocked_until_release

func handle_input(event: InputEvent) -> bool:
	if not eligible(): return false
	if event.is_action("combat_aim"):
		update(0.0)
		if active and event is InputEventMouseButton:
			_previous_mouse_mode = Input.mouse_mode
			_mouse_owned = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return true
	if not active or not allowed(): return false
	if event is InputEventMouseMotion:
		orbit.camera_rotation -= event.relative.x * orbit.mouse_sensitivity * (-1.0 if InputConfig.invert_camera_x else 1.0)
		orbit.camera_pitch = clampf(orbit.camera_pitch + event.relative.y * orbit.mouse_sensitivity, orbit.min_pitch_offset, orbit.max_pitch_offset)
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p = orbit.target
		if event.pressed and p.current_state in [p.PlayerState.IDLE, p.PlayerState.WALKING, p.PlayerState.RUNNING, p.PlayerState.ATTACKING]:
			p._start_attack()
		return true
	return false

func release_mouse() -> void:
	if _mouse_owned:
		Input.mouse_mode = _previous_mouse_mode
		_mouse_owned = false

func facing() -> float:
	return orbit.camera_rotation + PI

static func travel(input: Vector2, yaw: float) -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y).limit_length(1.0)

func move_player(p) -> void:
	p.player_rotation = facing()
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var movement := travel(input, orbit.camera_rotation)
	p.walk_timer = 0.0
	var next: int = p.PlayerState.IDLE if input.is_zero_approx() else p.PlayerState.WALKING
	if p.current_state != next: p.transition_to(next)
	p._apply_walk_velocity(movement.normalized(), p.WALK_SPEED * input.length())
	play_step(p, input)

func play_step(p, input: Vector2) -> void:
	var ap: AnimationPlayer = p.animation_player
	if ap == null: return
	if input.is_zero_approx():
		if not ap.current_animation.ends_with("_wait"): p.play_animation(p._anim_prefix + "_wait")
		return
	var lateral := absf(input.x) > absf(input.y)
	var suffix := "_stp_lr" if lateral else "_stp_fb"
	var clip: String = p._anim_prefix + suffix
	# Female libraries use male-named shared step clips. Select by the actual suffix.
	if not ap.has_animation(clip):
		for candidate in ap.get_animation_list():
			if candidate.ends_with(suffix): clip = candidate; break
	if not ap.has_animation(clip): return
	var speed := (1.0 if input.x > 0 else -1.0) if lateral else (1.0 if input.y < 0 else -1.0)
	if ap.current_animation != clip or _clip_speed != speed:
		ap.play(clip, 0.08, speed, speed < 0.0)
		_clip_speed = speed

func apply_camera() -> void:
	if blend <= 0.0 or not is_instance_valid(orbit.target) or orbit._shop_focus: return
	var camera: Camera3D = orbit.camera
	var anchor: Vector3 = orbit.target.global_position + Vector3.UP * orbit.LOOK_HEIGHT
	anchor.y = orbit._follow_y + orbit.LOOK_HEIGHT
	var basis := camera.global_basis
	var desired := anchor + basis.z * 3.0 + basis.x * 0.6
	desired = camera.global_position.lerp(desired, blend)
	var fraction := ProjectileSweep.environment_fraction(orbit.get_world_3d().direct_space_state, anchor, desired - anchor, 0.2)
	if fraction >= 0.0: desired = anchor.lerp(desired, maxf(0.0, fraction - 0.02))
	camera.global_position = desired

func aim_point(max_range: float) -> Vector3:
	var camera: Camera3D = orbit.camera
	var start := camera.global_position
	var end := start - camera.global_basis.z * (max_range + 6.0)
	var ray := PhysicsRayQueryParameters3D.create(start, end, 1 | 32)
	ray.collide_with_areas = true
	var hit := orbit.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.position if not hit.is_empty() else end

func shot_direction(start: Vector3, max_range: float) -> Vector3:
	return (aim_point(max_range) - start).normalized()

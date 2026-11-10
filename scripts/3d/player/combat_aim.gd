extends RefCounted
## Opt-in Ranger control slice (#775). OrbitCamera owns the view; Player owns locomotion.
const WEAPONS := [WeaponData.WeaponType.HANDGUN, WeaponData.WeaponType.RIFLE, WeaponData.WeaponType.MECH_GUN]
enum Mode { NORMAL, SHOULDER, LOCKED }
var mode := Mode.NORMAL
var active: bool:
	get: return mode != Mode.NORMAL
var lock := preload("res://scripts/3d/player/combat_lock.gd").new()
var focused := true
var blend := 0.0
var orbit: Node3D
var reticle: Control
var _mouse_owned := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _clip_speed := 1.0

func setup(camera_rig: Node3D) -> void:
	orbit = camera_rig
	if OS.get_environment("PSZ_AIM_PROTOTYPE") != "1": return
	for binding in [["combat_aim", KEY_Z], ["combat_lock", KEY_Q], ["combat_switch", KEY_TAB]]:
		if not InputMap.has_action(binding[0]): InputMap.add_action(binding[0])
		var key := InputEventKey.new()
		key.physical_keycode = binding[1]
		if not InputMap.action_has_event(binding[0], key): InputMap.action_add_event(binding[0], key)
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
	if not allowed() or not focused:
		clear()
		release_mouse()
	else:
		capture_mouse()
		if mode == Mode.LOCKED:
			lock.update(orbit, delta)
			if not is_instance_valid(lock.target): clear()
			else: orbit.camera_rotation = facing() + PI
		else:
			var direction := 1.0 if InputConfig.invert_camera_x else -1.0
			orbit.camera_rotation += Input.get_axis("camera_left", "camera_right") * orbit.rotation_speed * direction * delta * 60.0
			orbit.camera_pitch = clampf(orbit.camera_pitch + Input.get_axis("camera_down", "camera_up") * orbit.rotation_speed * delta * 60.0, orbit.min_pitch_offset, orbit.max_pitch_offset)
	blend = move_toward(blend, 1.0 if mode == Mode.SHOULDER else 0.0, delta / 0.15)
	if is_instance_valid(reticle):
		reticle.visible = active
		if active:
			reticle.locked = mode == Mode.LOCKED
			reticle.target_pixel = orbit.camera.unproject_position(lock.point(lock.target)) if reticle.locked else Vector2.ZERO
			reticle.set_combo(combo_feedback())

func clear() -> void:
	var was_active := active
	mode = Mode.NORMAL
	lock.clear()
	if was_active and is_instance_valid(orbit): restore_locomotion()

func capture_mouse() -> void:
	if _mouse_owned: return
	_previous_mouse_mode = Input.mouse_mode
	_mouse_owned = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func restore_locomotion() -> void:
	var p = orbit.target
	if is_instance_valid(p) and p.current_state in [p.PlayerState.IDLE, p.PlayerState.WALKING, p.PlayerState.RUNNING]:
		p.transition_to(p.current_state)

func handle_input(event: InputEvent) -> bool:
	if not eligible(): return false
	if not allowed() or not focused: return true if event is InputEventMouseMotion else false
	for action in ["combat_aim", "combat_lock", "combat_switch"]:
		if event.is_action(action):
			if event.is_action_pressed(action) and not event.is_echo(): change_mode(action)
			return true
	if event is InputEventMouseMotion:
		if mode != Mode.LOCKED:
			orbit.camera_rotation -= event.relative.x * orbit.mouse_sensitivity * (-1.0 if InputConfig.invert_camera_x else 1.0)
			orbit.camera_pitch = clampf(orbit.camera_pitch + event.relative.y * orbit.mouse_sensitivity, orbit.min_pitch_offset, orbit.max_pitch_offset)
		return true
	if event is InputEventMouseButton:
		var buttons := [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]
		var slot := buttons.find(event.button_index)
		if slot >= 0:
			var p = orbit.target
			if p._freeze.remaining <= 0.0:
				if event.pressed: p._on_palette_pressed(slot)
				else: p._on_palette_released(slot)
			return true
	return false

func change_mode(action: String) -> void:
	if action == "combat_aim":
		var shoulder := mode == Mode.SHOULDER
		clear()
		if not shoulder: mode = Mode.SHOULDER
	elif action == "combat_lock" and mode != Mode.SHOULDER:
		if mode == Mode.LOCKED: clear()
		else:
			lock.select(orbit)
			if is_instance_valid(lock.target): mode = Mode.LOCKED
	elif action == "combat_switch" and mode == Mode.LOCKED:
		lock.select(orbit, true)

func release_mouse() -> void:
	if _mouse_owned:
		Input.mouse_mode = _previous_mouse_mode
		_mouse_owned = false

func facing() -> float:
	if mode == Mode.LOCKED and is_instance_valid(lock.target):
		var direction: Vector3 = lock.target.global_position - orbit.target.global_position
		return atan2(direction.x, direction.z)
	return orbit.camera_rotation + PI

static func travel(input: Vector2, yaw: float) -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y).limit_length(1.0)

func move_player(p) -> void:
	p.player_rotation = facing()
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var movement := travel(input, facing() - PI)
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
	if (blend <= 0.0 and mode != Mode.LOCKED) or not is_instance_valid(orbit.target) or orbit._shop_focus: return
	var camera: Camera3D = orbit.camera
	var anchor: Vector3 = orbit.target.global_position + Vector3.UP * orbit.LOOK_HEIGHT
	anchor.y = orbit._follow_y + orbit.LOOK_HEIGHT
	var basis := camera.global_basis
	var desired := anchor + basis.z * 3.0 + basis.x * 0.6
	desired = camera.global_position.lerp(desired, blend)
	var fraction := ProjectileSweep.environment_fraction(orbit.get_world_3d().direct_space_state, anchor, desired - anchor, 0.2)
	if fraction >= 0.0: desired = anchor.lerp(desired, maxf(0.0, fraction - 0.02))
	camera.global_position = desired
	if mode == Mode.LOCKED and is_instance_valid(lock.target):
		camera.look_at(anchor.lerp(lock.point(lock.target), 0.5))

func aim_point(max_range: float) -> Vector3:
	var camera: Camera3D = orbit.camera
	var start := camera.global_position
	var end := start - camera.global_basis.z * (max_range + 6.0)
	var ray := PhysicsRayQueryParameters3D.create(start, end, 1 | 32)
	ray.collide_with_areas = true
	var hit := orbit.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.position if not hit.is_empty() else end

func shot_direction(start: Vector3, max_range: float) -> Vector3:
	var point: Vector3 = lock.point(lock.target) if mode == Mode.LOCKED and is_instance_valid(lock.target) else aim_point(max_range)
	return (point - start).normalized()

func combo_feedback() -> Dictionary:
	var p = orbit.target
	var step: int = p.combo_state if p.current_state == p.PlayerState.ATTACKING else 0
	var window: Array[float] = [0.0, 0.0]
	if step > 0 and step < 3:
		var timing: Dictionary = CombatManager.get_combo_timing(p._get_equipped_weapon_type(), step)
		if not timing.is_empty(): window = p._chain_window(timing)
	var fraction: float = p._attack_frac()
	return {"step": step, "fraction": fraction, "open": window[0], "close": window[1],
		"state": combo_prompt(step, fraction, window, p._combo_fumbled, p._queued_combo != p.ComboQueue.NONE)}

static func combo_prompt(step: int, fraction: float, window: Array[float], fumbled: bool, queued: bool) -> String:
	if step <= 0: return "FIRE"
	if step >= 3: return "FINISHER"
	if queued: return "QUEUED"
	if fumbled or fraction > window[1]: return "MISSED"
	return "CLICK" if fraction >= window[0] else "WAIT"

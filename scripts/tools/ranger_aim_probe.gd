extends "res://scripts/tools/probe_checks.gd"
## Real player, native weapon clips, actual projectile/physics contact, isolated save.
var player
var orbit
var enemies: Array = []
var origin := Vector3.ZERO

func _run() -> void:
	probe_label = "ranger-aim"
	if ProjectSettings.get_setting("application/config/name") != "PSZ Aim Prototype":
		push_error("Launch using scripts/tools/run_ranger_aim.py for save isolation")
		get_tree().quit(1)
		return
	get_tree().current_scene = null
	await launch_fixture()
	if OS.get_environment("PSZ_AIM_CHECK") == "1":
		await verify_controls()
		await verify_shots()
		await preload("res://scripts/tools/ranger_aim_combo_check.gd").run(self, player)
		await preload("res://scripts/tools/ranger_lock_check.gd").run(self)
		print("[ranger-aim] DONE %s" % ("ok" if _ok else "FAIL"))
		get_tree().quit(0 if _ok else 1)

func launch_fixture() -> void:
	seed(775)
	DebugConfig.invincible = false
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "ramarl" if OS.get_environment("PSZ_AIM_FEMALE") == "1" else "ramar", "Aim Test")
	CharacterManager._characters[0].equipment.weapon = OS.get_environment("PSZ_AIM_WEAPON")
	CharacterManager.set_active_slot(0)
	SessionManager.enter_quest("debug_coliseum", "normal")
	ColiseumRoster.selected_enemy_level = 1
	var sections := ColiseumRoster.make_sections("ghowl")
	sections[0].cells[0].objects.append({"type":"enemy", "enemy_id":"ghowl", "position":[3.0,0.0,5.0]})
	SessionManager.set_field_sections(sections)
	ColiseumRoster.apply_level_override()
	await SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", ColiseumRoster.warp_data())
	player = get_tree().get_first_node_in_group("player")
	orbit = get_viewport().get_camera_3d().get_parent()
	player.global_position = Vector3(0, player.global_position.y, -3)
	origin = player.global_position
	orbit.camera_rotation = PI
	orbit.camera_pitch = 0.0
	player.player_rotation = 0.0
	enemies = get_tree().get_nodes_in_group("enemies").filter(func(e): return e is EnemyBase)
	for enemy in enemies:
		enemy.set_physics_process(false)
		enemy.enemy_data = enemy.enemy_data.duplicate(true)
		enemy.enemy_data.hp_base = 10000
		enemy.current_hp = 10000
		# Trajectory checks must not randomly miss through the RPG accuracy roll.
		enemy.current_evasion = -10000 if OS.get_environment("PSZ_AIM_CHECK") == "1" else 0
		if OS.get_environment("PSZ_AIM_CHECK") == "1": enemy.current_defense = 0
		# Toggle the opponents with T for a repeatable positioning/combat comparison.
	DisplayServer.window_set_title("PSZ Ranger Aim — Z shoulder • Q lock • Tab switch • LMB / J shoot • Space / LB dodge • T enemies • R reset")
	var layer := CanvasLayer.new()
	get_tree().current_scene.add_child(layer)
	var label := Label.new()
	label.text = "RANGER AIM PROTOTYPE\nZ: shoulder toggle   •   Q: lock toggle   •   Tab: switch   •   WASD / left stick: move   •   mouse / right stick: aim\nLeft / right / middle click: palette   •   J: shoot   •   Space / LB: dodge   •   T: toggle enemies   •   R: reset\nClick when the crosshair says CLICK to chain all 3 shots. T activates enemies."
	label.position = Vector2(20, 145)
	label.add_theme_font_size_override("font_size", 16)
	layer.add_child(label)
	add_practice_cover()
	await ticks(15)

func add_practice_cover() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 0.5)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var visual := BoxMesh.new()
	visual.size = box.size
	mesh.mesh = visual
	body.add_child(mesh)
	get_tree().current_scene.add_child(body)
	body.global_position = Vector3(4, 1, 0)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not is_instance_valid(player) or GameState.is_gameplay_blocked(): return
	if event.physical_keycode == KEY_T:
		for enemy in enemies:
			if is_instance_valid(enemy): enemy.set_physics_process(not enemy.is_physics_processing())
	elif event.physical_keycode == KEY_R:
		player.global_position = origin
		GameState.set_hp(GameState.max_hp)
		player.transition_to(player.PlayerState.IDLE)
		for i in range(enemies.size()):
			if is_instance_valid(enemies[i]):
				enemies[i].global_position = origin + Vector3(3 * i, 0, -6)
				enemies[i].current_hp = 10000

func ticks(count: int) -> void:
	for frame in range(count): await get_tree().physics_frame

func verify_controls() -> void:
	_check(player.animation_player != null and player.model != null, "real Ranger rig loaded")
	set_shoulder(true)
	await ticks(15)
	_check(player.combat_aim.active and orbit.combat_aim.reticle.visible, "Z toggle enables shoulder aim and reticle after key release")
	for action in ["move_right", "move_left", "move_backward", "move_forward"]:
		var before: Vector3 = player.global_position
		Input.action_press(action)
		await ticks(12)
		_check(player.global_position.distance_to(before) > 0.1, "real player moves: " + action)
		_check(absf(angle_difference(player.player_rotation, orbit.combat_aim.facing())) < 0.01, "travel does not turn away from aim: " + action)
		_check("_stp_" in player.animation_player.current_animation, "native step clip plays: " + action)
		Input.action_release(action)
	player.dodge_cooldown = 0
	Input.action_press("move_right")
	player._start_dodge()
	var heading: float = player.dodge_direction
	Input.action_release("move_right")
	orbit.camera_rotation += 0.5
	await ticks(12)
	_check(player.current_state == player.PlayerState.DODGING and player.dodge_direction == heading, "dodge heading stays fixed when aim moves")
	player._start_attack()
	_check(player.current_state == player.PlayerState.DODGING, "aim fire cannot cancel dodge")
	await ticks(90)
	await verify_input_lifecycle()
	await verify_aim_axes()
	await verify_mouse_palette()
	await _snapshot("ranger-aim-strafe")

static func key(code: int, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	event.echo = false
	Input.parse_input_event(event)

func set_shoulder(enabled: bool) -> void:
	if (orbit.combat_aim.mode == orbit.combat_aim.Mode.SHOULDER) != enabled: key(KEY_Z)

func verify_input_lifecycle() -> void:
	key(KEY_Z, true)
	await ticks(3)
	_check(player.combat_aim.active, "key repeat does not toggle shoulder mode off")
	key(KEY_Q)
	await ticks(3)
	_check(orbit.combat_aim.mode == orbit.combat_aim.Mode.SHOULDER, "Q cannot acquire lock in shoulder mode")
	GameState.modal_stack += 1
	await ticks(3)
	_check(not player.combat_aim.active, "modal clears aim")
	GameState.modal_stack -= 1
	await ticks(3)
	_check(not player.combat_aim.active, "closing modal does not restore stale toggle")
	set_shoulder(true)
	await ticks(3)
	var weapon: String = CharacterManager.get_active_character().equipment.weapon
	CharacterManager.get_active_character().equipment.weapon = "saber"
	await ticks(3)
	_check(not player.combat_aim.active, "unsupported weapon clears stance")
	CharacterManager.get_active_character().equipment.weapon = weapon
	await ticks(3)
	_check(not player.combat_aim.active, "weapon swap does not restore stale toggle")
	set_shoulder(true)
	await ticks(15)

func verify_mouse_palette() -> void:
	player.transition_to(player.PlayerState.IDLE)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	Input.parse_input_event(click)
	await ticks(2)
	_check(player.current_state == player.PlayerState.ATTACKING and player._is_special_attack, "right mouse dispatches second palette action")
	_check(orbit.combat_aim.mode == orbit.combat_aim.Mode.SHOULDER, "right mouse does not change aiming mode")
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await ticks(100)
	orbit._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not orbit.combat_aim.active and not orbit.combat_aim._mouse_owned, "focus loss clears stance and releases mouse")
	orbit._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await ticks(3)
	_check(not orbit.combat_aim.active, "focus return does not restore stale stance")
	set_shoulder(true)
	await ticks(15)

func verify_shots() -> void:
	player.global_position = origin
	player.transition_to(player.PlayerState.IDLE)
	orbit.camera_rotation = 0.0
	orbit.camera_pitch = -atan2(orbit.height, orbit.distance)
	await ticks(15)
	for frame in range(2): await get_tree().process_frame
	var camera: Camera3D = orbit.camera
	var aim_position: Vector3 = camera.global_position - camera.global_basis.z * 8.0
	var target = enemies[0]
	target.global_position = Vector3(aim_position.x, aim_position.y - target.enemy_data.collision_height * 0.5, aim_position.z)
	enemies[1].global_position = origin + Vector3(-0.7, 0, -3)
	var hp: int = target.current_hp
	var off_hp: int = enemies[1].current_hp
	Input.action_press("move_left")
	var click := InputEventMouseButton.new()
	click.position = get_viewport().get_visible_rect().size * 0.5
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	Input.action_release("move_left")
	var committed: Vector3 = player.global_position
	await ticks(8)
	_check(player.current_state == player.PlayerState.ATTACKING, "mouse fire enters the real attack state")
	_check(player.global_position.distance_to(committed) < 0.1, "shot animation retains movement commitment")
	await ticks(100)
	_check(target.current_hp < hp and enemies[1].current_hp == off_hp, "real animation releases a shot at reticle target, not nearer off-center enemy (HP %d -> %d, other %d -> %d)" % [hp, target.current_hp, off_hp, enemies[1].current_hp])
	await verify_cover(target)
	await verify_damage_commitment()
	set_shoulder(false)
	await ticks(15)
	_check(not player.combat_aim.active and not orbit.combat_aim.reticle.visible, "second Z restores exploration and hides reticle")

func verify_cover(target) -> void:
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 0.2)
	collider.shape = box
	wall.add_child(collider)
	get_tree().current_scene.add_child(wall)
	wall.global_position = origin + Vector3(0, 1.5, -1)
	await ticks(3)
	var hp: int = target.current_hp
	player._start_attack()
	await ticks(100)
	_check(target.current_hp == hp, "cover blocks aimed shots during actual animation release")
	var anchor: Vector3 = player.global_position + Vector3.UP * orbit.LOOK_HEIGHT
	wall.global_transform = Transform3D(orbit.camera.global_basis, anchor + orbit.camera.global_basis.z)
	await ticks(15)
	# Camera follows at render rate; physics ticks can be batched in one slow rendered frame.
	for frame in range(2): await get_tree().process_frame
	_check(orbit.camera.global_position.distance_to(player.global_position + Vector3.UP * orbit.LOOK_HEIGHT) < 1.3, "shoulder camera pulls in before world cover")
	wall.queue_free()


func verify_damage_commitment() -> void:
	player._hit_invulnerability_left = 0.0
	player.take_damage(1)
	var damage_state: int = player.current_state
	var click := InputEventMouseButton.new()
	click.position = get_viewport().get_visible_rect().size * 0.5
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await ticks(1)
	_check(damage_state == player.PlayerState.DAMAGED and player.current_state == damage_state, "mouse fire cannot cancel real damage recovery")
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await ticks(90)


func verify_aim_axes() -> void:
	var before_yaw: float = orbit.camera_rotation
	var before_pitch: float = orbit.camera_pitch
	var motion := InputEventMouseMotion.new()
	motion.position = get_viewport().get_visible_rect().size * 0.5
	motion.relative = Vector2(12, 5)
	Input.parse_input_event(motion)
	await ticks(2)
	var sign_expected := 1.0 if InputConfig.invert_camera_x else -1.0
	_check(angle_difference(before_yaw, orbit.camera_rotation) * sign_expected > 0, "mouse horizontal aim follows the configured direction")
	_check(orbit.camera_pitch > before_pitch, "mouse down aims down")
	before_yaw = orbit.camera_rotation
	Input.action_press("camera_right")
	await ticks(3)
	Input.action_release("camera_right")
	_check(angle_difference(before_yaw, orbit.camera_rotation) * sign_expected > 0, "right-stick direction agrees with mouse aim")

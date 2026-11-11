extends RefCounted

static func run(probe) -> void:
	var p = probe.player
	probe.set_shoulder(true)
	p.global_position = probe.origin
	p.transition_to(p.PlayerState.IDLE)
	probe.orbit.camera_rotation = 0.0
	probe.orbit.camera_pitch = 0.0
	probe.enemies[0].global_position = probe.origin + Vector3(0, 0, -1.0)
	probe.enemies[1].global_position = probe.origin + Vector3(4, 0, -5)
	await probe.ticks(15)
	var hp: int = probe.enemies[0].current_hp
	preload("res://scripts/tools/ranger_aim_combo_check.gd").click(p)
	await probe.ticks(150)
	probe._check(probe.enemies[0].current_hp < hp, "native melee attack hits nearby target while aiming")
	if str(CharacterManager.get_active_character().class_id).begins_with("fo"):
		await check_force(probe)

static func check_force(probe) -> void:
	var p = probe.player
	probe.set_shoulder(false)
	probe.enemies[0].global_position = p.global_position + Vector3(0, 0, -5)
	await probe.ticks(15)
	probe.key(KEY_Q)
	await probe.ticks(3)
	probe._check(is_instance_valid(p.combat_aim.lock.target), "Force acquires explicit enemy lock")
	var target = p.combat_aim.lock.target
	if not is_instance_valid(target): return
	var hp: int = target.current_hp
	var pp: int = GameState.mp
	var click := InputEventMouseButton.new()
	click.position = p.get_viewport().get_visible_rect().size * 0.5
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	Input.parse_input_event(click)
	await probe.ticks(2)
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await probe.ticks(150)
	probe._check(GameState.mp < pp and target.current_hp < hp, "right-click Foie spends PP and hits locked target")
	probe.key(KEY_Q)
	await probe.ticks(3)

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
	p._start_attack()
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
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await probe.ticks(2)
	var cue: Dictionary = preload("res://scripts/3d/player/combat_palette_cue.gd").read(p)
	probe._check(cue.get("charging", false) and cue.get("slot", -1) == 0, "front Foie slot exposes its charge circle")
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await probe.ticks(2)
	cue = preload("res://scripts/3d/player/combat_palette_cue.gd").read(p)
	probe._check(cue.get("recovery", false), "casting exposes palette recovery circles")
	await probe._snapshot("force-palette-cast")
	await probe.ticks(150)
	probe._check(GameState.mp < pp and target.current_hp < hp, "left-click Foie spends PP and hits locked target")
	await check_other_techniques(probe, target)
	probe.key(KEY_Q)
	await probe.ticks(3)

static func check_other_techniques(probe, target) -> void:
	var p = probe.player
	var hp: int = target.current_hp
	var pp: int = GameState.mp
	await cast_button(probe, MOUSE_BUTTON_RIGHT)
	probe._check(target.current_hp < hp and GameState.mp < pp, "front Barta spends PP and hits locked enemy")
	GameState.set_hp(maxi(1, GameState.hp - 10))
	var before: int = GameState.hp
	await cast_button(probe, MOUSE_BUTTON_MIDDLE)
	probe._check(GameState.hp > before, "front Resta heals the player")
	probe._check(preload("res://scripts/3d/player/combat_palette_cue.gd").read(p).is_empty(), "palette recovery clears when casting finishes")

static func cast_button(probe, button: int) -> void:
	var click := InputEventMouseButton.new()
	click.position = probe.get_viewport().get_visible_rect().size * 0.5
	click.button_index = button
	click.pressed = true
	Input.parse_input_event(click)
	await probe.ticks(2)
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await probe.ticks(150)

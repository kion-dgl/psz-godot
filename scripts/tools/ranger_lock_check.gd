extends RefCounted
## Actual input, camera, enemy selection, projectiles and combo clocks.
static func run(probe) -> void:
	await probe.ticks(3)
	var p = probe.player
	var orbit = probe.orbit
	var aim = orbit.combat_aim
	probe.set_shoulder(false)
	p.global_position = probe.origin
	p.transition_to(p.PlayerState.IDLE)
	orbit.camera_rotation = 0
	orbit.camera_pitch = 0
	probe.enemies[0].global_position = probe.origin + Vector3(0, 0, -6)
	probe.enemies[1].global_position = probe.origin + Vector3(2, 0, -5)
	await probe.ticks(15)
	probe.key(KEY_Q)
	await probe.ticks(3)
	probe._check(aim.mode == aim.Mode.LOCKED and aim.lock.target == probe.enemies[0], "Q acquires enemy nearest screen center")
	probe.key(KEY_TAB)
	await probe.ticks(3)
	probe._check(aim.lock.target == probe.enemies[1], "Tab switches explicit target")
	await probe._snapshot("ranger-lock")
	var selected = aim.lock.target
	Input.action_press("move_left")
	await probe.ticks(12)
	Input.action_release("move_left")
	probe._check(absf(angle_difference(p.player_rotation, aim.facing())) < 0.02, "locked strafe faces selected enemy")
	probe._check(aim.lock.target == selected, "movement does not steal explicit target")
	var hp: int = selected.current_hp
	await preload("res://scripts/tools/ranger_aim_combo_check.gd").run(probe, p, true)
	probe._check(selected.current_hp < hp, "locked combo projectiles reach selected enemy")
	probe._check(aim.lock.target == selected, "all three attacks retain selected target")
	await check_dodge_and_cover(probe, selected)
	probe.key(KEY_Q)
	await probe.ticks(3)
	probe._check(not aim.active, "second Q releases lock")
	probe.key(KEY_Q)
	await probe.ticks(3)
	probe.key(KEY_Z)
	await probe.ticks(3)
	probe._check(aim.mode == aim.Mode.SHOULDER and aim.lock.target == null, "Z switches lock to manual shoulder aim")
	probe.set_shoulder(false)
	await probe.ticks(3)
	probe.key(KEY_Q)
	await probe.ticks(3)
	selected = aim.lock.target
	probe._check(is_instance_valid(selected), "normal mode can reacquire target")
	if not is_instance_valid(selected): return
	selected.current_hp = 0
	await probe.ticks(3)
	probe._check(not aim.active and aim.lock.target == null, "dead target clears without stealing another enemy")
	selected.current_hp = 10000
	probe.key(KEY_Q)
	await probe.ticks(3)
	selected = aim.lock.target
	if not is_instance_valid(selected):
		probe._check(false, "target reacquired before range check")
		return
	selected.global_position = p.global_position + Vector3(0, 0, -30)
	await probe.ticks(3)
	probe._check(not aim.active, "target outside retention range clears lock")

static func check_dodge_and_cover(probe, selected) -> void:
	var p = probe.player
	var aim = probe.orbit.combat_aim
	p.dodge_cooldown = 0
	Input.action_press("move_right")
	probe.key(KEY_SPACE)
	await probe.ticks(2)
	Input.action_release("move_right")
	var heading: float = p.dodge_direction
	probe._check(p.current_state == p.PlayerState.DODGING, "Space dodges while locked")
	selected.global_position.x += 0.5
	await probe.ticks(5)
	probe._check(p.dodge_direction == heading, "moving locked enemy cannot bend dodge")
	await probe.ticks(90)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 4, 0.3)
	collision.shape = box
	wall.add_child(collision)
	p.get_tree().current_scene.add_child(wall)
	wall.global_position = p.global_position.lerp(selected.global_position, 0.5) + Vector3.UP
	await probe.ticks(3)
	probe._check(aim.active, "brief occlusion preserves explicit lock")
	await probe.ticks(45)
	probe._check(not aim.active, "sustained world occlusion clears lock")
	probe.key(KEY_Q)
	await probe.ticks(3)
	probe._check(not aim.active, "Q cannot acquire through world cover")
	wall.queue_free()
	await probe.ticks(3)
	probe.key(KEY_Q)
	await probe.ticks(3)
	probe._check(aim.active, "Q reacquires after cover clears")

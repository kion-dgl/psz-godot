extends RefCounted
## Exercise the real player's weapon release against the spawned arena enemy.
## Run by coliseum_probe before its enemy-damage → kill → return-warp checks.

static func run(player: Node3D, enemy: EnemyBase) -> bool:
	var player_pos := player.global_position
	var enemy_pos := enemy.global_position
	var yaw: float = player.player_rotation
	var enemy_hp := enemy.current_hp
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	var contacts: Array[int] = []
	var capture := func(damage: int, _kb: Vector3, _accuracy: int) -> void: contacts.append(damage)
	enemy.hurtbox.hit_received.connect(capture)
	var ok := true
	# Handgun/rifle targets are beyond the old shot lifetime; mechgun target
	# is off-axis but inside its weapon cone. All must match the reticle promise.
	var cases := [
		{"type": 9, "offset": Vector3(0.8, 0, -8), "hits": 1},
		{"type": 11, "offset": Vector3(0.7, 0, -10), "hits": 1},
		{"type": 10, "offset": Vector3(2, 0, -5), "hits": 3},
		{"type": 6, "offset": Vector3(1, 0, -6), "hits": 1},
	]
	for test in cases:
		contacts.clear()
		player.global_position = player_pos
		player.player_rotation = PI
		enemy.global_position = player_pos + test.offset
		enemy.current_hp = maxi(enemy_hp, 1000)
		await player.get_tree().physics_frame
		await player.get_tree().physics_frame
		player._fire_projectile({"weapon_type": test.type, "hits": test.hits,
			"damage": 10, "accuracy": 100, "knockback": 0.0, "max_targets": 1})
		await player.get_tree().create_timer(0.8).timeout
		var passed: bool = contacts.size() == int(test.hits)
		print("[coliseum] weapon %d at %.1fm: %d/%d contacts — %s" % [
			test.type, test.offset.length(), contacts.size(), test.hits, "PASS" if passed else "FAIL"])
		ok = ok and passed
	enemy.hurtbox.hit_received.disconnect(capture)
	enemy.current_hp = enemy_hp
	enemy.global_position = enemy_pos
	player.global_position = player_pos
	player.player_rotation = yaw
	player.set_physics_process(true)
	enemy.set_physics_process(true)
	return ok

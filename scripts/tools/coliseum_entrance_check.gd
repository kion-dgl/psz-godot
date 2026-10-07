extends RefCounted
## Observe real Booma clips in the arena, including two attack cycles.
## The player stands still; enemy AI and AnimationPlayer run normally.

static func run(player: Node3D, enemy: EnemyBase) -> bool:
	if not enemy.dormant or enemy.animation_player == null:
		push_error("[coliseum] entrance check needs a dormant enemy with real animations")
		return false
	player.set_physics_process(false)
	var clips: Array[String] = []
	var capture := func(clip: StringName) -> void: clips.append(str(clip))
	enemy.animation_player.animation_started.connect(capture)
	var origin := Vector2(enemy.global_position.x, enemy.global_position.z)
	var hp := GameState.hp
	enemy.reveal()
	var entrance := enemy._find_animation("stt")
	var length := enemy.animation_player.get_animation(entrance).length
	var ok := enemy.current_anim == "stt" and is_equal_approx(enemy._spawn_lock, length)
	var elapsed := 0.0
	while enemy._spawn_lock > 0 and elapsed < 5.0:
		var pos := Vector2(enemy.global_position.x, enemy.global_position.z)
		ok = ok and pos.distance_to(origin) < 0.01 and GameState.hp == hp
		ok = ok and enemy.animation_player.current_animation == entrance
		await player.get_tree().physics_frame
		elapsed += player.get_physics_process_delta_time()
	ok = ok and enemy._spawn_lock <= 0.0
	print("[coliseum] %s entrance: %.2fs, stationary and no damage — %s" % [enemy.enemy_data.id, length, "PASS" if ok else "FAIL"])
	var moved := false
	while elapsed < 35.0 and _strikes(clips) < 2:
		await player.get_tree().physics_frame
		elapsed += player.get_physics_process_delta_time()
		var pos := Vector2(enemy.global_position.x, enemy.global_position.z)
		moved = moved or pos.distance_to(origin) > 0.1
		if GameState.hp < hp / 2:
			GameState.set_hp(hp)
	ok = ok and moved and _strikes(clips) >= 2 and clips.count(entrance) == 1
	print("[coliseum] emergence count=%d strikes=%d pursued=%s — %s" % [clips.count(entrance), _strikes(clips), moved, "PASS" if ok else "FAIL"])
	enemy.animation_player.animation_started.disconnect(capture)
	GameState.set_hp(hp)
	player.set_physics_process(true)
	return ok


static func _strikes(clips: Array[String]) -> int:
	return clips.filter(func(clip: String): return clip.ends_with("_atk")).size()

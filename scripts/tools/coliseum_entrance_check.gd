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
	ok = await _observe_dash(player, enemy, clips, hp) and ok
	enemy.animation_player.animation_started.disconnect(capture)
	GameState.set_hp(hp)
	player.set_physics_process(true)
	return ok


static func _observe_dash(player: Node3D, enemy: EnemyBase, clips: Array[String], hp: int) -> bool:
	var ok := true
	var elapsed := 0.0
	while elapsed < 35.0 and clips.count(enemy._find_animation("atk_mi")) < 2:
		var preparing: bool = enemy._charge.get("phase", "") == "st"
		var before := enemy.global_position
		var before_hp := GameState.hp
		await player.get_tree().physics_frame
		elapsed += player.get_physics_process_delta_time()
		if preparing:
			ok = ok and before.distance_to(enemy.global_position) < 0.01 and before_hp == GameState.hp
		if GameState.hp < hp / 2:
			GameState.set_hp(hp)
	var sequence: Array[String] = []
	for clip in clips:
		if clip in [enemy._find_animation("atk"), enemy._find_animation("run"), enemy._find_animation("atk_mi")]:
			sequence.append(clip.trim_prefix("s071_"))
	ok = ok and sequence == ["atk", "run", "atk_mi", "atk", "run", "atk_mi"]
	ok = ok and clips.count(enemy._find_animation("stt")) == 1
	print("[coliseum] dash sequence=%s; stationary, harmless preparation — %s" % [sequence, "PASS" if ok else "FAIL"])
	return ok

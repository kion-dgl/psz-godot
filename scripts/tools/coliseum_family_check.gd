extends RefCounted
## Real imported clips and real deliveries. Decisions are checked separately by
## enemy_decision_scenarios; here each attack is explicitly exercised, including dodge.
static func run(player: Node3D, enemy: EnemyBase) -> bool:
	enemy.set_physics_process(false)
	var origin := enemy.global_position
	var ok := true
	for definition in enemy._attacks:
		if definition.get("berserk_only", false): continue
		for dodge in [false, true]:
			ok = await _attack(player, enemy, origin, definition, dodge) and ok
	player.current_state = player.PlayerState.IDLE
	enemy.global_position = origin
	enemy.current_state = enemy.EnemyState.CHASING
	enemy._attack_def = {}
	enemy._recovery_started = false
	enemy.set_physics_process(true)
	return ok

static func _attack(player: Node3D, enemy: EnemyBase, origin: Vector3, definition: Dictionary, dodge: bool) -> bool:
	_clear_deliveries(enemy)
	enemy.global_position = origin
	var distance := (float(definition.min_range) + float(definition.max_range)) * 0.5
	player.global_position = origin + Vector3(0,0,distance)
	player._freeze.clear(player)
	player.current_state = player.PlayerState.IDLE
	GameState.set_hp(82)
	enemy._attack_def = definition
	enemy.current_state = enemy.EnemyState.ATTACKING
	enemy._telegraphing = false
	enemy.velocity = Vector3.ZERO
	var clips: Array[String] = []
	var capture := func(clip: StringName): clips.append(str(clip))
	enemy.animation_player.animation_started.connect(capture)
	enemy._start_attack()
	var safe := true
	var finished := false
	var settle := 0
	for frame in range(480):
		if dodge:
			player.current_state = player.PlayerState.DODGING
			player.dodge_timer = 0.0
		await player.get_tree().physics_frame
		var before := enemy.global_position
		var preparation: bool = not enemy._windup_done or enemy._charge.get("phase", "") == "st"
		var recovery: bool = enemy._recovery_started or enemy._charge.get("phase", "") == "ed"
		if not finished:
			enemy._process_attacking(1.0/60.0)
			enemy.move_and_slide()
			if preparation:
				safe = safe and GameState.hp == 82 and enemy.global_position.distance_to(before) < 0.01
			if recovery:
				safe = safe and enemy.global_position.distance_to(before) < 0.01
			finished = not enemy.is_attacking
		else:
			settle += 1
			if settle >= 120: break
	enemy.animation_player.animation_started.disconnect(capture)
	var clip_ok := _clips_match(enemy, definition, clips)
	var hit := GameState.hp < 82
	var passed := safe and finished and clip_ok and hit != dodge
	print("[family-execution] ", enemy.enemy_data.id, "/", definition.id, " dodge=", dodge, " clips=", clips, " safe=", safe, " finished=", finished, " hit=", hit, " PASS=", passed)
	_clear_deliveries(enemy)
	return passed

static func _clips_match(enemy: EnemyBase, definition: Dictionary, clips: Array[String]) -> bool:
	var tokens: Array = definition.get("windup_clips", []).duplicate()
	if definition.get("kind", "") == "charge":
		var segments: Dictionary = definition.charge_segments
		tokens.append_array([segments.st, segments.lp, segments.ed])
	else:
		tokens.append(definition.clip)
		if definition.has("recovery_clip"): tokens.append(definition.recovery_clip)
	var cursor := 0
	for token in tokens:
		var full := enemy._find_animation(token)
		if full.is_empty(): return false
		var found := clips.find(full, cursor)
		if found < 0: return false
		cursor = found + 1
	return true

static func _clear_deliveries(enemy: EnemyBase) -> void:
	for node in enemy.get_parent().get_children():
		if node is EnemyProjectile or node is EnemyLob or node is IceTechnique:
			node.queue_free()

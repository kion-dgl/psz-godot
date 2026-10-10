extends RefCounted
## #684: ordinary AI + real rigs/physics. No forced attack selection or phase timers.
const MODES := ["hit", "dodge", "sidestep", "retreat", "wall", "thin_wall", "edge", "hurt", "hurt_travel", "lost"]

static func run(player: Node3D, enemy: EnemyBase) -> bool:
	var origin := enemy.global_position
	var hp: int = GameState.hp
	player.set_physics_process(false)
	var ok := _inspect_rig(enemy)
	for mode in MODES:
		ok = await _case(player, enemy, origin, str(mode), hp) and ok
	for phase in ["st", "lp"]:
		ok = await _death_case(player, enemy, origin, hp, phase) and ok
	preload("res://scripts/tools/enemy_decision_scenarios.gd").prepare(enemy, player, {"distance": 3.0, "condition": "ready"}, origin, 684)
	GameState.set_hp(hp)
	player.current_state = player.PlayerState.IDLE
	player.set_physics_process(true)
	enemy.set_physics_process(true)
	return ok

static func _box(parent: Node, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = position
	return body

static func _case(player: Node3D, enemy: EnemyBase, arena_origin: Vector3, mode: String, hp: int) -> bool:
	var origin := arena_origin
	var fixture: StaticBody3D
	if mode == "edge":
		# Above the arena floor: a finite platform with an unsupported gap ahead.
		origin.y += 12.0
		fixture = _box(enemy.get_parent(), origin + Vector3(0, -0.3, 0), Vector3(8, 0.5, 2.5))
	elif mode in ["wall", "thin_wall"]:
		fixture = _box(enemy.get_parent(), origin + Vector3(0, 1, 1.4 if mode == "wall" else 0.7), Vector3(8, 4, 0.1))
	var distance := 1.0 if mode == "thin_wall" else 3.0
	preload("res://scripts/tools/enemy_decision_scenarios.gd").prepare(enemy, player, {"distance": distance, "condition": "ready"}, origin, 684)
	enemy._recovery_started = false
	enemy.current_hp = enemy.enemy_data.hp_base
	player.current_state = player.PlayerState.IDLE
	GameState.set_hp(hp)
	await player.get_tree().physics_frame
	enemy.set_physics_process(true)
	var result := await _observe(player, enemy, origin, mode, hp)
	var passed: bool = result.started and result.finished and result.safe and result.hits == (1 if mode == "hit" else 0)
	passed = passed and (result.recovery or mode in ["hurt", "hurt_travel"]) and result.travel <= 4.01
	if mode in ["wall", "thin_wall"]: passed = passed and result.travel < (1.4 if mode == "wall" else 0.7)
	if mode == "edge": passed = passed and enemy.global_position.y > origin.y - 0.5 and result.travel < 1.25
	result.merge({"enemy":enemy.enemy_data.id,"difficulty":SessionManager.get_session().get("difficulty"),"mode":mode,"passed":passed,"seed":684})
	print("[booma-live] RESULT ", JSON.stringify(result))
	if fixture:
		fixture.queue_free()
		await player.get_tree().physics_frame
	return passed


static func _observe(player: Node3D, enemy: EnemyBase, origin: Vector3, mode: String, hp: int) -> Dictionary:
	var started := false
	var finished := false
	var safe := true
	var changed := false
	var saw_recovery := false
	var hits := 0
	var facing := Vector3.ZERO
	var previous_hp := hp
	var max_travel := 0.0
	var preparation_time := 0.0
	for frame in range(300):
		if mode == "dodge":
			player.current_state = player.PlayerState.DODGING
			player.dodge_timer = 0.0
		var phase: String = enemy._charge.get("phase", "")
		var before := enemy.global_position
		await player.get_tree().physics_frame
		var current_phase: String = enemy._charge.get("phase", "")
		if GameState.hp < previous_hp: hits += 1
		if phase in ["st", "ed"]:
			safe = safe and GameState.hp == previous_hp and Vector2(before.x, before.z).distance_to(Vector2(enemy.global_position.x, enemy.global_position.z)) < 0.01
		if current_phase == "st": preparation_time += 1.0 / 60.0
		previous_hp = GameState.hp
		if enemy.is_attacking and not started:
			started = true
			facing = enemy._attack_facing
		if started:
			safe = safe and enemy._attack_facing.is_equal_approx(facing)
			saw_recovery = saw_recovery or current_phase == "ed"
			max_travel = maxf(max_travel, Vector2(enemy.global_position.x-origin.x, enemy.global_position.z-origin.z).length())
			if not changed and (mode != "hurt_travel" or current_phase == "lp"):
				match mode:
					"sidestep": player.global_position.x += 4.0
					"retreat": player.global_position.z += 8.0
					"lost": enemy.target = null
					"hurt", "hurt_travel":
						# Accuracy is capped below 100%; pin the global hit roll as well
						# as the enemy RNG so this tests interruption, not random misses.
						seed(684)
						enemy._on_hit_received(1, Vector3.ZERO, 10000)
				changed = true
			if not enemy.is_attacking:
				finished = true
				break
	enemy.set_physics_process(false)
	return {"started":started,"finished":finished,"safe":safe,"hits":hits,"recovery":saw_recovery,"travel":max_travel,"preparation_seconds":preparation_time}


static func _death_case(player: Node3D, source: EnemyBase, origin: Vector3, hp: int, phase: String) -> bool:
	# A disposable real rig avoids reviving the arena's counted enemy after death.
	source.global_position = origin + Vector3(1000, 0, 0)
	var enemy := EnemyBase.new()
	enemy.enemy_data = source.enemy_data
	for child in source.get_children():
		if child is CollisionShape3D: enemy.add_child(child.duplicate())
	source.get_parent().add_child(enemy)
	preload("res://scripts/tools/enemy_decision_scenarios.gd").prepare(enemy, player, {"distance":3.0,"condition":"ready"}, origin, 684)
	player.current_state = player.PlayerState.IDLE
	GameState.set_hp(hp)
	enemy.set_physics_process(true)
	var reached := false
	for frame in range(180):
		await player.get_tree().physics_frame
		if enemy._charge.get("phase", "") == phase:
			reached = true
			break
	enemy._die()
	var position := enemy.global_position
	for frame in range(15): await player.get_tree().physics_frame
	var passed := reached and not enemy.is_alive and not enemy.is_attacking and GameState.hp == hp and enemy.global_position.distance_to(position) < 0.01
	print("[booma-live] RESULT ", JSON.stringify({"enemy":source.enemy_data.id,"difficulty":SessionManager.get_session().get("difficulty"),"mode":"death_"+phase,"passed":passed,"seed":684}))
	enemy.queue_free()
	source.global_position = origin
	await player.get_tree().physics_frame
	return passed


static func _inspect_rig(enemy: EnemyBase) -> bool:
	var clips := {}
	var complete := true
	for token in ["stt", "wat", "wlk", "atk", "run", "atk_mi", "atk_hi", "dam", "ded"]:
		var full := enemy._find_animation(token)
		if full.is_empty():
			complete = false
		else:
			clips[token] = {"name":full,"seconds":enemy.animation_player.get_animation(full).length}
	print("[booma-live] RIG ", JSON.stringify({"enemy":enemy.enemy_data.id,"model":enemy.enemy_data.model_id,"clips":clips,"complete":complete,"collision_radius":enemy.enemy_data.collision_radius,"collision_height":enemy.enemy_data.collision_height}))
	return complete


## PSO rigs: verify search versus combat-hold timing on the imported AnimationPlayer.
static func run_search(player: Node3D, enemy: EnemyBase) -> bool:
	var position := player.global_position
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	player.global_position = enemy.global_position + Vector3(100, 0, 0)
	enemy.target = player
	enemy.current_state = EnemyBase.EnemyState.IDLE
	enemy._process_idle(0.1)
	await player.get_tree().create_timer(0.1).timeout
	var ok := enemy.current_anim == "mihari" and enemy.animation_player.is_playing()
	ok = ok and enemy.animation_player.current_animation_position > 0.0
	player.global_position = enemy.global_position + Vector3(0, 0, 1.5)
	enemy._process_idle(0.1)
	ok = ok and enemy.current_state == EnemyBase.EnemyState.CHASING
	enemy._begin_telegraph()
	await player.get_tree().create_timer(0.1).timeout
	ok = ok and not enemy.animation_player.is_playing()
	ok = ok and is_zero_approx(enemy.animation_player.current_animation_position)
	enemy._process_telegraph(10.0)
	await player.get_tree().create_timer(0.1).timeout
	ok = ok and enemy.current_anim in ["atk_l", "atk_r"] and enemy.animation_player.is_playing()
	player.global_position = enemy.global_position + Vector3(100, 0, 0)
	enemy.current_state = EnemyBase.EnemyState.IDLE
	enemy._process_idle(0.1)
	await player.get_tree().create_timer(0.1).timeout
	ok = ok and enemy.current_anim == "mihari" and enemy.animation_player.is_playing()
	print("[coliseum] PSO search → neutral telegraph → swipe → search: ", "PASS" if ok else "FAIL")
	enemy.is_attacking = false
	enemy._telegraphing = false
	enemy.current_state = EnemyBase.EnemyState.CHASING
	player.global_position = position
	player.set_physics_process(true)
	enemy.set_physics_process(true)
	return ok

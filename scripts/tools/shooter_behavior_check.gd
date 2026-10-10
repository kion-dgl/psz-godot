extends RefCounted
## Ordinary-AI, imported-rig checks for the requested individual Korse behavior.
static func run(player: Node3D, enemy: EnemyBase) -> bool:
	var origin := enemy.global_position
	player.set_physics_process(false)
	var ok := true
	for mode in ["pressure", "shuffle", "recovery", "cover", "blocked_side", "edge", "committed"]:
		ok = await _case(player, enemy, origin, mode) and ok
	preload("res://scripts/tools/enemy_decision_scenarios.gd").prepare(enemy, player,
		{"distance":5.0,"condition":"ready"}, origin, 704)
	enemy.set_physics_process(true)
	player.set_physics_process(true)
	return ok


static func _case(player: Node3D, enemy: EnemyBase, original: Vector3, mode: String) -> bool:
	var origin := original + (Vector3.UP * 12.0 if mode == "edge" else Vector3.ZERO)
	var distance := 2.5 if mode in ["pressure", "edge"] else 5.0
	preload("res://scripts/tools/enemy_decision_scenarios.gd").prepare(enemy, player,
		{"distance":distance,"condition":"ready"}, origin, 704)
	enemy._recovery_started = false
	enemy._arc_side = 1.0
	enemy._arc_timer = 10.0
	enemy.attack_cooldown_timer = 5.0 if mode != "cover" and mode != "committed" else 0.0
	if mode == "recovery":
		enemy.current_state = EnemyBase.EnemyState.LOAFING
		enemy.loaf_timer = 2.0
	var wall: StaticBody3D
	if mode == "cover": wall = preload("res://scripts/tools/coliseum_booma_check.gd")._box(enemy.get_parent(), origin + Vector3(0,2,2.5), Vector3(3,4,0.1))
	if mode == "blocked_side": wall = preload("res://scripts/tools/coliseum_booma_check.gd")._box(enemy.get_parent(), origin + Vector3(-0.8,1,0), Vector3(0.3,3,2))
	if mode == "edge": wall = preload("res://scripts/tools/coliseum_booma_check.gd")._box(enemy.get_parent(), origin + Vector3(0,-0.3,0), Vector3(1.4,0.5,1.4))
	await player.get_tree().physics_frame
	await player.get_tree().physics_frame
	var passed := await _observe(player, enemy, origin, mode)
	if wall: wall.queue_free()
	preload("res://scripts/tools/coliseum_family_check.gd")._clear_deliveries(enemy)
	await player.get_tree().physics_frame
	return passed



static func _observe(player: Node3D, enemy: EnemyBase, origin: Vector3, mode: String) -> bool:
	var passed := true
	var started := false
	var start := Vector3.ZERO
	enemy.set_physics_process(true)
	for frame in range(240 if mode == "cover" else 30):
		GameState.set_hp(82)
		await player.get_tree().physics_frame
		if enemy.is_attacking and not started:
			started = true
			start = enemy.global_position
			if mode == "committed": player.global_position = origin + Vector3(1,0,2)
		if mode == "cover" and started:
			passed = passed and absf(enemy.global_position.x - origin.x) > 1.0
			break
		if mode == "committed" and started:
			passed = passed and enemy.global_position.distance_to(start) < 0.05
	enemy.set_physics_process(false)
	var moved := enemy.global_position - origin
	passed = _passes(mode, moved, started, passed)
	print("[shooter-behavior] ", enemy.enemy_data.id, "/", mode, " moved=", moved, " shot=", started, " PASS=", passed)
	return passed


static func _passes(mode: String, moved: Vector3, started: bool, passed: bool) -> bool:
	match mode:
		"pressure": passed = not started and absf(moved.x) > 0.25 and moved.z < -0.15
		"shuffle", "recovery": passed = not started and absf(moved.x) > 0.25
		"blocked_side": passed = not started and moved.x > 0.25
		"edge": passed = not started and Vector2(moved.x,moved.z).length() < 0.05 and moved.y > -0.5
		"cover", "committed": passed = passed and started
	return passed

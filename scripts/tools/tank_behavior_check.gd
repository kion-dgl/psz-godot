extends RefCounted
static func run(player: Node3D, enemy: EnemyBase) -> bool:
	var origin := enemy.global_position
	player.set_physics_process(false)
	var ok := true
	for mode in ["waves", "interrupt", "travel", "cooldowns", "guidance", "missile_wall", "missile_dodge", "missile_lost"]:
		_prepare(player, enemy, origin)
		var passed := await _case(player, enemy, mode)
		ok = passed and ok
		print("[tank-behavior] ", enemy.enemy_data.id, "/", mode, " PASS=", passed)
		preload("res://scripts/tools/coliseum_family_check.gd")._clear_deliveries(enemy)
	_prepare(player, enemy, origin)
	enemy.set_physics_process(true)
	player.set_physics_process(true)
	return ok

static func _case(player: Node3D, enemy: EnemyBase, mode: String) -> bool:
	if mode == "cooldowns":
		for definition in enemy._attacks:
			enemy._attack_def = definition
			enemy._tank.begin(enemy)
		if enemy._has_attack_in_band(4.0, 0.0) or enemy._has_attack_in_band(7.0, 0.0): return false
		enemy._tank.tick(enemy, 4.1)
		return enemy._select_attack_for(7.0).id == "shot" and enemy._tank.cooldowns.blitz > 0 and enemy._tank.cooldowns.missiles > 0
	if mode.begins_with("missile_"): return await _impact(enemy, mode)
	if mode == "guidance": return await _guidance(player, enemy)
	if mode == "travel": return await _travel(player, enemy)
	return await _waves(player, enemy, mode == "interrupt")

static func _travel(player: Node3D, enemy: EnemyBase) -> bool:
	for definition in enemy._attacks: enemy._tank.cooldowns[definition.id] = 20.0
	var origin := enemy.global_position
	var phases: Array[String] = []
	for i in range(165):
		await player.get_tree().physics_frame
		enemy._tank.tick(enemy, 1.0/60.0)
		enemy._process_chasing(1.0/60.0)
		var phase: String = enemy._tank.phase
		if not phase.is_empty() and phase not in phases: phases.append(phase)
		if enemy.is_attacking: return false
		if phase in ["st", "ed"] and Vector2(enemy.velocity.x, enemy.velocity.z).length() > 0.01: return false
		enemy.move_and_slide()
	return phases == ["st", "lp", "ed"] and enemy.global_position.distance_to(origin) > 2.0

static func _waves(player: Node3D, enemy: EnemyBase, interrupt: bool) -> bool:
	for definition in enemy._attacks:
		if definition.id == "missiles": enemy._attack_def = definition
	enemy._start_attack()
	var releases: Array[float] = []
	var capture := func(node: Node):
		if node is EnemyLob: releases.append(enemy._attack_pos / enemy._attack_clip_len)
	enemy.get_parent().child_entered_tree.connect(capture)
	for i in range(300):
		GameState.set_hp(82)
		await player.get_tree().physics_frame
		if enemy.is_attacking: enemy._process_attacking(1.0/60.0)
		if interrupt and releases.size() >= 2 and enemy.is_attacking:
			enemy._on_hit_received(1, Vector3.ZERO, 10000)
		if not enemy.is_attacking and i > 180: break
	enemy.get_parent().child_entered_tree.disconnect(capture)
	if interrupt: return releases.size() == 2 and enemy.animation_player.speed_scale == 1.0
	return releases.size() == 6 and releases[2] - releases[0] > 0.15 and releases[4] - releases[2] > 0.15

static func _guidance(player: Node3D, enemy: EnemyBase) -> bool:
	var missile := preload("res://scripts/3d/enemies/tank_missile.gd").new()
	missile.from = enemy.global_position + Vector3.UP * 1.5
	missile.to = player.global_position
	missile.target = player
	missile.flight_time = 1.5
	enemy.get_parent().add_child(missile)
	missile.set_physics_process(false)
	missile.global_position = missile.from
	player.global_position.x += 2.0
	missile._physics_process(0.4)
	var tracked := missile.to.x
	missile._physics_process(0.4)
	var locked := missile.to
	player.global_position.x += 5.0
	missile._physics_process(0.1)
	var passed := tracked > enemy.global_position.x and missile.to.is_equal_approx(locked)
	missile.queue_free()
	await player.get_tree().physics_frame
	return passed

static func _prepare(player: Node3D, enemy: EnemyBase, origin: Vector3) -> void:
	preload("res://scripts/tools/enemy_decision_scenarios.gd").prepare(enemy, player,
		{"distance":7.0,"condition":"ready"}, origin, 7240)

static func _impact(enemy: EnemyBase, mode: String) -> bool:
	var target := preload("res://scripts/tools/coliseum_projectile_check.gd").Target.new()
	enemy.get_parent().add_child(target)
	target.global_position = enemy.global_position + Vector3(0, 0, 7)
	target.dodge = mode == "missile_dodge"
	var missile := preload("res://scripts/3d/enemies/tank_missile.gd").new()
	missile.from = enemy.global_position + Vector3.UP * 1.5
	missile.to = target.global_position
	missile.target = target if mode != "missile_lost" else null
	missile.flight_time = 1.5
	missile.blast_radius = 0.65
	enemy.get_parent().add_child(missile)
	missile.set_physics_process(false)
	missile.global_position = missile.from
	var wall: StaticBody3D
	if mode == "missile_wall":
		wall = preload("res://scripts/tools/coliseum_booma_check.gd")._box(enemy.get_parent(), enemy.global_position + Vector3(0,3,3.5), Vector3(8,6,0.1))
	await enemy.get_tree().physics_frame
	await enemy.get_tree().physics_frame
	# A single slow frame still subdivides the curved path for cover collision.
	missile._physics_process(1.6)
	var passed := target.hits == 0 and missile._spent and missile.is_queued_for_deletion()
	if wall: wall.queue_free()
	target.queue_free()
	return passed

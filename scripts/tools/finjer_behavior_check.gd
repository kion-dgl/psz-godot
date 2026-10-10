extends RefCounted
## Imported-rig movement and commitment checks, separate from hit/dodge delivery checks.
static func run(player: Node3D, enemy: EnemyBase) -> bool:
	var origin := enemy.global_position
	player.set_physics_process(false)
	var ok := true
	for mode in ["pressure", "strafe_fire", "spin_commit", "spin_cooldown"]:
		preload("res://scripts/tools/enemy_decision_scenarios.gd").prepare(enemy, player,
			{"distance":1.5 if mode == "pressure" else 7.0,"condition":"ready"}, origin, 704)
		enemy._arc_timer = 10.0
		enemy._arc_side = 1.0
		var passed := await _case(player, enemy, mode)
		ok = passed and ok
		print("[finjer-behavior] ", enemy.enemy_data.id, "/", mode, " PASS=", passed)
		preload("res://scripts/tools/coliseum_family_check.gd")._clear_deliveries(enemy)
	preload("res://scripts/tools/enemy_decision_scenarios.gd").prepare(enemy, player,
		{"distance":7.0,"condition":"ready"}, origin, 704)
	enemy.set_physics_process(true)
	player.set_physics_process(true)
	return ok


static func _case(player: Node3D, enemy: EnemyBase, mode: String) -> bool:
	if mode == "pressure":
		enemy._process_chasing(1.0/60.0)
		return not enemy.is_attacking and absf(enemy.velocity.x) > 1.0 and enemy.velocity.z < -1.0
	if mode == "spin_cooldown": return _cooldown(enemy)
	return await _attack(player, enemy, mode)


static func _attack(player: Node3D, enemy: EnemyBase, mode: String) -> bool:
	for definition in enemy._attacks:
		if definition.id == ("shot" if mode == "strafe_fire" else "spin"):
			enemy._attack_def = definition
	enemy._start_attack()
	var origin := enemy.global_position
	var facing := enemy._attack_facing
	var moved := false
	var released := false
	for i in range(180):
		await player.get_tree().physics_frame
		enemy._process_attacking(1.0/60.0)
		enemy.move_and_slide()
		if mode == "spin_commit" and not enemy._attack_facing.is_equal_approx(facing): return false
		if mode == "strafe_fire":
			moved = moved or absf(enemy.global_position.x - origin.x) > 0.2
			released = released or enemy._window_opened
		if i == 1 and mode == "spin_commit": player.global_position.x += 5.0
		if not enemy.is_attacking: break
	return (moved and released) if mode == "strafe_fire" else enemy._finjer_spin_cooldown > 0.0 and not enemy.is_attacking


static func _cooldown(enemy: EnemyBase) -> bool:
	enemy._finjer_spin_cooldown = 6.0
	for i in range(100):
		if enemy._select_attack_for(7.0).id != "shot": return false
	enemy._tick_combat_timers(6.0)
	var spins := 0
	for i in range(100):
		if enemy._select_attack_for(7.0).id == "spin": spins += 1
	return spins > 0 and spins < 40

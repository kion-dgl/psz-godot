extends RefCounted
## Optional live-rig checks before the existing weapon/room-clear probe.
static func run(player: Node3D, enemy: EnemyBase) -> bool:
	var hp: int = GameState.hp
	player.set_physics_process(false)
	enemy.reveal()
	while enemy._spawn_lock > 0.0:
		await player.get_tree().physics_frame
	player.global_position = enemy.global_position + Vector3(0, 0, -2.0)
	var ok := false
	match enemy._archetype:
		"boarder", "missile_tank", "shade", "mother_caster", "shooter": ok = await preload("res://scripts/tools/coliseum_family_check.gd").run(player, enemy)
		"simple_melee": ok = await preload("res://scripts/tools/coliseum_family_check.gd").run(player, enemy)
		"lunging_melee": ok = await preload("res://scripts/tools/coliseum_helion_check.gd").run(player, enemy)
		"roller": ok = await _roller(player, enemy)
		"stance_riser": ok = await _snake(player, enemy)
		"two_attack": ok = await preload("res://scripts/tools/coliseum_family_check.gd").run(player, enemy)
		_: ok = await _lily(player, enemy)
	if enemy._archetype == "shooter":
		ok = await preload("res://scripts/tools/shooter_behavior_check.gd").run(player, enemy) and ok
	if enemy._archetype == "boarder":
		ok = await preload("res://scripts/tools/finjer_behavior_check.gd").run(player, enemy) and ok
	if enemy._tank.enabled(enemy):
		ok = await preload("res://scripts/tools/tank_behavior_check.gd").run(player, enemy) and ok
	GameState.set_hp(hp)
	player._freeze.clear(player)
	player.set_physics_process(true)
	print("[coliseum] %s runtime regression — %s" % [enemy.enemy_data.id, "PASS" if ok else "FAIL"])
	return ok

static func _lily(player: Node3D, enemy: EnemyBase) -> bool:
	var starts: Array[String] = []
	var capture := func(clip: StringName): starts.append(str(clip))
	enemy.animation_player.animation_started.connect(capture)
	for i in range(600):
		await player.get_tree().physics_frame
		GameState.set_hp(82)
	enemy.animation_player.animation_started.disconnect(capture)
	var attacks := starts.count("attack_re2_b_root")
	print("[coliseum] lily attacks in 10 seconds=", attacks)
	return attacks >= 2

static func _snake(player: Node3D, enemy: EnemyBase) -> bool:
	for i in range(900):
		await player.get_tree().physics_frame
		GameState.set_hp(82)
		if enemy._lower_timer > 0.1:
			var pos := enemy.global_position
			await player.get_tree().physics_frame
			return enemy.current_anim == "wt2w" and enemy.global_position.distance_to(pos) < 0.01
	return false

static func _roller(player: Node3D, enemy: EnemyBase) -> bool:
	var basis := enemy.model.basis
	for i in range(900):
		await player.get_tree().physics_frame
		GameState.set_hp(82)
		if enemy._charge.get("phase", "") == "ed":
			var remaining: float = enemy._charge.ed_dur - enemy._charge.phase_t
			enemy._on_hit_received(1, Vector3.ZERO, 10000)
			return enemy.model.basis.is_equal_approx(basis) and enemy._vulnerable_mult > 1.0 and is_equal_approx(remaining, enemy._charge.ed_dur - enemy._charge.phase_t)
	return false

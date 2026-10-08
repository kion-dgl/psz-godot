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
		"boarder", "missile_tank", "shade", "mother_caster": ok = await preload("res://scripts/tools/coliseum_family_check.gd").run(player, enemy)
		"simple_melee": ok = await preload("res://scripts/tools/coliseum_family_check.gd").run(player, enemy)
		"lunging_melee": ok = await preload("res://scripts/tools/coliseum_helion_check.gd").run(player, enemy)
		"roller": ok = await _roller(player, enemy)
		"stance_riser": ok = await _snake(player, enemy)
		"two_attack": ok = await _ice(player, enemy)
		_: ok = await _lily(player, enemy)
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

static func _ice(player: Node3D, enemy: EnemyBase) -> bool:
	# Pin the authored cast to ensure weighted melee selection cannot hide it.
	enemy.set_physics_process(false)
	for definition in enemy._attacks:
		if not str(definition.get("tech", "")).is_empty(): enemy._attack_def = definition
	enemy._start_attack()
	var saw_bolt := false
	var hp: int = GameState.hp
	for i in range(240):
		await player.get_tree().physics_frame
		enemy._process_attacking(1.0 / 60.0)
		for node in enemy.get_parent().get_children():
			if node is EnemyProjectile and node.technique_id == enemy._attack_def.get("tech", ""): saw_bolt = true
	var hit := GameState.hp < hp
	enemy.set_physics_process(true)
	print("[coliseum] named ice projectile=", saw_bolt, " contact damage=", hit)
	return saw_bolt and hit

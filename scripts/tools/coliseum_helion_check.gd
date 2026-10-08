extends RefCounted
## Live imported rigs + physics: selection, timing, travel, dodge and wall contact.
static func run(player: Node3D, enemy: EnemyBase) -> bool:
	enemy.set_physics_process(false)
	var origin := enemy.global_position
	var ok := true
	for scenario in ["claws", "lunge", "dodge", "wall"]:
		var passed := await _scenario(player, enemy, origin, scenario)
		ok = ok and passed
	player.current_state = player.PlayerState.IDLE
	enemy.global_position = origin
	enemy.current_state = enemy.EnemyState.CHASING
	enemy._attack_def = {}
	enemy.set_physics_process(true)
	return ok

static func _scenario(player: Node3D, enemy: EnemyBase, origin: Vector3, scenario: String) -> bool:
	enemy.global_position = origin
	player.global_position = origin + Vector3(0,0,1.5 if scenario == "claws" else 5.0)
	player.current_state = player.PlayerState.DODGING if scenario == "dodge" else player.PlayerState.IDLE
	player.dodge_timer = 0.0
	GameState.set_hp(82)
	var wall: StaticBody3D
	if scenario == "wall":
		wall = StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(8,4,0.2)
		shape.shape = box
		wall.add_child(shape)
		enemy.get_parent().add_child(wall)
		wall.global_position = origin + Vector3(0,1,2)
	await player.get_tree().physics_frame
	enemy._attack_def = enemy._select_attack_for(enemy.global_position.distance_to(player.global_position))
	enemy.current_state = enemy.EnemyState.ATTACKING
	enemy._telegraphing = false
	enemy.velocity = Vector3.ZERO
	enemy._start_attack()
	var expected := "atk" if scenario == "claws" else "atkb"
	var correct_clip := enemy.current_anim == expected
	var preparation_ok := true
	for i in range(120):
		await player.get_tree().physics_frame
		if scenario == "dodge":
			player.current_state = player.PlayerState.DODGING
			player.dodge_timer = 0.0
		enemy._process_attacking(1.0 / 60.0)
		if enemy._attack_pos < enemy._attack_clip_len * float(enemy._attack_def.get("windup_frac", 0)):
			preparation_ok = preparation_ok and enemy.global_position.distance_to(origin) < 0.01 and GameState.hp == 82
		if not enemy.is_attacking: break
	var hit := GameState.hp < 82
	var travel := enemy.global_position.distance_to(origin)
	var passed: bool = preparation_ok and hit == (scenario in ["claws", "lunge"])
	passed = passed and (travel < 0.01 if scenario == "claws" else travel <= 5.51)
	if scenario == "wall": passed = passed and travel < 2 and enemy._lunge.blocked
	print("[coliseum] Helion ", scenario, " clip=", expected, " travel=", travel, " hit=", hit, " PASS=", passed)
	passed = passed and correct_clip
	if wall: wall.queue_free()
	return passed

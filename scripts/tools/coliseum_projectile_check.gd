extends RefCounted
## Individual imported-rig delivery contracts. Selection is independently checked
## through ordinary AI by enemy_decision_scenarios. No mixed groups are used.
const MODES := ["hit", "dodge", "wall", "muzzle_wall", "sidestep", "hurt", "death", "lost", "owner_death", "aim_lock", "retreat"]

class Target extends Node3D:
	var hits := 0
	var dodge := false
	func is_dodge_iframed() -> bool: return dodge
	func take_damage(_damage: int, _knockback: Vector3, _knockdown: bool) -> void: hits += 1
	func take_technique_hit(_damage: int, _tech: String) -> void: hits += 1


static func run(player: Node3D, source: EnemyBase) -> bool:
	player.set_physics_process(false)
	source.set_physics_process(false)
	var origin := source.global_position
	source.global_position += Vector3(1000, 0, 0)
	var ok := true
	for definition in source._attacks:
		if definition.get("kind", "") not in ["projectile", "lob"] or definition.get("missile_waves", false): continue
		for mode in MODES:
			ok = await _case(source, origin, definition, mode) and ok
	source.global_position = origin
	preload("res://scripts/tools/enemy_decision_scenarios.gd").prepare(source, player,
		{"distance": 5.0, "condition": "ready"}, origin, 7240)
	source.set_physics_process(true)
	player.set_physics_process(true)
	return ok


static func _case(source: EnemyBase, origin: Vector3, definition: Dictionary, mode: String) -> bool:
	var parent := source.get_parent()
	var target := Target.new()
	parent.add_child(target)
	var distance := (float(definition.min_range) + float(definition.max_range)) * 0.5
	target.global_position = origin + Vector3.BACK * distance
	target.dodge = mode == "dodge"
	var enemy := EnemyBase.new()
	enemy.enemy_data = source.enemy_data
	parent.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = origin
	enemy.target = target
	enemy.dormant = false
	enemy._spawn_lock = 0.0
	enemy._rng.seed = 7240
	enemy.current_hp = 10000
	enemy.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var wall: StaticBody3D
	if mode in ["wall", "muzzle_wall"]:
		wall = StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(20, 12, 0.05)
		collision.shape = box
		wall.add_child(collision)
		parent.add_child(wall)
		wall.global_position = origin + Vector3(0, 3, 0.4 if mode == "muzzle_wall" else distance * 0.5)
	await source.get_tree().physics_frame
	await source.get_tree().physics_frame
	var deliveries: Array[Node] = []
	var releases: Array[Node] = []
	var capture := func(node: Node):
		if node is EnemyProjectile or node is EnemyLob or node is IceTechnique:
			deliveries.append(node)
			node.set_physics_process(false)
			if not (node is EnemyProjectile and not node.technique_id.is_empty()): releases.append(node)
	parent.child_entered_tree.connect(capture)
	enemy._attack_def = definition
	enemy.current_state = EnemyBase.EnemyState.ATTACKING
	enemy._start_attack()
	var result := _simulate(enemy, target, definition, mode, deliveries, releases)
	result["enemy"] = source.enemy_data.id
	print("[projectile-live] RESULT ", JSON.stringify(result))
	parent.child_entered_tree.disconnect(capture)
	for node in deliveries:
		if is_instance_valid(node): node.free()
	if wall: wall.free()
	enemy.free()
	target.free()
	return result.passed


static func _interrupt(enemy: EnemyBase, target: Target, mode: String) -> void:
	match mode:
		"hurt":
			seed(7240)
			enemy._on_hit_received(1, Vector3.ZERO, 10000)
		"death": enemy._die()
		"lost": enemy.target = null
		"aim_lock": target.global_position.x += 6.0


static func _simulate(enemy: EnemyBase, target: Target, definition: Dictionary,
		mode: String, deliveries: Array[Node], releases: Array[Node]) -> Dictionary:
	var safe := true
	var changed := false
	var saw_release := false
	for frame in range(600):
		if frame == 1: _interrupt(enemy, target, mode)
		var before_window := not enemy._window_opened
		if enemy.current_state == EnemyBase.EnemyState.ATTACKING:
			enemy.animation_player.advance(1.0 / 60.0)
			enemy._process_attacking(1.0 / 60.0)
		if before_window and not enemy._window_opened:
			safe = safe and releases.is_empty() and target.hits == 0
		if not releases.is_empty():
			saw_release = true
			if not changed:
				changed = true
				if mode == "sidestep": target.global_position.x += 6.0
				if mode == "retreat": target.global_position.z += float(definition.hit_reach) + 5.0
				if mode == "owner_death": enemy._die()
		# Snapshot: ice controllers may append bolts while being stepped.
		for node in deliveries.duplicate():
			if is_instance_valid(node) and not node.is_queued_for_deletion(): node._physics_process(1.0 / 60.0)
		if frame > 300 and not enemy.is_attacking: break
	return _result(enemy, target, definition, mode, deliveries, releases, safe, saw_release)


static func _result(enemy: EnemyBase, target: Target, definition: Dictionary, mode: String,
		deliveries: Array[Node], releases: Array[Node], safe: bool, saw_release: bool) -> Dictionary:
	var cancelled := mode in ["hurt", "death", "lost"]
	var expected_hits := 1 if mode in ["hit", "owner_death"] or (mode == "aim_lock" and (definition.kind == "lob" or enemy._archetype == "boarder")) else 0
	var expired := deliveries.all(func(node: Node): return node.is_queued_for_deletion())
	var passed := safe and expired and target.hits == expected_hits and releases.size() == (0 if cancelled else 1) and not enemy.is_attacking
	return {"attack":definition.id,"mode":mode,"passed":passed,"hits":target.hits,
		"releases":releases.size(),"safe":safe,"finished":not enemy.is_attacking,
		"saw_release":saw_release,"expired":expired,"seed":7240}

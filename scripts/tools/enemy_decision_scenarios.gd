extends RefCounted
## Shared expectations, ordinary AI entry: never select or start an attack here.
const CASE_PATH := "res://data/combat_scenarios.json"

static func config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CASE_PATH))

static func prepare(enemy: EnemyBase, player: Node3D, row: Dictionary, origin: Vector3, seed_value: int) -> void:
	enemy.set_physics_process(false)
	enemy.global_position = origin
	player.global_position = origin + Vector3(0,0,float(row.distance))
	enemy.target = player
	enemy.velocity = Vector3.ZERO
	enemy.current_state = EnemyBase.EnemyState.CHASING
	enemy.is_attacking = false
	enemy._attack_def = {}
	enemy._charge = {}
	enemy._telegraphing = false
	enemy._threat_timer = 0.0
	enemy._lower_timer = 0.0
	enemy._berserk = false
	enemy._status_effects.clear()
	enemy._update_immobilized()
	enemy.dormant = false
	enemy._spawn_lock = 0.0
	enemy._tank.cooldowns.clear()
	enemy._tank.phase = ""
	enemy._tank.travel_cooldown = 0.0
	enemy._finjer_spin_cooldown = 0.0
	enemy.attack_cooldown_timer = 0.0
	enemy._rng.seed = seed_value
	enemy._play_animation("wat", true)
	apply_condition(enemy, str(row.condition))

static func apply_condition(enemy: EnemyBase, condition: String) -> void:
	match condition:
		"cooldown": enemy.attack_cooldown_timer = 1.0
		"hurt":
			enemy.current_state = EnemyBase.EnemyState.HURT
			enemy.hurt_timer = 1.0
		"recovery":
			enemy.current_state = EnemyBase.EnemyState.LOAFING
			enemy.loaf_timer = 1.0
		"dormant": enemy.dormant = true
		"entrance": enemy._spawn_lock = 1.0
		"freeze": enemy.apply_status_effect("freeze")
		"stun_no_attack":
			enemy._status_effects = [{"type":"stun", "timer":1.0, "dot_timer":0.0, "phase":"no_attack"}]
			enemy._update_immobilized()

static func observed(enemy: EnemyBase) -> String:
	return str(enemy._attack_def.get("id", "")) if enemy.is_attacking else ""

static func passes(row: Dictionary, actual: String) -> bool:
	return actual.is_empty() if row.allowed_attacks.is_empty() else actual in row.allowed_attacks

static func run(r: Node) -> void:
	var cfg := config()
	for row in cfg.cases:
		for id in row.enemies:
			for seed_offset in range(8):
				_unit_case(r, row, str(id), int(cfg.seed) + seed_offset, int(cfg.observation_frames))

static func _unit_case(r: Node, row: Dictionary, id: String, seed_value: int, frames: int) -> void:
	var enemy: EnemyBase = r._make_rig_enemy({"wat":0.5, "atk":1.0, "atkb":0.9})
	enemy.set_physics_process(false)
	enemy._attacks = EnemyAttackRegistry.get_attacks(id, 2.0)
	enemy._archetype = EnemyAttackRegistry.get_archetype(id)
	enemy._fsm = EnemyAttackRegistry.get_fsm(id)
	var player := Node3D.new()
	r.add_child(player)
	prepare(enemy, player, row, Vector3.ZERO, seed_value)
	var actual := ""
	for i in range(frames):
		enemy._physics_process(1.0/60.0)
		actual = observed(enemy)
		if not actual.is_empty(): break
	r.assert_true(passes(row, actual), "%s/%s seed=%d expected=%s observed=%s" % [id, row.id, seed_value, str(row.allowed_attacks), actual])
	enemy.free()
	player.free()

static func run_live(player: Node3D, enemy: EnemyBase) -> bool:
	var cfg := config()
	var origin := enemy.global_position
	var hp: int = GameState.hp
	enemy.reveal()
	while enemy._spawn_lock > 0.0:
		await player.get_tree().physics_frame
	player.set_physics_process(false)
	var results: Array = []
	var ok := true
	for row in cfg.cases:
		if enemy.enemy_data.id not in row.enemies: continue
		prepare(enemy, player, row, origin, int(cfg.seed))
		enemy.set_physics_process(true)
		var actual := ""
		for i in range(int(cfg.observation_frames)):
			await player.get_tree().physics_frame
			actual = observed(enemy)
			if not actual.is_empty(): break
		enemy.set_physics_process(false)
		var passed := passes(row, actual)
		results.append({"case":row.id, "expected":row.allowed_attacks, "observed":actual, "pass":passed})
		print("[combat-scenario] ", enemy.enemy_data.id, "/", row.id, " expected=", row.allowed_attacks, " observed=", actual, " PASS=", passed)
		ok = ok and passed
	if results.is_empty():
		push_error("No decision scenarios authored for " + enemy.enemy_data.id)
		ok = false
	var file := FileAccess.open("user://combat-scenarios-%s.json" % enemy.enemy_data.id, FileAccess.WRITE)
	file.store_string(JSON.stringify({"enemy":enemy.enemy_data.id,"seed":cfg.seed,"results":results,"pass":ok}, "  "))
	prepare(enemy, player, {"distance":5.0,"condition":"ready"}, origin, int(cfg.seed))
	GameState.set_hp(hp)
	player.set_physics_process(true)
	enemy.set_physics_process(true)
	return ok

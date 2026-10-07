extends RefCounted
## Asset-independent regression for per-archetype stt semantics.

static func run(runner: Node) -> void:
	for enemy_id in ["booma_origin", "gigobooma_origin"]:
		var data: EnemyData = EnemyRegistry.get_enemy(enemy_id)
		runner.assert_eq(EnemyAttackRegistry.get_archetype(enemy_id), "bruiser", enemy_id + " is a bruiser")
		runner.assert_eq(EnemyAttackRegistry.get_fsm(enemy_id).get("spawn_clip"), "stt", enemy_id + " authors emergence")
		var enemy: EnemyBase = runner._make_rig_enemy({"stt": 1.4, "wat": 0.5, "atk": 0.5})
		enemy.enemy_data = data
		enemy._archetype = "bruiser"
		enemy._fsm = EnemyAttackRegistry.get_fsm(enemy_id)
		enemy.dormant = true
		enemy.animation_player.speed_scale = 0.5
		enemy.reveal()
		runner.assert_eq(enemy.current_anim, "stt", "bruiser emergence starts at reveal")
		runner.assert_almost_eq(enemy._spawn_lock, 2.8, 0.001, "spawn hold follows clip and playback speed")
		runner.assert_eq(enemy.animation_player.get_animation("stt").loop_mode, Animation.LOOP_NONE, "emergence is one-shot")
		enemy.velocity = Vector3(3, 0, 3)
		runner.assert_true(enemy._early_process_returns(0.9), "entrance still gates AI after the old 0.8s lock")
		runner.assert_true(enemy.velocity.x == 0 and enemy.velocity.z == 0, "no movement during emergence")
		var remaining := enemy._spawn_lock
		enemy.reveal()
		runner.assert_eq(enemy._spawn_lock, remaining, "reveal cannot replay an active entrance")
		enemy.free()
	_test_telegraphs(runner)
	_test_dash(runner)
	var absent: EnemyBase = runner._make_rig_enemy({"wat": 0.5})
	absent._fsm = {"spawn_clip": "missing"}
	absent.dormant = true
	absent.reveal()
	runner.assert_eq(absent._spawn_lock, EnemyBase.SPAWN_LOCK_SEC, "missing clip retains finite fallback hold")
	absent.free()


static func _test_telegraphs(runner: Node) -> void:
	var target := Node3D.new()
	runner.add_child(target)
	target.position = Vector3(0, 0, 1)
	for archetype in ["bruiser", "bigrig_combo", "flyer_combo", "roller", "ape_gunner", "quadruped", "box_mimic", "simple_melee"]:
		var enemy: EnemyBase = runner._make_rig_enemy({"stt": 1.0, "wat": 0.5, "wat1": 0.5, "wat2": 0.5, "tk": 0.5, "tk1": 0.5, "atk": 0.5})
		enemy._archetype = archetype
		enemy.target = target
		runner.assert_eq(enemy._find_animation("spawn"), "", archetype + " does not borrow stt for spawn")
		enemy._begin_telegraph()
		runner.assert_true(not enemy._telegraph_rising, archetype + " does not replay stt before a strike")
		runner.assert_true(enemy.current_anim not in ["stt", "wat2"], archetype + " uses its own ready pose")
		enemy.free()
	target.free()


class ContactTarget extends Node3D:
	var hits := 0
	var invincible := false
	func take_damage(_amount: int, _knockback: Vector3 = Vector3.ZERO, _knockdown: bool = false) -> void:
		hits += 1
	func is_dodge_iframed() -> bool:
		return invincible


static func _test_dash(runner: Node) -> void:
	for dodging in [false, true]:
		var target := ContactTarget.new()
		runner.add_child(target)
		target.position = Vector3(0, 0, 2.5)
		target.invincible = dodging
		var definition: Dictionary = EnemyAttackRegistry.get_attacks("booma_origin")[0]
		var enemy: EnemyBase = runner._make_charge_enemy({"atk": 0.8167, "run": 0.3333, "atk_mi": 0.2333}, definition, target)
		enemy._archetype = "bruiser"
		target.position.z = 0.5  # inside contact range throughout preparation
		runner.assert_true(not enemy._charge["rotate_model"], "explicit Booma segments do not spin its body")
		for i in range(45):
			enemy._process_attacking(1.0 / 60.0)
		runner.assert_eq(target.hits, 0, "dash preparation cannot damage")
		runner.assert_eq(enemy.current_anim, "atk", "preparation plays before dash")
		runner.assert_eq(enemy.velocity, Vector3.ZERO, "preparation stays stationary")
		target.position.z = 2.5
		var saw_run := false
		var saw_recovery := false
		for i in range(160):
			enemy._process_attacking(1.0 / 60.0)
			enemy.position += enemy.velocity / 60.0
			saw_run = saw_run or enemy.current_anim == "run"
			saw_recovery = saw_recovery or enemy.current_anim == "atk_mi"
		runner.assert_true(saw_run and saw_recovery, "dash and recovery follow preparation")
		runner.assert_eq(target.hits, 0 if dodging else 1, "dash contact respects dodge and one-hit budget")
		runner.assert_true(not enemy.is_attacking, "charge recovers even after a dodge")
		enemy.free()
		target.free()

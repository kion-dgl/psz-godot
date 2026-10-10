extends RefCounted
## #684: authored decisions and committed charge lifetime, independent of rendering.

static func run(r: Node) -> void:
	seed(684)
	for id in ["booma_origin", "gigobooma_origin"]:
		for mode in ["sidestep", "retreat", "lost", "dodge_then_release", "hurt", "death"]:
			var target := preload("res://scripts/tools/enemy_entrance_tests.gd").ContactTarget.new()
			r.add_child(target)
			target.position = Vector3(0, 0, 2.5)
			var enemy: EnemyBase = r._make_charge_enemy({"atk": 0.8167, "run": 0.3333, "atk_mi": 0.2333, "dam": 0.5, "ded": 0.5}, EnemyAttackRegistry.get_attacks(id)[0], target)
			enemy._archetype = "bruiser"
			var facing := enemy._attack_facing
			var budget: float = enemy._charge.travel_target
			match mode:
				"sidestep": target.position.x = 3.0
				"retreat": target.position.z = 20.0
				"lost": enemy.target = null
				"dodge_then_release":
					target.position.z = 0.5
					target.invincible = true
				"hurt": enemy._on_hit_received(1, Vector3.ZERO, 10000)
				"death": enemy._die()
			var saw_recovery := false
			var facing_held := true
			for frame in range(150):
				if enemy.current_state == EnemyBase.EnemyState.ATTACKING:
					enemy._process_attacking(1.0 / 60.0)
					enemy.position += enemy.velocity / 60.0
					saw_recovery = saw_recovery or enemy.current_anim == "atk_mi"
				if mode == "dodge_then_release" and enemy._attack_hit_resolved:
					target.invincible = false
				facing_held = facing_held and enemy._attack_facing.is_equal_approx(facing)
			r.assert_true(facing_held, id + " committed direction " + mode)
			r.assert_eq(target.hits, 0, id + " no contact after " + mode)
			r.assert_true(not enemy.is_attacking, id + " bounded completion " + mode)
			r.assert_true(enemy.position.z <= budget + 0.01, id + " bounded travel " + mode)
			if mode not in ["hurt", "death"]:
				r.assert_true(saw_recovery, id + " miss recovers " + mode)
			enemy.free()
			target.free()

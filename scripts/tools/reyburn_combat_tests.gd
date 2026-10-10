extends RefCounted

class Victim extends Node3D:
	var hits := 0
	var push := Vector3.ZERO
	func take_damage(_damage: int) -> void: hits += 1
	func apply_knockback(value: Vector3) -> void: push = value

static func run(t: Node) -> void:
	seed(563)
	var b = t._make_rig_enemy({"start": 0.6, "brslp": 0.4, "strike": 1.0, "wlk1": 1.0}, ReyburnBoss.new())
	b.set_physics_process(false)
	var v := Victim.new()
	t.add_child(v)
	b.target = v
	v.position = Vector3(0, 0, 3)
	b.rotation.y = 0
	t.assert_true(b._arc_hit(4, 60, 1), "Reyburn +Z front hits")
	v.position.z = -3
	t.assert_true(not b._arc_hit(4, 60, 1), "Reyburn rear cannot take frontal bite")
	v.position = Vector3(0, 0, 4.01)
	t.assert_true(not b._arc_hit(4, 60, 1), "retreat outside reach avoids bite")
	v.position = Vector3(3, 0, 0)
	b._face(v.position, 0.25)
	t.assert_true(absf(b.rotation.y - deg_to_rad(30)) < 0.001, "turn limited to authored 120 degrees/s")
	b.rotation.y = 0
	b._knockback_player(8)
	t.assert_eq(v.push, Vector3(0, 0, 8), "push follows model forward")
	b._ground_attacks = [{"clip": "strike", "min_range": 4.0, "max_range": 8.0, "weight": 1.0}]
	for distance in [3.99, 8.01]:
		t.assert_true(not b._pick_ground_attack(distance), "outside selection band rejected")
	for distance in [4.0, 8.0]:
		t.assert_true(b._pick_ground_attack(distance), "inclusive selection boundary")
	b._ground_attacks[0].weight = 0.0
	t.assert_true(not b._pick_ground_attack(5.0), "disabled attack weight never selected")
	b._begin_attack({"clip": "strike", "chain": ["start", "brslp", "strike"], "lp_loops": 2, "windup_frac": 0.7})
	t.assert_true(absf(b._t - 0.6) < 0.001, "first prelude uses real clip duration")
	b._tick_telegraph(0.6)
	t.assert_eq(b._s, b.S.TELEGRAPH, "second prelude is not skipped")
	t.assert_true(absf(b._t - 0.8) < 0.001, "loop prelude repeats authored count")
	b._tick_telegraph(0.8)
	t.assert_eq(b._s, b.S.ATTACK, "final clip starts after all preludes")
	t.assert_true(absf(b._cur._hit_at - 0.3) < 0.001, "release uses authored fraction")
	v.position = b.position + Vector3(0, 0, 2)
	b.rotation.y = 0
	var before := v.hits
	b._tick_attack(0.69)
	t.assert_eq(v.hits, before, "before release harmless")
	b._tick_attack(0.02)
	b._tick_attack(0.02)
	t.assert_eq(v.hits, before + 1, "strike releases exactly once")
	b._walk_toward(v.position + Vector3(0, 0, 5), 0.1)
	b.animation_player.advance(0.3)
	b._walk_toward(v.position + Vector3(0, 0, 5), 0.1)
	t.assert_true(b.animation_player.current_animation_position > 0.2, "walk does not restart")
	b._cur = {"clip": "strike", "kind": "charge"}
	b.rotation.y = 0
	b._execute_attack()
	b._tick_attack(0.05)
	t.assert_true(b.velocity.z > 0.0, "charge advances toward model front")
	var locked_yaw: float = b.rotation.y
	v.position = b.position + Vector3(3, 0, 0)
	b._tick_attack(0.05)
	t.assert_eq(b.rotation.y, locked_yaw, "strike facing stays locked when player sidesteps")
	b._enter_enrage()
	t.assert_eq(b.animation_player.current_animation, "strike", "enrage preserves active clip")
	b.free()
	v.free()

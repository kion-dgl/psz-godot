extends RefCounted
## Guard facing, immediate startup, active melee sweep, and enemy hit reaction regressions.
static func run(t: Node) -> void:
	var rules = preload("res://scripts/3d/player/humar_saber_prototype.gd")
	t.assert_true(rules.facing_guard(0, Vector3(0,0,2)), "saber guard accepts front")
	t.assert_true(not rules.facing_guard(0, Vector3(0,0,-2)), "saber guard rejects rear")
	t.assert_true(not rules.facing_guard(0, Vector3(2,0,0)), "saber guard rejects flank")
	t.assert_true(not rules.facing_guard(0, Vector3.ZERO), "saber guard requires a direction")
	t.assert_true(rules.facing_guard(PI, Vector3(0,0,-2)), "guard respects player facing")
	t.assert_true(rules.facing_guard(0, Vector3(1.7,0,1)), "guard accepts just inside cone")
	t.assert_true(not rules.facing_guard(0, Vector3(1.8,0,1)), "guard rejects just outside cone")
	t.assert_eq(rules.READY_PREP, 0.0, "fresh attacks start immediately without 250ms prepare freeze")
	_check_enemy_feel(t)
	_check_pso_accuracy_and_trail(t)


static func _check_enemy_feel(t: Node) -> void:
	var enemy := EnemyBase.new()
	enemy.enemy_data = EnemyRegistry.get_enemy("ghowl").duplicate()
	enemy.set_physics_process(false)
	t.add_child(enemy)
	enemy.rotation.y = 0.0
	enemy._face_direction(Vector3(1.0, 0.0, 0.0), true)
	t.assert_true(enemy.rotation.y > 0.0 and enemy.rotation.y < PI * 0.5, "smooth enemy turn interpolates instead of snapping 90 deg")
	enemy._face_direction(Vector3(1.0, 0.0, 0.0), false)
	t.assert_true(is_equal_approx(enemy.rotation.y, PI * 0.5), "instant enemy facing locks immediately when requested")
	enemy.current_evasion = 0
	enemy.enemy_data.hp_base = 500
	enemy.current_hp = 500
	enemy._hit_is_heavy = false
	enemy._on_hit_received(40, Vector3(0.0, 0.0, 5.0), 999)
	t.assert_true(enemy.hurt_timer >= 0.40, "light hit stagger covers combo follow-up")
	var light_recoil: float = enemy._hit_recoil_vel.z
	t.assert_true(light_recoil > 0.3 and light_recoil < 2.0, "light hit keeps enemy in melee combo reach")
	enemy._hit_is_heavy = true
	enemy._on_hit_received(40, Vector3(0.0, 0.0, 5.0), 999)
	enemy._hit_is_heavy = false
	t.assert_true(enemy.hurt_timer >= 0.58, "heavy hit applies deeper stagger")
	t.assert_true(enemy._hit_recoil_vel.z >= 5.0 and enemy._hit_recoil_vel.z > light_recoil * 3.0, "heavy/finisher hit delivers strong PSO knockback slide")
	enemy._fsm["stationary"] = true
	enemy._hit_recoil_vel = Vector3.ZERO
	enemy._hit_is_heavy = true
	enemy._on_hit_received(40, Vector3(0.0, 0.0, 5.0), 999)
	enemy._hit_is_heavy = false
	t.assert_true(enemy._hit_recoil_vel.is_zero_approx(), "stationary enemies never recoil")
	enemy.free()


static func _check_pso_accuracy_and_trail(t: Node) -> void:
	var saved_chars: Array = CharacterManager._characters.duplicate(true)
	var saved_slot: int = CharacterManager._active_slot
	CharacterManager._characters.resize(20)
	var ch = CharacterManager.create_character(19, "humarl", "ComboAccFixture")
	if ch.is_empty():
		CharacterManager.delete_character(19)
		CharacterManager.create_character(19, "humarl", "ComboAccFixture")
	CharacterManager.set_active_slot(19)
	var s1 := CombatManager.calculate_attack_damage(1, false)
	var s2 := CombatManager.calculate_attack_damage(2, false)
	var s3 := CombatManager.calculate_attack_damage(3, false)
	var h1 := CombatManager.calculate_attack_damage(1, true)
	var h3 := CombatManager.calculate_attack_damage(3, true)
	t.assert_true(int(s2.accuracy) > int(s1.accuracy) and int(s3.accuracy) > int(s2.accuracy), "PSO combo accuracy scales up across steps 1->2->3")
	t.assert_true(int(h1.accuracy) < int(s1.accuracy) and int(h3.accuracy) > int(s1.accuracy), "Step-1 strong trades accuracy while step-3 strong out-accurates step-1 normal (0.7 * 1.69 = 1.183x)")
	t.assert_eq(int(s3.combo_step), 3, "attack packet carries combo_step")
	t.assert_true(bool(h3.strong), "attack packet carries strong flag")
	CharacterManager.delete_character(19)
	CharacterManager._characters = saved_chars
	CharacterManager._active_slot = -1
	if saved_slot >= 0:
		CharacterManager.set_active_slot(saved_slot)

	var trail_cls = preload("res://scripts/3d/combat/weapon_slash_trail.gd")
	var fake_weapon := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.1, 1.2)
	fake_weapon.mesh = box
	t.add_child(fake_weapon)
	var ep: Dictionary = trail_cls.compute_blade_endpoints(fake_weapon)
	t.assert_true(ep.tip.z > ep.base.z + 0.5, "slash trail computes blade base-to-tip along longest mesh axis")
	var trail = trail_cls.new()
	t.add_child(trail)
	trail.step_trail(fake_weapon, ep, true, Color(0.35, 0.85, 1.0), 0.016)
	fake_weapon.position = Vector3(0.3, 0.0, 0.1)
	trail.step_trail(fake_weapon, ep, true, Color(0.35, 0.85, 1.0), 0.016)
	t.assert_true(trail.visible, "slash trail renders ribbon once blade sweeps two samples")
	trail.clear_trail()
	t.assert_true(not trail.visible, "clear_trail hides ribbon cleanly")
	trail.free()
	fake_weapon.free()

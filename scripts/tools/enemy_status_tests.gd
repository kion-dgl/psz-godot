extends RefCounted

static func run(t: Node) -> void:
	for kind in ["freeze", "stun"]:
		var enemy: EnemyBase = t._make_rig_enemy({"atk": 10.0, "dmg": 1.0})
		enemy.current_hp = 10000
		enemy.enemy_data.hp_base = 10000
		enemy.animation_player.speed_scale = 1.4
		enemy._play_animation("atk", true)
		enemy.apply_status_effect(kind)
		var at := enemy.position
		enemy.velocity = Vector3(5, 3, 5)
		enemy._physics_process(1.0)
		t.assert_eq(enemy.position, at, kind + " stops all movement")
		t.assert_eq(enemy.animation_player.speed_scale, 0.0, kind + " freezes animation and its attack events")
		enemy._on_hit_received(10, Vector3.ZERO, 10000)
		t.assert_true(enemy.current_hp < 10000 and enemy._is_immobilized, kind + " permits damage without releasing control")
		t.assert_eq(enemy.current_anim, "atk", kind + " cannot restart animation on damage")
		enemy._process_status_effects(3.8)
		t.assert_true(enemy._is_immobilized, kind + " gives nearly five seconds to heal or attack")
		enemy._process_status_effects(0.3)
		t.assert_true(not enemy._is_immobilized, kind + " releases after five seconds")
		t.assert_almost_eq(enemy.animation_player.speed_scale, 1.4, 0.001, kind + " restores original animation speed")
		t.assert_true(not enemy._status_feedback.ice.visible and not enemy._status_feedback.stars.visible, kind + " clears visuals on expiry")
		enemy.free()
	var burning: EnemyBase = t._make_rig_enemy({})
	burning.enemy_data.hp_base = 1000
	burning.current_hp = 1000
	burning.apply_status_effect("burn")
	t.assert_true(burning._status_feedback.fire.emitting, "burn shows fire on the enemy")
	burning._process_status_effects(0.5)
	burning.apply_status_effect("burn")
	t.assert_eq(burning._status_effects.size(), 1, "repeated burn refreshes without stacking")
	burning._process_status_effects(0.5)
	t.assert_eq(burning.current_hp, 950, "refresh keeps the damage tick cadence")
	burning._process_status_effects(5.5)
	t.assert_eq(burning.current_hp, 700, "burn deals six ticks of five percent maximum HP")
	t.assert_true(not burning._status_feedback.fire.emitting, "fire stops on expiry")
	burning.current_hp = 40
	burning.apply_status_effect("freeze")
	burning.apply_status_effect("burn")
	burning._process_status_effects(1.0)
	t.assert_true(not burning.is_alive, "burn can kill an immobilized enemy")
	t.assert_true(burning._status_effects.is_empty(), "death clears all statuses")
	burning.free()
	for action in ["attack", "strong_attack", "heat_trap", "ice_trap", "light_trap", "heal_trap"]:
		t.assert_true(ActionPalette.get_action_icon(action) != null, action + " has palette artwork")

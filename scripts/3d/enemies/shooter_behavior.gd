extends RefCounted
## Player-directed Korse design: a ranged skirmisher, with committed firing windows.

static func chase(enemy: EnemyBase, distance: float) -> void:
	if enemy.attack_cooldown_timer <= 0.0 and not enemy._stun_no_attack \
			and enemy._has_attack_in_band(distance, 0.0) and _clear_shot(enemy, enemy.global_position):
		enemy.current_state = EnemyBase.EnemyState.ATTACKING
		enemy._begin_telegraph()
		return
	move(enemy, distance)


static func move(enemy: EnemyBase, distance: float, animate: bool = true) -> void:
	if not is_instance_valid(enemy.target):
		enemy.velocity = Vector3.ZERO
		return
	enemy._tick_arc_side(1.5, 2.5, 0.4)
	var radial := enemy._radial_to_target()
	var preferred := float(enemy._fsm.get("standoff_range", 5.0))
	var direction := Vector3.ZERO
	var best := -INF
	for side in [enemy._arc_side, -enemy._arc_side]:
		var candidate := EnemyLocomotionLogic.shooter_move(distance, preferred, radial, side)
		if not enemy._can_move_to(candidate) or enemy.test_move(enemy.global_transform, candidate * 0.65):
			continue
		var score := 0.1 if side == enemy._arc_side else 0.0
		if _clear_shot(enemy, enemy.global_position + candidate * 1.2): score += 2.0
		if score > best:
			best = score
			direction = candidate
			enemy._arc_side = side
	var speed := enemy._base_move_speed() * float(enemy._fsm.get("evade_speed_mult", 1.0) if distance < preferred * 0.8 else enemy._fsm.get("strafe_speed_mult", 0.7))
	var clip := String(enemy._fsm.get("move_clip", "run")) if not direction.is_zero_approx() else "wat"
	enemy._apply_move(direction, speed, radial, clip if animate else "")


static func _clear_shot(enemy: EnemyBase, position: Vector3) -> bool:
	if not is_instance_valid(enemy.target): return false
	var origin := position + Vector3.UP * 1.2
	var end := Vector3(enemy.target.global_position.x, origin.y, enemy.target.global_position.z)
	return ProjectileSweep.environment_fraction(enemy.get_world_3d().direct_space_state,
		origin, end - origin, 0.04) < 0.0

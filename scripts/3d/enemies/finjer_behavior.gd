extends RefCounted
## Observed strafing fire; spin cadence and speeds are design tuning, not recovered AI.
static func shooting_move(enemy: EnemyBase) -> void:
	if enemy._archetype != "boarder" or enemy._attack_kind != "projectile" or not is_instance_valid(enemy.target): return
	preload("res://scripts/3d/enemies/shooter_behavior.gd").move(enemy,
		enemy.global_position.distance_to(enemy.target.global_position), false)
	# Track until release, then the laser flies straight without homing.
	if not enemy._window_opened:
		enemy._attack_facing = enemy._radial_to_target()

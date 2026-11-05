extends EnemyProjectile
## Neutral environmental damage, like BombTrap: enemy hurtbox owns defense,
## defeat and rewards. No player attack attribution, combos or on-hit procs.
## Only the locked actor can be hit; bystanders and other traps are unaffected.

func _resolve_contact() -> void:
	if not GunTrap.eligible_target(target): return
	if target is EnemyBase:
		var enemy := target as EnemyBase
		if is_instance_valid(enemy.hurtbox):
			enemy.hurtbox.take_hit(damage, Vector3.ZERO, 1000)
	else:
		super._resolve_contact()

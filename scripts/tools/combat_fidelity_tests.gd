extends RefCounted
## Seeded delivery regressions; the physics-space half lives in combat_fidelity_probe.

class Target extends Node3D:
	var hits := 0
	var effects := 0
	var invincible := false
	func is_dodge_iframed() -> bool:
		return invincible
	func take_damage(_damage: int, _knockback: Vector3, _knockdown: bool) -> void:
		hits += 1


static func run(runner: Node) -> void:
	seed(629)
	for dt in [1.0 / 60.0, 1.0 / 15.0, 0.5]:
		var target := Target.new()
		runner.add_child(target)
		target.position = Vector3(0, 0, 2)
		var shot := _shot(runner, target)
		for tick in range(60):
			shot._physics_process(dt)
			if shot._hit:
				break
		runner.assert_eq(target.hits, 1, "enemy shot cannot tunnel at dt=%s" % dt)
		shot._physics_process(dt)
		runner.assert_eq(target.hits, 1, "consumed enemy shot cannot resolve twice")
		shot.free()
		target.free()

	var target := Target.new()
	runner.add_child(target)
	target.position = Vector3(0, 0, 3)
	var shot := _shot(runner, target)
	shot.max_range = 1.0
	shot._physics_process(0.5)
	runner.assert_eq(target.hits, 0, "range expiry precedes out-of-range contact")
	runner.assert_true(shot.position.z <= 1.0, "enemy travel clamps to range")
	shot.free()
	target.position = Vector3(1, 0, 2)
	shot = _shot(runner, target)
	shot._physics_process(0.5)
	runner.assert_eq(target.hits, 0, "swept near miss stays a miss")
	shot.free()
	target.position = Vector3(0, 0, 2)
	target.invincible = true
	shot = _shot(runner, target)
	shot._physics_process(0.5)
	runner.assert_true(shot._hit, "dodge consumes swept contact")
	runner.assert_eq(target.hits, 0, "dodge suppresses direct damage")
	runner.assert_eq(target.effects, 0, "dodge suppresses on-hit poison")
	target.invincible = false
	shot._physics_process(0.5)
	runner.assert_eq(target.hits, 0, "dodged projectile cannot hit after i-frames end")
	shot.free()
	target.free()


static func _shot(runner: Node, target: Target) -> EnemyProjectile:
	var shot := EnemyProjectile.new()
	shot.target = target
	shot.dir = Vector3(0, 0, 1)
	shot.max_range = 8.0
	shot.on_hit = func(_body: Node3D) -> void: target.effects += 1
	runner.add_child(shot)
	shot.set_physics_process(false)
	return shot

extends RefCounted

class TestGun extends GunTrap:
	var blocked: Node3D
	func _ready() -> void:
		model = Node3D.new()
		add_child(model)
	func clear_sight(actor: Node3D) -> bool:
		return actor != blocked

class TestEnemy extends EnemyBase:
	func _ready() -> void:
		add_to_group("enemies")
		hurtbox = Hurtbox.new()
		add_child(hurtbox)

static func run(t: Node) -> void:
	var root := Node3D.new()
	t.add_child(root)
	var gun := TestGun.new()
	root.add_child(gun)
	gun.set_process(false)
	var enemy := TestEnemy.new()
	root.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.position = Vector3(0, 0, 4)
	t.assert_eq(gun.nearby_actor(), enemy, "turret acquires living enemy")
	gun.blocked = enemy
	t.assert_true(gun.nearby_actor() == null, "turret rejects occluded enemy")
	gun.blocked = null
	enemy.position.z = -4
	t.assert_true(gun.nearby_actor() == null, "turret rejects enemy behind authored cone")
	enemy.position.z = GunTrap.RANGE + 1
	t.assert_true(gun.nearby_actor() == null, "turret rejects distant enemy")
	enemy.position.z = 4
	enemy.is_alive = false
	t.assert_true(gun.nearby_actor() == null, "turret rejects defeated enemy")
	enemy.is_alive = true
	var box := Box.new()
	t.assert_true(not GunTrap.eligible_target(box), "turret excludes destructible scenery")
	box.free()
	var hits: Array = []
	enemy.hurtbox.hit_received.connect(func(damage, _knockback, accuracy): hits.append([damage, accuracy]))
	var bullet := preload("res://scripts/3d/elements/turret_projectile.gd").new()
	bullet.target = enemy
	bullet.damage = 8
	bullet._resolve_contact()
	t.assert_eq(hits, [[8, 1000]], "turret uses enemy hurtbox damage contract")
	enemy.is_alive = false
	bullet._resolve_contact()
	t.assert_eq(hits.size(), 1, "turret shot ignores a defeated target")
	gun.add_child(bullet)
	gun.take_damage(0)
	t.assert_true(gun.is_alive, "zero damage does not destroy turret")
	gun.take_damage(1)
	t.assert_true(not gun.is_alive and gun.model.visible, "hit disables turret but retains spinning model")
	t.assert_true(bullet.is_queued_for_deletion(), "destruction clears existing projectiles immediately")
	gun._update_animation(0.3)
	t.assert_true(not gun.model.rotation.is_zero_approx() and gun.detonations == 0, "turret wobbles before exploding")
	gun.take_damage(1)
	gun._update_animation(0.3)
	gun._update_animation(0.31)
	t.assert_eq(gun.detonations, 1, "repeat hits do not restart destruction")
	t.assert_true(not gun.model.visible, "explosion hides turret")
	gun._update_animation(2.0)
	t.assert_eq(gun.detonations, 1, "explosion occurs exactly once")
	var records := PlacedTraps.snapshots(root)
	var restored := PlacedTraps.build("gun_trap", records[0].state, records[0]) as GunTrap
	t.assert_true(not restored.is_alive and restored._spin_remaining == 0.0, "room restore cannot resurrect or replay destroyed turret")
	restored.free()
	root.free()

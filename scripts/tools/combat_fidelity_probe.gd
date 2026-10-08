extends Node3D
## Real physics-space regression, independent of asset availability.
## Run with an isolated user-data project: godot --headless --path <project>
## res://scripts/tools/combat_fidelity_probe.tscn

var _fail := 0
var _fixtures: Array[Node] = []

class Target extends Node3D:
	var is_alive := true
	var hits := 0
	var elements: Array[String] = []
	func _on_hit_received(_damage: int, _knockback: Vector3, _accuracy: int,
			element: String, _level: int) -> void:
		hits += 1
		elements.append(element)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_order_and_pierce()
	await _check_point_blank_and_exclusions()

	print("[combat-fidelity] DONE %s" % ("ok" if _fail == 0 else "FAIL"))
	get_tree().quit(0 if _fail == 0 else 1)


func _check_order_and_pierce() -> void:
	seed(629)
	for delta in [1.0 / 60.0, 1.0 / 15.0, 0.5]:
		# Reverse insertion order: the physically nearest target must win.
		var far := _target(Vector3(0, 1, 5))
		var near := _target(Vector3(0, 1, 2))
		var shot := _shot(false, 3)
		await _sync_physics()
		for tick in range(60):
			shot._physics_process(delta)
			if shot._spent:
				break
		_check(near.hits == 1 and far.hits == 0, "nearest single contact at dt=%s" % delta)
		shot._physics_process(delta)
		_check(near.hits == 1, "no duplicate contact after consumption")
		_clear()

	var first := _target(Vector3(0, 1, 2))
	_add_hurtbox(first, Vector3(0, 0, 0.2))  # Two parts, one owner.
	var second := _target(Vector3(0, 1, 4))
	var third := _target(Vector3(0, 1, 6))
	var piercing := _shot(true, 2)
	piercing.element = "fire"
	await _sync_physics()
	piercing._physics_process(0.5)
	_check(first.hits == 1 and second.hits == 1 and third.hits == 0, "pierce cap counts unique owners")
	_check(first.elements == ["fire"] and second.elements == ["fire"], "elements survive swept delivery")
	_clear()

	# A large shape can be first even though its owner center is farther away.
	var small := _target(Vector3(0, 1, 5))
	var large := _target(Vector3(0, 1, 8))
	var large_shape: SphereShape3D = large.get_child(0).get_child(0).shape
	large_shape.radius = 4.0
	var ordered := _shot(false, 1)
	await _sync_physics()
	ordered._physics_process(0.5)
	_check(large.hits == 1 and small.hits == 0, "impact order uses shape surfaces, not owner centers")
	_clear()

	# More than one physics query page: unlimited pierce must not lose contacts.
	var crowd: Array[Target] = []
	for index in range(40):
		crowd.append(_target(Vector3(0, 1, 1.0 + index * 0.1)))
	var unlimited := _shot(true, 0)
	await _sync_physics()
	unlimited._physics_process(0.5)
	_check(crowd.all(func(t: Target): return t.hits == 1), "unlimited pierce covers more than 32 hurtboxes")
	_clear()



func _check_point_blank_and_exclusions() -> void:
	var point_blank := _target(Vector3(0, 1, 0))
	var shot := _shot(false, 1)
	await _sync_physics()
	shot._physics_process(0.5)
	_check(point_blank.hits == 1, "shot spawned inside a hurtbox still hits")
	_clear()

	var outside := _target(Vector3(0, 1, 3))
	shot = _shot(false, 1)
	shot.max_range = 1.0
	await _sync_physics()
	shot._physics_process(0.5)
	_check(outside.hits == 0 and shot.position.z <= 1.0, "range clamped before contact")
	_clear()

	var high := _target(Vector3(0, 4, 2))
	var shooter := _target(Vector3(0, 1, 0))
	var eligible := _target(Vector3(0, 1, 4))
	shot = _shot(false, 1)
	shot.owner_node = shooter
	await _sync_physics()
	shot._physics_process(0.5)
	_check(shooter.hits == 0 and high.hits == 0 and eligible.hits == 1, "owner excluded and real vertical shape respected")
	_clear()
	var dormant := _target(Vector3(0, 1, 1))
	var corpse := _target(Vector3(0, 1, 2))
	corpse.is_alive = false
	var live := _target(Vector3(0, 1, 4))
	shot = _shot(false, 1)
	await _sync_physics()
	dormant.get_child(0).monitorable = false
	await _sync_physics()
	shot._physics_process(0.5)
	_check(dormant.hits == 0 and corpse.hits == 0 and live.hits == 1, "inactive hurtboxes and corpses do not consume shots")
	_clear()


func _target(pos: Vector3) -> Target:
	var target := Target.new()
	add_child(target)
	target.position = pos
	_add_hurtbox(target, Vector3.ZERO)
	_fixtures.append(target)
	return target


func _add_hurtbox(target: Target, offset: Vector3) -> void:
	var hurtbox := Hurtbox.new()
	hurtbox.owner_node = target
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	shape.shape = sphere
	hurtbox.add_child(shape)
	target.add_child(hurtbox)
	hurtbox.position = offset


func _shot(pierce: bool, cap: int) -> Projectile:
	var shot := Projectile.new()
	shot.pierce = pierce
	shot.max_hits = cap
	shot.max_range = 10.0
	shot.direction = Vector3(0, 0, 1)
	add_child(shot)
	shot.position = Vector3(0, 1, 0)
	shot.set_physics_process(false)
	_fixtures.append(shot)
	return shot


func _sync_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _clear() -> void:
	for fixture in _fixtures:
		if is_instance_valid(fixture):
			fixture.free()
	_fixtures.clear()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[combat-fidelity] PASS: " + label)
		return
	_fail += 1
	push_error("[combat-fidelity] FAIL: " + label)

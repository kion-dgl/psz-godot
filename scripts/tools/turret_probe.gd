extends "res://scripts/tools/probe_checks.gd"
## Run turret_probe.tscn with disposable user data and downloaded assets.
## PSZ_BOSS_SCREENSHOTS optionally captures both turret variants.

func _run() -> void:
	probe_label = "turret"
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(4, 4, 6)
	camera.look_at(Vector3.UP)
	camera.current = true
	for variant in ["o0c_gun01", "o0c_gun02"]:
		await _variant(variant)
	print("[turret] DONE %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _variant(variant: String) -> void:
	var arena := Node3D.new()
	add_child(arena)
	var gun := PlacedTraps.build("gun_trap", "on", {"model": variant}) as GunTrap
	arena.add_child(gun)
	gun.set_process(false)
	_check(gun.model != null, variant + " model loads")
	var enemy := preload("res://scripts/tools/turret_tests.gd").TestEnemy.new()
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.position = Vector3(0, 0, 4)
	var hits: Array = []
	enemy.hurtbox.hit_received.connect(func(damage, _knockback, _accuracy): hits.append(damage))
	gun._update_animation(0.01)
	_check(gun.element_state == "warning", "living enemy triggers warning")
	gun._update_animation(GunTrap.WARNING)
	await get_tree().create_timer(0.6).timeout
	_check(hits == [8] and gun.shots_fired == 1, "swept projectile delivers exactly one enemy hit")
	await _snapshot(variant + "-intact")
	gun.hurtbox.take_hit(1, Vector3.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not gun.hurtbox.monitorable and not gun.is_alive, "hurtbox disables immediately")
	gun._update_animation(0.35)
	await _snapshot(variant + "-spin")
	_check(gun.model.visible and gun.detonations == 0, "model spins before explosion")
	var record := PlacedTraps.snapshots(arena)
	_check(record.size() == 1 and record[0].state == "spent", "mid-spin room snapshot is spent")
	gun._update_animation(GunTrap.SPIN_TIME)
	await get_tree().create_timer(0.15).timeout
	await _snapshot(variant + "-blast")
	_check(not gun.model.visible and gun.detonations == 1, "explosion completes once")
	await get_tree().create_timer(1.2).timeout
	_check(arena.get_node_or_null("HazardBlast") == null, "explosion cleans up")
	enemy.free()
	arena.free()

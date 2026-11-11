extends "res://scripts/tools/probe_checks.gd"
const Visual = preload("res://scripts/3d/effects/technique_visual.gd")

func _run() -> void:
	probe_label = "technique-vfx"
	var geometry := Visual.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var rock := geometry._ice_rock(rng)
	var arrays := rock.surface_get_arrays(0)
	var outward := 0.0
	for i in range(arrays[Mesh.ARRAY_VERTEX].size()):
		var vertex: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
		outward += Vector3(vertex.x, 0, vertex.z).dot(arrays[Mesh.ARRAY_NORMAL][i])
	_check(outward > 0.0, "ice surfaces face outward for transparent back-face culling")
	geometry.free()
	var scene := Node3D.new()
	add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 3, 6)
	camera.look_at(Vector3(0, 0.4, 0))
	camera.current = true
	var projectiles: Array = []
	for i in range(2):
		var projectile := Projectile.new()
		projectile.visual_kind = "foie" if i == 0 else "ice"
		projectile.speed = 0.0
		projectile.direction = Vector3.FORWARD
		scene.add_child(projectile)
		projectile.position = Vector3(-1.5 + i, 0.5, 0)
		projectiles.append(projectile)
		_check(projectile.get_child_count() == 3 and not projectile._mesh.visible, "distinct travelling visual replaces sphere")
		_check(is_equal_approx(projectile.get_child(2).shape.radius, Projectile.COLLISION_RADIUS), "visual preserves collision radius")
	var line := Projectile.new()
	line.visual_kind = "ice_line"
	line.speed = 10.0
	line.max_range = 4.0
	line.direction = Vector3.RIGHT
	scene.add_child(line)
	line.position = Vector3(-2, 0.3, -1)
	var pulse := Visual.burst(scene, Vector3(1.2, 0, 0), "heal", 0.7)
	await get_tree().create_timer(0.2).timeout
	_check(get_tree().get_nodes_in_group("technique_visuals").filter(func(n): return n.kind == "ice_growth").size() >= 3, "Barta leaves a continuous world-space ice line")
	await _snapshot("technique-vfx-fire-and-ice")
	await get_tree().create_timer(1.0).timeout
	_check(not is_instance_valid(pulse), "heal pulse expires")
	for projectile in projectiles: projectile.queue_free()
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("technique_visuals").is_empty(), "projectile removal cleans travelling effects")
	var started := Time.get_ticks_usec()
	for i in range(100):
		Visual.burst(scene, Vector3.ZERO, "ice_contact", 0.1)
	await get_tree().create_timer(0.2).timeout
	_check(get_tree().get_nodes_in_group("technique_visuals").is_empty(), "100 overlapping bursts leave no visual nodes")
	print("[technique-vfx] 100-burst elapsed_ms=", (Time.get_ticks_usec() - started) / 1000.0)
	Visual.burst(scene, Vector3.ZERO, "fire_area", 2.0)
	scene.queue_free()
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("technique_visuals").is_empty(), "scene removal cleans unfinished effects")
	print("[technique-vfx] DONE ", "ok" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)

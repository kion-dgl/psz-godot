extends "res://scripts/tools/probe_checks.gd"
## Runtime/render layer for #777–779. Use XDG_DATA_HOME pointing to a disposable directory.
## PSZ_FEEDBACK_CAPTURE_DIR optionally saves frames; PSZ_PROBE_PACK mounts a built pack.
var camera: Camera3D

func _run() -> void:
	seed(777)
	probe_label = "ambience-feedback"
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "FeedbackProbe")
	CharacterManager.set_active_slot(0)
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.16, 0.22)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	add_child(environment)
	await _city()
	await _combat()
	print("[ambience-feedback] DONE %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _city() -> void:
	var market := preload("res://assets/stages/city_e/market/dairon2.glb").instantiate()
	add_child(market)
	camera.position = Vector3(0, 14, 49)
	camera.look_at(Vector3(0, 0, 30))
	await capture("city-before")
	var draws_before := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var before := market.get_child_count()
	var counts := preload("res://scripts/3d/city/market_ambience.gd").apply(market)
	_check(counts.ground > 0 and counts.crowd == 1, "cloud ground and authored crowd surfaces found")
	_check(market.get_child_count() == before, "ambience adds no nodes or collision")
	camera.position = Vector3(0, 14, 49)
	camera.look_at(Vector3(0, 0, 30))
	await capture("city-a")
	var draws_after := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("[ambience-feedback] city draw calls: %d -> %d; surfaces: %s" % [draws_before, draws_after, counts])
	_check(draws_after <= draws_before + int(counts.ground), "clouds add at most one draw per ground surface")
	await get_tree().create_timer(6.0).timeout
	await capture("city-b")
	camera.position = Vector3(16, 5, 30)
	camera.look_at(Vector3(14, 1, 22))
	await capture("crowd")
	await get_tree().create_timer(0.2).timeout
	await capture("crowd-b")
	market.free()

func _combat() -> void:
	camera.position = Vector3(9, 8, 12)
	camera.look_at(Vector3(0, 1, 0))
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	await _burn()
	await _traps()
	await _destruction()

func _burn() -> void:
	camera.position = Vector3(3, 2.5, 4.5)
	camera.look_at(Vector3.UP)
	var player := preload("res://scenes/3d/player/player.tscn").instantiate()
	add_child(player)
	player.set_physics_process(false)
	camera.make_current()
	GameState.set_hp(GameState.max_hp)
	player.apply_status_effect("burn")
	_check(is_instance_valid(player._ailments._burn_effect), "player burn creates flames")
	await get_tree().create_timer(0.2).timeout
	await capture("burn")
	player.clear_status_effects()
	_check(player._ailments._burn_effect == null, "cure removes burn")
	player.apply_status_effect("burn")
	player._ailments.tick(player, 3.1)
	_check(player._ailments._burn_effect == null, "expiry removes burn")
	player.apply_status_effect("burn")
	player._is_defeated = true
	player._ailments.tick(player, 0.01)
	_check(player._ailments._burn_effect == null, "defeat removes burn")
	player.free()

func _traps() -> void:
	camera.position = Vector3(9, 8, 12)
	camera.look_at(Vector3.UP)
	for id in ["heat_trap", "ice_trap", "light_trap", "heal_trap"]:
		var trap := TrapBall.build(id)
		add_child(trap)
		trap._detonate()
		var blast := get_node_or_null("HazardBlast")
		_check(blast != null and is_equal_approx(blast.get_child(0).mesh.radius, trap.blast_radius), id + " shows actual blast radius")
		await capture(id)
		await get_tree().create_timer(0.5).timeout
		_check(not is_instance_valid(blast), "blast outlives trap then cleans up")
	var bomb := PlacedTraps.build("burn_trap") as BombTrap
	add_child(bomb)
	bomb.take_damage(1)
	bomb._update_animation(bomb.WARNING + 0.01)
	var bomb_blast := get_node_or_null("HazardBlast")
	_check(bomb.detonations == 1 and bomb_blast != null, "bomb retains warning and emits once")
	_check(bomb_blast != null and is_equal_approx(bomb_blast.get_child(0).mesh.radius, bomb.RADIUS), "bomb visual matches damage radius")
	await capture("bomb")
	await get_tree().create_timer(0.5).timeout
	bomb.free()
	var unused := TrapBall.build("heat_trap")
	add_child(unused)
	unused._expire()
	_check(get_node_or_null("HazardBlast") == null, "unused trap expiry has no blast")

func _destruction() -> void:
	var restored := Box.new()
	add_child(restored)
	restored.set_state("destroyed")
	_check(get_node_or_null("DestructionBurst") == null, "restoring destroyed state does not replay break effect")
	restored.free()
	var box := Box.new()
	box.position = Vector3(-2, 0, 0)
	box.drop_type = "meseta"
	box.drop_value = "10"
	add_child(box)
	var wall := Wall.new()
	wall.position = Vector3(3, 0, -1)
	wall.rotation.y = 0.5
	add_child(wall)
	box.destroy()
	wall.take_damage()
	wall.take_damage()
	_check(wall.element_state == "intact", "wall retains three-hit rule")
	wall.take_damage()
	var count := get_child_count()
	box.destroy()
	wall.destroy()
	_check(get_child_count() == count, "repeated destruction adds no burst")
	await get_tree().process_frame
	_check(box.collision_body.collision_layer == 0 and wall.collision_body.collision_layer == 0, "destroyed collision removed")
	_check(not box.hurtbox.monitorable and not wall.hurtbox.monitorable, "destroyed hurtboxes disabled")
	await capture("destruction")
	var drops := 0
	for child in get_children():
		if child is DropMeseta: drops += 1
	_check(drops == 1, "box drops loot exactly once")
	await get_tree().create_timer(0.8).timeout
	for child in get_children():
		_check(not child is ShrapnelBurst, "destruction burst cleaned up")
	box.free()
	wall.free()

func capture(label: String) -> void:
	await get_tree().process_frame
	var directory := OS.get_environment("PSZ_FEEDBACK_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png"))

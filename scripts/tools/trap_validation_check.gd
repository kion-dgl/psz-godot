extends RefCounted
## Live actor/physics counterpart to test_trap_validation.gd.
const Recovery := preload("res://scripts/tools/gameplay_recovery_check.gd")
static func run(player: Node3D, enemy: EnemyBase) -> bool:
	var ok := await Recovery.run(player, enemy)
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	enemy.global_position += Vector3(0, 0, 100)
	ok = await _player_items(player, enemy) and ok
	ok = await _vision_expiry(player) and ok
	for difficulty in 3:
		ok = await _escape(player, difficulty) and ok
	ok = await _radii(player) and ok
	ok = await _ball_materials(player) and ok
	await _render_balls(player)
	ok = await preload("res://scripts/tools/trap_layout_check.gd").run(player.get_tree()) and ok
	return ok

static func _settle(player: Node3D) -> void:
	await player.get_tree().physics_frame
	await player.get_tree().physics_frame

static func _escape(player: Node3D, difficulty: int) -> bool:
	player.clear_status_effects()
	player._recovery_left = 0.0
	player.transition_to(player.PlayerState.IDLE)
	GameState.set_hp(GameState.max_hp)
	var origin := player.global_position
	var trap := TrapBall.build_field("heat_trap", difficulty)
	player.get_parent().add_child(trap)
	trap.global_position = origin
	var fired := [0]
	trap.triggered.connect(func(_id): fired[0] += 1)
	await _settle(player)
	await player.get_tree().process_frame
	for frame in 12:
		if trap._armed: break
		await player.get_tree().physics_frame
	var ok := Recovery._check(trap._armed and trap._model.visible, "difficulty %d proximity reveals and arms" % difficulty)
	var elapsed := 0.0
	# Move through real CharacterBody collision at normal movement speed.
	while is_instance_valid(trap) and elapsed < 5.0:
		await player.get_tree().physics_frame
		var delta := 1.0 / float(Engine.physics_ticks_per_second)
		player.velocity = Vector3.RIGHT * player.MOVE_SPEED
		player.move_and_slide()
		elapsed += delta
	ok = Recovery._check(fired[0] == 1 and GameState.hp == GameState.max_hp, "difficulty %d movement escapes once-only blast" % difficulty) and ok
	ok = Recovery._check(elapsed >= TrapBall.FIELD_RISE_SECONDS + float([46,31,16][difficulty])/30.0 - 0.1, "difficulty %d retains rise plus full fuse" % difficulty) and ok
	if is_instance_valid(trap): trap.queue_free()
	player.global_position = origin
	player.velocity = Vector3.ZERO
	return ok

static func _radii(player: Node3D) -> bool:
	var origin := player.global_position
	var ok := true
	for distance in [1.95, 2.05]:
		var trap := TrapBall.build_field("heat_trap")
		trap.trigger_radius = 2.0
		trap.blast_radius = 3.0
		player.get_parent().add_child(trap)
		trap.set_process(false)
		trap.global_position = origin + Vector3(distance, 0, 0)
		await _settle(player)
		ok = Recovery._check(trap._check_targets() == (distance < 2.0), "trigger uses actor origin at %.2fm, not capsule edge" % distance) and ok
		trap.queue_free()
		await player.get_tree().process_frame
	for distance in [2.95, 3.05]:
		GameState.set_hp(GameState.max_hp)
		player.clear_status_effects()
		player.transition_to(player.PlayerState.IDLE)
		player._recovery_left = 0.0
		var trap := TrapBall.build_field("heat_trap")
		trap.blast_radius = 3.0
		player.get_parent().add_child(trap)
		trap.set_process(false)
		trap.global_position = origin + Vector3(distance, 0, 0)
		await _settle(player)
		trap._detonate()
		ok = Recovery._check((GameState.hp < GameState.max_hp) == (distance < 3.0), "blast uses independent actor-origin boundary %.2fm" % distance) and ok
		await player.get_tree().process_frame
	return ok

static func _render_balls(player: Node3D) -> void:
	var destination := OS.get_environment("PSZ_GAMEPLAY_CAPTURE_DIR")
	if destination.is_empty() or DisplayServer.get_name() == "headless": return
	var camera := Camera3D.new()
	player.get_parent().add_child(camera)
	camera.global_position = Vector3(0, 5, 9)
	camera.look_at(Vector3(0, 1, 0))
	camera.make_current()
	var traps: Array[TrapBall] = []
	var ids := ["heal_trap", "heat_trap", "light_trap", "ice_trap"]
	for i in ids.size():
		var trap := TrapBall.build_field(ids[i])
		player.get_parent().add_child(trap)
		trap.set_process(false)
		trap.position = Vector3((i - 1.5) * 3, 0, 0)
		traps.append(trap)
	player.global_position = Vector3(0, 0, 12)
	TrapBall.grant_vision()
	for phase in ["revealed", "armed"]:
		for trap in traps:
			if phase == "armed":
				trap._arm()
				trap._rise = 1.0
				trap._armed_motion()
			trap._apply_visibility()
		await RenderingServer.frame_post_draw
		player.get_viewport().get_texture().get_image().save_png(destination.path_join("balls-" + phase + ".png"))
	for i in traps.size():
		camera.global_position = traps[i].global_position + Vector3(1.4, 3.8, 2.5)
		camera.look_at(traps[i].global_position + Vector3.UP * 2.8)
		await RenderingServer.frame_post_draw
		player.get_viewport().get_texture().get_image().save_png(destination.path_join(ids[i] + "-close.png"))
	# Leave the post-draw callback before releasing render resources.
	await player.get_tree().process_frame
	for trap in traps: trap.queue_free()
	camera.queue_free()
	await player.get_tree().process_frame

static func _ball_materials(player: Node3D) -> bool:
	var ok := true
	for id in TrapBall.TRAP_MODELS:
		var trap := TrapBall.build(id)
		player.get_parent().add_child(trap)
		trap.set_process(false)
		var count := 0
		for node in trap._model.find_children("*", "MeshInstance3D", true, false):
			for index in node.mesh.get_surface_count():
				var material: ShaderMaterial = node.get_surface_override_material(index)
				var valid := material != null and material.shader == TrapBall.MIRROR_SHADER
				if valid:
					valid = material.get_shader_parameter("uv_scale") == Vector2(2, 2) and material.get_shader_parameter("uv_offset") == Vector2(0, -1)
				ok = Recovery._check(valid, id + " restores original GPU texture transform") and ok
				count += 1
		ok = Recovery._check(count > 0, id + " has real imported surfaces") and ok
		# Let the renderer register each override before freeing its owner.
		await player.get_tree().process_frame
		await player.get_tree().process_frame
		trap.queue_free()
		await player.get_tree().process_frame
	return ok

static func _player_items(player: Node3D, enemy: EnemyBase) -> bool:
	var character: Dictionary = CharacterManager.get_active_character()
	var saved_class: String = character.class_id
	var saved_items := Inventory._items.duplicate()
	character.class_id = "hucast"
	var ok := true
	for id in TrapBall.TRAP_MODELS:
		enemy.global_position = player.global_position + Vector3(0, 0, 100)
		enemy._status_effects.clear()
		Inventory._items[id] = 1
		GameState.set_hp(1)
		ok = Recovery._check(Inventory.use_item(id) and Inventory.get_item_count(id) == 0, id + " placement consumes exactly one") and ok
		var trap: TrapBall
		for node in player.get_tree().get_nodes_in_group("player_traps"):
			if not node.field_placed and node.trap_id == id: trap = node
		if trap == null:
			ok = false
			continue
		var fired := [0]
		trap.triggered.connect(func(_id): fired[0] += 1)
		await player.get_tree().create_timer(1.1).timeout
		ok = Recovery._check(trap._armed, id + " arms on the live timer") and ok
		if id != "heal_trap":
			ok = Recovery._check(not trap._triggered, id + " waits without an eligible target") and ok
			enemy.global_position = player.global_position + Vector3(2, 0, 0)
		await _settle(player)
		await player.get_tree().create_timer(trap.fuse_seconds() + 0.2).timeout
		ok = Recovery._check(fired[0] == 1 and not is_instance_valid(trap), id + " detonates once and cleans up") and ok
		if id == "heal_trap":
			ok = Recovery._check(GameState.hp == 1 + int(GameState.max_hp * 0.5), "live Heal restores half maximum HP") and ok
		else:
			var status: String = TrapBall.TRAP_EFFECTS[id].status
			ok = Recovery._check(enemy._status_effects.any(func(fx): return fx.type == status), id + " delivers current " + status + " payload") and ok
		if is_instance_valid(trap): trap.queue_free()
	character.class_id = saved_class
	Inventory._items = saved_items
	enemy.global_position = player.global_position + Vector3(0, 0, 100)
	GameState.set_hp(GameState.max_hp)
	return ok

static func _vision_expiry(player: Node3D) -> bool:
	var trap := TrapBall.build_field("heat_trap")
	player.get_parent().add_child(trap)
	trap.global_position = player.global_position + Vector3(0, 0, 20)
	TrapBall.vision_until_msec = 0
	TrapBall.grant_vision(1.0)
	# process_frame fires before node processing; wait through a complete pass.
	await player.get_tree().process_frame
	await player.get_tree().process_frame
	await player.get_tree().physics_frame
	var ok := Recovery._check(trap._model.visible and trap.can_be_targeted(), "short live vision reveals dormant trap (visible=%s target=%s remaining_ms=%d)" % [trap._model.visible, trap.can_be_targeted(), TrapBall.vision_until_msec - Time.get_ticks_msec()])
	await player.get_tree().create_timer(1.2).timeout
	ok = Recovery._check(not trap._model.visible and not trap.hurtbox.monitorable and not trap.can_be_targeted(), "real timer expiry hides dormant model and targeting") and ok
	trap._arm()
	await player.get_tree().process_frame
	await player.get_tree().physics_frame
	ok = Recovery._check(trap._model.visible and trap.hurtbox.monitorable and trap.can_be_targeted(), "arming reveals trap after vision expires") and ok
	trap.queue_free()
	return ok

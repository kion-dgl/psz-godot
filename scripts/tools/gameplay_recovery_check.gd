extends RefCounted
## Real rig/physics layer for /states/gameplay-recovery-traps.
## PSZ_GAMEPLAY_RECOVERY_CHECK=1 godot --headless --path . res://scripts/tools/coliseum_probe.tscn

static func run(player: Node3D, enemy: EnemyBase) -> bool:
	var inventory: Dictionary = Inventory._items.duplicate()
	var character: Dictionary = CharacterManager.get_active_character()
	var saved_character := character.duplicate(true)
	var hp := GameState.hp
	var pp := GameState.mp
	var position := player.global_position
	var yaw: float = player.player_rotation
	var enemy_position := enemy.global_position
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	enemy.global_position += Vector3(0, 0, 50)
	var ok := await _counterplay(player)
	ok = await _blast_boundaries(player) and ok
	ok = await _materials(player) and ok
	ok = await _placement(player, character) and ok
	ok = await _recovery_and_support(player, character) and ok
	player.clear_status_effects()
	player._recovery_left = 0.0
	player.transition_to(player.PlayerState.IDLE)
	player.global_position = position
	player.player_rotation = yaw
	enemy.global_position = enemy_position
	Inventory._items = inventory
	character.clear()
	character.merge(saved_character)
	GameState.set_hp(hp)
	GameState.set_mp(pp)
	TrapBall.vision_until_msec = 0
	player.set_physics_process(true)
	enemy.set_physics_process(true)
	return ok

static func _check(condition: bool, message: String) -> bool:
	print("[gameplay] %s — %s" % [message, "PASS" if condition else "FAIL"])
	return condition

static func _counterplay(player: Node3D) -> bool:
	TrapBall.vision_until_msec = 0
	var trap := TrapBall.build_field("ice_trap")
	trap.trigger_radius = 0.1
	trap.blast_radius = 2.0
	player.get_parent().add_child(trap)
	trap.global_position = player.global_position + Vector3(0, 0, -6)
	await player.get_tree().physics_frame
	await player.get_tree().physics_frame
	var config := CombatManager.get_weapon_type_config(9)
	player.player_rotation = PI
	var ok := _check(not trap._model.visible and not trap.hurtbox.monitorable and not player._enemies_in_hit_cone(config).has(trap), "hidden human trap excluded from render/hurtbox/targeting")
	TrapBall.grant_vision()
	await player.get_tree().process_frame
	await player.get_tree().physics_frame
	ok = _check(trap._model.visible and trap.hurtbox.monitorable and player._enemies_in_hit_cone(config).has(trap), "Trap Vision reveals and targets real trap") and ok
	var counts: Array[int] = []
	trap.hurtbox.hit_received.connect(func(d: int, _k: Vector3, _a: int): counts.append(d))
	player._fire_projectile({"weapon_type": 9, "hits": 1, "damage": 10, "accuracy": 100, "knockback": 0.0, "max_targets": 1})
	await player.get_tree().create_timer(0.8).timeout
	ok = _check(counts.size() == 1 and not is_instance_valid(trap), "real handgun projectile disarms without detonation") and ok
	if is_instance_valid(trap): trap.queue_free()
	TrapBall.vision_until_msec = 0
	return ok

static func _materials(player: Node3D) -> bool:
	var bear := BearTrap.new()
	var needle := NeedleTrap.new()
	player.get_parent().add_child(bear)
	player.get_parent().add_child(needle)
	bear.global_position = player.global_position + Vector3(3, 0, 0)
	needle.global_position = player.global_position + Vector3(-3, 0, 0)
	var ok := _check(not bear._prong_materials.is_empty() and not needle._spike_materials.is_empty(), "real floor-trap surfaces use mirrored shaders")
	if not bear._prong_materials.is_empty():
		var mat: ShaderMaterial = bear._prong_materials[0]
		var offset: Vector2 = mat.get_shader_parameter("uv_offset")
		bear._update_animation(0.5)
		ok = _check(is_equal_approx(mat.get_shader_parameter("uv_offset").y, offset.y - 0.25) and not mat.get_shader_parameter("mirror_y"), "armed bear scrolls with repeat V") and ok
		bear.set_state("off")
		ok = _check(mat.get_shader_parameter("visibility_alpha") == 0.0, "bear off hides prongs") and ok
	if not needle._spike_materials.is_empty():
		var mat: ShaderMaterial = needle._spike_materials[0]
		ok = _check(mat.get_shader_parameter("uv_scale") == Vector2(2, 1) and mat.get_shader_parameter("uv_offset") == Vector2(-0.17, -0.18), "needle uses storybook UV profile") and ok
		needle.set_state("on")
		ok = _check(mat.get_shader_parameter("visibility_alpha") == 1.0, "needle on reveals spikes") and ok
	bear.set_state("on")
	player.transition_to(player.PlayerState.IDLE)
	bear._on_body_stepped(player)
	ok = _check(player.current_state == player.PlayerState.CUTSCENE, "bear catches live player") and ok
	bear._release()
	ok = _check(player.current_state == player.PlayerState.DAMAGED, "bear release preserves damage reaction") and ok
	bear.set_state("on")
	player.transition_to(player.PlayerState.IDLE)
	bear._on_body_stepped(player)
	bear._exit_tree()
	ok = _check(player.current_state == player.PlayerState.IDLE, "room teardown releases surviving bear hold") and ok
	await _capture_materials(player, bear, needle)
	bear.queue_free()
	needle.queue_free()
	return ok

static func _placement(player: Node3D, character: Dictionary) -> bool:
	Inventory._items = {"heat_trap": 3, "ice_trap": 3, "trap_vision": 3}
	character.class_id = "humar"
	var ok := _check(not Inventory.use_item("heat_trap") and Inventory.get_item_count("heat_trap") == 3, "human placement rejects without consuming")
	var field_trap := TrapBall.build_field("heat_trap")
	field_trap.disarmed = true
	player.get_parent().add_child(field_trap)
	field_trap.global_position = player.global_position + Vector3(0, 0, 20)
	character.class_id = "hucast"
	field_trap._apply_visibility()
	ok = _check(field_trap._model.visible, "CAST sees dormant field trap without vision") and ok
	ok = _check(Inventory.use_item("heat_trap"), "CAST can place trap") and ok
	var first: TrapBall
	for node in player.get_tree().get_nodes_in_group("player_traps"):
		if not node.field_placed: first = node
	ok = _check(Inventory.use_item("ice_trap") and is_instance_valid(first) and first._spent, "replacement expires previous player trap") and ok
	await player.get_tree().process_frame
	var active := 0
	for node in player.get_tree().get_nodes_in_group("player_traps"):
		if not node.field_placed:
			active += 1
			node.queue_free()
	ok = _check(is_instance_valid(field_trap) and not field_trap._spent, "replacement preserves authored field traps") and ok
	field_trap.queue_free()
	ok = _vision_use() and ok
	ok = _check(active == 1, "only one player trap survives replacement") and ok
	character.class_id = "humar"
	return ok

static func _vision_use() -> bool:
	var ok := true
	GameState.set_hp(0)
	ok = _check(not Inventory.use_item("trap_vision") and Inventory.get_item_count("trap_vision") == 3, "dead vision use preserves item") and ok
	GameState.set_hp(GameState.max_hp)
	var location: String = SessionManager._location
	SessionManager._location = "city"
	ok = _check(not Inventory.use_item("trap_vision") and not Inventory.use_item("heat_trap"), "city rejects vision and placement") and ok
	SessionManager._location = location
	ok = _check(Inventory.use_item("trap_vision") and TrapBall.vision_active(), "living field vision consumes and grants reveal") and ok
	var expiry := TrapBall.vision_until_msec
	TrapBall.grant_vision(0.1)
	ok = _check(TrapBall.vision_until_msec == expiry, "shorter vision grant cannot shorten expiry") and ok
	TrapBall.vision_until_msec = 0
	return ok

static func _recovery_and_support(player: Node3D, character: Dictionary) -> bool:
	Inventory._items = {"scape_doll": 2}
	GameState.set_hp(GameState.max_hp)
	var deaths: Array[int] = []
	var capture := func(): deaths.append(1)
	player.died.connect(capture)
	player.apply_status_effect("burn")
	player.take_damage(99999)
	var ok := _check(GameState.hp == GameState.max_hp and Inventory.get_item_count("scape_doll") == 1 and deaths.is_empty() and player._ailments.effects.is_empty(), "lethal hit consumes one doll, clears burn, suppresses defeat")
	var trap := TrapBall.build_field("ice_trap")
	trap._hit_player(player, "freeze", 0.0)
	ok = _check(GameState.hp == GameState.max_hp and player._freeze.remaining == 0.0, "recovery rejects both trap damage and freeze") and ok
	trap.free()
	player.set_physics_process(true)
	await player.get_tree().create_timer(2.2).timeout
	player.set_physics_process(false)
	ok = _check(player._recovery_left == 0.0 and player.current_state != player.PlayerState.DAMAGED, "real stand-up recovers to playable state") and ok
	character["techniques"] = {"resta": 1, "anti": 1}
	GameState.set_hp(1)
	GameState.set_mp(GameState.max_mp)
	player.transition_to(player.PlayerState.IDLE)
	var pp_before := GameState.mp
	character.class_id = "hucast"
	player._cast_technique("resta")
	ok = _check(GameState.hp == 1 and GameState.mp == pp_before, "CAST stale technique binding does not heal or spend PP") and ok
	character.class_id = "humar"
	player._cast_technique("resta")
	ok = _check(GameState.hp > 1 and GameState.mp < pp_before, "live Resta cast heals and spends PP") and ok
	player.transition_to(player.PlayerState.IDLE)
	player.apply_status_effect("burn")
	GameState.set_mp(GameState.max_mp)
	player._cast_technique("anti")
	ok = _check(player._ailments.effects.is_empty(), "live Anti cast cures burn") and ok
	ok = _cure_items(player) and ok
	player.died.disconnect(capture)
	return ok


static func _cure_items(player: Node3D) -> bool:
	var ok := true
	player.transition_to(player.PlayerState.IDLE)
	Inventory._items = {"sol_atomizer": 2, "moon_atomizer": 2}
	GameState.set_hp(GameState.max_hp - 10)
	player.apply_status_effect("burn")
	ok = _check(Inventory.use_item("sol_atomizer") and player._ailments.effects.is_empty() and GameState.hp == GameState.max_hp - 10, "Sol cures actual player without healing") and ok
	ok = _check(not Inventory.use_item("sol_atomizer") and Inventory.get_item_count("sol_atomizer") == 1, "healthy Sol use preserves item") and ok
	ok = _check(not Inventory.use_item("moon_atomizer") and GameState.hp == GameState.max_hp - 10 and Inventory.get_item_count("moon_atomizer") == 2, "Moon without downed teammate cannot self-heal or consume") and ok
	return ok


static func _capture_materials(player: Node3D, bear: BearTrap, needle: NeedleTrap) -> void:
	var destination := OS.get_environment("PSZ_GAMEPLAY_CAPTURE_DIR")
	if destination.is_empty(): return
	DirAccess.make_dir_recursive_absolute(destination)
	var previous := player.get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	player.get_parent().add_child(camera)
	bear.global_position = Vector3(2, 0, 0)
	needle.global_position = Vector3(-2, 0, 0)
	camera.global_position = Vector3(4, 8, 7)
	camera.look_at(Vector3(0, 0.3, 0))
	camera.make_current()
	bear.set_state("on")
	needle.set_state("on")
	await RenderingServer.frame_post_draw
	player.get_viewport().get_texture().get_image().save_png(destination.path_join("traps-on.png"))
	bear.set_state("off")
	needle.set_state("off")
	await RenderingServer.frame_post_draw
	player.get_viewport().get_texture().get_image().save_png(destination.path_join("traps-off.png"))
	previous.make_current()
	camera.queue_free()


static func _blast_boundaries(player: Node3D) -> bool:
	var ok := true
	for distance in [1.0, 6.0]:
		var trap := TrapBall.build_field("heat_trap")
		trap.trigger_radius = 0.1
		trap.blast_radius = 2.0
		player.get_parent().add_child(trap)
		trap.global_position = player.global_position + Vector3(distance, 0, 0)
		await player.get_tree().physics_frame
		await player.get_tree().physics_frame
		ok = _check(not trap._should_arm(), "outside separate trigger radius %.1fm" % distance) and ok
		GameState.set_hp(GameState.max_hp)
		player.transition_to(player.PlayerState.IDLE)
		player.clear_status_effects()
		trap._arm()
		trap._fuse_left = 0.123
		trap._trigger()
		ok = _check(is_equal_approx(trap._fuse_left, 0.123), "repeat trigger cannot restart fuse") and ok
		trap._detonate()
		var hp_after := GameState.hp
		trap._detonate()
		var expected := TrapBall.FIELD_TRAP_DAMAGE if distance == 1.0 else 0
		ok = _check(GameState.hp == GameState.max_hp - expected and GameState.hp == hp_after, "blast range and exactly-once payload %.1fm" % distance) and ok
		player.clear_status_effects()
		await player.get_tree().process_frame
	return ok

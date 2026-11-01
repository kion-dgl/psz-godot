extends Node3D
## Run with an isolated user directory/project name; never on the live save.
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("[playtest] %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failures += 1

func _run() -> void:
	if OS.get_environment("PSZ_PROBE_ENTRY_ONLY") == "1":
		get_tree().change_scene_to_file("res://scenes/tools/valley_entry_debug.tscn")
		return
	var pack := OS.get_environment("PSZ_PROBE_PACK")
	if not pack.is_empty():
		check(ProjectSettings.load_resource_pack(pack), "built asset pack mounts")
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "FeedbackProbe")
	CharacterManager.set_active_slot(0)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 4, 9)
	camera.look_at(Vector3(0, 1, 0))
	camera.current = true
	if OS.get_environment("PSZ_PROBE_UI_ONLY") == "1":
		await _shops()
		await _guild()
		print("[playtest] UI DONE (%d failures)" % failures)
		get_tree().quit(0 if failures == 0 else 1)
		return
	await _feedback()
	await _shops()
	await _underground()
	await _entries()
	print("[playtest] DONE %s (%d failures)" % ["ok" if failures == 0 else "failed", failures])
	await get_tree().create_timer(1.3).timeout
	get_tree().quit(0 if failures == 0 else 1)

func _feedback() -> void:
	var cube := HealPad.new()
	add_child(cube)
	var body := CharacterBody3D.new()
	body.add_to_group("player")
	add_child(body)
	GameState.set_hp(GameState.max_hp)
	var before := SfxManager._next_idx
	cube._on_body_entered(body)
	check(cube.element_state == "unused" and SfxManager._next_idx == before, "full HP leaves cube charged and silent")
	GameState.set_hp(GameState.max_hp - 1)
	cube._on_body_entered(body)
	check(GameState.hp == GameState.max_hp and SfxManager._next_idx == (before + 1) % SfxManager.POOL_SIZE, "cube heals and sounds once")
	cube._on_body_entered(body)
	check(SfxManager._next_idx == (before + 1) % SfxManager.POOL_SIZE, "spent cube does not replay sound")
	cube._update_animation(1.0)
	check(cube._mat.get_shader_parameter("albedo_tint").r < 0.3, "spent cube dark grey")
	cube.free()
	body.free()
	var waypoint := Waypoint.new()
	add_child(waypoint)
	for mesh in MeshUtils.collect_mesh_instances(waypoint, []):
		check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "waypoint mesh shadow disabled")
	waypoint.free()
	var gun := GunTrap.new()
	add_child(gun)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var shape := SphereShape3D.new()
	shape.radius = 0.1
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = gun.global_position + Vector3(1.3, 1, 0)
	query.collision_mask = gun.hurtbox.collision_layer
	query.collide_with_areas = true
	query.collide_with_bodies = false
	check(not get_world_3d().direct_space_state.intersect_shape(query).is_empty(), "melee contact at turret outer edge reaches hurtbox")
	print("[playtest] turret visual bounds: ", MeshUtils.global_mesh_aabb(gun.model))
	gun.free()
	var enemy := EnemyBase.new()
	enemy.enemy_data = EnemyRegistry.get_enemy("vulkure")
	add_child(enemy)
	enemy.set_physics_process(false)
	check(enemy._reticle.get_parent() is BoneAttachment3D or enemy._reticle.get_parent().name == "Point_Spine", "Vulkure reticle follows animated spine")
	var miss := preload("res://scripts/3d/elements/combat_popup.gd").show(self, Vector3.UP * 2, "MISS", Color.RED, true)
	check(miss.font_size < 48 and miss.modulate == Color.RED, "miss is smaller and red")
	var voice := SfxManager._next_3d_idx
	enemy._die()
	check(SfxManager._next_3d_idx == (voice + 1) % SfxManager.POOL_SIZE, "defeat starts voice immediately")
	enemy._die()
	check(SfxManager._next_3d_idx == (voice + 1) % SfxManager.POOL_SIZE, "defeat voice does not repeat")
	check(ResourceLoader.exists(EnemySoundPlayback.defeat_sound("pso_booma")), "imported Booma has defeat cue")
	await get_tree().create_timer(0.2).timeout
	enemy.queue_free()
	await get_tree().process_frame

func _shops() -> void:
	for id in ["item_shop", "weapon_shop", "crafting_shop", "tekker", "photon_shop", "storage"]:
		var path := "res://scenes/2d/storage.tscn" if id == "storage" else "res://scenes/2d/shops/%s.tscn" % id
		var shop := (load(path) as PackedScene).instantiate()
		add_child(shop)
		await get_tree().process_frame
		await get_tree().process_frame
		var balance := shop.find_child("ShopBalance", true, false) as Label
		var card := shop.find_child("ShopBodyCard", true, false) as Control
		var title := shop.find_child("TitleLabel", true, false) as Control
		check(balance != null and balance.visible, id + " balance visible")
		check(balance.global_position.y > card.global_position.y + card.size.y * 0.8, id + " balance at bottom")
		check(absf(title.size.x - (card.size.x - 6.0)) < 1, id + " title fills card width")
		check(not shop.find_child("HintLabel", true, false).visible, id + " directions footer hidden")
		if id == "photon_shop":
			check(balance.text == "Photon Drops: %d" % Inventory.get_item_count("photon_drop"), "collector uses photon balance")
		PszStyle.update_shop_balance(shop, 1234)
		check(balance.text == "Meseta: 1234", id + " balance refreshes")
		if id == "item_shop" and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("/tmp/psz-playtest-shop.png")
		shop.queue_free()
		await get_tree().process_frame

func _underground() -> void:
	var helper := preload("res://scripts/utils/underground_mirror_variants.gd")
	for path in helper.PATHS:
		var scene := (load(path) as PackedScene).instantiate() as Node3D
		add_child(scene)
		check(helper.apply(scene), "native mirror variant " + path.get_file())
		for mesh in MeshUtils.collect_mesh_instances(scene, []):
			for surface in mesh.mesh.get_surface_count():
				var material = mesh.get_active_material(surface)
				check(material is StandardMaterial3D, "underground surface uses native material")
		scene.free()
	var city := (load("res://scenes/3d/city/city_underground.tscn") as PackedScene).instantiate()
	add_child(city)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/psz-playtest-underground.png")
	city.queue_free()
	await get_tree().process_frame

func _entries() -> void:
	var generator := preload("res://scripts/3d/field/grid_generator.gd").new()
	generator.set_seed(1101)
	var field: Dictionary = generator.generate_field("normal", "gurhacia")
	var sections: Array = field.sections
	for entry in [[1, ""], [2, ""], [1, "north"], [2, "north"]]:
		var index: int = entry[0]
		var expected: String = "south" if str(entry[1]).is_empty() else str(entry[1])
		SessionManager.enter_field("gurhacia", "normal")
		SessionManager.set_field_sections(sections)
		SessionManager.set_current_section(index)
		SceneManager._transition_data = {"current_cell_pos": sections[index].start_pos, "spawn_edge": entry[1]}
		var room := (load("res://scenes/3d/field/valley_field.tscn") as PackedScene).instantiate()
		add_child(room)
		for frame in range(120):
			await get_tree().process_frame
			if room.player != null and room._gate_mgr != null:
				break
		check(room.player != null, "field player initialized")
		if room.player == null:
			room.queue_free()
			return
		room.player.set_physics_process(false)
		await get_tree().physics_frame
		await get_tree().process_frame
		check(room._spawn_edge == expected, "section %d enters %s" % [index, expected])
		var spawn: Vector3 = room._portal_data[expected].spawn_pos
		check(Vector2(room.player.global_position.x, room.player.global_position.z).distance_to(Vector2(spawn.x, spawn.z)) < 0.5, "section %d player at %s spawn" % [index, expected])
		if index == 2:
			check(room._portal_data.south.id == "portal_1769178737883_7bppcx8w1", "Valley B arrives through Valley E themed gate")
		else:
			check(room._portal_data.north.gate_pos.z < room._portal_data.south.gate_pos.z, "transition room orientation preserved")
		var before := SfxManager._next_idx
		room._deferred_key_pickup = {"key_for": "probe", "count": 1}
		room._drop_deferred_room_key()
		check(SfxManager._next_idx == (before + 1) % SfxManager.POOL_SIZE, "new key drop sounds")
		room._drop_deferred_room_key()
		check(SfxManager._next_idx == (before + 1) % SfxManager.POOL_SIZE, "key drop cannot sound twice")
		room._cell_spawner._spawn_enemy_drops(Vector3.ZERO, "vulkure")
		var popup := room.find_child("CombatPopup", false, false) as Label3D
		check(popup != null and popup.text == "+10 exp" and popup.modulate.b > popup.modulate.g, "actual EXP displayed in purple")
		await get_tree().create_timer(1.5).timeout
		room.queue_free()
		await get_tree().process_frame

func _guild() -> void:
	SessionManager.cancel_accepted_quest()
	GameState.unlocked_difficulties = ["normal"]
	var guild := (load("res://scenes/2d/guild_counter.tscn") as PackedScene).instantiate()
	add_child(guild)
	await get_tree().process_frame
	guild._select_difficulty(1)
	check(guild._difficulty_index == 0, "locked Hard cannot be selected")
	GameState.unlock_difficulty("hard")
	GameState.unlock_difficulty("super-hard")
	guild._select_difficulty(2)
	check(guild._difficulty_index == 2, "Very Hard tab selects third tier")
	guild._entries = [{"type": "quest", "quest_id": "search_and_rescue", "available": true}]
	guild._selected_index = 0
	GameState.unlocked_difficulties = ["normal"]
	guild._accept_entry()
	check(not SessionManager.has_accepted_quest(), "acceptance rechecks difficulty unlock")
	GameState.unlock_difficulty("super-hard")
	guild._accept_entry()
	check(SessionManager.get_accepted_quest().get("difficulty") == "super-hard", "Very Hard passes existing scaling key")
	guild._select_difficulty(0)
	check(guild._difficulty_index == 2, "active quest keeps difficulty")
	SessionManager.cancel_accepted_quest()
	guild.queue_free()
	await get_tree().process_frame

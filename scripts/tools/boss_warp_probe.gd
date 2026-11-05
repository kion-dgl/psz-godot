extends "res://scripts/tools/probe_checks.gd"
## Run in a disposable project/user-data namespace. Optional PSZ_BOSS_SCREENSHOTS.

func _run() -> void:
	probe_label = "boss-warp"
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "WarpProbe")
	CharacterManager.set_active_slot(0)
	var generator := preload("res://scripts/3d/field/grid_generator.gd").new()
	generator.set_seed(782)
	var field: Dictionary = generator.generate_field("normal", "gurhacia")
	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.set_field_sections(field.sections)
	SessionManager.set_current_section(2)
	SceneManager._transition_data = {"current_cell_pos": field.sections[2].end_pos}
	var room := (load("res://scenes/3d/field/valley_field.tscn") as PackedScene).instantiate()
	add_child(room)
	for frame in range(120):
		await get_tree().process_frame
		if room.player != null and room._gate_mgr != null:
			break
	await get_tree().create_timer(1.0).timeout
	var warp := _find_warp(room)
	_check(warp != null, "actual Valley goal room spawns boss warp")
	if warp == null:
		get_tree().quit(1)
		return
	room.player.set_physics_process(false)
	warp.set_process(false)
	warp._scroll_time = 0.0
	warp._update_animation(0.0)
	_check(warp._scroll_mat != null and warp._scroll_mat is StandardMaterial3D, "real GLB animated surface found")
	await _snapshot_states(warp, room)
	warp._update_animation(0.5)
	await _snapshot("boss-warp-scroll")
	_check(abs(warp._scroll_mat.uv1_offset.y - (-7.62 - 1.35 * 0.5) / 2.0) < 0.0001, "real surface scrolls at catalog speed")
	_check_materials(warp)
	room.free()
	print("[boss-warp] DONE %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


func _find_warp(room: Node) -> BossWarp:
	for child in room.get_children():
		if child is BossWarp:
			return child
	return null


func _snapshot_states(warp: BossWarp, room: Node) -> void:
	var camera := Camera3D.new()
	room.add_child(camera)
	camera.global_position = warp.global_position + Vector3(7, 5, 10)
	camera.look_at(warp.global_position + Vector3.UP * 2)
	camera.current = true
	for state in ["locked", "open", "inactive", "active"]:
		warp.set_state(state)
		await _snapshot("boss-warp-" + state)


func _check_materials(warp: BossWarp) -> void:
	var surface_count := [0]
	warp.apply_to_all_materials(func(mat: Material, _mesh: MeshInstance3D, _surface: int):
		if mat is StandardMaterial3D and mat.texture_repeat:
			surface_count[0] += 1
			var std := mat as StandardMaterial3D
			_check(std.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
				and std.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST
				and std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
				"real material retains unlit nearest alpha cutout on a standard repeat material")
	)
	_check(surface_count[0] == 2, "both real GLB surfaces configured")
	var atlas_ok := [false, false]
	var bake_ok := [0, 0]
	warp.apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int):
		if mat is not StandardMaterial3D:
			return
		var tex: Texture2D = (mat as StandardMaterial3D).albedo_texture
		if tex == null:
			return
		var uvs: PackedVector2Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
		if tex.get_width() == 32:
			atlas_ok[0] = tex.get_height() == 64
			for uv in uvs:
				if abs(uv.x - 0.125) < 0.001:
					bake_ok[0] += 1
		elif tex.get_width() == 64:
			atlas_ok[1] = tex.get_height() == 128
			for uv in uvs:
				if abs(uv.y - 1.015625) < 0.001:
					bake_ok[1] += 1
	)
	_check(atlas_ok[0] and atlas_ok[1], "both surfaces sample doubled mirror atlases (swarp3 32x64, bwarp1 64x128)")
	_check(bake_ok[0] >= 8, "curtain UVs baked into atlas space (x=0.125 count=%d)" % bake_ok[0])
	_check(bake_ok[1] >= 8, "base UVs carry the one-page gold shift (v=1.0156 count=%d)" % bake_ok[1])

extends "res://scripts/tools/probe_checks.gd"
var _materials: Array[Material] = []
var _scenes: Array[PackedScene] = []
const Cutouts := preload("res://scripts/utils/texture_cutouts.gd")

func _run() -> void:
	probe_label = "weapon-visual"
	# Loading the scene first avoids recursive script/scene preloads in Player.
	var player = load("res://scenes/3d/player/player.tscn").instantiate()
	var checked := 0
	var missing := 0
	var cutouts := 0
	for id in WeaponRegistry.get_all_weapon_ids():
		var data: WeaponData = WeaponRegistry.get_weapon(id)
		if data.glb_path.is_empty():
			missing += 1
			continue
		var packed = load(data.glb_path)
		_check(packed is PackedScene, "load " + id)
		if not packed is PackedScene: continue
		_scenes.append(packed)
		var node: Node3D = packed.instantiate()
		add_child(node)
		var surfaces: Array = []
		player._collect_surfaces(node, surfaces)
		var originals: Array = []
		for entry in surfaces:
			var mat = entry[0].get_active_material(entry[1])
			originals.append([mat, mat.transparency, mat.blend_mode])
		player._apply_weapon_materials(node, data)
		for i in surfaces.size():
			var entry = surfaces[i]
			var material: StandardMaterial3D = entry[0].get_active_material(entry[1])
			var original: StandardMaterial3D = originals[i][0]
			_materials.append(material)
			_materials.append(original)
			_check(original.transparency == originals[i][1] and original.blend_mode == originals[i][2], id + " imported resource unchanged")
			_check(Cutouts.cutout_copy(material) == material, id + " normalized")
			if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR: cutouts += 1
			if original.albedo_texture and not Cutouts.binary_alpha(original.albedo_texture.get_image()):
				_check(material.transparency == original.transparency, id + " fractional texture alpha preserved")
			if material.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
				_check(material.transparency == original.transparency, id + " photon blending preserved")
		await get_tree().process_frame
		node.queue_free()
		await get_tree().process_frame
		checked += 1
	player.free()
	_check(checked == 94 and missing == 266, "registry coverage: %d checked, %d missing models" % [checked, missing])
	_check(cutouts > 0, "real weapon cutouts exercised")
	print("[weapon-visual] DONE %s" % ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

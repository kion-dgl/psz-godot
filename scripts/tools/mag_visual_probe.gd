extends "res://scripts/tools/probe_checks.gd"
const Visuals := preload("res://scripts/utils/texture_cutouts.gd")
var models: Array[Node3D] = []

func _run() -> void:
	probe_label = "mag-visual"
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.15, 0.2)
	world.add_child(env)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 2, 7)
	camera.look_at(Vector3(0, 0.8, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.5
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var label := Label.new()
	label.text = "Original imported material                         Corrected alpha cutout"
	label.position = Vector2(160, 50)
	label.add_theme_font_size_override("font_size", 24)
	layer.add_child(label)
	DisplayServer.window_set_title("Mag surface comparison")
	var forms: Dictionary = MagManager.MAG_MODEL_MAP.duplicate()
	# Include source assets not currently assigned to an obtainable form.
	for file in DirAccess.get_files_at("res://assets/mags"):
		var path := "res://assets/mags/" + file
		if file.ends_with(".glb") and not path in forms.values(): forms[file.get_basename()] = path
	var loaded := 0
	var missing: Array[String] = []
	for form in forms:
		var path: String = forms[form]
		if FileAccess.get_file_as_bytes(path).is_empty():
			missing.append(form)
			continue
		var packed = load(path)
		if not packed is PackedScene:
			_check(false, "cannot load " + form)
			continue
		for i in range(2):
			var node: Node3D = packed.instantiate()
			world.add_child(node)
			node.position.x = (i - 0.5) * 2.6
			node.scale = Vector3.ONE * 3.5
			models.append(node)
			if i > 0: Visuals.apply(node)
		check_materials(models[0], false)
		check_materials(models[1], true)
		label.text = "%s: Original                              Alpha cutout" % form.capitalize()
		for angle in [0, 45, 90, 135, 180, 225, 270, 315]:
			for node in models: node.rotation.y = deg_to_rad(angle)
			await get_tree().process_frame
			await get_tree().process_frame
			await _snapshot("%s-%03d" % [form, angle])
		for node in models: node.queue_free()
		models.clear()
		loaded += 1
		print("[mag-visual] inspected " + form)
	print("[mag-visual] coverage: %d/%d; empty assets: %s" % [loaded, forms.size(), ", ".join(missing)])
	print("[mag-visual] DONE %s" % ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func check_materials(node: Node, corrected: bool) -> void:
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var material = node.get_active_material(surface)
			_check(material.transparency == (BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if corrected else BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS), "real Mag material mode; corrected=%s" % corrected)
			_check(material.cull_mode == BaseMaterial3D.CULL_DISABLED, "real Mag retains double-sided geometry")
	for child in node.get_children(): check_materials(child, corrected)

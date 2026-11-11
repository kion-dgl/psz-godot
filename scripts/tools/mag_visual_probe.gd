extends "res://scripts/tools/probe_checks.gd"
const Visuals := preload("res://scripts/3d/player/mag_visuals.gd")
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
	var packed = load("res://assets/mags/wmaa1_1_1.glb")
	for i in range(2):
		var node: Node3D = packed.instantiate()
		world.add_child(node)
		node.position.x = (i - 0.5) * 2.6
		node.scale = Vector3.ONE * 7.5
		models.append(node)
		if i > 0: Visuals.apply(node)
	check_materials(models[0], false)
	check_materials(models[1], true)
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var label := Label.new()
	label.text = "Original imported material                         Corrected alpha cutout"
	label.position = Vector2(160, 50)
	label.add_theme_font_size_override("font_size", 24)
	layer.add_child(label)
	DisplayServer.window_set_title("Mag surface comparison")
	for angle in [0, 45, 90, 135, 180, 225, 270, 315]:
		for node in models: node.rotation.y = deg_to_rad(angle)
		await get_tree().process_frame
		await get_tree().process_frame
		await _snapshot("mag-surfaces-%03d" % angle)
	print("[mag-visual] DONE %s" % ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func check_materials(node: Node, corrected: bool) -> void:
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var material = node.get_active_material(surface)
			_check(material.transparency == (BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if corrected else BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS), "real Mag material mode; corrected=%s" % corrected)
			_check(material.cull_mode == BaseMaterial3D.CULL_DISABLED, "real Mag retains double-sided geometry")
	for child in node.get_children(): check_materials(child, corrected)

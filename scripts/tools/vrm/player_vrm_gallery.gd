extends Node3D
## Portable models rendered without the native compatibility adapter.
var elapsed := 0.0
func _ready() -> void:
	var variation := int(OS.get_environment("PSZ_VRM_VARIATION"))
	var index := 0
	for class_id in PlayerConfig.CLASS_PREFIX:
		var path: String = PlayerConfig.get_model_path(class_id, variation)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_buffer(FileAccess.get_file_as_bytes(path), "", state) != OK:
			get_tree().quit(1)
			return
		var avatar := document.generate_scene(state)
		add_child(avatar)
		avatar.position = Vector3((index % 7 - 3) * 1.85, 2.7 if index < 7 else 0.0, 0)
		var label := Label3D.new()
		label.text = "%s · %d" % [class_id, variation]
		label.position = avatar.position + Vector3(0, -0.25, 0)
		label.font_size = 48
		add_child(label)
		index += 1
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 2.4, 12)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8
	camera.current = true
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("19222f")
	add_child(world)

func _process(delta: float) -> void:
	elapsed += delta
	var screenshot := OS.get_environment("PSZ_VRM_SCREENSHOT")
	if elapsed > 3 and not screenshot.is_empty():
		get_viewport().get_texture().get_image().save_png(screenshot)
		get_tree().quit()

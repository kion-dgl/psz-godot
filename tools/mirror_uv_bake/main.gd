extends Control
const Fixture = preload("fixture.gd")
const VIEW_SIZE := Vector2i(640, 640)
var viewports: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var lights: Array[DirectionalLight3D] = []
var meshes: Array[MeshInstance3D] = []
var worlds: Array[Node3D] = []
var source_picker: OptionButton
var lit_toggle: CheckButton
var mip_toggle: CheckButton
var light_slider: HSlider
var details: Label
var result: Label
var fixture: Dictionary
var source_id := "stage"
var yaw := 0.0
var pitch := 0.0
var distance := 6.0
var reference_code := ""
var busy := false
var output_dir := "res://output"

func _ready() -> void:
	reference_code = FileAccess.get_file_as_string("res://reference.gdshader")
	_build_ui()
	_rebuild()
	var args := OS.get_cmdline_user_args()
	var output_index := args.find("--output")
	if output_index >= 0 and output_index + 1 < args.size():
		output_dir = args[output_index + 1]
	if args.has("--verify"):
		call_deferred("_verify")

func _label(text: String, font_size: int = 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _button(text: String, callback: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("101927")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	layout.add_child(_label("Mirror UV bake | Godot native-material proof", 25))
	layout.add_child(_label("Drag either view to orbit. Scroll to zoom. Both cameras and lights stay linked."))
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 16)
	layout.add_child(toolbar)
	source_picker = OptionButton.new()
	source_picker.add_item("Valley dirt path")
	source_picker.add_item("Asymmetric test card")
	source_picker.item_selected.connect(_select_source)
	toolbar.add_child(source_picker)
	lit_toggle = CheckButton.new()
	lit_toggle.text = "Native lighting"
	lit_toggle.button_pressed = true
	lit_toggle.toggled.connect(func(_value: bool): _update_materials())
	toolbar.add_child(lit_toggle)
	mip_toggle = CheckButton.new()
	mip_toggle.text = "Mipmaps"
	mip_toggle.toggled.connect(func(_value: bool): _update_materials())
	toolbar.add_child(mip_toggle)
	toolbar.add_child(_label("Light angle"))
	light_slider = HSlider.new()
	light_slider.min_value = -170
	light_slider.max_value = 170
	light_slider.value = 40
	light_slider.custom_minimum_size.x = 180
	light_slider.value_changed.connect(func(_value: float): _update_lights())
	toolbar.add_child(light_slider)
	_button("Reset view", _reset_view, toolbar)
	var views := HBoxContainer.new()
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views.add_theme_constant_override("separation", 12)
	layout.add_child(views)
	for i in range(2):
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		views.add_child(column)
		var heading := _label("Original UVs + mirror shader" if i == 0 else "Baked UVs + StandardMaterial3D", 19)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(heading)
		var viewport := SubViewport.new()
		viewport.size = VIEW_SIZE
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		add_child(viewport)
		viewports.append(viewport)
		var display := TextureRect.new()
		display.texture = viewport.get_texture()
		display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		display.size_flags_vertical = Control.SIZE_EXPAND_FILL
		display.custom_minimum_size.y = 320
		display.mouse_filter = Control.MOUSE_FILTER_STOP
		display.gui_input.connect(_view_input)
		column.add_child(display)
		var world := Node3D.new()
		viewport.add_child(world)
		worlds.append(world)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("101927")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.25
		world.add_child(environment)
		var camera := Camera3D.new()
		camera.fov = 42
		camera.near = 0.01
		camera.far = 100
		world.add_child(camera)
		camera.make_current()
		cameras.append(camera)
		var sun := DirectionalLight3D.new()
		sun.light_energy = 1.3
		world.add_child(sun)
		lights.append(sun)
		var mesh := MeshInstance3D.new()
		world.add_child(mesh)
		meshes.append(mesh)
	details = _label("")
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(details)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	layout.add_child(actions)
	_button("Measure pixel difference", _measure, actions)
	_button("Save comparison screenshots", _capture, actions)
	_button("Save native-only scene", _save_native, actions)
	result = _label("Linear filtering without mipmaps is the baseline. Toggle lighting to inspect native shading.")
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(result)
	var note := _label("Independent project: no game autoloads, stage configs or shipped assets are changed. Reflected textures trade memory for native wrapping.", 13)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(note)

func _select_source(index: int) -> void:
	source_id = "stage" if index == 0 else "synthetic"
	_rebuild()

func _rebuild() -> void:
	fixture = Fixture.read_fixture(source_id)
	meshes[0].mesh = Fixture.mesh_from_data(fixture.original)
	meshes[1].mesh = Fixture.build_candidate(fixture, lit_toggle.button_pressed, mip_toggle.button_pressed)
	_update_materials()
	_update_camera()
	_update_lights()

func _update_materials() -> void:
	if fixture.is_empty():
		return
	var code := reference_code
	if mip_toggle.button_pressed:
		code = code.replace("filter_linear,", "filter_linear_mipmap,")
	if not lit_toggle.button_pressed:
		code = code.replace("render_mode cull_disabled;", "render_mode cull_disabled, unshaded;")
	var shader := Shader.new()
	shader.code = code
	var reference := ShaderMaterial.new()
	reference.shader = shader
	var image: Image = Fixture.source_image(fixture)
	reference.set_shader_parameter("albedo_texture", Fixture.texture(image, mip_toggle.button_pressed))
	reference.set_shader_parameter("uv_scale", Vector2(fixture.settings.repeat[0], fixture.settings.repeat[1]))
	reference.set_shader_parameter("uv_offset", Vector2(fixture.settings.offset[0], fixture.settings.offset[1]))
	reference.set_shader_parameter("mirror_x", bool(fixture.settings.mirror[0]))
	reference.set_shader_parameter("mirror_y", bool(fixture.settings.mirror[1]))
	meshes[0].material_override = reference
	var atlas: Image = Fixture.reflected_atlas(image, fixture.settings.mirror)
	var native: StandardMaterial3D = Fixture.native_material(atlas, lit_toggle.button_pressed, mip_toggle.button_pressed)
	meshes[1].mesh.surface_set_material(0, native)
	meshes[1].material_override = null
	var source_triangles: int = fixture.original.position.size() / 9
	var baked_triangles: int = fixture.baked.position.size() / 9
	details.text = "%d → %d triangles | texture %d×%d → %d×%d (%d× pixels) | Right: StandardMaterial3D, repeat enabled, no custom shader" % [source_triangles, baked_triangles, image.get_width(), image.get_height(), atlas.get_width(), atlas.get_height(), atlas.get_width()*atlas.get_height()/(image.get_width()*image.get_height())]
	result.text = "Ready to compare. Both views use %s lighting and %s filtering." % ["native per-pixel" if lit_toggle.button_pressed else "unshaded", "linear mipmapped" if mip_toggle.button_pressed else "linear, no mipmaps"]

func _update_camera() -> void:
	for camera in cameras:
		camera.position = Vector3(sin(yaw)*cos(pitch), sin(pitch), cos(yaw)*cos(pitch)) * distance
		camera.look_at(Vector3.ZERO)

func _update_lights() -> void:
	var angle := deg_to_rad(light_slider.value)
	for sun in lights:
		sun.position = Vector3(sin(angle)*4.0, 3.0, cos(angle)*4.0)
		sun.look_at(Vector3.ZERO)

func _reset_view() -> void:
	yaw = 0.0
	pitch = 0.0
	distance = 6.0
	_update_camera()

func _view_input(event: InputEvent) -> void:
	if busy:
		return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch + event.relative.y * 0.008, -1.3, 1.3)
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(1.0, distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(20.0, distance / 0.9)
		_update_camera()

func _settle() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _diff(a: Image, b: Image) -> Dictionary:
	assert(a.get_size() == b.get_size())
	var total := 0.0
	var peak := 0.0
	var changed := 0
	var foreground := 0
	var foreground_error := 0.0
	var background := a.get_pixel(0, 0)
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var left := a.get_pixel(x, y)
			var right := b.get_pixel(x, y)
			var error := Vector3(abs(left.r-right.r), abs(left.g-right.g), abs(left.b-right.b)) * 255.0
			var local_peak := maxf(error.x, maxf(error.y, error.z))
			total += error.x + error.y + error.z
			peak = maxf(peak, local_peak)
			if local_peak > 2.01:
				changed += 1
			if maxf(abs(left.r-background.r), maxf(abs(left.g-background.g), abs(left.b-background.b))) > 0.01:
				foreground += 1
				foreground_error += error.x + error.y + error.z
	var pixels := a.get_width() * a.get_height()
	return {"mean_rgb": total / (pixels * 3.0), "max_rgb": peak, "pixels_over_2_percent": changed * 100.0 / pixels, "foreground_pixels": foreground, "foreground_mean_rgb": foreground_error / maxf(foreground * 3.0, 1.0)}

func _measure() -> void:
	if busy:
		return
	busy = true
	await _settle()
	var stats := _diff(viewports[0].get_texture().get_image(), viewports[1].get_texture().get_image())
	result.text = "640² pixels | mean %.4f/255 | foreground mean %.4f/255 | max %.1f/255 | %.3f%% pixels differ by >2" % [stats.mean_rgb, stats.foreground_mean_rgb, stats.max_rgb, stats.pixels_over_2_percent]
	print("[mirror-diff] ", source_id, " ", JSON.stringify(stats))
	busy = false

func _ensure_output() -> String:
	var path := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(path)
	return path

func _capture() -> void:
	if busy:
		return
	busy = true
	await _settle()
	var path := _ensure_output()
	viewports[0].get_texture().get_image().save_png(path.path_join(source_id + "-reference.png"))
	viewports[1].get_texture().get_image().save_png(path.path_join(source_id + "-native.png"))
	get_viewport().get_texture().get_image().save_png(path.path_join(source_id + "-comparison.png"))
	result.text = "Saved comparison to " + path
	busy = false

func _save_native() -> void:
	var directory := _ensure_output()
	var path := directory.path_join(source_id + "-native.res")
	var error := ResourceSaver.save(meshes[1].mesh, path)
	if error != OK:
		result.text = "Resource save failed: " + str(error)
		return
	# A second, script-free scene proves the candidate works without this lab.
	var root := Node3D.new()
	root.name = "NativeMirrorSample"
	var sample := MeshInstance3D.new()
	sample.name = "BakedMesh_StandardMaterial3D"
	sample.mesh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	root.add_child(sample)
	sample.owner = root
	for child in worlds[1].get_children():
		if child is Camera3D or child is DirectionalLight3D or child is WorldEnvironment:
			var copy := child.duplicate()
			root.add_child(copy)
			copy.owner = root
	var packed := PackedScene.new()
	error = packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, directory.path_join(source_id + "-native.tscn"))
	root.free()
	result.text = "Saved script-free native scene and mesh to " + directory if error == OK else "Scene save failed: " + str(error)

func _verify() -> void:
	busy = true
	var path := _ensure_output()
	var report: Array = []
	var failed := false
	for id in ["stage", "synthetic"]:
		source_id = id
		source_picker.select(0 if id == "stage" else 1)
		_rebuild()
		var unlit_native: Image
		var lit_native: Image
		for lit in [false, true]:
			for mipmaps in [false, true]:
				lit_toggle.set_pressed_no_signal(lit)
				mip_toggle.set_pressed_no_signal(mipmaps)
				_update_materials()
				await _settle()
				var original := viewports[0].get_texture().get_image()
				var native := viewports[1].get_texture().get_image()
				var stats := _diff(original, native)
				stats["source"] = id
				stats["lit"] = lit
				stats["mipmaps"] = mipmaps
				var tag := "%s-%s-%s" % [id, "lit" if lit else "unlit", "mips" if mipmaps else "linear"]
				original.save_png(path.path_join(tag + "-reference.png"))
				native.save_png(path.path_join(tag + "-native.png"))
				get_viewport().get_texture().get_image().save_png(path.path_join(tag + "-comparison.png"))
				# No-mip baseline is the exact sampling contract. Mips are diagnostic:
				# the old folded shader has discontinuous derivatives at boundaries.
				if not mipmaps and (stats.foreground_mean_rgb > 1.0 or stats.foreground_pixels < 100):
					failed = true
				if not mipmaps:
					if lit:
						lit_native = native
					else:
						unlit_native = native
				report.append(stats)
				print("[mirror-verify] ", tag, " ", JSON.stringify(stats))
		var lighting_response := _diff(unlit_native, lit_native)
		if lighting_response.foreground_mean_rgb < 2.0:
			failed = true
		report.append({"source": id, "native_lighting_response": lighting_response})
		# A second native-light direction proves the result is not a static tint.
		mip_toggle.set_pressed_no_signal(false)
		lit_toggle.set_pressed_no_signal(true)
		_update_materials()
		light_slider.set_value_no_signal(135)
		_update_lights()
		await _settle()
		var moved_light := viewports[1].get_texture().get_image()
		var directional_response := _diff(lit_native, moved_light)
		if directional_response.foreground_mean_rgb < 2.0:
			failed = true
		moved_light.save_png(path.path_join(id + "-moved-light-native.png"))
		report.append({"source": id, "native_directional_response": directional_response})
		light_slider.set_value_no_signal(40)
		_update_lights()
		var candidate_material := meshes[1].mesh.surface_get_material(0)
		if not candidate_material is StandardMaterial3D or candidate_material.next_pass != null or meshes[1].material_override != null:
			failed = true
		_save_native()
	var report_file := FileAccess.open(path.path_join("report.json"), FileAccess.WRITE)
	report_file.store_string(JSON.stringify({"failed": failed, "renderer": RenderingServer.get_current_rendering_method(), "results": report}, "  "))
	print("[mirror-verify] ", "FAIL" if failed else "DONE ok", " | ", path)
	get_tree().quit(1 if failed else 0)

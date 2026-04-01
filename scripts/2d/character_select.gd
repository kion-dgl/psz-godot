extends Control
## Character selection screen — PSZ-themed 2x2 grid with info + preview per slot.

const SLOT_COUNT := 4
const GRID_COLS := 2

# PSZ Color Palette
const COL_BG := Color(0.66, 0.78, 0.88)
const COL_METAL_TOP := Color(0.78, 0.80, 0.84)
const COL_METAL_BOT := Color(0.55, 0.58, 0.62)
const COL_SELECTED := Color(0.94, 0.66, 0.18)
const COL_DARK_TEXT := Color(0.15, 0.20, 0.25)
const COL_MUTED_TEXT := Color(0.45, 0.50, 0.55)
const COL_SLOT_BG := Color(0.88, 0.90, 0.94)
const COL_EMPTY_TEXT := Color(0.55, 0.60, 0.68)

var _current_slot: int = 0


func _ready() -> void:
	# Clear tscn children and build programmatically
	for child in get_children():
		child.queue_free()

	# Full-screen background
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main VBox
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# Title bar
	var title_bar := PanelContainer.new()
	var title_style := StyleBoxFlat.new()
	title_style.bg_color = COL_METAL_TOP
	title_style.border_color = COL_METAL_BOT
	title_style.border_width_bottom = 2
	title_style.content_margin_top = 10.0
	title_style.content_margin_bottom = 10.0
	title_bar.add_theme_stylebox_override("panel", title_style)
	var title_label := Label.new()
	title_label.text = "Select File"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", COL_DARK_TEXT)
	title_bar.add_child(title_label)
	root.add_child(title_bar)

	# Grid area
	var grid_margin := MarginContainer.new()
	grid_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_margin.add_theme_constant_override("margin_left", 24)
	grid_margin.add_theme_constant_override("margin_right", 24)
	grid_margin.add_theme_constant_override("margin_top", 16)
	grid_margin.add_theme_constant_override("margin_bottom", 8)
	root.add_child(grid_margin)

	var grid := GridContainer.new()
	grid.columns = GRID_COLS
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_margin.add_child(grid)

	for i in range(SLOT_COUNT):
		var slot := _build_slot(i)
		grid.add_child(slot)

	# Hint bar
	var hint_bar := PanelContainer.new()
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = COL_METAL_BOT
	hint_style.border_color = COL_METAL_TOP
	hint_style.border_width_top = 1
	hint_style.content_margin_top = 8.0
	hint_style.content_margin_bottom = 8.0
	hint_style.content_margin_left = 20.0
	hint_style.content_margin_right = 20.0
	hint_bar.add_theme_stylebox_override("panel", hint_style)
	var hint_label := Label.new()
	hint_label.text = "[D-Pad] Navigate   [Confirm] Select   [Cancel] Back   [Delete] Remove"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", COL_DARK_TEXT)
	hint_bar.add_child(hint_label)
	root.add_child(hint_bar)


func _build_slot(index: int) -> PanelContainer:
	var character = CharacterManager.get_character(index)
	var is_selected: bool = index == _current_slot

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	if is_selected:
		style.bg_color = COL_SELECTED
		style.border_color = Color(0.80, 0.50, 0.10)
	else:
		style.bg_color = COL_SLOT_BG
		style.border_color = Color(0.70, 0.72, 0.78)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	# Left: character info
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)

	if character != null:
		var text_color: Color = Color.WHITE if is_selected else Color(0.1, 0.12, 0.18)
		var sub_color: Color = Color(1, 1, 1, 0.75) if is_selected else COL_MUTED_TEXT
		var dim_color: Color = Color(1, 1, 1, 0.55) if is_selected else Color(0.5, 0.54, 0.6)

		var name_label := Label.new()
		name_label.text = str(character.get("name", "???"))
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.add_theme_color_override("font_color", text_color)
		info.add_child(name_label)

		var class_id: String = str(character.get("class_id", ""))
		var class_data = ClassRegistry.get_class_data(class_id)
		var class_label := Label.new()
		class_label.text = class_data.name if class_data else class_id
		class_label.add_theme_font_size_override("font_size", 16)
		class_label.add_theme_color_override("font_color", sub_color)
		info.add_child(class_label)

		var level_label := Label.new()
		level_label.text = "LV %d" % int(character.get("level", 1))
		level_label.add_theme_font_size_override("font_size", 18)
		level_label.add_theme_color_override("font_color", Color(0.3, 0.55, 0.85) if not is_selected else Color(1, 1, 0.8))
		info.add_child(level_label)

		# Spacer
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		info.add_child(spacer)

		# Meseta
		var meseta_label := Label.new()
		meseta_label.text = "%d Meseta" % int(character.get("meseta", 0))
		meseta_label.add_theme_font_size_override("font_size", 13)
		meseta_label.add_theme_color_override("font_color", dim_color)
		info.add_child(meseta_label)

		# Materials used
		var mat_used: int = int(character.get("materials_used", 0))
		var mat_label := Label.new()
		mat_label.text = "Materials: %d / 100" % mat_used
		mat_label.add_theme_font_size_override("font_size", 13)
		mat_label.add_theme_color_override("font_color", dim_color)
		info.add_child(mat_label)

		# Equipped mag
		var mag_id: String = str(character.get("equipment", {}).get("mag", ""))
		if not mag_id.is_empty():
			var mag_label := Label.new()
			mag_label.text = "Mag: %s" % mag_id.capitalize()
			mag_label.add_theme_font_size_override("font_size", 13)
			mag_label.add_theme_color_override("font_color", dim_color)
			info.add_child(mag_label)
	else:
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		info.add_child(spacer)

		var empty_label := Label.new()
		empty_label.text = "New Game"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", COL_EMPTY_TEXT if not is_selected else Color.WHITE)
		info.add_child(empty_label)

		var spacer2 := Control.new()
		spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		info.add_child(spacer2)

	hbox.add_child(info)

	# Right: 3D preview (only for populated slots, skip on web)
	if character != null and not OS.has_feature("web"):
		var preview := _build_slot_preview(character)
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hbox.add_child(preview)

	panel.add_child(hbox)
	return panel


func _build_slot_preview(character: Dictionary) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(180, 200)
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var viewport := SubViewport.new()
	viewport.size = Vector2i(240, 300)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	container.add_child(viewport)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.5, 2.0)
	camera.rotation_degrees = Vector3(-5, 0, 0)
	camera.fov = 32
	viewport.add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	light.light_energy = 1.2
	viewport.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.4
	viewport.add_child(fill)

	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.45, 0.55)
	env.ambient_light_energy = 0.8
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var paths: Dictionary = PlayerConfig.get_paths_for_character(character)
	var model_path: String = paths["model_path"]
	var texture_path: String = paths["texture_path"]

	if ResourceLoader.exists(model_path):
		var packed: PackedScene = load(model_path) as PackedScene
		if packed:
			var model_node := packed.instantiate() as Node3D
			model_node.scale = Vector3(0.6, 0.6, 0.6)
			model_node.position.y = -0.7
			model_node.rotation_degrees.y = -15
			viewport.add_child(model_node)

			if ResourceLoader.exists(texture_path):
				var texture := load(texture_path) as Texture2D
				if texture:
					_apply_texture_recursive(model_node, texture)

	return container


func _apply_texture_recursive(node: Node, texture: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh:
			for surface_idx in range(mesh.get_surface_count()):
				var mat := mesh_instance.get_active_material(surface_idx)
				if mat is StandardMaterial3D:
					var new_mat := mat.duplicate() as StandardMaterial3D
					new_mat.albedo_texture = texture
					new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mesh_instance.set_surface_override_material(surface_idx, new_mat)
				elif mat == null:
					var new_mat := StandardMaterial3D.new()
					new_mat.albedo_texture = texture
					new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mesh_instance.set_surface_override_material(surface_idx, new_mat)
	for child in node.get_children():
		_apply_texture_recursive(child, texture)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		if _current_slot % GRID_COLS > 0:
			_current_slot -= 1
		else:
			_current_slot += GRID_COLS - 1
		_rebuild_grid()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		if _current_slot % GRID_COLS < GRID_COLS - 1:
			_current_slot += 1
		else:
			_current_slot -= GRID_COLS - 1
		_rebuild_grid()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_current_slot = wrapi(_current_slot - GRID_COLS, 0, SLOT_COUNT)
		_rebuild_grid()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_current_slot = wrapi(_current_slot + GRID_COLS, 0, SLOT_COUNT)
		_rebuild_grid()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_select_slot()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		SceneManager.goto_scene("res://scenes/2d/title.tscn")
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_DELETE:
		_delete_slot()
		get_viewport().set_input_as_handled()


func _rebuild_grid() -> void:
	# Find the grid and rebuild slot panels
	var grid: GridContainer = null
	for node in get_children():
		if node is VBoxContainer:
			for sub in node.get_children():
				if sub is MarginContainer:
					for inner in sub.get_children():
						if inner is GridContainer:
							grid = inner
	if grid == null:
		return
	for child in grid.get_children():
		child.queue_free()
	for i in range(SLOT_COUNT):
		grid.add_child(_build_slot(i))


func _select_slot() -> void:
	var character = CharacterManager.get_character(_current_slot)
	if character != null:
		CharacterManager.set_active_slot(_current_slot)
		SceneManager.goto_scene("res://scenes/3d/city/city_market.tscn")
	else:
		SceneManager.goto_scene("res://scenes/2d/character_create.tscn", {"slot": _current_slot})


func _delete_slot() -> void:
	var character = CharacterManager.get_character(_current_slot)
	if character == null:
		return
	CharacterManager.delete_character(_current_slot)
	_rebuild_grid()

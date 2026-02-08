extends Control
## Character selection screen — 2x2 grid with 3D character previews.

const SLOT_COUNT := 4
const GRID_COLS := 2

var _current_slot: int = 0

@onready var title_label: Label = $VBox/TitleLabel
@onready var slots_grid: GridContainer = $VBox/SlotsGrid
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "SELECT CHARACTER"
	hint_label.text = "[↑/↓/←/→] Navigate  [ENTER] Select  [DELETE] Delete  [ESC] Back"
	_refresh_slots()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		if _current_slot % GRID_COLS > 0:
			_current_slot -= 1
		else:
			_current_slot += GRID_COLS - 1
		_refresh_slots()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		if _current_slot % GRID_COLS < GRID_COLS - 1:
			_current_slot += 1
		else:
			_current_slot -= GRID_COLS - 1
		_refresh_slots()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_current_slot = wrapi(_current_slot - GRID_COLS, 0, SLOT_COUNT)
		_refresh_slots()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_current_slot = wrapi(_current_slot + GRID_COLS, 0, SLOT_COUNT)
		_refresh_slots()
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


func _refresh_slots() -> void:
	for child in slots_grid.get_children():
		child.queue_free()

	for i in range(SLOT_COUNT):
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var style := StyleBoxFlat.new()
		style.bg_color = ThemeColors.BG_PANEL
		style.border_color = ThemeColors.TEXT_HIGHLIGHT if i == _current_slot else ThemeColors.BORDER
		style.set_border_width_all(2 if i == _current_slot else 1)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(12)
		panel.add_theme_stylebox_override("panel", style)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)

		# 3D preview on the left (skip on web — SubViewport 3D causes WebGL issues)
		var character = CharacterManager.get_character(i)
		if character != null and not OS.has_feature("web"):
			var preview := _build_slot_preview(character)
			hbox.add_child(preview)

		# Info on the right
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 4)

		var slot_header := Label.new()
		slot_header.text = "Slot %d" % (i + 1)
		slot_header.add_theme_color_override("font_color", ThemeColors.HEADER)
		vbox.add_child(slot_header)

		if character != null:
			var name_label := Label.new()
			name_label.text = character.get("name", "???")
			name_label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT if i == _current_slot else ThemeColors.TEXT_PRIMARY)
			vbox.add_child(name_label)

			var class_id: String = character.get("class_id", "")
			var class_display := class_id
			var class_data = ClassRegistry.get_class_data(class_id)
			if class_data:
				class_display = "%s  %s %s" % [class_data.name, class_data.race, class_data.gender]
			var class_label := Label.new()
			class_label.text = class_display
			class_label.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
			vbox.add_child(class_label)

			var level_label := Label.new()
			level_label.text = "Level %d" % character.get("level", 1)
			vbox.add_child(level_label)
		else:
			var empty_label := Label.new()
			empty_label.text = "\n[ Empty Slot ]"
			empty_label.add_theme_color_override("font_color", ThemeColors.TEXT_DISABLED)
			vbox.add_child(empty_label)

		hbox.add_child(vbox)
		panel.add_child(hbox)
		slots_grid.add_child(panel)


func _build_slot_preview(character: Dictionary) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(160, 200)
	container.stretch = true

	var viewport := SubViewport.new()
	viewport.size = Vector2i(160, 200)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	container.add_child(viewport)

	# Camera
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.0, 2.2)
	camera.rotation_degrees = Vector3(-3, 0, 0)
	camera.fov = 30
	viewport.add_child(camera)

	# Lighting
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	light.light_energy = 1.2
	viewport.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.4
	viewport.add_child(fill)

	# Environment
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.35, 0.45)
	env.ambient_light_energy = 0.8
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.08, 0.14, 0.0)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	# Load model
	var paths: Dictionary = PlayerConfig.get_paths_for_character(character)
	var model_path: String = paths["model_path"]
	var texture_path: String = paths["texture_path"]

	if ResourceLoader.exists(model_path):
		var packed: PackedScene = load(model_path) as PackedScene
		if packed:
			var model_node := packed.instantiate() as Node3D
			model_node.scale = Vector3(0.6, 0.6, 0.6)
			model_node.position.y = -0.7
			viewport.add_child(model_node)

			# Apply texture
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
	# TODO: Add confirm dialog before deletion
	CharacterManager.delete_character(_current_slot)
	_refresh_slots()

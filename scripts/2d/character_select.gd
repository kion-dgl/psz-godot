extends Control
## Character selection screen — PSZ-themed file select with left slot list + right detail panel.

const SLOT_COUNT := 4

# PSZ Color Palette
const COL_BG := Color(0.66, 0.78, 0.88)
const COL_METAL_TOP := Color(0.78, 0.80, 0.84)
const COL_METAL_BOT := Color(0.55, 0.58, 0.62)
const COL_SELECTED := Color(0.94, 0.66, 0.18)
const COL_DARK_TEXT := Color(0.15, 0.20, 0.25)
const COL_MUTED_TEXT := Color(0.45, 0.50, 0.55)
const COL_PANEL_BORDER := Color(0.50, 0.55, 0.62)
const COL_SLOT_BG := Color(0.85, 0.87, 0.91)
const COL_DETAIL_BG := Color(0.80, 0.84, 0.90)
const COL_DIVIDER := Color(0.60, 0.64, 0.70)
const COL_EMPTY_TEXT := Color(0.55, 0.60, 0.68)
const COL_LEVEL_TEXT := Color(0.30, 0.50, 0.72)

var _current_slot: int = 0

# UI references (built programmatically)
var _slot_panels: Array = []
var _detail_container: VBoxContainer
var _preview_container: SubViewportContainer
var _preview_viewport: SubViewport
var _hint_label: Label


func _ready() -> void:
	# Clear everything from tscn — we build the whole UI programmatically
	for child in get_children():
		child.queue_free()
	# Wait one frame so queue_free completes before we add new children
	await get_tree().process_frame
	_build_ui()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_current_slot = wrapi(_current_slot - 1, 0, SLOT_COUNT)
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_current_slot = wrapi(_current_slot + 1, 0, SLOT_COUNT)
		_refresh()
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


# ---------------------------------------------------------------------------
#  Build UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Full-screen light blue background
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Main layout — vertical: title bar, content, hint bar
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	# --- Title bar (metallic gradient) ---
	var title_bar := _make_metal_bar(44)
	root_vbox.add_child(title_bar)

	var title_label := Label.new()
	title_label.text = "Select File"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", COL_DARK_TEXT)
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.set_anchors_preset(PRESET_FULL_RECT)
	title_bar.add_child(title_label)

	# --- Content area (left + right panels) ---
	var content := HBoxContainer.new()
	content.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	root_vbox.add_child(content)

	# Left panel — file slot list
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.42
	var left_style := StyleBoxFlat.new()
	left_style.bg_color = COL_BG
	left_style.content_margin_left = 20
	left_style.content_margin_right = 10
	left_style.content_margin_top = 16
	left_style.content_margin_bottom = 16
	left_panel.add_theme_stylebox_override("panel", left_style)
	content.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 6)
	left_panel.add_child(left_vbox)

	_slot_panels.clear()
	for i in range(SLOT_COUNT):
		var slot_panel := _build_slot_row(i)
		left_vbox.add_child(slot_panel)
		_slot_panels.append(slot_panel)

	# Vertical divider line
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(1, 0)
	divider.size_flags_vertical = SIZE_EXPAND_FILL
	divider.color = COL_DIVIDER
	content.add_child(divider)

	# Right panel — character detail + 3D preview
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.58
	var right_style := StyleBoxFlat.new()
	right_style.bg_color = COL_DETAIL_BG
	right_style.content_margin_left = 20
	right_style.content_margin_right = 20
	right_style.content_margin_top = 16
	right_style.content_margin_bottom = 16
	right_panel.add_theme_stylebox_override("panel", right_style)
	content.add_child(right_panel)

	# Right panel inner layout: HBox with detail text on left, 3D preview on right
	var right_hbox := HBoxContainer.new()
	right_hbox.add_theme_constant_override("separation", 12)
	right_panel.add_child(right_hbox)

	_detail_container = VBoxContainer.new()
	_detail_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_detail_container.size_flags_stretch_ratio = 0.5
	_detail_container.add_theme_constant_override("separation", 8)
	right_hbox.add_child(_detail_container)

	# 3D preview area (right side of right panel)
	var preview_wrapper := CenterContainer.new()
	preview_wrapper.size_flags_horizontal = SIZE_EXPAND_FILL
	preview_wrapper.size_flags_vertical = SIZE_EXPAND_FILL
	preview_wrapper.size_flags_stretch_ratio = 0.5
	right_hbox.add_child(preview_wrapper)

	_preview_container = SubViewportContainer.new()
	_preview_container.custom_minimum_size = Vector2(220, 320)
	_preview_container.stretch = true
	preview_wrapper.add_child(_preview_container)

	_preview_viewport = SubViewport.new()
	_preview_viewport.size = Vector2i(220, 320)
	_preview_viewport.transparent_bg = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_preview_viewport.own_world_3d = true
	_preview_viewport.world_3d = World3D.new()
	_preview_container.add_child(_preview_viewport)

	# --- Hint bar (metallic gradient) ---
	var hint_bar := _make_metal_bar(36)
	root_vbox.add_child(hint_bar)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", COL_DARK_TEXT)
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.set_anchors_preset(PRESET_FULL_RECT)
	hint_bar.add_child(_hint_label)


func _make_metal_bar(height: int) -> PanelContainer:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(0, height)
	var style := StyleBoxFlat.new()
	# Approximate metallic gradient with a mid-tone — Godot StyleBoxFlat doesn't do
	# gradients, so we use the average and add a top/bottom highlight via borders.
	style.bg_color = lerp(COL_METAL_TOP, COL_METAL_BOT, 0.45)
	style.border_color = COL_METAL_TOP
	style.border_width_top = 1
	style.border_width_bottom = 0
	# Add a subtle bottom edge
	style.shadow_color = COL_METAL_BOT
	style.shadow_size = 1
	bar.add_theme_stylebox_override("panel", style)
	return bar


func _build_slot_row(_index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 64)
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	# Style gets set during _refresh
	var placeholder_style := StyleBoxFlat.new()
	placeholder_style.bg_color = COL_SLOT_BG
	placeholder_style.set_corner_radius_all(6)
	placeholder_style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", placeholder_style)
	return panel


# ---------------------------------------------------------------------------
#  Refresh
# ---------------------------------------------------------------------------

func _refresh() -> void:
	_refresh_slot_list()
	_refresh_detail_panel()
	_refresh_3d_preview()
	_refresh_hint()


func _refresh_slot_list() -> void:
	for i in range(SLOT_COUNT):
		var panel: PanelContainer = _slot_panels[i]
		var is_selected: bool = (i == _current_slot)

		# Remove old children from slot panel
		for child in panel.get_children():
			child.queue_free()

		# Update style
		var style := StyleBoxFlat.new()
		if is_selected:
			style.bg_color = COL_SELECTED
			style.border_color = COL_SELECTED.darkened(0.2)
		else:
			style.bg_color = COL_SLOT_BG
			style.border_color = COL_PANEL_BORDER
		style.set_border_width_all(2 if is_selected else 1)
		style.set_corner_radius_all(6)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", style)

		var character = CharacterManager.get_character(i)
		if character != null:
			var row := _build_populated_slot(i, character, is_selected)
			panel.add_child(row)
		else:
			var row := _build_empty_slot(i, is_selected)
			panel.add_child(row)


func _build_populated_slot(_index: int, character: Dictionary, is_selected: bool) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN

	# Left side: slot number + name
	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	var char_name: String = character.get("name", "???")
	name_label.text = char_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color.WHITE if is_selected else COL_DARK_TEXT)
	left.add_child(name_label)

	var class_id: String = character.get("class_id", "")
	var class_data = ClassRegistry.get_class_data(class_id)
	var class_name_str: String = class_id
	if class_data:
		class_name_str = class_data.name

	var class_label := Label.new()
	class_label.text = class_name_str
	class_label.add_theme_font_size_override("font_size", 13)
	class_label.add_theme_color_override("font_color",
		Color(1, 1, 1, 0.8) if is_selected else COL_MUTED_TEXT)
	left.add_child(class_label)

	hbox.add_child(left)

	# Right side: level
	var level_label := Label.new()
	var level: int = character.get("level", 1)
	level_label.text = "LV %d" % level
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.size_flags_horizontal = SIZE_SHRINK_END
	level_label.size_flags_vertical = SIZE_EXPAND_FILL
	level_label.add_theme_font_size_override("font_size", 15)
	level_label.add_theme_color_override("font_color",
		Color.WHITE if is_selected else COL_LEVEL_TEXT)
	hbox.add_child(level_label)

	return hbox


func _build_empty_slot(_index: int, is_selected: bool) -> CenterContainer:
	var center := CenterContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.size_flags_vertical = SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = "New Game"
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color",
		Color.WHITE if is_selected else COL_EMPTY_TEXT)
	center.add_child(label)
	return center


func _refresh_detail_panel() -> void:
	# Clear detail panel
	for child in _detail_container.get_children():
		child.queue_free()

	var character = CharacterManager.get_character(_current_slot)
	if character == null:
		_show_empty_detail()
		return

	# Slot header
	var slot_label := Label.new()
	slot_label.text = "FILE %d" % (_current_slot + 1)
	slot_label.add_theme_font_size_override("font_size", 13)
	slot_label.add_theme_color_override("font_color", COL_MUTED_TEXT)
	_detail_container.add_child(slot_label)

	# Character name
	var name_label := Label.new()
	name_label.text = character.get("name", "???")
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", COL_DARK_TEXT)
	_detail_container.add_child(name_label)

	# Horizontal rule
	_detail_container.add_child(_make_hr())

	# Class
	var class_id: String = character.get("class_id", "")
	var class_data = ClassRegistry.get_class_data(class_id)
	var class_name_str: String = class_id
	var class_desc: String = ""
	if class_data:
		class_name_str = class_data.name
		class_desc = "%s %s %s" % [class_data.race, class_data.gender, class_data.type]

	var class_label := Label.new()
	class_label.text = class_name_str
	class_label.add_theme_font_size_override("font_size", 17)
	class_label.add_theme_color_override("font_color", COL_DARK_TEXT)
	_detail_container.add_child(class_label)

	if not class_desc.is_empty():
		var desc_label := Label.new()
		desc_label.text = class_desc
		desc_label.add_theme_font_size_override("font_size", 13)
		desc_label.add_theme_color_override("font_color", COL_MUTED_TEXT)
		_detail_container.add_child(desc_label)

	# Level
	var level: int = character.get("level", 1)
	var level_label := Label.new()
	level_label.text = "LV %d" % level
	level_label.add_theme_font_size_override("font_size", 20)
	level_label.add_theme_color_override("font_color", COL_LEVEL_TEXT)
	_detail_container.add_child(level_label)

	# Another divider
	_detail_container.add_child(_make_hr())

	# Created date
	var created_at = character.get("created_at", 0)
	if created_at > 0:
		var dt: Dictionary = Time.get_datetime_dict_from_unix_time(int(created_at))
		var date_str := "%04d/%02d/%02d" % [dt.get("year", 0), dt.get("month", 0), dt.get("day", 0)]
		var created_label := Label.new()
		created_label.text = "Created: %s" % date_str
		created_label.add_theme_font_size_override("font_size", 13)
		created_label.add_theme_color_override("font_color", COL_MUTED_TEXT)
		_detail_container.add_child(created_label)

	# Meseta
	var meseta: int = character.get("meseta", 0)
	var meseta_label := Label.new()
	meseta_label.text = "Meseta: %s" % _format_number(meseta)
	meseta_label.add_theme_font_size_override("font_size", 13)
	meseta_label.add_theme_color_override("font_color", COL_MUTED_TEXT)
	_detail_container.add_child(meseta_label)

	# Spacer to push content up
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	_detail_container.add_child(spacer)


func _show_empty_detail() -> void:
	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = SIZE_EXPAND_FILL
	_detail_container.add_child(spacer_top)

	var slot_label := Label.new()
	slot_label.text = "FILE %d" % (_current_slot + 1)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.add_theme_font_size_override("font_size", 15)
	slot_label.add_theme_color_override("font_color", COL_MUTED_TEXT)
	_detail_container.add_child(slot_label)

	var empty_label := Label.new()
	empty_label.text = "No Data"
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.add_theme_font_size_override("font_size", 20)
	empty_label.add_theme_color_override("font_color", COL_EMPTY_TEXT)
	_detail_container.add_child(empty_label)

	var hint := Label.new()
	hint.text = "Press confirm to create\na new character"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", COL_MUTED_TEXT)
	_detail_container.add_child(hint)

	var spacer_bot := Control.new()
	spacer_bot.size_flags_vertical = SIZE_EXPAND_FILL
	_detail_container.add_child(spacer_bot)


func _make_hr() -> ColorRect:
	var hr := ColorRect.new()
	hr.custom_minimum_size = Vector2(0, 1)
	hr.color = COL_DIVIDER
	hr.size_flags_horizontal = SIZE_EXPAND_FILL
	return hr


# ---------------------------------------------------------------------------
#  3D Preview
# ---------------------------------------------------------------------------

func _refresh_3d_preview() -> void:
	# Clear existing preview nodes
	for child in _preview_viewport.get_children():
		child.queue_free()

	var character = CharacterManager.get_character(_current_slot)
	if character == null or OS.has_feature("web"):
		_preview_container.visible = character != null and not OS.has_feature("web")
		_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return

	_preview_container.visible = true

	# Camera
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.05, 2.0)
	camera.rotation_degrees = Vector3(-3, 0, 0)
	camera.fov = 30
	_preview_viewport.add_child(camera)

	# Lighting — soft key + fill
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35, 40, 0)
	key_light.light_energy = 1.3
	key_light.light_color = Color(1.0, 0.98, 0.95)
	_preview_viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-15, -100, 0)
	fill_light.light_energy = 0.35
	fill_light.light_color = Color(0.85, 0.90, 1.0)
	_preview_viewport.add_child(fill_light)

	# Environment — light ambient to match the panel background
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.72, 0.82)
	env.ambient_light_energy = 0.6
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_preview_viewport.add_child(world_env)

	# Load model
	var paths: Dictionary = PlayerConfig.get_paths_for_character(character)
	var model_path: String = paths["model_path"]
	var texture_path: String = paths["texture_path"]

	if ResourceLoader.exists(model_path):
		var packed: PackedScene = load(model_path) as PackedScene
		if packed:
			var model_node := packed.instantiate() as Node3D
			model_node.scale = Vector3(0.65, 0.65, 0.65)
			model_node.position.y = -0.72
			# Slight angle for visual interest
			model_node.rotation_degrees.y = -10.0
			_preview_viewport.add_child(model_node)

			if ResourceLoader.exists(texture_path):
				var texture := load(texture_path) as Texture2D
				if texture:
					_apply_texture_recursive(model_node, texture)

	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


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


# ---------------------------------------------------------------------------
#  Hint bar
# ---------------------------------------------------------------------------

func _refresh_hint() -> void:
	var character = CharacterManager.get_character(_current_slot)
	if character != null:
		_hint_label.text = "[Up/Down] Navigate    [Confirm] Load Game    [Cancel] Back    [Delete] Delete File"
	else:
		_hint_label.text = "[Up/Down] Navigate    [Confirm] New Game    [Cancel] Back"


# ---------------------------------------------------------------------------
#  Actions
# ---------------------------------------------------------------------------

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
	_refresh()


# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

func _format_number(n: int) -> String:
	var s := str(n)
	var result := ""
	var count := 0
	for idx in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[idx] + result
		count += 1
	return result

extends Control
## Character selection — PSO PC V2 list-style layout.
## See web/src/storybook/MenuDesign.tsx (CharacterSelect) for the mock
## this is ported from, and skeleton/character_select.html for the
## blockout that drove panel positions. Issue #168.

const SLOT_COUNT := 20  # mirrors CharacterManager.MAX_SLOTS

const FRAME_W := 1280
const FRAME_H := 720

# --- Palette (mirrors C{} in MenuDesign.tsx) ---
const COL_BG_LIGHT := Color(0.659, 0.800, 0.910)         # #a8cce8
const COL_BG_MID := Color(0.541, 0.722, 0.847)           # #8ab8d8
const COL_BG_DARK := Color(0.165, 0.204, 0.282)          # #2a3448
const COL_BANNER := Color(0.984, 0.729, 0.094)           # #FBBA18
const COL_BANNER_OUTLINE := Color(0.102, 0.102, 0.165)   # #1a1a2a
const COL_TEXT := Color(0.102, 0.102, 0.165)
const COL_TEXT_LIGHT := Color(0.227, 0.290, 0.353)
const COL_TEXT_WHITE := Color.WHITE
const COL_HINT_BG := Color(1, 1, 1, 0.7)
const COL_HINT_BORDER := Color(0.541, 0.659, 0.784)      # #8aa8c8
const COL_SEPARATOR := Color(0.478, 0.627, 0.753)        # #7aa0c0
const COL_ROW_BG := Color(1, 1, 1, 0.85)
const COL_ROW_BG_HOVER := Color(1, 1, 1, 0.95)
const COL_SELECTED_A := Color(0.941, 0.627, 0.125)       # #f0a020
const COL_SELECTED_B := Color(0.973, 0.784, 0.251)       # #f8c840
const COL_DESC_BORDER := Color(0.235, 0.392, 0.549, 0.85)

const CLASS_FLAVOR := {
	"humar": "Balanced human Hunter. Strong ATP, decent EVP, no techs.",
	"humarl": "Female human Hunter. Mid-ATP melee with some support utility.",
	"hunewearl": "Newman Hunter. Trades raw ATP for higher EVP and basic techs.",
	"hucast": "Cast Hunter. Highest HP and ATP, immune to status, no techs.",
	"hucaseal": "Female Cast Hunter. ATA-leaning Cast variant, no techs.",
	"ramar": "Human Ranger. Solid all-rounder with mid-tier techs.",
	"ramarl": "Female human Ranger. Higher MST than RAmar, basic support techs.",
	"racast": "Cast Ranger. Trap specialist, immune to status, no techs.",
	"racaseal": "Female Cast Ranger. ATA-leaning, traps, no techs.",
	"fomar": "Male Force. Balanced caster, ATP+ over FOnewearl.",
	"fomarl": "Female human Force. Highest ATA caster.",
	"fonewm": "Male Newman Force. Stronger tech multipliers than human Forces.",
	"fonewearl": "Newman Force. Highest tech multiplier in the game; fragile.",
}

var _current_slot: int = 0
var _confirming_delete: bool = false

# Cached node refs (rebuilt only when necessary)
var _list_vbox: VBoxContainer
var _list_scroll: ScrollContainer
var _row_panels: Array[PanelContainer] = []
var _hint_label: Label
var _desc_label: Label
var _preview_viewport: SubViewport
var _preview_root: Node3D = null


# --- Inner Banner Control: draws the 6-vertex polygon + outline ---

class BannerPolygon extends Control:
	var fill_color: Color = Color(0.984, 0.729, 0.094)
	var outline_color: Color = Color(0.102, 0.102, 0.165)
	var outline_width: float = 2.0

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# Same shape as the CSS clip-path in MenuDesign.tsx:
		#   polygon(0 0, 100% 0, 100% 58%, 49% 58%, 44% 100%, 0 100%)
		var pts := PackedVector2Array([
			Vector2(0, 0),
			Vector2(w, 0),
			Vector2(w, h * 0.58),
			Vector2(w * 0.49, h * 0.58),
			Vector2(w * 0.44, h),
			Vector2(0, h),
		])
		draw_colored_polygon(pts, fill_color)
		var loop := PackedVector2Array(pts)
		loop.append(pts[0])
		draw_polyline(loop, outline_color, outline_width, true)


func _ready() -> void:
	MusicManager.play_location_music("character_select")

	# Drop tscn placeholders, build everything programmatically.
	for child in get_children():
		child.queue_free()

	# Anchors fill the viewport, but everything inside is placed against
	# a fixed 1280x720 frame (matches project.godot viewport size).
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_build_background()
	_build_banner()
	_build_divider()
	_build_list()
	_build_preview()
	_build_description()
	_build_next_button()
	_build_hint_bar()

	_refresh_selection()


# --- Layout builders ---

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var bg_path := "res://assets/ui/character_select/character_select_bg.png"
	if ResourceLoader.exists(bg_path):
		var tex := load(bg_path) as Texture2D
		if tex:
			var img := TextureRect.new()
			img.texture = tex
			img.set_anchors_preset(Control.PRESET_FULL_RECT)
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			add_child(img)


func _build_banner() -> void:
	var banner := BannerPolygon.new()
	banner.position = Vector2(0, 22)
	banner.size = Vector2(FRAME_W, 84)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)

	var title := Label.new()
	title.text = "CHARACTER SELECT"
	title.position = Vector2(36, 34)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COL_BANNER_OUTLINE)
	title.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.35))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	add_child(title)


func _build_divider() -> void:
	var line := ColorRect.new()
	line.color = Color.WHITE
	line.position = Vector2(0, 131)
	line.size = Vector2(FRAME_W, 3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)


func _build_list() -> void:
	# Outer panel mimics the <Panel title="Characters (X/N)"> wrapper.
	var panel := _make_panel(Vector2(200, 180), Vector2(400, 450), "Characters (%d/%d)" % [
		_filled_count(), SLOT_COUNT
	])
	add_child(panel)

	var body: Control = panel.get_meta("body")

	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_list_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", 4)
	_list_scroll.add_child(_list_vbox)

	_row_panels.clear()
	for i in range(SLOT_COUNT):
		var row := _build_row(i)
		_list_vbox.add_child(row)
		_row_panels.append(row)


func _build_row(index: int) -> PanelContainer:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 38)
	row.set_meta("slot_index", index)
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if _current_slot != index:
				_current_slot = index
				SfxManager.play("res://assets/sfx/ui/menu_move.wav")
				_refresh_selection()
	)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var character = CharacterManager.get_character(index)
	var name_label := Label.new()
	var right_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_label.add_theme_font_size_override("font_size", 15)
	right_label.add_theme_font_size_override("font_size", 13)

	if character != null:
		var class_id: String = str(character.get("class_id", ""))
		var class_data = ClassRegistry.get_class_data(class_id)
		var class_name_str: String = class_data.name if class_data else class_id.capitalize()
		name_label.text = "%s  ·  %s  ·  Lv.%d" % [
			str(character.get("name", "???")),
			class_name_str,
			int(character.get("level", 1)),
		]
		right_label.text = "%d M" % int(character.get("meseta", 0))
	else:
		name_label.text = "(Empty Slot)"
		right_label.text = ""

	# Pad inside the row.
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	hbox.add_child(margin)
	var inner := HBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	margin.add_child(inner)
	inner.add_child(name_label)
	inner.add_child(right_label)

	# Set initial style; _refresh_selection() will keep this in sync.
	row.add_theme_stylebox_override("panel", _row_style(false))
	return row


func _row_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if _confirming_delete and selected:
		s.bg_color = Color(0.85, 0.25, 0.25)
		s.border_color = Color(0.7, 0.15, 0.15)
		s.set_border_width_all(2)
	elif selected:
		# Mock uses a left-to-right gradient; StyleBoxFlat is solid only,
		# so approximate with the warmer mid-tone.
		s.bg_color = COL_SELECTED_A
		s.border_color = Color(0.65, 0.42, 0.08)
		s.set_border_width_all(1)
	else:
		s.bg_color = COL_ROW_BG
		s.border_color = Color(0.6, 0.7, 0.8, 0.6)
		s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	return s


func _build_preview() -> void:
	# 400x430 anchored container starting at (680, 180). No title bar —
	# matches the post-strip mock so the model floats over the bg.
	var holder := Control.new()
	holder.position = Vector2(680, 180)
	holder.size = Vector2(400, 430)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	var sub_container := SubViewportContainer.new()
	sub_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub_container.stretch = true
	sub_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(sub_container)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 430)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_container.add_child(viewport)
	_preview_viewport = viewport

	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.1, 3.4)
	camera.look_at_from_position(Vector3(0, 1.1, 3.4), Vector3(0, 1.0, 0), Vector3.UP)
	camera.fov = 35
	viewport.add_child(camera)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-30, 35, 0)
	key_light.light_energy = 0.85
	viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-15, -120, 0)
	fill_light.light_energy = 0.4
	viewport.add_child(fill_light)

	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 0.85
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)


func _build_description() -> void:
	var holder := Control.new()
	holder.position = Vector2(670, 520)
	holder.size = Vector2(430, 90)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var s := StyleBoxFlat.new()
	s.bg_color = COL_BG_LIGHT
	s.border_color = COL_DESC_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 2)
	s.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", s)
	holder.add_child(panel)

	_desc_label = Label.new()
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.add_theme_font_size_override("font_size", 13)
	_desc_label.add_theme_color_override("font_color", COL_TEXT)
	_desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	panel.add_child(_desc_label)


func _build_next_button() -> void:
	var btn := Button.new()
	btn.size = Vector2(240, 60)
	btn.position = Vector2(FRAME_W - 240 - 20, FRAME_H - 60 - 20)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", COL_TEXT)
	btn.pressed.connect(_select_slot)

	var s_normal := StyleBoxFlat.new()
	s_normal.bg_color = COL_SELECTED_A
	s_normal.border_color = Color(0, 0, 0, 0.25)
	s_normal.set_border_width_all(1)
	s_normal.set_corner_radius_all(6)
	s_normal.shadow_color = Color(0, 0, 0, 0.3)
	s_normal.shadow_size = 6
	s_normal.shadow_offset = Vector2(0, 3)
	btn.add_theme_stylebox_override("normal", s_normal)

	var s_hover := s_normal.duplicate() as StyleBoxFlat
	s_hover.bg_color = COL_SELECTED_B
	btn.add_theme_stylebox_override("hover", s_hover)

	var s_pressed := s_normal.duplicate() as StyleBoxFlat
	s_pressed.bg_color = Color(0.85, 0.55, 0.10)
	btn.add_theme_stylebox_override("pressed", s_pressed)

	btn.text = "Start"
	add_child(btn)
	# Stash the button so we can update its text on selection change.
	set_meta("next_button", btn)


func _build_hint_bar() -> void:
	_hint_label = Label.new()
	_hint_label.text = "↑/↓ Navigate    A Confirm    B Back    Del Remove"
	_hint_label.position = Vector2(0, FRAME_H - 28)
	_hint_label.size = Vector2(FRAME_W, 24)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", COL_TEXT_WHITE)
	_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_hint_label)


# --- Panel helper (mirrors web Panel component) ---

func _make_panel(pos: Vector2, sz: Vector2, title: String) -> Control:
	var holder := Control.new()
	holder.position = pos
	holder.size = sz

	var title_h := 32
	# Title strip with diagonal-cut accent.
	var title_strip := PanelContainer.new()
	title_strip.position = Vector2(0, 0)
	title_strip.size = Vector2(sz.x, title_h)
	var title_style := StyleBoxFlat.new()
	title_style.bg_color = COL_BG_DARK
	title_style.set_corner_radius_all(0)
	title_strip.add_theme_stylebox_override("panel", title_style)
	holder.add_child(title_strip)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", COL_TEXT_WHITE)
	title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title_label.add_theme_constant_override("shadow_offset_x", 1)
	title_label.add_theme_constant_override("shadow_offset_y", 1)
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 14)
	title_margin.add_theme_constant_override("margin_top", 6)
	title_margin.add_theme_constant_override("margin_bottom", 6)
	title_margin.add_child(title_label)
	title_strip.add_child(title_margin)

	# Body — pale icy blue with a thin top border.
	var body_panel := PanelContainer.new()
	body_panel.position = Vector2(0, title_h)
	body_panel.size = Vector2(sz.x, sz.y - title_h)
	var body_style := StyleBoxFlat.new()
	body_style.bg_color = COL_BG_LIGHT
	body_style.border_color = COL_BG_DARK
	body_style.border_width_top = 2
	body_style.border_width_bottom = 2
	body_style.set_content_margin_all(8)
	body_panel.add_theme_stylebox_override("panel", body_style)
	holder.add_child(body_panel)

	holder.set_meta("body", body_panel)
	return holder


# --- Selection / refresh ---

func _refresh_selection() -> void:
	for i in range(_row_panels.size()):
		var row: PanelContainer = _row_panels[i]
		row.add_theme_stylebox_override("panel", _row_style(i == _current_slot))

	# Scroll selected row into view.
	if _list_scroll and _row_panels.size() > _current_slot:
		_list_scroll.ensure_control_visible(_row_panels[_current_slot])

	# Update preview model.
	_update_preview()

	# Update description.
	if _desc_label:
		var character = CharacterManager.get_character(_current_slot)
		if character != null:
			var class_id: String = str(character.get("class_id", ""))
			_desc_label.text = CLASS_FLAVOR.get(class_id, "Class flavor text TBD.")
		else:
			_desc_label.text = "No character in this slot yet — confirm to create one."

	# Update Next button label.
	var btn: Button = get_meta("next_button") as Button
	if btn:
		btn.text = "Start" if CharacterManager.get_character(_current_slot) != null else "Create"

	# Update hint bar.
	if _hint_label:
		if _confirming_delete:
			_hint_label.text = "Delete this character? This cannot be undone.    A Yes    B No"
			_hint_label.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
		else:
			_hint_label.text = "↑/↓ Navigate    A Confirm    B Back    Del Remove"
			_hint_label.add_theme_color_override("font_color", COL_TEXT_WHITE)


func _update_preview() -> void:
	if _preview_viewport == null:
		return
	# Drop previous model.
	if _preview_root != null and is_instance_valid(_preview_root):
		_preview_root.queue_free()
		_preview_root = null

	var character = CharacterManager.get_character(_current_slot)
	if character == null:
		return

	var paths: Dictionary = PlayerConfig.get_paths_for_character(character)
	var model_path: String = paths["model_path"]
	var texture_path: String = paths["texture_path"]
	if not ResourceLoader.exists(model_path):
		return
	var packed: PackedScene = load(model_path) as PackedScene
	if packed == null:
		return
	var model_node := packed.instantiate() as Node3D
	if model_node == null:
		return
	model_node.position = Vector3.ZERO
	_preview_viewport.add_child(model_node)
	_preview_root = model_node
	if ResourceLoader.exists(texture_path):
		var tex := load(texture_path) as Texture2D
		if tex:
			_apply_texture_recursive(model_node, tex)


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


func _filled_count() -> int:
	var n := 0
	for i in range(SLOT_COUNT):
		if CharacterManager.get_character(i) != null:
			n += 1
	return n


# --- Input handling ---

func _unhandled_input(event: InputEvent) -> void:
	if _confirming_delete:
		if event.is_action_pressed("ui_accept"):
			CharacterManager.delete_character(_current_slot)
			SaveManager.save_game()
			_confirming_delete = false
			_rebuild_list()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel"):
			_confirming_delete = false
			_refresh_selection()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_up"):
		_current_slot = wrapi(_current_slot - 1, 0, SLOT_COUNT)
		SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		_refresh_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_current_slot = wrapi(_current_slot + 1, 0, SLOT_COUNT)
		SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		_refresh_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		SfxManager.play("res://assets/sfx/ui/menu_select.wav")
		_select_slot()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		SfxManager.play("res://assets/sfx/ui/menu_back.wav")
		SceneManager.goto_scene("res://scenes/2d/title.tscn")
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_DELETE:
		_delete_slot()
		get_viewport().set_input_as_handled()


func _rebuild_list() -> void:
	if _list_vbox == null:
		return
	for child in _list_vbox.get_children():
		child.queue_free()
	_row_panels.clear()
	for i in range(SLOT_COUNT):
		var row := _build_row(i)
		_list_vbox.add_child(row)
		_row_panels.append(row)
	_refresh_selection()


func _select_slot() -> void:
	var character = CharacterManager.get_character(_current_slot)
	if character != null:
		CharacterManager.set_active_slot(_current_slot)
		SceneManager.goto_scene("res://scenes/3d/city/city_market.tscn")
	else:
		SceneManager.goto_scene("res://scenes/2d/character_create.tscn", {"slot": _current_slot})


func _delete_slot() -> void:
	if CharacterManager.get_character(_current_slot) == null:
		return
	_confirming_delete = true
	_refresh_selection()

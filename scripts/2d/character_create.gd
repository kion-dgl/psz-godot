extends Node3D
## Character creation screen — PSZ-themed design with Gamecube-style class select,
## appearance customization with 3D preview, name entry, and confirmation.
## All UI is built programmatically on a CanvasLayer overlay.

enum Step { CLASS_SELECT, APPEARANCE, NAME_ENTRY, CONFIRM }

# ── PSZ Theme Colors ────────────────────────────────────────────
const C_BG := Color(0.66, 0.78, 0.88)                     # light blue background
const C_TITLE_TOP := Color(0.78, 0.80, 0.84)              # metallic bar top
const C_TITLE_BOT := Color(0.55, 0.58, 0.62)              # metallic bar bottom
const C_CREAM := Color(0.88, 0.90, 0.94)                  # list item bg
const C_CREAM_HOVER := Color(0.92, 0.94, 0.97)            # hovered list item
const C_ORANGE := Color(0.94, 0.66, 0.18)                 # selected highlight
const C_DARK := Color(0.15, 0.20, 0.25)                   # dark text
const C_DARK_MUTED := Color(0.30, 0.35, 0.42)             # muted text
const C_WHITE := Color(1.0, 1.0, 1.0)                     # white text
const C_GREEN_ARROW := Color(0.20, 0.55, 0.25)            # appearance arrows
const C_TYPE_HUNTER := Color(0.9, 0.35, 0.35)             # red sidebar
const C_TYPE_RANGER := Color(0.3, 0.75, 0.35)             # green sidebar
const C_TYPE_FORCE := Color(0.35, 0.5, 0.9)               # blue sidebar
const C_PANEL_BORDER := Color(0.50, 0.55, 0.62, 0.6)      # subtle border

# ── State ───────────────────────────────────────────────────────
var _step: int = Step.CLASS_SELECT
var _slot: int = 0
var _class_list: Array = []                  # sorted ClassData array
var _selected_class_index: int = 0
var _selected_class_id: String = ""
var _char_name: String = ""
var _hovered_type_index: int = 0             # which type group (0=Hunter,1=Ranger,2=Force)

var _appearance_row: int = 0                 # 0=head, 1=hair/bodyA, 2=costume/bodyB, 3=skin/bodyC
var _appearance := {
	"variation_index": 0,
	"body_color_index": 0,
	"hair_color_index": 0,
	"skin_tone_index": 0,
}

# Classes grouped by type for the sidebar
var _type_groups: Array = []                 # [{type, color, classes: [{index, data}]}]

# 3D preview state
var _preview_model: Node3D = null
var _preview_pivot: Node3D = null
var _preview_nodes: Array = []
var _preview_active := false

# UI references (built in _ready)
var _canvas_layer: CanvasLayer
var _root_control: Control
var _bg_rect: ColorRect
var _title_bar: PanelContainer
var _title_label: Label
var _content_area: Control
var _hint_bar: PanelContainer
var _hint_label: Label

# Cached class art textures
var _class_art_cache: Dictionary = {}

# Class art filename overrides (some IDs don't match image names)
const CLASS_ART_OVERRIDES := {
	"hucaseal": "hucasteal",
	"racaseal": "racasteal",
}


func _ready() -> void:
	_slot = SceneManager.get_transition_data().get("slot", 0)
	_load_classes()
	_build_ui()
	_show_class_select()


# ── Class Loading & Sorting ─────────────────────────────────────

func _load_classes() -> void:
	_class_list = ClassRegistry.get_all_classes()
	var type_order := {"Hunter": 0, "Ranger": 1, "Force": 2}
	var gender_order := {"Male": 0, "Female": 1}
	var race_order := {"Human": 0, "Newman": 1, "Cast": 2}
	_class_list.sort_custom(func(a, b):
		var ta: int = type_order.get(a.type, 9)
		var tb: int = type_order.get(b.type, 9)
		if ta != tb: return ta < tb
		var ra: int = race_order.get(a.race, 9)
		var rb: int = race_order.get(b.race, 9)
		if ra != rb: return ra < rb
		var ga: int = gender_order.get(a.gender, 9)
		var gb: int = gender_order.get(b.gender, 9)
		return ga < gb
	)

	# Build type groups for sidebar
	_type_groups.clear()
	var type_colors := {"Hunter": C_TYPE_HUNTER, "Ranger": C_TYPE_RANGER, "Force": C_TYPE_FORCE}
	var current_type := ""
	var current_group: Dictionary = {}
	for i in range(_class_list.size()):
		var cls = _class_list[i]
		if cls.type != current_type:
			if not current_type.is_empty():
				_type_groups.append(current_group)
			current_type = cls.type
			current_group = {
				"type": current_type,
				"color": type_colors.get(current_type, C_DARK),
				"classes": [],
			}
		current_group["classes"].append({"index": i, "data": cls})
	if not current_type.is_empty():
		_type_groups.append(current_group)

	# Preload class art textures
	for cls in _class_list:
		var art_name: String = CLASS_ART_OVERRIDES.get(cls.id, cls.id)
		var art_path := "res://assets/images/%s.png" % art_name
		if ResourceLoader.exists(art_path):
			_class_art_cache[cls.id] = load(art_path) as Texture2D


func _is_cast_class() -> bool:
	if _class_list.is_empty():
		return false
	return _class_list[_selected_class_index].race == "Cast"


func _get_type_color(type_name: String) -> Color:
	match type_name:
		"Hunter": return C_TYPE_HUNTER
		"Ranger": return C_TYPE_RANGER
		"Force": return C_TYPE_FORCE
	return C_DARK


# ── UI Construction ─────────────────────────────────────────────

func _build_ui() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 10
	add_child(_canvas_layer)

	_root_control = Control.new()
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas_layer.add_child(_root_control)

	# Background
	_bg_rect = ColorRect.new()
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.color = C_BG
	_root_control.add_child(_bg_rect)

	# Main vertical layout
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 0)
	margin.add_theme_constant_override("margin_right", 0)
	margin.add_theme_constant_override("margin_top", 0)
	margin.add_theme_constant_override("margin_bottom", 0)
	_root_control.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 0)
	margin.add_child(vbox)

	# Title bar — metallic gradient
	_title_bar = PanelContainer.new()
	_title_bar.custom_minimum_size = Vector2(0, 48)
	var title_style := StyleBoxFlat.new()
	title_style.bg_color = C_TITLE_BOT
	title_style.content_margin_left = 20
	title_style.content_margin_right = 20
	title_style.border_width_bottom = 2
	title_style.border_color = Color(0.40, 0.44, 0.50, 0.8)
	_title_bar.add_theme_stylebox_override("panel", title_style)
	vbox.add_child(_title_bar)

	_title_label = Label.new()
	_title_label.text = "CHARACTER CREATION"
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", C_WHITE)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_bar.add_child(_title_label)

	# Content area — fills the middle
	_content_area = Control.new()
	_content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_content_area)

	# Hint bar at the bottom
	_hint_bar = PanelContainer.new()
	_hint_bar.custom_minimum_size = Vector2(0, 36)
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color(0.50, 0.55, 0.62, 0.85)
	hint_style.content_margin_left = 20
	hint_style.content_margin_right = 20
	hint_style.border_width_top = 1
	hint_style.border_color = Color(0.40, 0.44, 0.50, 0.6)
	_hint_bar.add_theme_stylebox_override("panel", hint_style)
	vbox.add_child(_hint_bar)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", C_WHITE)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_bar.add_child(_hint_label)


func _clear_content() -> void:
	for child in _content_area.get_children():
		child.queue_free()


func _make_stylebox(color: Color, radius: int = 6, margins: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	if margins > 0:
		sb.content_margin_left = margins
		sb.content_margin_right = margins
		sb.content_margin_top = margins
		sb.content_margin_bottom = margins
	return sb


func _make_bordered_stylebox(color: Color, border_color: Color, border_width: int = 1, radius: int = 6, margins: int = 8) -> StyleBoxFlat:
	var sb := _make_stylebox(color, radius, margins)
	sb.border_width_left = border_width
	sb.border_width_right = border_width
	sb.border_width_top = border_width
	sb.border_width_bottom = border_width
	sb.border_color = border_color
	return sb


# ── Input Handling ──────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	match _step:
		Step.CLASS_SELECT:
			_handle_class_select_input(event)
		Step.APPEARANCE:
			_handle_appearance_input(event)
		Step.NAME_ENTRY:
			_handle_name_entry_input(event)
		Step.CONFIRM:
			_handle_confirm_input(event)


func _handle_class_select_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_selected_class_index = wrapi(_selected_class_index - 1, 0, _class_list.size())
		_sync_type_from_class()
		_update_class_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_class_index = wrapi(_selected_class_index + 1, 0, _class_list.size())
		_sync_type_from_class()
		_update_class_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_selected_class_id = _class_list[_selected_class_index].id
		_appearance = {"variation_index": 0, "body_color_index": 0, "hair_color_index": 0, "skin_tone_index": 0}
		_appearance_row = 0
		_show_appearance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		SceneManager.goto_scene("res://scenes/2d/character_select.tscn")
		get_viewport().set_input_as_handled()


func _handle_appearance_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_appearance_row = wrapi(_appearance_row - 1, 0, 4)
		_update_appearance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_appearance_row = wrapi(_appearance_row + 1, 0, 4)
		_update_appearance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") and not Input.is_action_pressed("camera_lock"):
		_cycle_appearance_value(-1)
		_update_appearance()
		_update_preview_model()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") and not Input.is_action_pressed("camera_lock"):
		_cycle_appearance_value(1)
		_update_appearance()
		_update_preview_model()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not Input.is_action_pressed("camera_lock"):
		_teardown_preview()
		_show_name_entry()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_teardown_preview()
		_show_class_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_lock"):
		get_viewport().set_input_as_handled()


func _cycle_appearance_value(direction: int) -> void:
	match _appearance_row:
		0:
			_appearance["variation_index"] = wrapi(
				int(_appearance["variation_index"]) + direction, 0, PlayerConfig.HEAD_VARIATIONS)
		1:
			_appearance["hair_color_index"] = wrapi(
				int(_appearance["hair_color_index"]) + direction, 0, PlayerConfig.HAIR_COLORS.size())
		2:
			_appearance["body_color_index"] = wrapi(
				int(_appearance["body_color_index"]) + direction, 0, PlayerConfig.BODY_COLORS.size())
		3:
			_appearance["skin_tone_index"] = wrapi(
				int(_appearance["skin_tone_index"]) + direction, 0, PlayerConfig.SKIN_TONES.size())


func _handle_name_entry_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_show_appearance()
		get_viewport().set_input_as_handled()


func _handle_confirm_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_create_character()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_show_name_entry()
		get_viewport().set_input_as_handled()


# ── Step 1: CLASS SELECT (Gamecube style) ───────────────────────

func _sync_type_from_class() -> void:
	var cls = _class_list[_selected_class_index]
	for gi in range(_type_groups.size()):
		if _type_groups[gi]["type"] == cls.type:
			_hovered_type_index = gi
			break


func _show_class_select() -> void:
	_step = Step.CLASS_SELECT
	_title_label.text = "SELECT CLASS"
	_hint_label.text = "Up/Down: Select    Confirm: Choose    Cancel: Back"
	_sync_type_from_class()
	_update_class_select()


func _update_class_select() -> void:
	_clear_content()

	# We need to wait a frame for _content_area to have its size
	await get_tree().process_frame
	var area_size: Vector2 = _content_area.size

	# Main horizontal split: left sidebar (~280px) | right panel (rest)
	var left_width: float = 280.0
	var padding: float = 12.0

	# ── Left Panel: Type sidebar with class rows ──
	var left_panel := Panel.new()
	left_panel.position = Vector2(padding, padding)
	left_panel.size = Vector2(left_width, area_size.y - padding * 2)
	left_panel.add_theme_stylebox_override("panel",
		_make_bordered_stylebox(Color(0.82, 0.84, 0.88, 0.95), C_PANEL_BORDER, 1, 8, 0))
	_content_area.add_child(left_panel)

	# Build sidebar rows — proportional height based on class count
	var y_offset: float = 0.0
	var total_classes := _class_list.size()  # 14
	var separator_total: float = (_type_groups.size() - 1) * 2.0
	var available_height: float = area_size.y - padding * 2 - separator_total

	for gi in range(_type_groups.size()):
		var group: Dictionary = _type_groups[gi]
		var group_classes: Array = group["classes"]
		var type_color: Color = group["color"]
		var type_name: String = group["type"]
		var group_height: float = (float(group_classes.size()) / float(total_classes)) * available_height

		# Type color stripe on the left
		var stripe := ColorRect.new()
		stripe.position = Vector2(0, y_offset)
		stripe.size = Vector2(8, group_height)
		stripe.color = type_color
		left_panel.add_child(stripe)

		# No separate type label — the stripe color indicates the type

		# Class rows within this type
		var row_h: float = group_height / float(group_classes.size())
		for ci in range(group_classes.size()):
			var entry: Dictionary = group_classes[ci]
			var cls_data = entry["data"]
			var cls_index: int = entry["index"]
			var is_selected := (cls_index == _selected_class_index)

			var row_y: float = y_offset + ci * row_h

			# Row background
			var row_bg := ColorRect.new()
			row_bg.position = Vector2(8, row_y)
			row_bg.size = Vector2(left_width - 8, row_h)
			if is_selected:
				row_bg.color = C_ORANGE
			elif ci % 2 == 0:
				row_bg.color = C_CREAM
			else:
				row_bg.color = C_CREAM_HOVER
			left_panel.add_child(row_bg)

			# Class name (no thumbnail)
			var name_lbl := Label.new()
			name_lbl.text = cls_data.name
			name_lbl.add_theme_font_size_override("font_size", 15)
			if is_selected:
				name_lbl.add_theme_color_override("font_color", C_WHITE)
			else:
				name_lbl.add_theme_color_override("font_color", C_DARK)
			name_lbl.position = Vector2(16, row_y + (row_h - 20) * 0.5)
			name_lbl.size = Vector2(left_width - 30, 20)
			left_panel.add_child(name_lbl)

		y_offset += group_height

		# Separator between type groups (except last)
		if gi < _type_groups.size() - 1:
			var sep := ColorRect.new()
			sep.position = Vector2(0, y_offset)
			sep.size = Vector2(left_width, 2)
			sep.color = C_PANEL_BORDER
			left_panel.add_child(sep)
			y_offset += 2

	# ── Right Panel: Class art gallery + info ──
	var right_x: float = left_width + padding * 2
	var right_width: float = area_size.x - right_x - padding
	var right_height: float = area_size.y - padding * 2

	var right_panel := Panel.new()
	right_panel.position = Vector2(right_x, padding)
	right_panel.size = Vector2(right_width, right_height)
	right_panel.add_theme_stylebox_override("panel",
		_make_bordered_stylebox(Color(0.75, 0.80, 0.86, 0.6), C_PANEL_BORDER, 1, 8, 0))
	_content_area.add_child(right_panel)

	# Show classes in the selected type group as art images spread horizontally
	var current_group: Dictionary = _type_groups[_hovered_type_index]
	var group_classes: Array = current_group["classes"]

	# Art gallery area (upper portion of right panel)
	var gallery_height: float = right_height - 100.0  # reserve 100px for info box
	var art_max_height: float = gallery_height - 20.0
	var art_width: float = minf(right_width / maxf(group_classes.size(), 1) - 8.0, 200.0)

	var total_art_width: float = group_classes.size() * (art_width + 8.0) - 8.0
	var gallery_start_x: float = maxf((right_width - total_art_width) / 2.0, 4.0)

	for ci in range(group_classes.size()):
		var entry: Dictionary = group_classes[ci]
		var cls_data = entry["data"]
		var cls_index: int = entry["index"]
		var is_selected := (cls_index == _selected_class_index)

		if _class_art_cache.has(cls_data.id):
			var art := TextureRect.new()
			art.texture = _class_art_cache[cls_data.id]
			art.position = Vector2(gallery_start_x + ci * (art_width + 8.0), 10.0)
			art.size = Vector2(art_width, art_max_height)
			art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

			if is_selected:
				art.modulate = Color(1.0, 1.0, 1.0, 1.0)
			else:
				art.modulate = Color(0.6, 0.6, 0.6, 0.45)

			right_panel.add_child(art)

			# Selected indicator — orange underline
			if is_selected:
				var underline := ColorRect.new()
				underline.position = Vector2(gallery_start_x + ci * (art_width + 8.0), art_max_height + 12.0)
				underline.size = Vector2(art_width, 3)
				underline.color = C_ORANGE
				right_panel.add_child(underline)

	# ── Info box at bottom of right panel ──
	var info_y: float = gallery_height
	var info_panel := Panel.new()
	info_panel.position = Vector2(10, info_y)
	info_panel.size = Vector2(right_width - 20, 90)
	info_panel.add_theme_stylebox_override("panel",
		_make_bordered_stylebox(Color(0.85, 0.87, 0.92, 0.95), C_PANEL_BORDER, 1, 6, 12))
	right_panel.add_child(info_panel)

	var cls = _class_list[_selected_class_index]

	# Class name (large)
	var cls_name := Label.new()
	cls_name.text = cls.name
	cls_name.add_theme_font_size_override("font_size", 22)
	cls_name.add_theme_color_override("font_color", _get_type_color(cls.type))
	cls_name.position = Vector2(12, 4)
	cls_name.size = Vector2(right_width - 44, 28)
	info_panel.add_child(cls_name)

	# Race / Gender / Type
	var cls_desc := Label.new()
	cls_desc.text = "%s %s  -  %s" % [cls.race, cls.gender, cls.type]
	cls_desc.add_theme_font_size_override("font_size", 14)
	cls_desc.add_theme_color_override("font_color", C_DARK_MUTED)
	cls_desc.position = Vector2(12, 34)
	cls_desc.size = Vector2(right_width - 44, 18)
	info_panel.add_child(cls_desc)

	# Stats preview (compact one-line)
	var stats: Dictionary = cls.get_stats_at_level(1)
	var stat_text := "HP:%d  PP:%d  ATK:%d  DEF:%d  ACC:%d  EVA:%d  TEC:%d" % [
		stats.get("hp", 0), stats.get("pp", 0), stats.get("attack", 0),
		stats.get("defense", 0), stats.get("accuracy", 0), stats.get("evasion", 0),
		stats.get("technique", 0)]
	var stat_lbl := Label.new()
	stat_lbl.text = stat_text
	stat_lbl.add_theme_font_size_override("font_size", 12)
	stat_lbl.add_theme_color_override("font_color", C_DARK_MUTED)
	stat_lbl.position = Vector2(12, 56)
	stat_lbl.size = Vector2(right_width - 44, 16)
	info_panel.add_child(stat_lbl)


# ── Step 2: APPEARANCE ──────────────────────────────────────────

func _show_appearance() -> void:
	_step = Step.APPEARANCE
	_title_label.text = "CUSTOMIZE APPEARANCE"
	_hint_label.text = "Up/Down: Row    Left/Right: Change    Tab+L/R: Rotate    Confirm: Next    Cancel: Back"

	# Hide background so 3D preview shows through
	_bg_rect.visible = false

	if not _preview_active:
		_build_preview_scene()

	_update_appearance()
	_update_preview_model()


func _update_appearance() -> void:
	_clear_content()

	await get_tree().process_frame
	var area_size: Vector2 = _content_area.size

	# Left panel for appearance options (~300px)
	var panel_width: float = 300.0
	var panel_height: float = 280.0
	var panel_x: float = 16.0
	var panel_y: float = (area_size.y - panel_height) / 2.0

	var panel_bg := Panel.new()
	panel_bg.position = Vector2(panel_x, panel_y)
	panel_bg.size = Vector2(panel_width, panel_height)
	panel_bg.add_theme_stylebox_override("panel",
		_make_bordered_stylebox(Color(0.82, 0.84, 0.88, 0.92), C_PANEL_BORDER, 1, 8, 0))
	_content_area.add_child(panel_bg)

	# Header inside panel
	var header_bar := ColorRect.new()
	header_bar.position = Vector2(0, 0)
	header_bar.size = Vector2(panel_width, 36)
	header_bar.color = C_TITLE_BOT
	panel_bg.add_child(header_bar)

	var header_lbl := Label.new()
	header_lbl.text = "  APPEARANCE"
	header_lbl.add_theme_font_size_override("font_size", 14)
	header_lbl.add_theme_color_override("font_color", C_WHITE)
	header_lbl.position = Vector2(0, 0)
	header_lbl.size = Vector2(panel_width, 36)
	header_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel_bg.add_child(header_lbl)

	var is_cast := _is_cast_class()

	# Row definitions: [label, current_value, max_count]
	var rows: Array = []
	if is_cast:
		rows = [
			["Head Parts", int(_appearance["variation_index"]) + 1, PlayerConfig.HEAD_VARIATIONS],
			["Body Color A", int(_appearance["hair_color_index"]) + 1, PlayerConfig.HAIR_COLORS.size()],
			["Body Color B", int(_appearance["body_color_index"]) + 1, PlayerConfig.BODY_COLORS.size()],
			["Body Color C", int(_appearance["skin_tone_index"]) + 1, PlayerConfig.SKIN_TONES.size()],
		]
	else:
		rows = [
			["Head Type", int(_appearance["variation_index"]) + 1, PlayerConfig.HEAD_VARIATIONS],
			["Hair Color", int(_appearance["hair_color_index"]) + 1, PlayerConfig.HAIR_COLORS.size()],
			["Costume Color", int(_appearance["body_color_index"]) + 1, PlayerConfig.BODY_COLORS.size()],
			["Skin Tone", int(_appearance["skin_tone_index"]) + 1, PlayerConfig.SKIN_TONES.size()],
		]

	var row_start_y: float = 44.0
	var row_height: float = 48.0

	for i in range(rows.size()):
		var row_data: Array = rows[i]
		var row_label_text: String = row_data[0]
		var current_val: int = row_data[1]
		var max_val: int = row_data[2]
		var is_selected := (i == _appearance_row)
		var ry: float = row_start_y + i * row_height

		# Row background
		var row_bg := ColorRect.new()
		row_bg.position = Vector2(4, ry)
		row_bg.size = Vector2(panel_width - 8, row_height - 4)
		if is_selected:
			row_bg.color = C_ORANGE
		else:
			row_bg.color = C_CREAM
		panel_bg.add_child(row_bg)

		# Row label
		var lbl := Label.new()
		lbl.text = row_label_text
		lbl.add_theme_font_size_override("font_size", 14)
		if is_selected:
			lbl.add_theme_color_override("font_color", C_WHITE)
		else:
			lbl.add_theme_color_override("font_color", C_DARK)
		lbl.position = Vector2(16, ry + 6)
		lbl.size = Vector2(panel_width - 32, 18)
		panel_bg.add_child(lbl)

		# Value row with arrows: "< 2/4 >"
		var arrow_y: float = ry + 24
		var counter_text := "%d/%d" % [current_val, max_val]

		# Left arrow
		var left_arrow := Label.new()
		if is_selected:
			left_arrow.text = "<"
			left_arrow.add_theme_color_override("font_color", C_WHITE)
		else:
			left_arrow.text = "<"
			left_arrow.add_theme_color_override("font_color", C_GREEN_ARROW)
		left_arrow.add_theme_font_size_override("font_size", 16)
		left_arrow.position = Vector2(panel_width - 100, arrow_y - 3)
		left_arrow.size = Vector2(20, 20)
		left_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel_bg.add_child(left_arrow)

		# Counter
		var counter := Label.new()
		counter.text = counter_text
		counter.add_theme_font_size_override("font_size", 14)
		if is_selected:
			counter.add_theme_color_override("font_color", C_WHITE)
		else:
			counter.add_theme_color_override("font_color", C_DARK)
		counter.position = Vector2(panel_width - 78, arrow_y)
		counter.size = Vector2(46, 18)
		counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel_bg.add_child(counter)

		# Right arrow
		var right_arrow := Label.new()
		if is_selected:
			right_arrow.text = ">"
			right_arrow.add_theme_color_override("font_color", C_WHITE)
		else:
			right_arrow.text = ">"
			right_arrow.add_theme_color_override("font_color", C_GREEN_ARROW)
		right_arrow.add_theme_font_size_override("font_size", 16)
		right_arrow.position = Vector2(panel_width - 30, arrow_y - 3)
		right_arrow.size = Vector2(20, 20)
		right_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel_bg.add_child(right_arrow)

	# Class name at bottom of panel
	var cls = _class_list[_selected_class_index]
	var cls_lbl := Label.new()
	cls_lbl.text = cls.name
	cls_lbl.add_theme_font_size_override("font_size", 16)
	cls_lbl.add_theme_color_override("font_color", _get_type_color(cls.type))
	cls_lbl.position = Vector2(12, panel_height - 32)
	cls_lbl.size = Vector2(panel_width - 24, 24)
	cls_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_bg.add_child(cls_lbl)


# ── Step 3: NAME ENTRY ──────────────────────────────────────────

func _show_name_entry() -> void:
	_step = Step.NAME_ENTRY
	_title_label.text = "ENTER NAME"
	_hint_label.text = "Type a name, then press Enter    Cancel: Back"
	_bg_rect.visible = true
	_clear_content()

	await get_tree().process_frame
	var area_size: Vector2 = _content_area.size

	# Centered panel
	var panel_width: float = 420.0
	var panel_height: float = 200.0
	var panel_x: float = (area_size.x - panel_width) / 2.0
	var panel_y: float = (area_size.y - panel_height) / 2.0

	var panel := Panel.new()
	panel.position = Vector2(panel_x, panel_y)
	panel.size = Vector2(panel_width, panel_height)
	panel.add_theme_stylebox_override("panel",
		_make_bordered_stylebox(Color(0.82, 0.84, 0.88, 0.95), C_PANEL_BORDER, 1, 8, 0))
	_content_area.add_child(panel)

	# Header bar
	var header_bar := ColorRect.new()
	header_bar.position = Vector2(0, 0)
	header_bar.size = Vector2(panel_width, 40)
	header_bar.color = C_TITLE_BOT
	panel.add_child(header_bar)

	var header_lbl := Label.new()
	header_lbl.text = "  CHARACTER NAME"
	header_lbl.add_theme_font_size_override("font_size", 16)
	header_lbl.add_theme_color_override("font_color", C_WHITE)
	header_lbl.position = Vector2(0, 0)
	header_lbl.size = Vector2(panel_width, 40)
	header_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(header_lbl)

	# Class info
	var cls = _class_list[_selected_class_index]
	var cls_info := Label.new()
	cls_info.text = "%s  (%s %s %s)" % [cls.name, cls.race, cls.gender, cls.type]
	cls_info.add_theme_font_size_override("font_size", 14)
	cls_info.add_theme_color_override("font_color", C_DARK_MUTED)
	cls_info.position = Vector2(20, 52)
	cls_info.size = Vector2(panel_width - 40, 20)
	cls_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(cls_info)

	# Name input
	var input_bg := ColorRect.new()
	input_bg.position = Vector2(40, 90)
	input_bg.size = Vector2(panel_width - 80, 44)
	input_bg.color = C_WHITE
	panel.add_child(input_bg)

	var line_edit := LineEdit.new()
	line_edit.max_length = 16
	line_edit.text = _char_name
	line_edit.placeholder_text = "Enter name..."
	line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	line_edit.position = Vector2(44, 94)
	line_edit.size = Vector2(panel_width - 88, 36)
	line_edit.add_theme_font_size_override("font_size", 18)
	line_edit.add_theme_color_override("font_color", C_DARK)
	line_edit.add_theme_color_override("caret_color", C_DARK)
	line_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	line_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	line_edit.text_submitted.connect(_on_name_submitted)
	line_edit.gui_input.connect(_on_name_gui_input)
	panel.add_child(line_edit)

	# Max chars hint
	var max_lbl := Label.new()
	max_lbl.text = "Max 16 characters"
	max_lbl.add_theme_font_size_override("font_size", 12)
	max_lbl.add_theme_color_override("font_color", C_DARK_MUTED)
	max_lbl.position = Vector2(20, 146)
	max_lbl.size = Vector2(panel_width - 40, 16)
	max_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(max_lbl)

	# Focus the line edit after a frame
	await get_tree().process_frame
	line_edit.grab_focus()


func _on_name_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_show_appearance()
		get_viewport().set_input_as_handled()


func _on_name_submitted(text: String) -> void:
	_char_name = text.strip_edges()
	if _char_name.is_empty():
		return
	_show_confirm()


# ── Step 4: CONFIRM ─────────────────────────────────────────────

func _show_confirm() -> void:
	_step = Step.CONFIRM
	_title_label.text = "CONFIRM CHARACTER"
	_hint_label.text = "Confirm: Create Character    Cancel: Back to Name"
	_bg_rect.visible = true
	_clear_content()

	await get_tree().process_frame
	var area_size: Vector2 = _content_area.size

	var cls = _class_list[_selected_class_index]
	var is_cast := _is_cast_class()

	# Centered confirmation panel
	var panel_width: float = 500.0
	var panel_height: float = 340.0
	var panel_x: float = (area_size.x - panel_width) / 2.0
	var panel_y: float = (area_size.y - panel_height) / 2.0

	var panel := Panel.new()
	panel.position = Vector2(panel_x, panel_y)
	panel.size = Vector2(panel_width, panel_height)
	panel.add_theme_stylebox_override("panel",
		_make_bordered_stylebox(Color(0.82, 0.84, 0.88, 0.95), C_PANEL_BORDER, 1, 8, 0))
	_content_area.add_child(panel)

	# Header
	var header_bar := ColorRect.new()
	header_bar.position = Vector2(0, 0)
	header_bar.size = Vector2(panel_width, 40)
	header_bar.color = C_TITLE_BOT
	panel.add_child(header_bar)

	var header_lbl := Label.new()
	header_lbl.text = "  CREATE THIS CHARACTER?"
	header_lbl.add_theme_font_size_override("font_size", 16)
	header_lbl.add_theme_color_override("font_color", C_WHITE)
	header_lbl.position = Vector2(0, 0)
	header_lbl.size = Vector2(panel_width, 40)
	header_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(header_lbl)

	# Class art on the left side
	var art_size: float = 180.0
	if _class_art_cache.has(cls.id):
		var art := TextureRect.new()
		art.texture = _class_art_cache[cls.id]
		art.position = Vector2(20, 54)
		art.size = Vector2(art_size, art_size)
		art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		panel.add_child(art)

	# Info on the right side
	var info_x: float = art_size + 40.0
	var info_width: float = panel_width - info_x - 20.0
	var iy: float = 54.0

	# Name
	var name_lbl := Label.new()
	name_lbl.text = _char_name
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", C_DARK)
	name_lbl.position = Vector2(info_x, iy)
	name_lbl.size = Vector2(info_width, 30)
	panel.add_child(name_lbl)
	iy += 36.0

	# Separator
	var sep := ColorRect.new()
	sep.position = Vector2(info_x, iy)
	sep.size = Vector2(info_width, 1)
	sep.color = C_PANEL_BORDER
	panel.add_child(sep)
	iy += 10.0

	# Class
	_add_confirm_row(panel, "Class:", cls.name, info_x, iy, info_width, _get_type_color(cls.type))
	iy += 24.0

	# Type
	_add_confirm_row(panel, "Type:", cls.type, info_x, iy, info_width)
	iy += 24.0

	# Race
	_add_confirm_row(panel, "Race:", cls.race, info_x, iy, info_width)
	iy += 24.0

	# Gender
	_add_confirm_row(panel, "Gender:", cls.gender, info_x, iy, info_width)
	iy += 32.0

	# Appearance summary
	var appear_header := Label.new()
	appear_header.text = "Appearance"
	appear_header.add_theme_font_size_override("font_size", 13)
	appear_header.add_theme_color_override("font_color", C_DARK_MUTED)
	appear_header.position = Vector2(info_x, iy)
	appear_header.size = Vector2(info_width, 16)
	panel.add_child(appear_header)
	iy += 20.0

	if is_cast:
		_add_confirm_row(panel, "Head:", str(int(_appearance["variation_index"]) + 1), info_x, iy, info_width)
		iy += 20.0
		_add_confirm_row(panel, "Color A:", str(int(_appearance["hair_color_index"]) + 1), info_x, iy, info_width)
		iy += 20.0
		_add_confirm_row(panel, "Color B:", str(int(_appearance["body_color_index"]) + 1), info_x, iy, info_width)
		iy += 20.0
		_add_confirm_row(panel, "Color C:", str(int(_appearance["skin_tone_index"]) + 1), info_x, iy, info_width)
	else:
		_add_confirm_row(panel, "Head:", str(int(_appearance["variation_index"]) + 1), info_x, iy, info_width)
		iy += 20.0
		_add_confirm_row(panel, "Hair:", PlayerConfig.HAIR_COLORS[int(_appearance["hair_color_index"])], info_x, iy, info_width)
		iy += 20.0
		_add_confirm_row(panel, "Costume:", PlayerConfig.BODY_COLORS[int(_appearance["body_color_index"])], info_x, iy, info_width)
		iy += 20.0
		_add_confirm_row(panel, "Skin:", PlayerConfig.SKIN_TONES[int(_appearance["skin_tone_index"])], info_x, iy, info_width)


func _add_confirm_row(parent: Node, label_text: String, value_text: String, x: float, y: float, width: float, value_color: Color = C_DARK) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", C_DARK_MUTED)
	lbl.position = Vector2(x, y)
	lbl.size = Vector2(80, 18)
	parent.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", value_color)
	val.position = Vector2(x + 80, y)
	val.size = Vector2(width - 80, 18)
	parent.add_child(val)


# ── 3D Preview ──────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _preview_active and _preview_pivot:
		if Input.is_action_pressed("camera_lock"):
			if Input.is_action_pressed("ui_left"):
				_preview_pivot.rotate_y(delta * 3.0)
			elif Input.is_action_pressed("ui_right"):
				_preview_pivot.rotate_y(-delta * 3.0)


func _build_preview_scene() -> void:
	# Transparent environment so PSZ light blue shows through the CanvasLayer
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 0.75)
	env.ambient_light_energy = 0.8

	var world_env := WorldEnvironment.new()
	world_env.environment = env

	# Camera offset left so model appears on the right side
	var camera := Camera3D.new()
	camera.position = Vector3(-0.3, 0.0, 2.2)
	camera.rotation_degrees = Vector3(-3, 0, 0)
	camera.fov = 30

	# Key light
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	light.light_energy = 1.2

	# Fill light
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.4

	# Pivot for model rotation
	_preview_pivot = Node3D.new()
	_preview_pivot.name = "PreviewPivot"

	_preview_nodes = [world_env, camera, light, fill, _preview_pivot]
	for node in _preview_nodes:
		add_child(node)

	_preview_active = true


func _update_preview_model() -> void:
	if not _preview_pivot:
		return

	if _preview_model:
		_preview_model.queue_free()
		_preview_model = null

	var vi: int = int(_appearance["variation_index"])
	var model_path: String = PlayerConfig.get_model_path(_selected_class_id, vi)

	if not ResourceLoader.exists(model_path):
		return

	var packed: PackedScene = load(model_path) as PackedScene
	if packed == null:
		return

	_preview_model = packed.instantiate() as Node3D
	_preview_model.scale = Vector3(0.6, 0.6, 0.6)
	_preview_model.position.y = -0.7
	_preview_pivot.add_child(_preview_model)

	# Apply texture
	var hair: int = int(_appearance["hair_color_index"])
	var skin: int = int(_appearance["skin_tone_index"])
	var body: int = int(_appearance["body_color_index"])
	var tex_path: String = PlayerConfig.get_texture_path(_selected_class_id, vi, hair, skin, body)

	if ResourceLoader.exists(tex_path):
		var texture := load(tex_path) as Texture2D
		if texture:
			_apply_texture_recursive(_preview_model, texture)


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


func _teardown_preview() -> void:
	_preview_active = false
	_preview_model = null
	_preview_pivot = null
	for node in _preview_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_preview_nodes.clear()
	_bg_rect.visible = true


# ── Character Creation ──────────────────────────────────────────

func _create_character() -> void:
	var character: Dictionary = CharacterManager.create_character(
		_slot, _selected_class_id, _char_name, _appearance)
	if character.is_empty():
		push_warning("[CharCreate] Failed to create character")
		return
	CharacterManager.set_active_slot(_slot)
	SaveManager.save_game()
	CityState.set_spawn_key("intro")
	SceneManager.goto_scene("res://scenes/3d/city/city_office.tscn")

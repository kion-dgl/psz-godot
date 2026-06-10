extends Node3D
## Character creation screen — PSZ-themed design with Gamecube-style class select,
## appearance customization with 3D preview, and name entry.
## All UI is built programmatically on a CanvasLayer overlay.

enum Step { CLASS_SELECT, APPEARANCE, NAME_ENTRY }

# ── PSZ Theme Colors ────────────────────────────────────────────
# Sourced from web/src/storybook/MenuDesign.tsx + slats-PSZ palette.
const C_BG := Color(0.659, 0.800, 0.910)                  # #a8cce8 pale icy blue
const C_TITLE_TOP := Color(0.165, 0.205, 0.282)           # #2a3448 bgDark (navy)
const C_TITLE_BOT := Color(0.118, 0.157, 0.220)           # #1e2838 bgDarker
const C_CREAM := Color(0.88, 0.90, 0.94)                  # list item bg
const C_CREAM_HOVER := Color(0.92, 0.94, 0.97)            # hovered list item
const C_ORANGE := Color(0.941, 0.627, 0.125)              # #f0a020 selectedGradient
const C_GOLD_TITLE := Color(0.973, 0.784, 0.251)          # #f8c840 italic title
const C_DARK := Color(0.102, 0.102, 0.165)                # #1a1a2a dark text
const C_DARK_MUTED := Color(0.227, 0.290, 0.353)          # #3a4a5a muted text
const C_WHITE := Color(1.0, 1.0, 1.0)                     # white text
const C_GREEN_ARROW := Color(0.20, 0.55, 0.25)            # appearance arrows
# Type accents — vivid PSO primaries so the slat stripes read at a glance.
# Hunter has zero green channel + a slight blue pull to compensate for the
# Retroid's warm-leaning panel, otherwise the stripe reads coral/orange.
const C_TYPE_HUNTER := Color(1.00, 0.00, 0.18)            # red
const C_TYPE_RANGER := Color(0.12, 0.60, 0.18)            # green
const C_TYPE_FORCE := Color(0.25, 0.40, 1.00)             # blue
const C_PANEL_BORDER := Color(0.478, 0.627, 0.753, 0.5)   # #7aa0c0 subtle

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
var _scanlines_overlay: ColorRect           # PSZ scanline texture
var _accent_bar: ColorRect                  # yellow top accent stripe
var _title_bar: PanelContainer
var _title_label: Label
var _content_area: Control
var _hint_bar: PanelContainer
var _hint_label: Label

# Slat caching for the class-select step. We build the 14 slats once on
# entry to the step and animate stretch_ratio / overlay alpha when the
# selection changes, instead of rebuilding the tree on every keypress.
const SLAT_RATIO_SELECTED := 5.0
const SLAT_RATIO_UNSELECTED := 1.0
const SLAT_ANIM_DURATION := 0.32
var _slats: Array = []                       # Control nodes in display order
var _slat_data: Array = []                   # Dictionary per slat: refs + orig_index
var _selection_tween: Tween = null
# Re-entry guard. _build_class_select_slats() awaits a frame, and the input
# handler can fire again during that await — without this we'd kick off
# overlapping builds that each call _clear_content() + add children.
var _slats_building: bool = false

# Cached class art textures
var _class_art_cache: Dictionary = {}

# Class art filename overrides (some IDs don't match image names)
const CLASS_ART_OVERRIDES := {
	"hucaseal": "hucasteal",
	"racaseal": "racasteal",
}


func _ready() -> void:
	MusicManager.play_location_music("character_create")
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

	# Background — pale icy blue (#a8cce8)
	_bg_rect = ColorRect.new()
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.color = C_BG
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.add_child(_bg_rect)

	# Scanlines overlay — 4px repeating pattern matching MenuDesign.tsx SCANLINES.
	# Embedded inline shader so this scene doesn't need an external resource.
	_scanlines_overlay = ColorRect.new()
	_scanlines_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scanlines_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scanline_shader := Shader.new()
	scanline_shader.code = "shader_type canvas_item;\n" + \
		"void fragment() {\n" + \
		"    float band = mod(FRAGCOORD.y, 4.0);\n" + \
		"    if (band < 2.0) { COLOR = vec4(0.0, 0.0, 0.0, 0.0); }\n" + \
		"    else { COLOR = vec4(0.471, 0.627, 0.784, 0.10); }\n" + \
		"}\n"
	var scanline_mat := ShaderMaterial.new()
	scanline_mat.shader = scanline_shader
	_scanlines_overlay.material = scanline_mat
	_root_control.add_child(_scanlines_overlay)

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

	# Yellow top accent bar (#f8c840 → #f0a020). Approximated as solid C_ORANGE
	# since StyleBoxFlat doesn't do gradients; the bottom shadow line gives it
	# a hint of depth.
	_accent_bar = ColorRect.new()
	_accent_bar.color = C_ORANGE
	_accent_bar.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(_accent_bar)

	# Title bar — dark navy with gold-tinted bottom shadow
	_title_bar = PanelContainer.new()
	_title_bar.custom_minimum_size = Vector2(0, 48)
	var title_style := StyleBoxFlat.new()
	title_style.bg_color = C_TITLE_TOP
	title_style.content_margin_left = 20
	title_style.content_margin_right = 20
	title_style.border_width_top = 1
	title_style.border_width_bottom = 1
	title_style.border_color = Color(0.785, 0.502, 0.063, 0.55)   # #c88010 darker gold trim
	_title_bar.add_theme_stylebox_override("panel", title_style)
	vbox.add_child(_title_bar)

	_title_label = Label.new()
	_title_label.text = "CHARACTER CREATION"
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", C_GOLD_TITLE)
	_title_label.add_theme_constant_override("outline_size", 4)
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_bar.add_child(_title_label)

	# Content area — fills the middle
	_content_area = Control.new()
	_content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_content_area)

	# Hint bar at the bottom — white-translucent hint strip (PSZ MenuDesign hintBg)
	_hint_bar = PanelContainer.new()
	_hint_bar.custom_minimum_size = Vector2(0, 32)
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color(1.0, 1.0, 1.0, 0.65)
	hint_style.content_margin_left = 20
	hint_style.content_margin_right = 20
	hint_style.border_width_top = 2
	hint_style.border_color = C_ORANGE
	_hint_bar.add_theme_stylebox_override("panel", hint_style)
	vbox.add_child(_hint_bar)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", C_DARK_MUTED)
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


func _handle_class_select_input(event: InputEvent) -> void:
	# Slats are arranged horizontally so left/right is the primary axis;
	# up/down still works as a secondary path so keyboard users with a
	# vertical mental model aren't stuck. Selection stops at the first /
	# last class (no wrap), so the leftmost / rightmost feel like edges.
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		var prev := _selected_class_index
		_selected_class_index = max(0, _selected_class_index - 1)
		if _selected_class_index != prev:
			_sync_type_from_class()
			_update_class_select()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		var prev := _selected_class_index
		_selected_class_index = min(_class_list.size() - 1, _selected_class_index + 1)
		if _selected_class_index != prev:
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
	# Dpad cycles row / value, accept confirms, cancel backs out. The
	# preview character is rotated by the right analog stick (handled in
	# _process), NOT by holding a modifier — a stuck or noisy R2 trigger
	# (which is bound to camera_lock) used to swallow every dpad press
	# and the accept button on Bluetooth pads with sloppy calibration.
	if event.is_action_pressed("ui_up"):
		_appearance_row = wrapi(_appearance_row - 1, 0, 4)
		_update_appearance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_appearance_row = wrapi(_appearance_row + 1, 0, 4)
		_update_appearance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_cycle_appearance_value(-1)
		_update_appearance()
		_update_preview_model()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_cycle_appearance_value(1)
		_update_appearance()
		_update_preview_model()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_teardown_preview()
		_show_name_entry()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_teardown_preview()
		_show_class_select()
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
	_hint_label.text = "◀  ▶  NAVIGATE          A · CONFIRM          ESC · BACK"
	# Restore PSZ chrome (in case we came back from APPEARANCE which hid the bg)
	_bg_rect.visible = true
	if _scanlines_overlay:
		_scanlines_overlay.visible = true
	if _accent_bar:
		_accent_bar.visible = true
	# Force a fresh slat build on (re-)entering the step; any cached refs
	# may be pointing at queue_free'd nodes from a previous visit.
	if _selection_tween != null:
		_selection_tween.kill()
		_selection_tween = null
	_slats.clear()
	_slat_data.clear()
	_slats_building = false
	_sync_type_from_class()
	_update_class_select()


func _update_class_select() -> void:
	# Horizontal slats: 14 columns sorted Hunter → Ranger → Force. The slats
	# themselves persist across navigation; only the selection state animates.
	# Ported from web/src/character-select/SlatsView.tsx (slats-PSZ palette).
	if _slats_building:
		# An initial build is in flight; it'll re-read _selected_class_index
		# when it finishes via its trailing _animate_to_selection(false), so
		# the latest input wins. Don't kick off a parallel build.
		return
	if _slats.is_empty():
		_slats_building = true
		await _build_class_select_slats()
		_slats_building = false
		return  # build already applied initial state
	_animate_to_selection(true)


func _build_class_select_slats() -> void:
	_clear_content()
	await get_tree().process_frame

	# Sort by type, preserving original index so the input handler can keep
	# operating on _class_list indices.
	var sorted_entries: Array = []
	for type_name in ["Hunter", "Ranger", "Force"]:
		for i in range(_class_list.size()):
			var c = _class_list[i]
			if c.type == type_name:
				sorted_entries.append({"cls": c, "orig_index": i})

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	_content_area.add_child(hbox)

	_slats.clear()
	_slat_data.clear()

	for entry in sorted_entries:
		var d := _make_slat_pack(entry["cls"], entry["orig_index"])
		hbox.add_child(d["slat"])
		_slats.append(d["slat"])
		_slat_data.append(d)

	# Apply the initial selection state instantly (no animation) so the
	# selected slat is already expanded on first paint.
	_animate_to_selection(false)


func _animate_to_selection(animated: bool) -> void:
	if _selection_tween != null and _selection_tween.is_running():
		_selection_tween.kill()
	_selection_tween = create_tween().set_parallel(true)
	_selection_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var dur: float = SLAT_ANIM_DURATION if animated else 0.0

	for d in _slat_data:
		var is_selected: bool = (d["orig_index"] == _selected_class_index)
		var target_ratio: float = SLAT_RATIO_SELECTED if is_selected else SLAT_RATIO_UNSELECTED
		var overlay_alpha: float = 1.0 if is_selected else 0.0
		var v_name_alpha: float = 0.0 if is_selected else 1.0
		var portrait_alpha: float = 1.0 if is_selected else 0.55
		# Stripes show/hide instantly — fading them would muddy the type colour.
		d["stripe_top"].visible = is_selected
		d["stripe_bot"].visible = is_selected
		_selection_tween.tween_property(d["slat"], "size_flags_stretch_ratio", target_ratio, dur)
		_selection_tween.tween_property(d["overlay"], "modulate:a", overlay_alpha, dur)
		_selection_tween.tween_property(d["v_name"], "modulate:a", v_name_alpha, dur * 0.6)
		_selection_tween.tween_property(d["portrait"], "modulate:a", portrait_alpha, dur * 0.6)


func _make_slat_pack(cls, orig_index: int) -> Dictionary:
	var type_color: Color = _get_type_color(cls.type)

	var slat := Control.new()
	slat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slat.size_flags_stretch_ratio = SLAT_RATIO_UNSELECTED
	slat.clip_contents = true

	# Portrait fills the slat
	var portrait := TextureRect.new()
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _class_art_cache.has(cls.id):
		portrait.texture = _class_art_cache[cls.id]
	slat.add_child(portrait)

	# Type-coloured top + bottom stripes — shown only when this slat is
	# the selected one. Visibility is toggled by _animate_to_selection().
	var stripe_top := ColorRect.new()
	stripe_top.color = type_color
	stripe_top.anchor_right = 1.0
	stripe_top.offset_bottom = 4
	stripe_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe_top.visible = false
	slat.add_child(stripe_top)

	var stripe_bot := ColorRect.new()
	stripe_bot.color = type_color
	stripe_bot.anchor_top = 1.0
	stripe_bot.anchor_right = 1.0
	stripe_bot.anchor_bottom = 1.0
	stripe_bot.offset_top = -4
	stripe_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe_bot.visible = false
	slat.add_child(stripe_bot)

	# Vertical class name — visible while unselected, faded out when selected.
	# Each glyph on its own line so we sidestep rotated-Label pivot maths.
	var v_name := Label.new()
	var v_text := ""
	for ch in cls.name:
		v_text += ch + "\n"
	v_name.text = v_text.strip_edges()
	v_name.add_theme_font_size_override("font_size", 13)
	v_name.add_theme_color_override("font_color", C_WHITE)
	v_name.add_theme_constant_override("outline_size", 4)
	v_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	v_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v_name.set_anchors_preset(Control.PRESET_TOP_WIDE)
	v_name.offset_top = 10
	v_name.offset_bottom = 240
	v_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slat.add_child(v_name)

	# Info overlay — always built and populated for this slat's class; alpha
	# is animated to 1.0 when selected, 0.0 otherwise.
	var overlay := Panel.new()
	overlay.anchor_top = 1.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.offset_top = -180
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.modulate.a = 0.0
	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.118, 0.157, 0.220, 0.92)
	overlay_style.content_margin_left = 18
	overlay_style.content_margin_right = 18
	overlay_style.content_margin_top = 14
	overlay_style.content_margin_bottom = 14
	overlay.add_theme_stylebox_override("panel", overlay_style)
	slat.add_child(overlay)

	var info_vbox := VBoxContainer.new()
	info_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	info_vbox.add_theme_constant_override("separation", 4)
	overlay.add_child(info_vbox)

	var name_lbl := Label.new()
	name_lbl.text = cls.name
	name_lbl.add_theme_font_size_override("font_size", 28)
	name_lbl.add_theme_color_override("font_color", C_WHITE)
	name_lbl.add_theme_constant_override("outline_size", 4)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	info_vbox.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = "%s · %s · %s" % [cls.race, cls.gender, cls.type.to_upper()]
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", type_color)
	info_vbox.add_child(desc_lbl)

	var tagline_row := HBoxContainer.new()
	tagline_row.add_theme_constant_override("separation", 8)
	info_vbox.add_child(tagline_row)

	var bar := ColorRect.new()
	bar.color = type_color
	bar.custom_minimum_size = Vector2(3, 22)
	tagline_row.add_child(bar)

	var tagline_lbl := Label.new()
	var tagline_text: String = cls.tagline if cls.tagline != "" else cls.get_description()
	tagline_lbl.text = tagline_text
	tagline_lbl.add_theme_font_size_override("font_size", 14)
	tagline_lbl.add_theme_color_override("font_color", Color(0.85, 0.89, 0.94))
	tagline_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tagline_row.add_child(tagline_lbl)

	if cls.bonuses.size() > 0:
		var bonuses_lbl := Label.new()
		var bonus_text: String = " · ".join(cls.bonuses)
		bonuses_lbl.text = bonus_text
		bonuses_lbl.add_theme_font_size_override("font_size", 10)
		bonuses_lbl.add_theme_color_override("font_color", type_color)
		bonuses_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_vbox.add_child(bonuses_lbl)

	return {
		"slat": slat,
		"portrait": portrait,
		"stripe_top": stripe_top,
		"stripe_bot": stripe_bot,
		"v_name": v_name,
		"overlay": overlay,
		"orig_index": orig_index,
	}


# ── Step 2: APPEARANCE ──────────────────────────────────────────

func _show_appearance() -> void:
	_step = Step.APPEARANCE
	_title_label.text = "CUSTOMIZE APPEARANCE"
	_hint_label.text = "Up/Down: Row    Left/Right: Change    Tab+L/R: Rotate    Confirm: Next    Cancel: Back"

	# Hide the 2D bg + shader scanlines so the 3D preview's bg plane (which
	# uses character_select_bg.png — sky-blue with baked-in scanlines and
	# sparkles, from web/public/menu-design/) reads cleanly without doubling
	# up the scanline pattern.
	_bg_rect.visible = false
	if _scanlines_overlay:
		_scanlines_overlay.visible = false

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
	_create_character()


# ── 3D Preview ──────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _preview_active and _preview_pivot:
		# Right analog stick X rotates the preview. Same axis the in-game
		# camera uses, so it feels consistent and leaves the dpad free for
		# row/value navigation.
		var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
		if absf(rx) > 0.2:
			_preview_pivot.rotate_y(-rx * delta * 3.0)


func _build_preview_scene() -> void:
	# PSZ light blue fallback (only visible at the edges if the bg plane
	# doesn't fully cover the camera frustum).
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = C_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 0.75)
	env.ambient_light_energy = 0.8

	var world_env := WorldEnvironment.new()
	world_env.environment = env

	# Backdrop plane — uses the same character-select bg PNG as the menu-design
	# reference at web/public/menu-design/character_select_bg.png. Positioned
	# far behind the camera focus so the character model renders in front of
	# it; the plane is large enough to fill the camera's 28° FOV at this
	# distance. Unshaded so the lighting setup doesn't tint the bg.
	var bg_mesh := MeshInstance3D.new()
	var bg_plane := PlaneMesh.new()
	bg_plane.size = Vector2(18.0, 10.125)  # 16:9, oversized so edges aren't visible
	bg_plane.orientation = PlaneMesh.FACE_Z
	bg_mesh.mesh = bg_plane
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_texture = load("res://assets/ui/menu-design/character_select_bg.png") as Texture2D
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bg_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	bg_mesh.material_override = bg_mat
	bg_mesh.position = Vector3(0, 0.5, -7.0)

	# Camera pulled back so full body fits, offset left
	var camera := Camera3D.new()
	camera.position = Vector3(-0.3, 0.5, 3.2)
	camera.rotation_degrees = Vector3(-3, 0, 0)
	camera.fov = 28

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

	# White particle dots (static, like PSZ snow)
	var particles := GPUParticles3D.new()
	var particle_mat := ParticleProcessMaterial.new()
	particle_mat.direction = Vector3(0.2, -0.1, 0)
	particle_mat.spread = 180.0
	particle_mat.initial_velocity_min = 0.05
	particle_mat.initial_velocity_max = 0.15
	particle_mat.gravity = Vector3(0, 0, 0)
	particle_mat.scale_min = 0.02
	particle_mat.scale_max = 0.05
	particle_mat.color = Color(1, 1, 1, 0.4)
	particles.process_material = particle_mat
	var sphere := SphereMesh.new()
	sphere.radius = 0.03
	sphere.height = 0.06
	var sphere_mat := StandardMaterial3D.new()
	sphere_mat.albedo_color = Color(1, 1, 1, 0.5)
	sphere_mat.emission_enabled = true
	sphere_mat.emission = Color(1, 1, 1)
	sphere_mat.emission_energy_multiplier = 1.5
	sphere_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material = sphere_mat
	particles.draw_pass_1 = sphere
	particles.amount = 60
	particles.lifetime = 8.0
	particles.visibility_aabb = AABB(Vector3(-4, -2, -2), Vector3(8, 5, 4))
	particles.position = Vector3(0, 1.0, 0)

	_preview_nodes = [world_env, bg_mesh, camera, light, fill, _preview_pivot, particles]
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
	_preview_model.position.y = -0.2
	_preview_pivot.add_child(_preview_model)

	# Apply texture
	var hair: int = int(_appearance["hair_color_index"])
	var skin: int = int(_appearance["skin_tone_index"])
	var body: int = int(_appearance["body_color_index"])
	var tex_path: String = PlayerConfig.get_texture_path(_selected_class_id, vi, hair, skin, body)

	if ResourceLoader.exists(tex_path):
		var texture := load(tex_path) as Texture2D
		if texture:
			MeshUtils.apply_texture_recursive(_preview_model, texture)


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

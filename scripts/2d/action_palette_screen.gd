extends Control
## Action Palette configuration screen — configure 2 pages of 3 action slots.
## Navigable with gamepad (d-pad + A/B) or keyboard (arrows + Enter/Esc).

var _active_page: int = 0
var _selected_slot: int = 0
var _picking: bool = false
var _pick_index: int = 0
var _pick_items: Array = []  # Flat list of action dicts for picker

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var content_panel: PanelContainer = $Panel/VBox/ContentPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	PszStyle.style_menu(title_label, hint_label, [content_panel])
	title_label.text = "Action Palette"
	_active_page = ActionPalette.current_page
	_build_pick_items()
	_refresh()


func _build_pick_items() -> void:
	_pick_items = []
	for action in ActionPalette.ALL_ACTIONS:
		_pick_items.append(action)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _picking:
			_picking = false
			_refresh()
		else:
			SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		if _picking:
			_pick_index = wrapi(_pick_index - PICKER_COLS, 0, _pick_items.size())
		else:
			_selected_slot = wrapi(_selected_slot - 1, 0, 3)
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if _picking:
			_pick_index = wrapi(_pick_index + PICKER_COLS, 0, _pick_items.size())
		else:
			_selected_slot = wrapi(_selected_slot + 1, 0, 3)
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		if _picking:
			_pick_index = wrapi(_pick_index - 1, 0, _pick_items.size())
		else:
			_active_page = wrapi(_active_page - 1, 0, ActionPalette.pages.size())
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		if _picking:
			_pick_index = wrapi(_pick_index + 1, 0, _pick_items.size())
		else:
			_active_page = wrapi(_active_page + 1, 0, ActionPalette.pages.size())
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _picking:
			_assign_action()
		else:
			_open_picker()
		get_viewport().set_input_as_handled()


func _open_picker() -> void:
	_picking = true
	# Pre-select current action in picker
	var current_id: String = ActionPalette.pages[_active_page][_selected_slot]
	_pick_index = 0
	for i in range(_pick_items.size()):
		if _pick_items[i].id == current_id:
			_pick_index = i
			break
	_refresh()


func _assign_action() -> void:
	var action_id: String = _pick_items[_pick_index].id
	# Block assigning unlearned techniques
	if not _is_action_available(action_id):
		hint_label.text = "Not yet learned!"
		return
	ActionPalette.set_action(_active_page, _selected_slot, action_id)
	_picking = false
	_refresh()


func _is_action_available(action_id: String) -> bool:
	if not TechniqueManager.TECHNIQUES.has(action_id):
		return true  # Non-technique actions are always available
	var character = CharacterManager.get_active_character()
	if character == null:
		return false
	return TechniqueManager.get_technique_level(character, action_id) > 0


func _refresh() -> void:
	# Clear content
	for child in content_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	content_panel.add_child(vbox)

	if _picking:
		_build_picker(vbox)
		hint_label.text = "Up/Down: Select   A: Confirm   B: Back"
	else:
		_build_slot_view(vbox)
		hint_label.text = "Left/Right: Page   Up/Down: Slot   A: Edit   B: Back"


func _build_slot_view(parent: VBoxContainer) -> void:
	var page_count: int = ActionPalette.pages.size()

	# Page tabs
	var tab_names: Array = []
	for i in range(page_count):
		tab_names.append("Page %d" % (i + 1))
	var tabs := PszStyle.create_tab_bar(tab_names, _active_page)
	parent.add_child(tabs)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	parent.add_child(spacer)

	# Diamond preview
	var preview := _build_diamond_preview()
	parent.add_child(preview)

	# Spacer
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 8
	parent.add_child(spacer2)

	# Slot list — original PszStyle pills with icon prepended
	var page: Array = ActionPalette.pages[_active_page]
	var slot_keys := ["Slot 1", "Slot 2", "Slot 3"]
	for i in range(3):
		var data: Dictionary = ActionPalette.get_action_data(page[i])
		var label_text: String = data.get("label", page[i])
		var pill := PszStyle.create_pill(slot_keys[i], _selected_slot == i, label_text)
		_prepend_icon(pill, page[i])
		parent.add_child(pill)


func _build_diamond_preview() -> CenterContainer:
	var center := CenterContainer.new()
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 0)

	# Swap indicator
	var swap_center := CenterContainer.new()
	var swap_pill := PanelContainer.new()
	var swap_style := StyleBoxFlat.new()
	swap_style.bg_color = PszStyle.PILL_BG
	swap_style.border_color = PszStyle.PILL_BORDER
	swap_style.set_border_width_all(1)
	swap_style.set_corner_radius_all(8)
	swap_style.content_margin_left = 10.0
	swap_style.content_margin_right = 10.0
	swap_style.content_margin_top = 2.0
	swap_style.content_margin_bottom = 2.0
	swap_pill.add_theme_stylebox_override("panel", swap_style)

	var swap_hbox := HBoxContainer.new()
	swap_hbox.add_theme_constant_override("separation", 4)
	var swap_key := Label.new()
	swap_key.text = "R"
	swap_key.add_theme_color_override("font_color", PszStyle.TEXT_WHITE)
	swap_key.add_theme_font_size_override("font_size", 10)
	var key_bg := PanelContainer.new()
	var key_style := StyleBoxFlat.new()
	key_style.bg_color = Color(0.16, 0.24, 0.31, 0.7)
	key_style.set_corner_radius_all(4)
	key_style.content_margin_left = 4.0
	key_style.content_margin_right = 4.0
	key_style.content_margin_top = 1.0
	key_style.content_margin_bottom = 1.0
	key_bg.add_theme_stylebox_override("panel", key_style)
	key_bg.add_child(swap_key)
	swap_hbox.add_child(key_bg)

	var page_label := Label.new()
	page_label.text = "%d/%d" % [_active_page + 1, ActionPalette.pages.size()]
	page_label.add_theme_color_override("font_color", PszStyle.TEXT_LIGHT)
	page_label.add_theme_font_size_override("font_size", 10)
	swap_hbox.add_child(page_label)
	swap_pill.add_child(swap_hbox)
	swap_center.add_child(swap_pill)
	container.add_child(swap_center)

	# 3 slots in a row — outer slots raised (via margin)
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 6)
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var page: Array = ActionPalette.pages[_active_page]
	for i in range(3):
		var data: Dictionary = ActionPalette.get_action_data(page[i])
		var short_label: String = data.get("short", page[i])

		var slot := PanelContainer.new()
		var is_sel: bool = _selected_slot == i
		slot.add_theme_stylebox_override("panel", PszStyle.pill_style(is_sel))
		slot.custom_minimum_size = Vector2(60, 36)

		var slot_vbox := VBoxContainer.new()
		slot_vbox.add_theme_constant_override("separation", 0)
		slot_vbox.alignment = BoxContainer.ALIGNMENT_CENTER

		var key_label := Label.new()
		key_label.text = str(i + 1)
		key_label.add_theme_color_override("font_color", PszStyle.TEXT_LIGHT)
		key_label.add_theme_font_size_override("font_size", 9)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_vbox.add_child(key_label)

		var action_label := Label.new()
		action_label.text = short_label
		action_label.add_theme_color_override("font_color", PszStyle.TEXT)
		action_label.add_theme_font_size_override("font_size", 11)
		action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_vbox.add_child(action_label)

		slot.add_child(slot_vbox)

		# Outer slots raised via bottom margin
		var margin := MarginContainer.new()
		if i != 1:
			margin.add_theme_constant_override("margin_bottom", 14)
		margin.add_child(slot)
		slot_row.add_child(margin)

	container.add_child(slot_row)
	center.add_child(container)
	return center


const PICKER_COLS := 3

func _build_picker(parent: VBoxContainer) -> void:
	var current_page: Array = ActionPalette.pages[_active_page]
	var current_id: String = current_page[_selected_slot]

	# Header
	var header := Label.new()
	header.text = "Assign to Page %d, Slot %d" % [_active_page + 1, _selected_slot + 1]
	header.add_theme_color_override("font_color", PszStyle.TEXT_LIGHT)
	header.add_theme_font_size_override("font_size", PszStyle.FONT_DETAIL)
	parent.add_child(header)

	# Group by category, render in a grid
	var last_category := ""
	var current_row: HBoxContainer = null
	var col_idx: int = 0

	for i in range(_pick_items.size()):
		var action: Dictionary = _pick_items[i]
		var cat: String = action.category

		# Category header — start a new row
		if cat != last_category:
			current_row = null
			var cat_label: String = cat.capitalize()
			parent.add_child(PszStyle.create_section_header(cat_label))
			last_category = cat
			col_idx = 0

		# Start a new row if needed
		if current_row == null or col_idx >= PICKER_COLS:
			current_row = HBoxContainer.new()
			current_row.add_theme_constant_override("separation", 4)
			parent.add_child(current_row)
			col_idx = 0

		var is_current: bool = action.id == current_id
		var is_selected: bool = i == _pick_index
		var available: bool = _is_action_available(action.id)
		var grey := Color(0.4, 0.4, 0.4)

		# Compact cell: icon + short label
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", PszStyle.pill_style(is_selected))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)

		var icon_tex: Texture2D = ActionPalette.get_action_icon(action.id)
		if icon_tex:
			var icon_bg := PanelContainer.new()
			var icon_style := StyleBoxFlat.new()
			icon_style.bg_color = Color(0.05, 0.05, 0.1, 0.9)
			icon_style.set_corner_radius_all(4)
			icon_style.content_margin_left = 2.0
			icon_style.content_margin_right = 2.0
			icon_style.content_margin_top = 2.0
			icon_style.content_margin_bottom = 2.0
			icon_bg.add_theme_stylebox_override("panel", icon_style)
			var tex_rect := TextureRect.new()
			tex_rect.texture = icon_tex
			tex_rect.custom_minimum_size = Vector2(20, 20)
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if not available:
				tex_rect.modulate = Color(0.4, 0.4, 0.4)
			icon_bg.add_child(tex_rect)
			hbox.add_child(icon_bg)

		var label := Label.new()
		label.text = action.short
		var text_color: Color = grey if not available else PszStyle.TEXT
		if is_selected:
			text_color = PszStyle.TEXT_WHITE
		label.add_theme_color_override("font_color", text_color)
		label.add_theme_font_size_override("font_size", PszStyle.FONT_TAB)
		hbox.add_child(label)

		if is_current:
			var check := Label.new()
			check.text = "\u2713"
			check.add_theme_color_override("font_color", PszStyle.TEXT_LIGHT)
			check.add_theme_font_size_override("font_size", PszStyle.FONT_TAB)
			hbox.add_child(check)

		cell.add_child(hbox)
		current_row.add_child(cell)
		col_idx += 1


## Insert an action icon at the start of a PszStyle pill's HBoxContainer
func _prepend_icon(pill: PanelContainer, action_id: String) -> void:
	var icon_tex: Texture2D = ActionPalette.get_action_icon(action_id)
	if not icon_tex:
		return
	# PszStyle.create_pill puts an HBoxContainer as the first child
	var hbox: HBoxContainer = pill.get_child(0) as HBoxContainer
	if not hbox:
		return
	var icon_bg := PanelContainer.new()
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(0.05, 0.05, 0.1, 0.9)
	icon_style.set_corner_radius_all(4)
	icon_style.content_margin_left = 2.0
	icon_style.content_margin_right = 2.0
	icon_style.content_margin_top = 2.0
	icon_style.content_margin_bottom = 2.0
	icon_bg.add_theme_stylebox_override("panel", icon_style)
	var tex_rect := TextureRect.new()
	tex_rect.texture = icon_tex
	tex_rect.custom_minimum_size = Vector2(20, 20)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_bg.add_child(tex_rect)
	hbox.add_child(icon_bg)
	hbox.move_child(icon_bg, 0)

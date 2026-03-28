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
			_pick_index = wrapi(_pick_index - 1, 0, _pick_items.size())
		else:
			_selected_slot = wrapi(_selected_slot - 1, 0, 3)
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if _picking:
			_pick_index = wrapi(_pick_index + 1, 0, _pick_items.size())
		else:
			_selected_slot = wrapi(_selected_slot + 1, 0, 3)
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		if not _picking:
			_active_page = wrapi(_active_page - 1, 0, ActionPalette.pages.size())
			_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		if not _picking:
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
	ActionPalette.set_action(_active_page, _selected_slot, action_id)
	_picking = false
	_refresh()


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

	# Slot list
	var page: Array = ActionPalette.pages[_active_page]
	var slot_keys := ["Slot 1", "Slot 2", "Slot 3"]
	for i in range(3):
		var data: Dictionary = ActionPalette.get_action_data(page[i])
		var label_text: String = data.get("label", page[i])
		var pill := _create_icon_pill(slot_keys[i], _selected_slot == i, label_text, page[i])
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
		var action_id: String = page[i]

		var slot := PanelContainer.new()
		var is_sel: bool = _selected_slot == i
		slot.add_theme_stylebox_override("panel", PszStyle.pill_style(is_sel))
		slot.custom_minimum_size = Vector2(48, 48)

		var center := CenterContainer.new()
		var icon_tex: Texture2D = ActionPalette.get_action_icon(action_id)
		if icon_tex:
			var tex_rect := TextureRect.new()
			tex_rect.texture = icon_tex
			tex_rect.custom_minimum_size = Vector2(32, 32)
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			center.add_child(tex_rect)
		else:
			var data: Dictionary = ActionPalette.get_action_data(action_id)
			var action_label := Label.new()
			action_label.text = data.get("short", action_id)
			action_label.add_theme_color_override("font_color", PszStyle.TEXT)
			action_label.add_theme_font_size_override("font_size", 11)
			center.add_child(action_label)

		slot.add_child(center)

		# Outer slots raised via bottom margin
		var margin := MarginContainer.new()
		if i != 1:
			margin.add_theme_constant_override("margin_bottom", 14)
		margin.add_child(slot)
		slot_row.add_child(margin)

	container.add_child(slot_row)
	center.add_child(container)
	return center


func _build_picker(parent: VBoxContainer) -> void:
	var current_page: Array = ActionPalette.pages[_active_page]
	var current_id: String = current_page[_selected_slot]

	# Header
	var header := Label.new()
	header.text = "Assign to Page %d, Slot %d" % [_active_page + 1, _selected_slot + 1]
	header.add_theme_color_override("font_color", PszStyle.TEXT_LIGHT)
	header.add_theme_font_size_override("font_size", PszStyle.FONT_DETAIL)
	parent.add_child(header)

	# Group by category
	var last_category := ""
	for i in range(_pick_items.size()):
		var action: Dictionary = _pick_items[i]
		var cat: String = action.category

		# Category header
		if cat != last_category:
			var cat_label: String = cat.capitalize()
			parent.add_child(PszStyle.create_section_header(cat_label))
			last_category = cat

		var is_current: bool = action.id == current_id
		var is_selected: bool = i == _pick_index
		var right_text := "\u2713" if is_current else ""
		var pill := _create_icon_pill(action.label, is_selected, right_text, action.id)
		parent.add_child(pill)


func _create_icon_pill(left_text: String, selected: bool, right_text: String, action_id: String) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", PszStyle.pill_style(selected))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	# Action icon
	var icon_tex: Texture2D = ActionPalette.get_action_icon(action_id)
	if icon_tex:
		var tex_rect := TextureRect.new()
		tex_rect.texture = icon_tex
		tex_rect.custom_minimum_size = Vector2(24, 24)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		hbox.add_child(tex_rect)

	# Left label
	var left := Label.new()
	left.text = left_text
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_color_override("font_color", PszStyle.TEXT if not selected else PszStyle.TEXT_WHITE)
	left.add_theme_font_size_override("font_size", PszStyle.FONT_BODY)
	hbox.add_child(left)

	# Right label
	if not right_text.is_empty():
		var right := Label.new()
		right.text = right_text
		right.add_theme_color_override("font_color", PszStyle.TEXT_LIGHT)
		right.add_theme_font_size_override("font_size", PszStyle.FONT_BODY)
		hbox.add_child(right)

	pill.add_child(hbox)
	return pill

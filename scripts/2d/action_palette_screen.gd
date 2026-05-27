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

const PALETTE_BG_BASE := "res://assets/ui/psz-palette/palette_bg"
const ICON_BASE := "res://assets/ui/psz-palette/"

const PICKER_ROWS: Array = [
	{"label": "Combat", "ids": ["attack", "strong_attack", "dodge"]},
	{"label": "Recovery", "ids": ["monomate", "dimate", "trimate"]},
	{"ids": ["monofluid", "difluid", "trifluid"]},
	{"ids": ["sol_atomizer", "star_atomizer", "moon_atomizer"]},
	{"ids": ["telepipe"]},
	{"label": "Technique", "ids": ["foie", "barta", "zonde"]},
	{"ids": ["grants", "megid"]},
	{"ids": ["resta", "anti"]},
	{"ids": ["shifta", "deband"]},
	{"ids": ["jellen", "zalure"]},
]

const SLOT_CENTERS := [
	Vector2(26.0, 27.0),
	Vector2(58.0, 41.0),
	Vector2(90.0, 27.0),
]

const HUD_SCALE := 1.5


func _ready() -> void:
	PszStyle.style_menu(title_label, hint_label, [content_panel])
	title_label.text = "Action Palette"
	_active_page = ActionPalette.current_page
	_build_pick_items()
	_refresh()


func _build_pick_items() -> void:
	_pick_items = []
	for row in PICKER_ROWS:
		for id in row.ids:
			var data: Dictionary = ActionPalette.get_action_data(id)
			if not data.is_empty():
				_pick_items.append(data)


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
			_pick_index = _move_picker(-1, 0)
		else:
			_selected_slot = wrapi(_selected_slot - 1, 0, 3)
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if _picking:
			_pick_index = _move_picker(1, 0)
		else:
			_selected_slot = wrapi(_selected_slot + 1, 0, 3)
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		if _picking:
			_pick_index = _move_picker(0, -1)
		else:
			_active_page = wrapi(_active_page - 1, 0, ActionPalette.pages.size())
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		if _picking:
			_pick_index = _move_picker(0, 1)
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


func _move_picker(row_delta: int, col_delta: int) -> int:
	var cur_row := -1
	var cur_col := -1
	var flat_idx := 0
	for ri in range(PICKER_ROWS.size()):
		var row_ids: Array = PICKER_ROWS[ri].ids
		for ci in range(row_ids.size()):
			if flat_idx == _pick_index:
				cur_row = ri
				cur_col = ci
			flat_idx += 1
		if cur_row >= 0:
			break

	if cur_row < 0:
		return 0

	var new_row: int = wrapi(cur_row + row_delta, 0, PICKER_ROWS.size())
	var new_col: int = cur_col + col_delta

	if col_delta != 0:
		var row_ids: Array = PICKER_ROWS[cur_row].ids
		new_col = wrapi(new_col, 0, row_ids.size())
		new_row = cur_row

	var target_row_ids: Array = PICKER_ROWS[new_row].ids
	new_col = clampi(new_col, 0, target_row_ids.size() - 1)

	var result := 0
	for ri in range(new_row):
		result += int(PICKER_ROWS[ri].ids.size())
	result += new_col
	return result


func _open_picker() -> void:
	_picking = true
	var current_id: String = ActionPalette.pages[_active_page][_selected_slot]
	_pick_index = 0
	for i in range(_pick_items.size()):
		if _pick_items[i].id == current_id:
			_pick_index = i
			break
	_refresh()


func _assign_action() -> void:
	var action_id: String = _pick_items[_pick_index].id
	if not _is_action_available(action_id):
		hint_label.text = "Not yet learned!"
		return
	ActionPalette.set_action(_active_page, _selected_slot, action_id)
	_picking = false
	_refresh()


func _is_action_available(action_id: String) -> bool:
	if not TechniqueManager.TECHNIQUES.has(action_id):
		return true
	var character = CharacterManager.get_active_character()
	if character == null:
		return false
	return TechniqueManager.get_technique_level(character, action_id) > 0


func _refresh() -> void:
	for child in content_panel.get_children():
		child.queue_free()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	content_panel.add_child(hbox)

	# Left column: page tabs + HUD preview
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size.x = 200
	hbox.add_child(left)

	_build_page_tabs(left)
	_build_hud_preview(left)

	# Right column: picker grid
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(right_scroll)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)

	_build_picker_grid(right)

	if _picking:
		hint_label.text = "D-pad: Navigate   A: Assign   B: Back"
	else:
		hint_label.text = "Left/Right: Page   Up/Down: Slot   A: Edit   B: Back"


func _build_page_tabs(parent: VBoxContainer) -> void:
	var page_count: int = ActionPalette.pages.size()
	var tab_names: Array = []
	for i in range(page_count):
		tab_names.append("Page %d" % (i + 1))
	var tabs := PszStyle.create_tab_bar(tab_names, _active_page)
	parent.add_child(tabs)


func _build_hud_preview(parent: VBoxContainer) -> void:
	var bg_path: String = PALETTE_BG_BASE + ("_r.png" if _active_page == 1 else ".png")
	var bg_tex: Texture2D = null
	if ResourceLoader.exists(bg_path):
		bg_tex = load(bg_path)

	var container := Control.new()
	container.custom_minimum_size = Vector2(128.0 * HUD_SCALE, 67.0 * HUD_SCALE)
	parent.add_child(container)

	if bg_tex:
		var bg_rect := TextureRect.new()
		bg_rect.texture = bg_tex
		bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
		bg_rect.size = Vector2(128.0 * HUD_SCALE, 67.0 * HUD_SCALE)
		bg_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		container.add_child(bg_rect)

	var page: Array = ActionPalette.pages[_active_page]
	for i in range(3):
		var center: Vector2 = SLOT_CENTERS[i] * HUD_SCALE
		var icon_size := 28.0
		var tex_rect := TextureRect.new()
		var icon: Texture2D = ActionPalette.get_action_icon(page[i])
		if icon:
			tex_rect.texture = icon
		tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
		tex_rect.size = Vector2(icon_size, icon_size)
		tex_rect.position = Vector2(center.x - icon_size * 0.5, center.y - icon_size * 0.5)
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		container.add_child(tex_rect)

		if _selected_slot == i:
			var sel_border := ReferenceRect.new()
			sel_border.border_color = Color(0.3, 0.8, 0.3, 0.9)
			sel_border.border_width = 2.0
			sel_border.editor_only = false
			sel_border.position = Vector2(center.x - icon_size * 0.5 - 2, center.y - icon_size * 0.5 - 2)
			sel_border.size = Vector2(icon_size + 4, icon_size + 4)
			container.add_child(sel_border)

	# Slot labels under preview
	var slot_list := VBoxContainer.new()
	slot_list.add_theme_constant_override("separation", 2)
	parent.add_child(slot_list)
	for i in range(3):
		var data: Dictionary = ActionPalette.get_action_data(page[i])
		var label_text: String = data.get("label", page[i])
		var is_sel: bool = _selected_slot == i
		var pill := PszStyle.create_pill("Slot %d" % (i + 1), is_sel, label_text)
		_prepend_icon(pill, page[i])
		slot_list.add_child(pill)


func _build_picker_grid(parent: VBoxContainer) -> void:
	var current_page: Array = ActionPalette.pages[_active_page]
	var current_id: String = current_page[_selected_slot]
	var flat_idx := 0

	for row_def in PICKER_ROWS:
		if row_def.has("label"):
			var header := Label.new()
			header.text = str(row_def.label)
			header.add_theme_color_override("font_color", PszStyle.TEXT_LIGHT)
			header.add_theme_font_size_override("font_size", 12)
			parent.add_child(header)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		parent.add_child(row)

		var row_ids: Array = row_def.ids
		for ci in range(3):
			if ci < row_ids.size():
				var action_id: String = row_ids[ci]
				var data: Dictionary = ActionPalette.get_action_data(action_id)
				var is_current: bool = action_id == current_id
				var is_selected: bool = flat_idx == _pick_index and _picking
				var available: bool = _is_action_available(action_id)

				var cell := PanelContainer.new()
				cell.add_theme_stylebox_override("panel", _picker_cell_style(is_selected, is_current))
				cell.custom_minimum_size = Vector2(140, 0)

				var cell_hbox := HBoxContainer.new()
				cell_hbox.add_theme_constant_override("separation", 6)

				var icon_tex: Texture2D = ActionPalette.get_action_icon(action_id)
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
					tex_rect.custom_minimum_size = Vector2(24, 24)
					tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
					tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					if not available:
						tex_rect.modulate = Color(0.4, 0.4, 0.4)
					icon_bg.add_child(tex_rect)
					cell_hbox.add_child(icon_bg)

				var label := Label.new()
				label.text = data.get("label", action_id)
				var text_color: Color
				if is_selected:
					text_color = PszStyle.TEXT_WHITE
				elif not available:
					text_color = Color(0.4, 0.4, 0.4)
				elif is_current:
					text_color = Color(0.3, 0.8, 0.3)
				else:
					text_color = PszStyle.TEXT
				label.add_theme_color_override("font_color", text_color)
				label.add_theme_font_size_override("font_size", 12)
				cell_hbox.add_child(label)

				cell.add_child(cell_hbox)
				row.add_child(cell)
				flat_idx += 1
			else:
				var spacer := Control.new()
				spacer.custom_minimum_size = Vector2(140, 0)
				row.add_child(spacer)


func _picker_cell_style(is_selected: bool, is_current: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if is_selected:
		style.bg_color = PszStyle.PILL_SELECTED
		style.border_color = PszStyle.TEXT_WHITE
		style.set_border_width_all(1)
	elif is_current:
		style.bg_color = Color(0.15, 0.3, 0.15, 0.6)
		style.border_color = Color(0.3, 0.8, 0.3, 0.5)
		style.set_border_width_all(1)
	else:
		style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_corner_radius_all(4)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


func _prepend_icon(pill: PanelContainer, action_id: String) -> void:
	var icon_tex: Texture2D = ActionPalette.get_action_icon(action_id)
	if not icon_tex:
		return
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

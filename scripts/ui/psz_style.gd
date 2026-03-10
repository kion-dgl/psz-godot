class_name PszStyle
## PSZ menu style utilities — pale icy blue palette with pill rows and tab buttons.

# ── Panel Colors ──
const BG := Color(0.66, 0.80, 0.91)
const BG_BORDER := Color(0.48, 0.63, 0.75)
const TITLE_BG := Color(0.16, 0.20, 0.28)
const INNER_BG := Color(1.0, 1.0, 1.0, 0.3)
const INNER_BORDER := Color(0.59, 0.71, 0.82, 0.4)
const SCANLINE := Color(0.47, 0.63, 0.78, 0.08)

# ── Pill / Tab Colors ──
const PILL_BG := Color(1.0, 1.0, 1.0, 0.85)
const PILL_BORDER := Color(0.59, 0.71, 0.82, 0.4)
const SEL_BG := Color(0.94, 0.63, 0.13)
const SEL_BORDER := Color(0.82, 0.5, 0.06)
const HINT_BG := Color(1.0, 1.0, 1.0, 0.7)

# ── Text Colors ──
const TEXT := Color(0.1, 0.1, 0.17)
const TEXT_WHITE := Color(1.0, 1.0, 1.0)
const TEXT_LIGHT := Color(0.23, 0.29, 0.35)
const TEXT_MUTED := Color(0.40, 0.45, 0.55)
const TEXT_DANGER := Color(0.80, 0.20, 0.20)
const TEXT_WARNING := Color(0.75, 0.50, 0.08)
const TEXT_SUCCESS := Color(0.13, 0.53, 0.13)
const TEXT_QUEST := Color(0.30, 0.38, 0.60)
const TEXT_CLEAR := Color(0.20, 0.50, 0.25)
const TEXT_HIGHLIGHT := Color(0.82, 0.45, 0.05)
const TEXT_MESETA := Color(0.82, 0.58, 0.05)

# ── Font Sizes ──
const FONT_TITLE := 16
const FONT_ITEM := 14
const FONT_HINT := 13
const FONT_DETAIL := 13
const FONT_TAB := 12


static func pill_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if selected:
		s.bg_color = SEL_BG
		s.border_color = SEL_BORDER
		s.border_width_left = 2
		s.border_width_top = 2
		s.border_width_right = 2
		s.border_width_bottom = 2
	else:
		s.bg_color = PILL_BG
		s.border_color = PILL_BORDER
		s.border_width_left = 1
		s.border_width_top = 1
		s.border_width_right = 1
		s.border_width_bottom = 1
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_right = 3
	s.corner_radius_bottom_left = 3
	s.content_margin_left = 10.0
	s.content_margin_right = 10.0
	s.content_margin_top = 5.0
	s.content_margin_bottom = 5.0
	return s


static func tab_style(active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if active:
		s.bg_color = SEL_BG
		s.border_color = SEL_BORDER
		s.border_width_left = 2
		s.border_width_top = 2
		s.border_width_right = 2
		s.border_width_bottom = 2
	else:
		s.bg_color = PILL_BG
		s.border_color = PILL_BORDER
		s.border_width_left = 1
		s.border_width_top = 1
		s.border_width_right = 1
		s.border_width_bottom = 1
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_right = 4
	s.corner_radius_bottom_left = 4
	s.content_margin_left = 12.0
	s.content_margin_right = 12.0
	s.content_margin_top = 4.0
	s.content_margin_bottom = 4.0
	return s


static func title_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = TITLE_BG
	s.content_margin_left = 14.0
	s.content_margin_right = 14.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	return s


static func hint_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = HINT_BG
	s.border_color = BG_BORDER
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.corner_radius_bottom_left = 12
	s.corner_radius_bottom_right = 12
	s.content_margin_left = 14.0
	s.content_margin_right = 14.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s


static func inner_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = INNER_BG
	s.border_color = INNER_BORDER
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_right = 6
	s.corner_radius_bottom_left = 6
	s.content_margin_left = 8.0
	s.content_margin_top = 8.0
	s.content_margin_right = 8.0
	s.content_margin_bottom = 8.0
	return s


static func section_header_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.48, 0.63, 0.75, 0.3)
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_right = 3
	s.corner_radius_bottom_left = 3
	s.content_margin_left = 10.0
	s.content_margin_right = 10.0
	s.content_margin_top = 3.0
	s.content_margin_bottom = 3.0
	return s


static func create_pill(left_text: String, selected: bool, right_text: String = "", text_color := Color.TRANSPARENT) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", pill_style(selected))
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hbox := HBoxContainer.new()
	var label := Label.new()
	label.text = left_text
	var color: Color = text_color if text_color.a > 0.0 else TEXT
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", FONT_ITEM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)
	if not right_text.is_empty():
		var right := Label.new()
		right.text = right_text
		right.add_theme_color_override("font_color", TEXT_LIGHT if text_color.a == 0.0 else color)
		right.add_theme_font_size_override("font_size", FONT_ITEM)
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(right)
	pill.add_child(hbox)
	return pill


static func create_section_header(text: String) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", section_header_style())
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", TITLE_BG)
	label.add_theme_font_size_override("font_size", FONT_DETAIL)
	pill.add_child(label)
	return pill


static func create_tab_bar(tab_names: Array, active_tab: int) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	for i in range(tab_names.size()):
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", tab_style(i == active_tab))
		var label := Label.new()
		label.text = str(tab_names[i])
		label.add_theme_color_override("font_color", TEXT)
		label.add_theme_font_size_override("font_size", FONT_TAB)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(label)
		hbox.add_child(panel)
	return hbox


static func create_meseta_label(meseta: int) -> Label:
	var label := Label.new()
	label.text = "%d M" % meseta
	label.add_theme_color_override("font_color", TEXT_MESETA)
	label.add_theme_font_size_override("font_size", FONT_ITEM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


static func detail_label(text: String, color := TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", FONT_DETAIL)
	return label


static func style_menu(p_title: Label, p_hint: Label, panels: Array = []) -> void:
	p_title.add_theme_stylebox_override("normal", title_style())
	p_title.add_theme_color_override("font_color", TEXT_WHITE)
	p_title.add_theme_font_size_override("font_size", FONT_TITLE)
	p_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	p_hint.add_theme_stylebox_override("normal", hint_style())
	p_hint.add_theme_color_override("font_color", TEXT)
	p_hint.add_theme_font_size_override("font_size", FONT_HINT)
	for panel in panels:
		if panel is PanelContainer:
			panel.add_theme_stylebox_override("panel", inner_panel_style())

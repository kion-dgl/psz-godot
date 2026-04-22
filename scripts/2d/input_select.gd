extends Control
## InputSelect — one-time onboarding between title and character-select, shown only
## when no input_config.json exists. Player picks a controller scheme with left/right
## + Start/accept; the choice is persisted via InputConfig so future boots skip this
## screen. To re-run the onboarding, delete user://input_config.json.

const KENNEY_BASE := "res://assets/kenney_input-prompts/"

const OPTIONS: Array = [
	{
		"scheme": "xinput",
		"label": "Xbox / X-Input",
		"sublabel": "A to accept, B to cancel",
		"icon": "Xbox Series/Default/controller_xboxseries.png",
	},
	{
		"scheme": "switch",
		"label": "Switch / Nintendo",
		"sublabel": "A (east) to accept, B (south) to cancel",
		"icon": "Nintendo Switch/Default/controller_switch_pro.png",
	},
	{
		"scheme": "ds_cross",
		"label": "DualSense — Cross accept",
		"sublabel": "Cross to accept, Circle to cancel (PSO-style)",
		"icon": "PlayStation Series/Default/controller_playstation5.png",
	},
	{
		"scheme": "ds_circle",
		"label": "DualSense — Circle accept",
		"sublabel": "Circle to accept, Cross to cancel (JP / PSZ-accurate)",
		"icon": "PlayStation Series/Default/controller_playstation5.png",
	},
	{
		"scheme": "keyboard",
		"label": "Keyboard",
		"sublabel": "Enter to accept, Esc to cancel",
		"icon": "Keyboard & Mouse/Default/keyboard.png",
	},
]

const CARD_WIDTH := 180
const CARD_HEIGHT := 180
const ICON_SIZE := 96

var _selected: int = 0
var _cards: Array = []
var _label: Label
var _sublabel: Label


func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.0
	vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	add_child(vbox)

	var title := Label.new()
	title.text = "Select Your Controller"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Left / Right to choose, Start or Enter to confirm"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	vbox.add_child(hint)

	var card_row := HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 16)
	vbox.add_child(card_row)

	for i in OPTIONS.size():
		var card := _build_card(OPTIONS[i])
		card_row.add_child(card)
		_cards.append(card)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_label)

	_sublabel = Label.new()
	_sublabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sublabel.add_theme_font_size_override("font_size", 14)
	_sublabel.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(_sublabel)

	var footer := Label.new()
	footer.text = "You can change this later by deleting input_config.json in the user data folder."
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(footer)

	_update_selection()


func _build_card(option: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 8)
	panel.add_child(inner)

	var icon := TextureRect.new()
	var tex := load(KENNEY_BASE + str(option["icon"])) as Texture2D
	if tex:
		icon.texture = tex
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	inner.add_child(icon)

	var caption := Label.new()
	caption.text = str(option["label"]).split(" —")[0]
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 13)
	inner.add_child(caption)

	return panel


func _update_selection() -> void:
	for i in _cards.size():
		var panel: PanelContainer = _cards[i]
		var style := StyleBoxFlat.new()
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		if i == _selected:
			style.bg_color = Color(0.2, 0.3, 0.45, 0.9)
			style.border_width_left = 3
			style.border_width_right = 3
			style.border_width_top = 3
			style.border_width_bottom = 3
			style.border_color = Color(1.0, 0.9, 0.5)
		else:
			style.bg_color = Color(0.1, 0.1, 0.12, 0.7)
			style.border_width_left = 1
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1
			style.border_color = Color(0.3, 0.3, 0.35)
		panel.add_theme_stylebox_override("panel", style)

	var opt: Dictionary = OPTIONS[_selected]
	_label.text = str(opt["label"])
	_sublabel.text = str(opt["sublabel"])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_selected = (_selected - 1 + OPTIONS.size()) % OPTIONS.size()
		_update_selection()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_right"):
		_selected = (_selected + 1) % OPTIONS.size()
		_update_selection()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("start"):
		_confirm()
		get_viewport().set_input_as_handled()
		return


func _confirm() -> void:
	var scheme: String = str(OPTIONS[_selected]["scheme"])
	InputConfig.set_scheme(scheme)
	SfxManager.play("res://assets/sfx/ui/title_start.wav")
	SceneManager.goto_scene("res://scenes/2d/character_select.tscn")

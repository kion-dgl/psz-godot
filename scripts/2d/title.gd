extends Control
## Title screen — 3D backdrop (scenes/3d/ui/title_backdrop.tscn, via SubViewport)
## with "Press Start" prompt and control-scheme selector overlay.

@onready var prompt_label: Label = $VBox/PromptLabel
@onready var version_label: Label = $VBox/VersionLabel

var _blink_timer: float = 0.0
var _prompt_visible: bool = true
var _debug_guide: PanelContainer
var _scheme_row: HBoxContainer
var _scheme_text: Label
var _scheme_icon_container: HBoxContainer

const KENNEY_BASE := "res://assets/kenney_input-prompts/"
const SCHEME_ICONS := {
	"keyboard": ["Keyboard & Mouse/Default/keyboard.png"],
	"kb_mouse": ["Keyboard & Mouse/Default/keyboard.png", "Keyboard & Mouse/Default/mouse.png"],
	"xinput": ["Xbox Series/Default/controller_xboxseries.png"],
	"switch": ["Nintendo Switch/Default/controller_switch_pro.png"],
}
const ICON_SIZE := 32


func _ready() -> void:
	MusicManager.play_location_music("title")
	prompt_label.text = "Press Start"
	var app_version: String = ProjectSettings.get_setting("application/config/version", "0.0.0")
	version_label.text = "PSZ Godot v%s" % app_version

	# Add text shadows for readability over the background image
	var prompt_settings := LabelSettings.new()
	prompt_settings.font_color = ThemeColors.HEADER_TEXT
	prompt_settings.shadow_color = Color(0, 0, 0, 0.8)
	prompt_settings.shadow_offset = Vector2(2, 2)
	prompt_settings.shadow_size = 3
	prompt_label.label_settings = prompt_settings

	var version_settings := LabelSettings.new()
	version_settings.font_color = ThemeColors.HINT_TEXT
	version_settings.shadow_color = Color(0, 0, 0, 0.8)
	version_settings.shadow_offset = Vector2(2, 2)
	version_settings.shadow_size = 3
	version_label.label_settings = version_settings

	_setup_scheme_selector()
	_setup_debug_guide()


func _process(delta: float) -> void:
	_blink_timer += delta
	if _blink_timer >= 0.6:
		_blink_timer = 0.0
		_prompt_visible = not _prompt_visible
		if prompt_label.label_settings:
			prompt_label.label_settings.font_color = ThemeColors.TEXT_HIGHLIGHT if _prompt_visible else ThemeColors.HEADER_TEXT


func _setup_scheme_selector() -> void:
	# Center container so the HBox is centered in the VBox
	var center := CenterContainer.new()

	_scheme_row = HBoxContainer.new()
	_scheme_row.add_theme_constant_override("separation", 10)
	_scheme_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var shadow_settings := LabelSettings.new()
	shadow_settings.font_color = Color(1.0, 0.9, 0.5)
	shadow_settings.font_size = 20
	shadow_settings.shadow_color = Color(0, 0, 0, 0.9)
	shadow_settings.shadow_offset = Vector2(2, 2)
	shadow_settings.shadow_size = 3

	# Left arrow
	var left_arrow := Label.new()
	left_arrow.text = "<"
	left_arrow.label_settings = shadow_settings
	_scheme_row.add_child(left_arrow)

	# Icon container (holds 1-2 icons)
	_scheme_icon_container = HBoxContainer.new()
	_scheme_icon_container.add_theme_constant_override("separation", 4)
	_scheme_row.add_child(_scheme_icon_container)

	# Scheme name label
	_scheme_text = Label.new()
	var text_settings := LabelSettings.new()
	text_settings.font_color = Color(1.0, 0.9, 0.5)
	text_settings.font_size = 16
	text_settings.shadow_color = Color(0, 0, 0, 0.9)
	text_settings.shadow_offset = Vector2(2, 2)
	text_settings.shadow_size = 3
	_scheme_text.label_settings = text_settings
	_scheme_row.add_child(_scheme_text)

	# Right arrow
	var right_arrow := Label.new()
	right_arrow.text = ">"
	right_arrow.label_settings = shadow_settings
	_scheme_row.add_child(right_arrow)

	center.add_child(_scheme_row)

	# Insert between PromptLabel and Spacer2
	var vbox := $VBox
	vbox.add_child(center)
	vbox.move_child(center, 1)

	_update_scheme_display()
	InputConfig.scheme_changed.connect(func(_s: String): _update_scheme_display())


func _update_scheme_display() -> void:
	_scheme_text.text = InputConfig.get_label()

	# Clear old icons
	for child in _scheme_icon_container.get_children():
		child.queue_free()

	# Add icons for current scheme
	var icon_paths: Array = SCHEME_ICONS.get(InputConfig.current_scheme, [])
	for path in icon_paths:
		var full_path: String = KENNEY_BASE + path
		var tex := load(full_path) as Texture2D
		if tex:
			var icon := TextureRect.new()
			icon.texture = tex
			icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
			icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_scheme_icon_container.add_child(icon)


func _open_input_debug() -> void:
	if get_tree().root.has_node("InputDebug"):
		return
	var debug_scene := preload("res://scripts/2d/input_debug.gd")
	var debug := debug_scene.new()
	debug.name = "InputDebug"
	get_tree().root.add_child(debug)


func _setup_debug_guide() -> void:
	_debug_guide = PanelContainer.new()
	_debug_guide.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.75)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	_debug_guide.add_theme_stylebox_override("panel", style)
	_debug_guide.anchor_left = 0.0
	_debug_guide.anchor_top = 0.0
	_debug_guide.offset_left = 12
	_debug_guide.offset_top = 12

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.4))
	label.text = "Field Debug (F1 to toggle)\n" \
		+ "F3   Toggle debug panel\n" \
		+ "F5   Triggers\n" \
		+ "F6   Gate markers\n" \
		+ "F7   Floor collision\n" \
		+ "F8   Spawn points\n" \
		+ "F9   All collision (labels)"
	_debug_guide.add_child(label)
	add_child(_debug_guide)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_debug_guide.visible = not _debug_guide.visible
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F2:
			_open_input_debug()
			get_viewport().set_input_as_handled()
			return

	# Select/Back button opens input debug
	if event is InputEventJoypadButton and event.pressed and event.button_index == 4:
		_open_input_debug()
		get_viewport().set_input_as_handled()
		return

	# Control scheme cycling with left/right
	if event.is_action_pressed("ui_left"):
		InputConfig.cycle(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_right"):
		InputConfig.cycle(1)
		get_viewport().set_input_as_handled()
		return

	# Start game (but not if input debug is open)
	if get_tree().root.has_node("InputDebug"):
		return
	if event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("start") \
			or (event is InputEventScreenTouch and event.pressed):
		SfxManager.play("res://assets/sfx/ui/title_start.wav")
		get_viewport().set_input_as_handled()
		SceneManager.goto_scene("res://scenes/2d/character_select.tscn")

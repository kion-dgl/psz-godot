extends Control
## Title screen — title.jpg background with blinking "Press ENTER" prompt.

@onready var prompt_label: Label = $VBox/PromptLabel
@onready var version_label: Label = $VBox/VersionLabel

var _blink_timer: float = 0.0
var _prompt_visible: bool = true
var _debug_guide: PanelContainer


func _ready() -> void:
	prompt_label.text = "[ Press ENTER to start ]"
	version_label.text = "PSZ Godot v0.1 — A Phantasy Star Zero fan game"

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

	_setup_debug_guide()


func _process(delta: float) -> void:
	_blink_timer += delta
	if _blink_timer >= 0.6:
		_blink_timer = 0.0
		_prompt_visible = not _prompt_visible
		if prompt_label.label_settings:
			prompt_label.label_settings.font_color = ThemeColors.TEXT_HIGHLIGHT if _prompt_visible else ThemeColors.HEADER_TEXT


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
		+ "F9   All collision (labels)\n" \
		+ "TAB  Map overlay"
	_debug_guide.add_child(label)
	add_child(_debug_guide)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_debug_guide.visible = not _debug_guide.visible
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		SceneManager.goto_scene("res://scenes/2d/character_select.tscn")

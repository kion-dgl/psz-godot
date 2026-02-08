extends Control
## Title screen — title.jpg background with blinking "Press ENTER" prompt.

@onready var prompt_label: Label = $VBox/PromptLabel
@onready var version_label: Label = $VBox/VersionLabel

var _blink_timer: float = 0.0
var _prompt_visible: bool = true


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


func _process(delta: float) -> void:
	_blink_timer += delta
	if _blink_timer >= 0.6:
		_blink_timer = 0.0
		_prompt_visible = not _prompt_visible
		if prompt_label.label_settings:
			prompt_label.label_settings.font_color = ThemeColors.TEXT_HIGHLIGHT if _prompt_visible else ThemeColors.HEADER_TEXT


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		SceneManager.goto_scene("res://scenes/2d/character_select.tscn")

extends Control
## Title screen — ASCII art title with blinking "Press ENTER" prompt.

@onready var title_label: Label = $VBox/TitleLabel
@onready var prompt_label: Label = $VBox/PromptLabel
@onready var version_label: Label = $VBox/VersionLabel

var _blink_timer: float = 0.0
var _prompt_visible: bool = true


func _ready() -> void:
	title_label.text = _get_title_art()
	prompt_label.text = "[ Press ENTER to start ]"
	version_label.text = "PSZ Godot v0.1 — A text-based Phantasy Star Zero experience"


func _process(delta: float) -> void:
	_blink_timer += delta
	if _blink_timer >= 0.6:
		_blink_timer = 0.0
		_prompt_visible = not _prompt_visible
		prompt_label.visible = _prompt_visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		SceneManager.goto_scene("res://scenes/2d/character_select.tscn")


func _get_title_art() -> String:
	return """
 ╔═══════════════════════════════════════════════════╗
 ║                                                   ║
 ║     P H A N T A S Y   S T A R   Z E R O          ║
 ║                                                   ║
 ║         ─── Text Adventure Edition ───            ║
 ║                                                   ║
 ╚═══════════════════════════════════════════════════╝
"""

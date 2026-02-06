extends Control
## Tekker — grind weapons and identify unknown weapons.

enum Mode { GRIND, IDENTIFY }

var _mode: int = Mode.GRIND

@onready var title_label: Label = $VBox/TitleLabel
@onready var mode_label: Label = $VBox/ModeLabel
@onready var content_panel: PanelContainer = $VBox/ContentPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "══════ TEKKER ══════"
	hint_label.text = "[←/→] Switch Mode  [ESC] Leave"
	_refresh_display()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_mode = Mode.IDENTIFY if _mode == Mode.GRIND else Mode.GRIND
		_refresh_display()
		get_viewport().set_input_as_handled()


func _refresh_display() -> void:
	if _mode == Mode.GRIND:
		mode_label.text = "[◄ GRIND ►]    IDENTIFY"
	else:
		mode_label.text = "   GRIND    [◄ IDENTIFY ►]"

	for child in content_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	if _mode == Mode.GRIND:
		var desc := Label.new()
		desc.text = "\n  Grinding increases a weapon's attack power.\n  Select a weapon and grinder to enhance it."
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc)

		var placeholder := Label.new()
		placeholder.text = "\n  (No grindable weapons in inventory)"
		placeholder.modulate = Color(0.333, 0.333, 0.333)
		vbox.add_child(placeholder)
	else:
		var desc := Label.new()
		desc.text = "\n  Identification reveals the true stats of\n  unidentified weapons (5-7★ rarity)."
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc)

		var placeholder := Label.new()
		placeholder.text = "\n  (No unidentified weapons in inventory)"
		placeholder.modulate = Color(0.333, 0.333, 0.333)
		vbox.add_child(placeholder)

	content_panel.add_child(vbox)

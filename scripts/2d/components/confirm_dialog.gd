extends CenterContainer
## Modal confirmation dialog with Yes/No options.

signal confirmed()
signal cancelled()

@onready var message_label: Label = $Panel/VBox/MessageLabel
@onready var menu: VBoxContainer = $Panel/VBox/MenuList

var _active: bool = false
var _selected: int = 0


func _ready() -> void:
	visible = false


func show_dialog(message: String) -> void:
	message_label.text = message
	_selected = 0
	_active = true
	visible = true
	_update_display()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		_selected = 1 - _selected
		_update_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_active = false
		visible = false
		if _selected == 0:
			confirmed.emit()
		else:
			cancelled.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_active = false
		visible = false
		cancelled.emit()
		get_viewport().set_input_as_handled()


func _update_display() -> void:
	for child in menu.get_children():
		child.queue_free()
	var yes_label := Label.new()
	var no_label := Label.new()
	if _selected == 0:
		yes_label.text = "> Yes"
		yes_label.modulate = ThemeColors.TEXT_HIGHLIGHT
		no_label.text = "  No"
	else:
		yes_label.text = "  Yes"
		no_label.text = "> No"
		no_label.modulate = ThemeColors.TEXT_HIGHLIGHT
	menu.add_child(yes_label)
	menu.add_child(no_label)

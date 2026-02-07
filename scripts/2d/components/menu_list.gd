extends VBoxContainer
## Keyboard-navigable text menu for terminal UI.
## Use add_item() to populate, then arrow keys + enter to navigate.

signal item_selected(index: int)
signal item_focused(index: int)

const COLOR_NORMAL := Color(0, 1, 0.533)  # Terminal green
const COLOR_HIGHLIGHT := Color(1, 0.8, 0)  # Yellow
const COLOR_MUTED := Color(0.333, 0.333, 0.333)  # Gray

var _items: Array[String] = []
var _disabled: Array[bool] = []
var _current_index: int = 0
var _active: bool = true

@export var cursor_char: String = "> "
@export var indent_char: String = "  "


func _ready() -> void:
	_update_display()


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _items.is_empty():
		return

	if event.is_action_pressed("ui_up"):
		_move_cursor(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_cursor(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if not _disabled[_current_index]:
			item_selected.emit(_current_index)
			get_viewport().set_input_as_handled()


func set_items(items: Array, disabled_mask: Array = []) -> void:
	_items.clear()
	for item in items:
		_items.append(str(item))
	_disabled.clear()
	for i in range(items.size()):
		if i < disabled_mask.size():
			_disabled.append(bool(disabled_mask[i]))
		else:
			_disabled.append(false)
	_current_index = 0
	# Skip to first enabled item
	_skip_to_enabled(1)
	_update_display()


func add_item(text: String, disabled: bool = false) -> void:
	_items.append(text)
	_disabled.append(disabled)
	_update_display()


func clear_items() -> void:
	_items.clear()
	_disabled.clear()
	_current_index = 0
	_update_display()


func get_current_index() -> int:
	return _current_index


func set_current_index(idx: int) -> void:
	if idx >= 0 and idx < _items.size():
		_current_index = idx
		_update_display()


func set_active(active: bool) -> void:
	_active = active
	_update_display()


func _move_cursor(direction: int) -> void:
	var old_index := _current_index
	_current_index = wrapi(_current_index + direction, 0, _items.size())
	_skip_to_enabled(direction)
	if _current_index != old_index:
		item_focused.emit(_current_index)
		_update_display()


func _skip_to_enabled(direction: int) -> void:
	if _items.is_empty():
		return
	var attempts := 0
	while _disabled[_current_index] and attempts < _items.size():
		_current_index = wrapi(_current_index + direction, 0, _items.size())
		attempts += 1


func _update_display() -> void:
	# Remove old labels
	for child in get_children():
		child.queue_free()

	for i in range(_items.size()):
		var label := Label.new()
		var color: Color
		if i == _current_index and _active:
			label.text = cursor_char + _items[i]
			color = COLOR_MUTED if _disabled[i] else COLOR_HIGHLIGHT
		else:
			label.text = indent_char + _items[i]
			color = COLOR_MUTED if _disabled[i] else COLOR_NORMAL
		var settings := LabelSettings.new()
		settings.font_color = color
		settings.shadow_color = Color(0, 0, 0, 0.7)
		settings.shadow_offset = Vector2(2, 2)
		settings.shadow_size = 3
		label.label_settings = settings
		add_child(label)

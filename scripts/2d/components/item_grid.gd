extends GridContainer
## Grid of selectable item slots for inventory and character selection.

signal item_selected(index: int)
signal item_focused(index: int)

const COLOR_NORMAL := ThemeColors.TEXT_PRIMARY
const COLOR_HIGHLIGHT := ThemeColors.TEXT_HIGHLIGHT
const COLOR_EMPTY := ThemeColors.TEXT_SECONDARY

var _items: Array[Dictionary] = []  # {text: String, empty: bool}
var _current_index: int = 0
var _active: bool = true
var _cols: int = 1


func _ready() -> void:
	_cols = columns if columns > 0 else 1


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _items.is_empty():
		return

	var moved := false
	if event.is_action_pressed("ui_up"):
		_current_index = wrapi(_current_index - _cols, 0, _items.size())
		moved = true
	elif event.is_action_pressed("ui_down"):
		_current_index = wrapi(_current_index + _cols, 0, _items.size())
		moved = true
	elif event.is_action_pressed("ui_left"):
		_current_index = wrapi(_current_index - 1, 0, _items.size())
		moved = true
	elif event.is_action_pressed("ui_right"):
		_current_index = wrapi(_current_index + 1, 0, _items.size())
		moved = true
	elif event.is_action_pressed("ui_accept"):
		item_selected.emit(_current_index)
		get_viewport().set_input_as_handled()
		return

	if moved:
		item_focused.emit(_current_index)
		_update_display()
		get_viewport().set_input_as_handled()


func set_items(items: Array[Dictionary]) -> void:
	_items = items
	_current_index = clampi(_current_index, 0, maxi(_items.size() - 1, 0))
	_update_display()


func set_active(active: bool) -> void:
	_active = active
	_update_display()


func get_current_index() -> int:
	return _current_index


func _update_display() -> void:
	for child in get_children():
		child.queue_free()

	for i in range(_items.size()):
		var label := Label.new()
		var item: Dictionary = _items[i]
		var text: String = item.get("text", "[Empty]")
		var is_empty: bool = item.get("empty", false)

		if i == _current_index and _active:
			label.text = "> " + text
			label.modulate = COLOR_HIGHLIGHT
		else:
			label.text = "  " + text
			label.modulate = COLOR_EMPTY if is_empty else COLOR_NORMAL
		label.custom_minimum_size = Vector2(200, 0)
		add_child(label)

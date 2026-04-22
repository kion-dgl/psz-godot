extends VBoxContainer
## Keyboard-navigable menu with PSZ-style pill-shaped rows.
## Use add_item() to populate, then arrow keys + enter to navigate.

signal item_selected(index: int)
signal item_focused(index: int)

var _items: Array[String] = []
var _disabled: Array[bool] = []
var _current_index: int = 0
var _active: bool = true
var _nav: NavRepeat


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	_nav = NavRepeat.new(["ui_up", "ui_down"], _on_nav_repeat)
	_update_display()


func _process(delta: float) -> void:
	if _active and not _items.is_empty():
		_nav.tick(delta)
	else:
		_nav.reset()


func _on_nav_repeat(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_unhandled_input(ev)


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _items.is_empty():
		return

	if event.is_action_pressed("ui_up"):
		_move_cursor(-1)
		SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_cursor(1)
		SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if not _disabled[_current_index]:
			SfxManager.play("res://assets/sfx/ui/menu_select.wav")
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
	# Remove old children
	for child in get_children():
		child.queue_free()

	for i in range(_items.size()):
		var is_selected: bool = (i == _current_index and _active)
		var is_disabled: bool = _disabled[i]
		var is_separator: bool = _items[i].begins_with("────")

		# Separators render as thin spacers
		if is_separator:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(0, 4)
			add_child(spacer)
			continue

		var pill := PszStyle.create_pill(_items[i], is_selected)
		if is_disabled:
			# Override colors for disabled items
			var label: Label = pill.get_child(0).get_child(0) if pill.get_child_count() > 0 else null
			if label:
				label.add_theme_color_override("font_color", PszStyle.TEXT_MUTED)
		add_child(pill)

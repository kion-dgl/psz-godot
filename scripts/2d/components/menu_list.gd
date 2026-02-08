extends VBoxContainer
## Keyboard-navigable menu with PSZ DS-style pill-shaped rows.
## Use add_item() to populate, then arrow keys + enter to navigate.

signal item_selected(index: int)
signal item_focused(index: int)

var _items: Array[String] = []
var _disabled: Array[bool] = []
var _current_index: int = 0
var _active: bool = true


func _ready() -> void:
	add_theme_constant_override("separation", 4)
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
	# Remove old children
	for child in get_children():
		child.queue_free()

	for i in range(_items.size()):
		var is_selected: bool = (i == _current_index and _active)
		var is_disabled: bool = _disabled[i]
		var is_separator: bool = _items[i].begins_with("────")

		# Separators render as simple labels (no panel)
		if is_separator:
			var sep_label := Label.new()
			sep_label.text = _items[i]
			var sep_settings := LabelSettings.new()
			sep_settings.font_color = ThemeColors.TEXT_DISABLED
			sep_label.label_settings = sep_settings
			add_child(sep_label)
			continue

		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()

		if is_selected:
			style.bg_color = ThemeColors.MENU_SELECTED
		elif is_disabled:
			style.bg_color = Color(ThemeColors.MENU_BG, 0.5)
		else:
			style.bg_color = ThemeColors.MENU_BG

		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_right = 12
		style.corner_radius_bottom_left = 12
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		panel.add_theme_stylebox_override("panel", style)

		var label := Label.new()
		label.text = _items[i]
		var settings := LabelSettings.new()
		if is_disabled:
			settings.font_color = ThemeColors.TEXT_DISABLED
		else:
			settings.font_color = ThemeColors.MENU_TEXT
		label.label_settings = settings
		panel.add_child(label)

		add_child(panel)

class_name ChoiceDialog extends Control
## Centered modal that offers N labeled choices (greater than the
## Yes/No `ConfirmDialog`). Used by the inventory item modal where the
## player picks Equip / Use / Drop / Sort on a selected item, and by
## the Sort sub-modal (Auto / Manual). Self-frees on selection or
## cancel.
##
## Usage:
##     var modal := ChoiceDialog.new()
##     modal.chosen.connect(_on_chosen)
##     modal.cancelled.connect(_on_cancelled)
##     add_child(modal)
##     modal.ask("Monomate", [
##         {"label": "Use", "enabled": true},
##         {"label": "Drop", "enabled": true},
##         {"label": "Sort", "enabled": true},
##     ])
##
## Signals:
##     chosen(idx: int)  index into the original choices array
##     cancelled         dismissed without picking
##
## Disabled choices render greyed and are skipped during navigation
## (matches PSO's modal where invalid options are visible but
## unselectable).

signal chosen(idx: int)
signal cancelled

const _BUTTON_MIN_SIZE := Vector2(120, 32)

var _prompt_label: Label
var _buttons: Array[Button] = []
var _enabled: Array[bool] = []
var _focused_idx: int = 0


func _init() -> void:
	name = "ChoiceDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size = Vector2(320, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", PszStyle.FONT_TITLE)
	_prompt_label.add_theme_color_override("font_color", PszStyle.TEXT_WHITE)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_label.custom_minimum_size = Vector2(280, 0)
	vbox.add_child(_prompt_label)


## Set the prompt and the choice list; choices is `[{label, enabled}]`.
## Returns self for chaining. Must be called before `add_child` returns
## input — order doesn't actually matter, but the ergonomic shape is
## `add_child(modal); modal.ask(...)`.
func ask(prompt: String, choices: Array) -> ChoiceDialog:
	_prompt_label.text = prompt
	for btn in _buttons:
		btn.queue_free()
	_buttons.clear()
	_enabled.clear()

	var vbox: VBoxContainer = _prompt_label.get_parent()
	for i in range(choices.size()):
		var c: Dictionary = choices[i]
		var label: String = str(c.get("label", "?"))
		var enabled: bool = bool(c.get("enabled", true))
		var btn := _make_button(label)
		btn.disabled = not enabled
		var captured_idx: int = i
		btn.pressed.connect(func() -> void: _emit_chosen(captured_idx))
		vbox.add_child(btn)
		_buttons.append(btn)
		_enabled.append(enabled)

	_focused_idx = _first_enabled()
	_refresh_focus()
	return self


func _first_enabled() -> int:
	for i in range(_enabled.size()):
		if _enabled[i]:
			return i
	return 0


func _input(event: InputEvent) -> void:
	if not visible or _buttons.is_empty():
		return
	if event.is_action_pressed("ui_up"):
		_step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_step(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _focused_idx < _enabled.size() and _enabled[_focused_idx]:
			SfxManager.play("res://assets/sfx/ui/menu_select.wav")
			_emit_chosen(_focused_idx)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		SfxManager.play("res://assets/sfx/ui/menu_back.wav")
		_emit_cancelled()
		get_viewport().set_input_as_handled()


func _step(dir: int) -> void:
	if _buttons.is_empty():
		return
	var n: int = _buttons.size()
	var idx: int = _focused_idx
	for _i in range(n):
		idx = wrapi(idx + dir, 0, n)
		if _enabled[idx]:
			break
	if idx != _focused_idx:
		_focused_idx = idx
		SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		_refresh_focus()


func _refresh_focus() -> void:
	for i in range(_buttons.size()):
		_apply_button_style(_buttons[i], i == _focused_idx, _enabled[i])


func _emit_chosen(idx: int) -> void:
	chosen.emit(idx)
	queue_free()


func _emit_cancelled() -> void:
	cancelled.emit()
	queue_free()


func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = _BUTTON_MIN_SIZE
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", PszStyle.FONT_ITEM)
	btn.add_theme_color_override("font_color", PszStyle.TEXT)
	btn.add_theme_color_override("font_hover_color", PszStyle.TEXT)
	btn.add_theme_color_override("font_pressed_color", PszStyle.TEXT)
	btn.add_theme_color_override("font_focus_color", PszStyle.TEXT)
	btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.58, 0.65))
	return btn


func _apply_button_style(btn: Button, selected: bool, enabled: bool) -> void:
	var style := PszStyle.pill_style(selected and enabled)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)
	btn.add_theme_stylebox_override("disabled", style)


static func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PszStyle.TITLE_BG
	s.border_color = PszStyle.BG_BORDER
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 24.0
	s.content_margin_right = 24.0
	s.content_margin_top = 20.0
	s.content_margin_bottom = 20.0
	return s

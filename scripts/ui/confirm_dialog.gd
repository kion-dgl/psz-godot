class_name ConfirmDialog extends Control
## Centered yes/no modal dialog used by shops (and any other screen that
## wants a real confirm step). Self-frees on either choice. Built
## programmatically — no .tscn — so callers just `add_child(modal)` and
## connect to the `confirmed` / `cancelled` signals.
##
## Usage:
##     var modal := ConfirmDialog.new()
##     modal.confirmed.connect(_on_confirmed)
##     modal.cancelled.connect(_on_cancelled)
##     add_child(modal)
##     modal.ask("Buy Monomate for 50 M?")
##
## Input:
##     ui_left/ui_right  swap focus between Yes and No
##     ui_accept         fire the focused button
##     ui_cancel         always emits cancelled
##
## Z-order: this Control sits at PRESET_FULL_RECT with a dimmed
## ColorRect backdrop (mouse_filter=STOP), so it absorbs clicks behind
## itself. It uses _input (priority over _unhandled_input) and calls
## set_input_as_handled, so the underlying scene's _unhandled_input
## won't see consumed events while the modal is open.

signal confirmed
signal cancelled

const _BUTTON_MIN_SIZE := Vector2(96, 36)

var _yes_button: Button
var _no_button: Button
var _prompt_label: Label
var _focused_idx: int = 0  # 0 = Yes, 1 = No
var _info_mode: bool = false  # Single-button dismiss; ui_accept/ui_cancel both dismiss


func _init() -> void:
	name = "ConfirmDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Dim backdrop — absorbs mouse clicks behind the modal too.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# Centered panel.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", PszStyle.FONT_TITLE)
	_prompt_label.add_theme_color_override("font_color", PszStyle.TEXT_WHITE)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_label.custom_minimum_size = Vector2(340, 0)
	vbox.add_child(_prompt_label)

	# Build the body region. Subclasses (QuantityDialog) add extra rows
	# between the prompt and the buttons by appending to this vbox.
	_build_body(vbox)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	_yes_button = _make_button("Yes")
	_no_button = _make_button("No")
	hbox.add_child(_yes_button)
	hbox.add_child(_no_button)
	_yes_button.pressed.connect(_emit_confirmed)
	_no_button.pressed.connect(_emit_cancelled)


## Hook for subclasses to add rows (qty selector, total, etc) between the
## prompt and the Yes/No row. Default does nothing.
func _build_body(_vbox: VBoxContainer) -> void:
	pass


func _ready() -> void:
	_focused_idx = 0
	_refresh_focus()


## Set the prompt text. Returns self for chaining.
func ask(prompt: String) -> ConfirmDialog:
	_prompt_label.text = prompt
	return self


## Info-only mode: single OK button, ui_accept and ui_cancel both dismiss.
## Use for unmissable error/state messages (e.g. "Inventory full!") where
## the player has no real choice — only acknowledgment. The `confirmed`
## signal fires on dismiss so callers can clean up active-modal state the
## same way as the two-button path.
func info(prompt: String, button_text: String = "OK") -> ConfirmDialog:
	_prompt_label.text = prompt
	_info_mode = true
	_no_button.visible = false
	_yes_button.text = button_text
	_focused_idx = 0
	_refresh_focus()
	return self


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _info_mode:
		# Single-button: any accept/cancel dismisses with `confirmed`.
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
			SfxManager.play("res://assets/sfx/ui/menu_select.wav")
			_emit_confirmed()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_focused_idx = 1 - _focused_idx
		SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		_refresh_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		SfxManager.play("res://assets/sfx/ui/menu_select.wav")
		if _focused_idx == 0:
			_emit_confirmed()
		else:
			_emit_cancelled()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		SfxManager.play("res://assets/sfx/ui/menu_back.wav")
		_emit_cancelled()
		get_viewport().set_input_as_handled()


func _refresh_focus() -> void:
	# Visually mark the focused button using the same selected-pill style
	# the rest of the shop UI uses, so the modal doesn't look out of place.
	_apply_button_style(_yes_button, _focused_idx == 0)
	_apply_button_style(_no_button, _focused_idx == 1)


func _emit_confirmed() -> void:
	confirmed.emit()
	queue_free()


func _emit_cancelled() -> void:
	cancelled.emit()
	queue_free()


# ── Styling helpers ────────────────────────────────────────────────────────

func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = _BUTTON_MIN_SIZE
	btn.focus_mode = Control.FOCUS_NONE  # we manage focus visuals ourselves
	btn.add_theme_font_size_override("font_size", PszStyle.FONT_ITEM)
	btn.add_theme_color_override("font_color", PszStyle.TEXT)
	btn.add_theme_color_override("font_hover_color", PszStyle.TEXT)
	btn.add_theme_color_override("font_pressed_color", PszStyle.TEXT)
	btn.add_theme_color_override("font_focus_color", PszStyle.TEXT)
	return btn


func _apply_button_style(btn: Button, selected: bool) -> void:
	var style := PszStyle.pill_style(selected)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)
	btn.add_theme_stylebox_override("disabled", style)


static func _panel_style() -> StyleBoxFlat:
	# Echoes title_style but with rounded corners and a subtle border
	# so the modal reads as a self-contained card on top of the dimmed
	# backdrop.
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

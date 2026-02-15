extends Control
class_name DialogBox
## Bottom-anchored RPG dialog box.
## Shows multi-page dialog with speaker name and text.
## Player presses E or Enter to advance, ESC to skip to end.

signal dialog_complete

var _pages: Array = []  # Array of {speaker: String, text: String}
var _current_page: int = 0
var _active: bool = false

# UI elements
var _panel: PanelContainer
var _speaker_label: Label
var _text_label: RichTextLabel
var _advance_label: Label


func _ready() -> void:
	_build_ui()
	visible = false
	# Consume input when visible
	mouse_filter = Control.MOUSE_FILTER_STOP


func _build_ui() -> void:
	# Full-screen anchor
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Bottom panel
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.1
	_panel.anchor_right = 0.9
	_panel.anchor_top = 0.7
	_panel.anchor_bottom = 0.95
	_panel.offset_left = 0
	_panel.offset_right = 0
	_panel.offset_top = 0
	_panel.offset_bottom = 0

	# Dark semi-transparent background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.border_color = Color(0.3, 0.5, 0.8, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	# Speaker name
	_speaker_label = Label.new()
	_speaker_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	_speaker_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_speaker_label)

	# Dialog text
	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.scroll_active = false
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_color_override("default_color", Color.WHITE)
	_text_label.add_theme_font_size_override("normal_font_size", 16)
	vbox.add_child(_text_label)

	# Advance prompt
	_advance_label = Label.new()
	_advance_label.text = "[E] Continue"
	_advance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_advance_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_advance_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_advance_label)


func show_dialog(pages: Array) -> void:
	if pages.is_empty():
		return

	_pages = pages
	_current_page = 0
	_active = true
	visible = true
	_show_page(0)


func _show_page(idx: int) -> void:
	if idx < 0 or idx >= _pages.size():
		return

	var page: Dictionary = _pages[idx]
	_speaker_label.text = str(page.get("speaker", ""))
	_text_label.text = str(page.get("text", ""))

	if idx >= _pages.size() - 1:
		_advance_label.text = "[E] Close"
	else:
		_advance_label.text = "[E] Continue"


func _advance() -> void:
	_current_page += 1
	if _current_page >= _pages.size():
		_close()
	else:
		_show_page(_current_page)


func _close() -> void:
	_active = false
	visible = false
	_pages.clear()
	_current_page = 0
	dialog_complete.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E, KEY_ENTER, KEY_SPACE:
				_advance()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_close()
				get_viewport().set_input_as_handled()

extends CanvasLayer
## Input debug overlay — shows raw joypad button/axis events in real time.
## Open from title screen with Select/Back or F2. Press ESC/B to close.

var _panel: Control
var _log_label: RichTextLabel
var _axis_label: Label
var _last_events: Array[String] = []
const MAX_LOG := 20


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	# Title
	var title := Label.new()
	title.text = "Controller Input Debug"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	title.position = Vector2(20, 10)
	_panel.add_child(title)

	# Close hint
	var hint := Label.new()
	hint.text = "Press ESC or B to close"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.position = Vector2(20, 38)
	_panel.add_child(hint)

	# Axis display (left side)
	_axis_label = Label.new()
	_axis_label.add_theme_font_size_override("font_size", 14)
	_axis_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	_axis_label.position = Vector2(20, 70)
	_panel.add_child(_axis_label)

	# Event log (right side)
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.position = Vector2(400, 70)
	_log_label.size = Vector2(860, 600)
	_log_label.add_theme_font_size_override("normal_font_size", 13)
	_log_label.add_theme_color_override("default_color", Color.WHITE)
	_panel.add_child(_log_label)

	# Header for event log
	var log_header := Label.new()
	log_header.text = "Event Log (most recent at bottom)"
	log_header.add_theme_font_size_override("font_size", 14)
	log_header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	log_header.position = Vector2(400, 52)
	_panel.add_child(log_header)


func _process(_delta: float) -> void:
	# Show live axis values
	var text := "Live Axis Values:\n\n"
	for axis_idx in range(8):
		var val: float = Input.get_joy_axis(0, axis_idx)
		var bar := _axis_bar(val)
		var axis_name: String = _get_axis_name(axis_idx)
		text += "Axis %d (%s): %s  %.2f\n" % [axis_idx, axis_name, bar, val]

	text += "\n\nActive Buttons:\n"
	var active_buttons: Array[String] = []
	for btn_idx in range(20):
		if Input.is_joy_button_pressed(0, btn_idx):
			active_buttons.append("  Button %d (%s)" % [btn_idx, _get_button_name(btn_idx)])
	if active_buttons.is_empty():
		text += "  (none)"
	else:
		text += "\n".join(active_buttons)

	text += "\n\n\nJoypad Info:\n"
	var joy_name: String = Input.get_joy_name(0)
	text += "  Name: %s\n" % joy_name
	var guid: String = Input.get_joy_guid(0)
	text += "  GUID: %s" % guid

	_axis_label.text = text


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
		return

	# Log joypad button events
	if event is InputEventJoypadButton:
		var btn: InputEventJoypadButton = event
		var action: String = "PRESSED" if btn.pressed else "released"
		var color: String = "lime" if btn.pressed else "gray"
		var btn_name: String = _get_button_name(btn.button_index)
		_add_log("[color=%s]Button %d (%s) %s[/color]" % [color, btn.button_index, btn_name, action])

	# Log joypad axis events (only significant movement)
	elif event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		if absf(motion.axis_value) > 0.3:
			var axis_name: String = _get_axis_name(motion.axis)
			_add_log("[color=cyan]Axis %d (%s) = %.2f[/color]" % [motion.axis, axis_name, motion.axis_value])


func _add_log(text: String) -> void:
	_last_events.append(text)
	if _last_events.size() > MAX_LOG:
		_last_events.pop_front()
	_log_label.clear()
	for line in _last_events:
		_log_label.append_text(line + "\n")


func _axis_bar(val: float) -> String:
	var bar := ""
	var pos: int = int((val + 1.0) * 10.0)
	for i in range(21):
		if i == 10:
			bar += "|"
		elif i == pos:
			bar += "#"
		else:
			bar += "-"
	return bar


func _get_button_name(idx: int) -> String:
	match idx:
		0: return "A / Cross"
		1: return "B / Circle"
		2: return "X / Square"
		3: return "Y / Triangle"
		4: return "Back / Select"
		5: return "Guide / Home"
		6: return "Start"
		7: return "Left Stick Click"
		8: return "Right Stick Click"
		9: return "Left Shoulder"
		10: return "Right Shoulder"
		11: return "D-Pad Up"
		12: return "D-Pad Down"
		13: return "D-Pad Left"
		14: return "D-Pad Right"
		15: return "Misc 1"
		16: return "Paddle 1"
		17: return "Paddle 2"
		18: return "Paddle 3"
		19: return "Paddle 4"
		_: return "Unknown"


func _get_axis_name(idx: int) -> String:
	match idx:
		0: return "Left X"
		1: return "Left Y"
		2: return "Right X"
		3: return "Right Y"
		4: return "Left Trigger"
		5: return "Right Trigger"
		6: return "Hat X"
		7: return "Hat Y"
		_: return "Unknown"

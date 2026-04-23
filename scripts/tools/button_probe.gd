extends Control
## Standalone controller button probe. Shows raw joypad button index and axis
## values so we can figure out the physical ↔ index mapping for the active
## controller. Launch with:
##
##     godot --path . res://scripts/tools/button_probe.tscn
##
## Press each face button in a known order (north, east, south, west) and
## report the indices back. Esc to quit.

var _log_lines: Array[String] = []
var _log_label: RichTextLabel
var _status_label: Label
const MAX_LINES := 20


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "Button Probe"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	title.position = Vector2(20, 16)
	add_child(title)

	var hint := Label.new()
	hint.text = "Press each face button (north, east, south, west), shoulders, triggers. Esc to quit."
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hint.position = Vector2(20, 56)
	add_child(hint)

	_status_label = Label.new()
	_status_label.text = "waiting for input…"
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	_status_label.position = Vector2(20, 100)
	_status_label.size = Vector2(900, 40)
	add_child(_status_label)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.fit_content = true
	_log_label.scroll_active = false
	_log_label.add_theme_font_size_override("normal_font_size", 16)
	_log_label.add_theme_color_override("default_color", Color.WHITE)
	_log_label.position = Vector2(20, 160)
	_log_label.size = Vector2(900, 500)
	add_child(_log_label)

	_append("Ready. Connected joypads: %s" % Input.get_connected_joypads())
	if Input.get_connected_joypads().size() > 0:
		var dev: int = Input.get_connected_joypads()[0]
		_append("Joypad 0 name: %s" % Input.get_joy_name(dev))
		_append("Joypad 0 guid: %s" % Input.get_joy_guid(dev))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
		return

	if event is InputEventJoypadButton and event.pressed:
		var btn := event as InputEventJoypadButton
		var label: String = _button_label(btn.button_index)
		_status_label.text = "Button %d  (%s)  device=%d" % [btn.button_index, label, btn.device]
		_append("BUTTON press  idx=%d  %s  device=%d" % [btn.button_index, label, btn.device])

	if event is InputEventJoypadMotion:
		var mot := event as InputEventJoypadMotion
		if absf(mot.axis_value) > 0.7:
			var label: String = _axis_label(mot.axis)
			_status_label.text = "Axis %d  (%s)  value=%.2f" % [mot.axis, label, mot.axis_value]
			_append("AXIS          idx=%d  %s  value=%.2f" % [mot.axis, label, mot.axis_value])


func _button_label(idx: int) -> String:
	match idx:
		0: return "FACE_SOUTH (Godot's A / Cross / Switch B)"
		1: return "FACE_EAST (Godot's B / Circle / Switch A)"
		2: return "FACE_WEST (Godot's X / Square / Switch Y)"
		3: return "FACE_NORTH (Godot's Y / Triangle / Switch X)"
		4: return "BACK / SELECT / SHARE"
		5: return "GUIDE / HOME"
		6: return "START / PLUS / OPTIONS"
		7: return "LEFT STICK CLICK"
		8: return "RIGHT STICK CLICK"
		9: return "L1 / LB / L"
		10: return "R1 / RB / R"
		11: return "DPAD UP"
		12: return "DPAD DOWN"
		13: return "DPAD LEFT"
		14: return "DPAD RIGHT"
		_: return "unknown"


func _axis_label(idx: int) -> String:
	match idx:
		0: return "LEFT STICK X"
		1: return "LEFT STICK Y"
		2: return "RIGHT STICK X"
		3: return "RIGHT STICK Y"
		4: return "LEFT TRIGGER (L2)"
		5: return "RIGHT TRIGGER (R2)"
		_: return "unknown"


func _append(line: String) -> void:
	_log_lines.append(line)
	if _log_lines.size() > MAX_LINES:
		_log_lines.pop_front()
	_log_label.text = "\n".join(_log_lines)

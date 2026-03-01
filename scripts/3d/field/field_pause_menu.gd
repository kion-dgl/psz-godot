extends CanvasLayer
## Simple pause menu overlay for field scenes.
## ESC toggles open/close. Selecting "Return to City" emits return_to_city.

signal return_to_city()
signal closed()

const BG_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const PANEL_COLOR := Color(0.1, 0.1, 0.18, 0.95)
const BORDER_COLOR := Color(0.4, 0.45, 0.6, 0.7)
const TITLE_COLOR := Color(0.8, 0.85, 1.0)
const ITEM_COLOR := Color(0.9, 0.9, 0.9)
const SELECTED_COLOR := Color(1.0, 0.9, 0.3)
const FONT_SIZE_TITLE := 18
const FONT_SIZE_ITEM := 15

var _selected: int = 0
var _items: Array = ["Resume", "Return to City"]
var _bg: ColorRect
var _panel: Control

func _ready() -> void:
	layer = 200
	name = "FieldPauseMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS

	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.size = Vector2(240, 140)
	_panel.position = Vector2(-120, -70)
	add_child(_panel)

	_panel.draw.connect(_draw_panel)
	_panel.queue_redraw()


func open() -> void:
	visible = true
	_selected = 0
	get_tree().paused = true
	_panel.queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected = (_selected - 1 + _items.size()) % _items.size()
		_panel.queue_redraw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected = (_selected + 1) % _items.size()
		_panel.queue_redraw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_activate_item()
		get_viewport().set_input_as_handled()


func _activate_item() -> void:
	match _items[_selected]:
		"Resume":
			close()
		"Return to City":
			get_tree().paused = false
			return_to_city.emit()


func _draw_panel() -> void:
	var font := ThemeDB.fallback_font
	var rect := Rect2(Vector2.ZERO, _panel.size)
	_panel.draw_rect(rect, PANEL_COLOR)
	_panel.draw_rect(rect, BORDER_COLOR, false, 1.5)

	# Title
	var pad := 16.0
	var y := pad + 18.0
	_panel.draw_string(font, Vector2(pad, y), "PAUSED",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_TITLE, TITLE_COLOR)

	y += 30.0
	for i in range(_items.size()):
		var color: Color = SELECTED_COLOR if i == _selected else ITEM_COLOR
		var prefix := "> " if i == _selected else "  "
		_panel.draw_string(font, Vector2(pad, y), prefix + _items[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_ITEM, color)
		y += 24.0

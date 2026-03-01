extends CanvasLayer
## Field pause menu overlay — mirrors the city menu (Inventory, Equipment, Status, Save).
## ESC toggles open/close. No "Return to City" — player must use a telepipe.

signal closed()

const BG_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const PANEL_COLOR := Color(0.1, 0.1, 0.18, 0.95)
const BORDER_COLOR := Color(0.4, 0.45, 0.6, 0.7)
const TITLE_COLOR := Color(0.8, 0.85, 1.0)
const ITEM_COLOR := Color(0.9, 0.9, 0.9)
const SELECTED_COLOR := Color(1.0, 0.9, 0.3)
const SEPARATOR_COLOR := Color(0.4, 0.4, 0.5, 0.4)
const HINT_COLOR := Color(0.6, 0.6, 0.7)
const FONT_SIZE_TITLE := 18
const FONT_SIZE_ITEM := 15
const FONT_SIZE_HINT := 11

const MENU_ITEMS := [
	"Resume",
	"Inventory",
	"Equipment",
	"Status",
	"──────────",
	"Save Game",
]

var _selected: int = 0
var _bg: ColorRect
var _panel: Control
var _feedback_timer: float = 0.0
var _feedback_text: String = ""


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
	_panel.size = Vector2(240, 220)
	_panel.position = Vector2(-120, -110)
	add_child(_panel)

	_panel.draw.connect(_draw_panel)
	_panel.queue_redraw()


func open() -> void:
	visible = true
	_selected = 0
	_feedback_text = ""
	get_tree().paused = true
	_panel.queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func _process(delta: float) -> void:
	if _feedback_timer > 0.0:
		_feedback_timer -= delta
		if _feedback_timer <= 0.0:
			_feedback_text = ""
			_panel.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_move_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_activate_item()
		get_viewport().set_input_as_handled()


func _move_selection(dir: int) -> void:
	var count := MENU_ITEMS.size()
	_selected = (_selected + dir + count) % count
	# Skip separators
	while MENU_ITEMS[_selected].begins_with("────"):
		_selected = (_selected + dir + count) % count
	_panel.queue_redraw()


func _activate_item() -> void:
	match MENU_ITEMS[_selected]:
		"Resume":
			close()
		"Inventory":
			close()
			SceneManager.push_scene("res://scenes/2d/inventory.tscn")
		"Equipment":
			close()
			SceneManager.push_scene("res://scenes/2d/equipment.tscn")
		"Status":
			close()
			SceneManager.push_scene("res://scenes/2d/status.tscn")
		"Save Game":
			SaveManager.save_game()
			_feedback_text = "Game saved!"
			_feedback_timer = 1.5
			_panel.queue_redraw()


func _draw_panel() -> void:
	var font := ThemeDB.fallback_font
	var rect := Rect2(Vector2.ZERO, _panel.size)
	_panel.draw_rect(rect, PANEL_COLOR)
	_panel.draw_rect(rect, BORDER_COLOR, false, 1.5)

	var pad := 16.0
	var y := pad + 18.0
	_panel.draw_string(font, Vector2(pad, y), "PAUSED",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_TITLE, TITLE_COLOR)

	y += 30.0
	for i in range(MENU_ITEMS.size()):
		var item: String = MENU_ITEMS[i]
		if item.begins_with("────"):
			_panel.draw_line(
				Vector2(pad, y - 6.0), Vector2(_panel.size.x - pad, y - 6.0),
				SEPARATOR_COLOR, 1.0)
			y += 12.0
			continue
		var color: Color = SELECTED_COLOR if i == _selected else ITEM_COLOR
		var prefix := "> " if i == _selected else "  "
		_panel.draw_string(font, Vector2(pad, y), prefix + item,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_ITEM, color)
		y += 24.0

	# Feedback text
	if not _feedback_text.is_empty():
		_panel.draw_string(font, Vector2(pad, _panel.size.y - 12.0), _feedback_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_ITEM, SELECTED_COLOR)

	# Hint at bottom
	var hint := "[ESC] Resume"
	var hint_w: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_HINT).x
	_panel.draw_string(font, Vector2(_panel.size.x - pad - hint_w, _panel.size.y - 12.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_HINT, HINT_COLOR)

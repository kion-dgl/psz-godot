extends CanvasLayer
## Field pause menu overlay — mirrors the city menu (Inventory, Equipment, Status, Save).
## ESC toggles open/close. No "Return to City" — player must use a telepipe.

signal closed()

# PSZ palette
const BG_COLOR := Color(0.0, 0.0, 0.0, 0.5)
const PANEL_COLOR := Color(0.66, 0.80, 0.91)        # Pale icy blue
const BORDER_COLOR := Color(0.48, 0.63, 0.75)       # Blue border
const TITLE_BG := Color(0.16, 0.16, 0.22)           # Dark navy title bar
const TITLE_COLOR := Color(1.0, 1.0, 1.0)           # White title text
const ITEM_COLOR := Color(0.1, 0.1, 0.17)           # Dark text
const ITEM_BG := Color(1.0, 1.0, 1.0, 0.85)         # White pill row
const SELECTED_BG_A := Color(0.94, 0.63, 0.13)      # Orange gradient start
const SELECTED_BG_B := Color(0.97, 0.78, 0.25)      # Orange gradient end
const SELECTED_BORDER := Color(0.82, 0.5, 0.06)     # Orange border
const SEPARATOR_COLOR := Color(0.48, 0.63, 0.75, 0.5)
const HINT_COLOR := Color(0.1, 0.1, 0.17)
const HINT_BG := Color(1.0, 1.0, 1.0, 0.7)
const SCANLINE_COLOR := Color(0.47, 0.63, 0.78, 0.08)
const FONT_SIZE_TITLE := 16
const FONT_SIZE_ITEM := 14
const FONT_SIZE_HINT := 11

const MENU_ITEMS := [
	"Resume",
	"Inventory",
	"Equipment",
	"Status",
	"──────────",
	"Save Game",
	"Return to Title",
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
	_panel.size = Vector2(260, 270)
	_panel.position = Vector2(-130, -135)
	add_child(_panel)

	_panel.draw.connect(_draw_panel)
	_panel.queue_redraw()


func open() -> void:
	visible = true
	_selected = 0
	_feedback_text = ""
	get_tree().paused = true
	_panel.queue_redraw()
	_set_field_hud_visible(false)


func close() -> void:
	visible = false
	get_tree().paused = false
	_set_field_hud_visible(true)
	closed.emit()


func _set_field_hud_visible(show: bool) -> void:
	var hud := get_parent().get_node_or_null("FieldHud")
	if hud and hud.has_method("hide_for_menu") and hud.has_method("restore_after_menu"):
		if show:
			hud.restore_after_menu()
		else:
			hud.hide_for_menu()


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
		"Return to Title":
			close()
			SaveManager.save_game()
			CityState.clear()
			SceneManager.goto_scene("res://scenes/2d/title.tscn")


func _draw_panel() -> void:
	var font := ThemeDB.fallback_font
	var pw: float = _panel.size.x
	var ph: float = _panel.size.y
	var rect := Rect2(Vector2.ZERO, _panel.size)
	var pad := 12.0

	# Panel background — pale icy blue
	_panel.draw_rect(rect, PANEL_COLOR)
	_panel.draw_rect(rect, BORDER_COLOR, false, 2.0)

	# Scanline overlay
	for sy in range(0, int(ph), 4):
		_panel.draw_rect(Rect2(0, sy + 2, pw, 2), SCANLINE_COLOR)

	# Title bar — dark navy
	var title_h := 32.0
	_panel.draw_rect(Rect2(0, 0, pw, title_h), TITLE_BG)
	_panel.draw_string(font, Vector2(pad, 22.0), "Menu",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_TITLE, TITLE_COLOR)

	var y := title_h + 10.0
	var item_h := 26.0
	for i in range(MENU_ITEMS.size()):
		var item: String = MENU_ITEMS[i]
		if item.begins_with("────"):
			_panel.draw_line(
				Vector2(pad, y + 2.0), Vector2(pw - pad, y + 2.0),
				SEPARATOR_COLOR, 1.0)
			y += 8.0
			continue

		var item_rect := Rect2(pad - 2.0, y, pw - (pad - 2.0) * 2, item_h - 3.0)
		if i == _selected:
			# Orange selected pill
			_panel.draw_rect(item_rect, SELECTED_BG_A)
			# Gradient effect — lighter right half
			_panel.draw_rect(Rect2(item_rect.position.x + item_rect.size.x * 0.5,
				item_rect.position.y, item_rect.size.x * 0.5, item_rect.size.y), SELECTED_BG_B)
			_panel.draw_rect(item_rect, SELECTED_BORDER, false, 2.0)
		else:
			# White pill
			_panel.draw_rect(item_rect, ITEM_BG)
			_panel.draw_rect(item_rect, Color(0.59, 0.71, 0.82, 0.4), false, 1.0)

		_panel.draw_string(font, Vector2(pad + 8.0, y + 17.0), item,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_ITEM, ITEM_COLOR)
		y += item_h

	# Feedback text
	if not _feedback_text.is_empty():
		_panel.draw_string(font, Vector2(pad, ph - 28.0), _feedback_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_ITEM, Color(0.13, 0.53, 0.13))

	# Hint bar at bottom
	var hint := "Select from the Menu."
	var hint_rect := Rect2(pad - 2.0, ph - 24.0, pw - (pad - 2.0) * 2, 20.0)
	_panel.draw_rect(hint_rect, HINT_BG)
	var hint_w: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_HINT).x
	_panel.draw_string(font, Vector2((pw - hint_w) * 0.5, ph - 10.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_HINT, HINT_COLOR)

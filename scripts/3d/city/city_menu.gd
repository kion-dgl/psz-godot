extends Control
## City menu overlay — ESC menu for the 3D city hub areas.
## Pushed as overlay; ESC pops back to the 3D area.

const BASE_MENU_ITEMS := [
	"Inventory",
	"Equipment",
	"Status",
	"Action Palette",
	"──────────────",
	"Save Game",
	"Options",
	"Return to Title",
]

@onready var title_label: Label = $CenterPanel/VBox/TitleLabel
@onready var menu_list = $CenterPanel/VBox/MenuList
@onready var hint_label: Label = $HintLabel
@onready var feedback_label: Label = $CenterPanel/VBox/FeedbackLabel

var _menu_items: Array = []
var _in_options: bool = false


func _ready() -> void:
	title_label.add_theme_stylebox_override("normal", PszStyle.title_style())
	title_label.add_theme_color_override("font_color", PszStyle.TEXT_WHITE)
	title_label.add_theme_font_size_override("font_size", PszStyle.FONT_TITLE)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	_build_main_menu()
	hint_label.text = "Up/Down: Navigate  Enter: Select  Esc: Resume"


func _build_main_menu() -> void:
	_in_options = false
	title_label.text = "Menu"
	_menu_items = []

	if SessionManager.has_suspended_session():
		_menu_items.append("Resume Session")

	_menu_items.append_array(BASE_MENU_ITEMS)

	var disabled_mask: Array = []
	for i in range(_menu_items.size()):
		disabled_mask.append(_menu_items[i].begins_with("────"))

	_connect_menu()
	menu_list.set_items(_menu_items, disabled_mask)


func _build_options_menu() -> void:
	_in_options = true
	title_label.text = "Options"
	hint_label.text = "Up/Down: Navigate  Enter: Toggle  Esc: Back"

	var on := "ON"
	var off := "OFF"
	_menu_items = [
		"Floor Collision: %s" % (on if DebugConfig.show_floor_collision else off),
		"Gate Dots: %s" % (on if DebugConfig.show_gate_dots else off),
		"Time + Room: %s" % (on if DebugConfig.show_time_room else off),
	]

	var disabled_mask: Array = []
	for i in range(_menu_items.size()):
		disabled_mask.append(false)

	_connect_menu()
	menu_list.set_items(_menu_items, disabled_mask)


func _connect_menu() -> void:
	if menu_list.item_selected.is_connected(_on_menu_selected):
		menu_list.item_selected.disconnect(_on_menu_selected)
	menu_list.item_selected.connect(_on_menu_selected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if _in_options:
			_build_main_menu()
		else:
			SceneManager.pop_scene()
		get_viewport().set_input_as_handled()


func _on_menu_selected(index: int) -> void:
	var item: String = _menu_items[index]

	if _in_options:
		if item.begins_with("Floor Collision:"):
			DebugConfig.show_floor_collision = not DebugConfig.show_floor_collision
		elif item.begins_with("Gate Dots:"):
			DebugConfig.show_gate_dots = not DebugConfig.show_gate_dots
		elif item.begins_with("Time + Room:"):
			DebugConfig.show_time_room = not DebugConfig.show_time_room
			TimeManager.show_hud(DebugConfig.show_time_room)
		var old_index: int = menu_list.get_current_index()
		_build_options_menu()
		menu_list.set_current_index(old_index)
		return

	match item:
		"Resume Session":
			SessionManager.resume_session()
			CityState.clear()
			SceneManager.goto_scene("res://scenes/2d/field.tscn")
		"Inventory":
			SceneManager.push_scene("res://scenes/2d/inventory.tscn")
		"Equipment":
			SceneManager.push_scene("res://scenes/2d/equipment.tscn")
		"Status":
			SceneManager.push_scene("res://scenes/2d/status.tscn")
		"Action Palette":
			SceneManager.push_scene("res://scenes/2d/action_palette.tscn")
		"Save Game":
			SaveManager.save_game()
			feedback_label.text = "Game saved!"
			feedback_label.visible = true
			await get_tree().create_timer(1.5).timeout
			if is_instance_valid(feedback_label):
				feedback_label.text = ""
				feedback_label.visible = false
		"Options":
			_build_options_menu()
		"Return to Title":
			SaveManager.save_game()
			CityState.clear()
			SceneManager.goto_scene("res://scenes/2d/title.tscn")

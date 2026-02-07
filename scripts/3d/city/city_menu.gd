extends Control
## City menu overlay — ESC menu for the 3D city hub areas.
## Pushed as overlay; ESC pops back to the 3D area.

const BASE_MENU_ITEMS := [
	"Inventory",
	"Equipment",
	"Status",
	"──────────────",
	"Save Game",
	"Return to Title",
]

@onready var menu_list = $CenterPanel/VBox/MenuList
@onready var hint_label: Label = $HintLabel
@onready var feedback_label: Label = $CenterPanel/VBox/FeedbackLabel

var _menu_items: Array = []


func _ready() -> void:
	_build_menu()
	hint_label.text = "[↑/↓] Navigate  [ENTER] Select  [ESC] Resume"


func _build_menu() -> void:
	_menu_items = []

	# Resume Session at top if there's one suspended
	if SessionManager.has_suspended_session():
		_menu_items.append("Resume Session")

	_menu_items.append_array(BASE_MENU_ITEMS)

	var disabled_mask: Array = []
	for i in range(_menu_items.size()):
		disabled_mask.append(_menu_items[i].begins_with("────"))

	menu_list.set_items(_menu_items, disabled_mask)
	menu_list.item_selected.connect(_on_menu_selected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()


func _on_menu_selected(index: int) -> void:
	match _menu_items[index]:
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
		"Save Game":
			SaveManager.save_game()
			feedback_label.text = "Game saved!"
			feedback_label.visible = true
			await get_tree().create_timer(1.5).timeout
			if is_instance_valid(feedback_label):
				feedback_label.text = ""
				feedback_label.visible = false
		"Return to Title":
			SaveManager.save_game()
			CityState.clear()
			SceneManager.goto_scene("res://scenes/2d/title.tscn")

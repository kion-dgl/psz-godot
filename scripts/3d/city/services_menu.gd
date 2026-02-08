extends Control
## Shop menu overlay — sub-menu for the Shop NPC.
## Options: Item Shop, Tech Shop.

const MENU_ITEMS := [
	"Item Shop",
	"Tech Shop",
]

@onready var menu_list = $CenterPanel/VBox/MenuList
@onready var hint_label: Label = $HintLabel


func _ready() -> void:
	hint_label.text = "[↑/↓] Navigate  [ENTER] Select  [ESC] Back"
	menu_list.set_items(MENU_ITEMS)
	menu_list.item_selected.connect(_on_menu_selected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()


func _on_menu_selected(index: int) -> void:
	match MENU_ITEMS[index]:
		"Item Shop":
			SceneManager.push_scene("res://scenes/2d/shops/item_shop.tscn")
		"Tech Shop":
			SceneManager.push_scene("res://scenes/2d/shops/tech_shop.tscn")

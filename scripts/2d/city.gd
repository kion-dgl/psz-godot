extends Control
## City hub — main navigation menu with character info sidebar.

const MENU_ITEMS := [
	"Item Shop",
	"Weapon Shop",
	"Tech Shop",
	"Tekker",
	"Storage",
	"Guild Counter",
	"Warp Teleporter",
	"──────────────",
	"Inventory",
	"Equipment",
	"Status",
	"──────────────",
	"Save Game",
	"Return to Title",
]

const DISABLED_ITEMS := [7, 11]  # Separator indices

@onready var title_label: Label = $HBox/LeftPanel/TitleLabel
@onready var menu_list = $HBox/LeftPanel/MenuList
@onready var char_panel: VBoxContainer = $HBox/RightPanel/CharInfo
@onready var hint_label: Label = $HintLabel


func _ready() -> void:
	title_label.text = "══════ CITY ══════"
	hint_label.text = "[↑/↓] Navigate  [ENTER] Select  [ESC] Quick Save & Quit"

	# Heal character to full on entering the city
	var character = CharacterManager.get_active_character()
	if character:
		character["hp"] = int(character.get("max_hp", 100))
		character["pp"] = int(character.get("max_pp", 50))
		CharacterManager._sync_to_game_state()

	var disabled_mask: Array = []
	for i in range(MENU_ITEMS.size()):
		disabled_mask.append(i in DISABLED_ITEMS)
	menu_list.set_items(MENU_ITEMS, disabled_mask)
	menu_list.item_selected.connect(_on_menu_selected)

	_update_char_info()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SaveManager.save_game()
		SceneManager.goto_scene("res://scenes/2d/title.tscn")
		get_viewport().set_input_as_handled()


func _on_menu_selected(index: int) -> void:
	match MENU_ITEMS[index]:
		"Item Shop":
			SceneManager.push_scene("res://scenes/2d/shops/item_shop.tscn")
		"Weapon Shop":
			SceneManager.push_scene("res://scenes/2d/shops/weapon_shop.tscn")
		"Tech Shop":
			SceneManager.push_scene("res://scenes/2d/shops/tech_shop.tscn")
		"Tekker":
			SceneManager.push_scene("res://scenes/2d/shops/tekker.tscn")
		"Storage":
			SceneManager.push_scene("res://scenes/2d/storage.tscn")
		"Guild Counter":
			SceneManager.push_scene("res://scenes/2d/guild_counter.tscn")
		"Warp Teleporter":
			SceneManager.push_scene("res://scenes/2d/warp_teleporter.tscn")
		"Inventory":
			SceneManager.push_scene("res://scenes/2d/inventory.tscn")
		"Equipment":
			SceneManager.push_scene("res://scenes/2d/equipment.tscn")
		"Status":
			SceneManager.push_scene("res://scenes/2d/status.tscn")
		"Save Game":
			SaveManager.save_game()
			hint_label.text = "Game saved!"
			await get_tree().create_timer(1.5).timeout
			hint_label.text = "[↑/↓] Navigate  [ENTER] Select  [ESC] Quick Save & Quit"
		"Return to Title":
			SaveManager.save_game()
			SceneManager.goto_scene("res://scenes/2d/title.tscn")


func _update_char_info() -> void:
	for child in char_panel.get_children():
		child.queue_free()

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	var stats: Dictionary = {}
	if class_data:
		stats = class_data.get_stats_at_level(int(character.get("level", 1)))

	_add_info_line("── CHARACTER ──", Color(0, 0.733, 0.8))
	_add_info_line("")
	_add_info_line(str(character.get("name", "???")), Color(1, 0.8, 0))
	_add_info_line("%s  Lv.%d" % [str(character.get("class_id", "???")), int(character.get("level", 1))])
	_add_info_line("")

	# HP bar
	var hp: int = int(character.get("hp", 0))
	var max_hp: int = int(character.get("max_hp", 1))
	var hp_ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var hp_filled := int(hp_ratio * 10)
	_add_info_line("HP %s %d/%d" % ["█".repeat(hp_filled) + "░".repeat(10 - hp_filled), hp, max_hp])

	# PP bar
	var pp: int = int(character.get("pp", 0))
	var max_pp: int = int(character.get("max_pp", 1))
	var pp_ratio := clampf(float(pp) / float(max_pp), 0.0, 1.0)
	var pp_filled := int(pp_ratio * 10)
	_add_info_line("PP %s %d/%d" % ["█".repeat(pp_filled) + "░".repeat(10 - pp_filled), pp, max_pp])

	_add_info_line("")
	_add_info_line("Meseta: %s" % _format_number(int(character.get("meseta", 0))), Color(1, 0.8, 0))

	# Stats
	_add_info_line("")
	_add_info_line("── STATS ──", Color(0, 0.733, 0.8))
	_add_info_line("  ATK  %d" % stats.get("attack", 0))
	_add_info_line("  DEF  %d" % stats.get("defense", 0))
	_add_info_line("  ACC  %d" % stats.get("accuracy", 0))
	_add_info_line("  EVA  %d" % stats.get("evasion", 0))
	_add_info_line("  TEC  %d" % stats.get("technique", 0))


func _add_info_line(text: String, color: Color = Color(0, 1, 0.533)) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	char_panel.add_child(label)


func _format_number(n: int) -> String:
	var s := str(n)
	var result := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	return result

extends Control
## City hub — main navigation menu with character info sidebar.

const BASE_MENU_ITEMS := [
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

@onready var title_label: Label = $HBox/LeftPanel/TitleLabel
@onready var menu_list = $HBox/LeftPanel/MenuList
@onready var char_panel: VBoxContainer = $HBox/RightPanel/CharInfo
@onready var hint_label: Label = $HintLabel

var _menu_items: Array = []
var _disabled_items: Array = []


func _ready() -> void:
	title_label.text = "CITY"
	hint_label.text = "[↑/↓] Navigate  [ENTER] Select  [ESC] Quick Save & Quit"

	title_label.add_theme_color_override("font_color", ThemeColors.HEADER_TEXT)
	title_label.add_theme_font_size_override("font_size", 18)
	hint_label.add_theme_color_override("font_color", ThemeColors.HINT_TEXT)
	hint_label.add_theme_font_size_override("font_size", 14)

	# Heal character to full on entering the city
	var character = CharacterManager.get_active_character()
	if character:
		character["hp"] = int(character.get("max_hp", 100))
		character["pp"] = int(character.get("max_pp", 50))
		CharacterManager._sync_to_game_state()

	_build_menu()
	_update_char_info()


func _build_menu() -> void:
	_menu_items = BASE_MENU_ITEMS.duplicate()
	_disabled_items = []

	# Insert "Resume Session" at index 0 if there's a suspended session
	if SessionManager.has_suspended_session():
		_menu_items.insert(0, "Resume Session")

	# Build disabled mask — separators are disabled
	var disabled_mask: Array = []
	for i in range(_menu_items.size()):
		var is_sep: bool = _menu_items[i].begins_with("────")
		disabled_mask.append(is_sep)
		if is_sep:
			_disabled_items.append(i)

	menu_list.set_items(_menu_items, disabled_mask)
	menu_list.item_selected.connect(_on_menu_selected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SaveManager.save_game()
		SceneManager.goto_scene("res://scenes/2d/title.tscn")
		get_viewport().set_input_as_handled()


func _on_menu_selected(index: int) -> void:
	match _menu_items[index]:
		"Resume Session":
			SessionManager.resume_session()
			SceneManager.goto_scene("res://scenes/2d/field.tscn")
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

	_add_info_line("CHARACTER", ThemeColors.HEADER)
	_add_info_line("")
	_add_info_line(str(character.get("name", "???")), ThemeColors.TEXT_HIGHLIGHT)
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
	_add_info_line("Meseta: %s" % _format_number(int(character.get("meseta", 0))), ThemeColors.MESETA_GOLD)

	# Stats
	_add_info_line("")
	_add_info_line("STATS", ThemeColors.HEADER)
	_add_info_line("  ATK  %d" % stats.get("attack", 0))
	_add_info_line("  DEF  %d" % stats.get("defense", 0))
	_add_info_line("  ACC  %d" % stats.get("accuracy", 0))
	_add_info_line("  EVA  %d" % stats.get("evasion", 0))
	_add_info_line("  TEC  %d" % stats.get("technique", 0))


func _add_info_line(text: String, color: Color = ThemeColors.TEXT_PRIMARY) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	char_panel.add_child(label)


func _format_number(n: int) -> String:
	var s := str(n)
	var result := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	return result

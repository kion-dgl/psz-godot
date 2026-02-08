extends Control
## Shop — buy consumables or technique disks, toggled with tabs.

enum Tab { ITEMS, DISKS }

var _tab: int = Tab.ITEMS
var _selected_index: int = 0

# Items tab data
var _shop_items: Array = []

# Disks tab data
var _disk_items: Array = []

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeBar/ModeLabel
@onready var shop_panel: PanelContainer = $Panel/VBox/HBox/ShopPanel
@onready var detail_panel: PanelContainer = $Panel/VBox/HBox/DetailPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	title_label.text = "SHOP"
	hint_label.text = "[←/→] Items/Disks  [↑/↓] Select  [ENTER] Buy  [ESC] Leave"
	_load_shop_items()
	_generate_disk_inventory()
	_refresh_display()


func _load_shop_items() -> void:
	_shop_items = ShopManager.get_shop_inventory("item_shop")
	if _shop_items.is_empty():
		for shop in ShopRegistry.get_all_shops():
			if "item" in shop.name.to_lower() or "consumable" in shop.description.to_lower():
				_shop_items = shop.items.duplicate()
				break


func _generate_disk_inventory() -> void:
	var character = CharacterManager.get_active_character()
	var char_level: int = int(character.get("level", 1)) if character else 1
	_disk_items = TechniqueManager.generate_shop_inventory(char_level)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_tab = Tab.DISKS if _tab == Tab.ITEMS else Tab.ITEMS
		_selected_index = 0
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected_index = wrapi(_selected_index - 1, 0, maxi(_get_current_list().size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_index = wrapi(_selected_index + 1, 0, maxi(_get_current_list().size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_on_select()
		get_viewport().set_input_as_handled()


func _get_current_list() -> Array:
	return _shop_items if _tab == Tab.ITEMS else _disk_items


func _on_select() -> void:
	if _tab == Tab.ITEMS:
		_buy_item()
	else:
		_buy_disk()


func _buy_item() -> void:
	if _shop_items.is_empty() or _selected_index >= _shop_items.size():
		return

	var item := _shop_items[_selected_index] as Dictionary
	var item_name: String = str(item.get("item", ""))
	var cost: int = int(item.get("cost", 0))
	if ShopManager.buy_item("item_shop", item_name):
		hint_label.text = "Bought %s for %d meseta!" % [item_name, cost]
	else:
		hint_label.text = "Not enough meseta!"
	_refresh_display()


func _buy_disk() -> void:
	if _disk_items.is_empty() or _selected_index >= _disk_items.size():
		return
	var item: Dictionary = _disk_items[_selected_index]
	var cost: int = int(item.get("cost", 0))
	var technique_id: String = str(item.get("technique_id", ""))
	var level: int = int(item.get("level", 1))
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	if int(character.get("meseta", 0)) < cost:
		hint_label.text = "Not enough meseta!"
		return

	var disk_id: String = "disk_%s_%d" % [technique_id, level]
	if not Inventory.can_add_item(disk_id):
		hint_label.text = "Inventory full!"
		return

	character["meseta"] = int(character["meseta"]) - cost
	GameState.meseta = int(character["meseta"])

	Inventory.add_item(disk_id, 1)
	var tech_name: String = str(TechniqueManager.TECHNIQUES.get(technique_id, {}).get("name", technique_id))
	hint_label.text = "Bought Disk: %s Lv.%d!" % [tech_name, level]
	_refresh_display()


func _refresh_display() -> void:
	# Mode bar
	if _tab == Tab.ITEMS:
		mode_label.text = "[◄ ITEMS ►]    DISKS    |  Meseta: %s" % _get_meseta_str()
	else:
		mode_label.text = "   ITEMS    [◄ DISKS ►] |  Meseta: %s" % _get_meseta_str()

	# Shop panel
	for child in shop_panel.get_children():
		child.queue_free()

	var list := _get_current_list()
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var selected_label: Label = null

	if list.is_empty():
		var empty := Label.new()
		empty.text = "  (No items)" if _tab == Tab.ITEMS else "  (No techniques available)"
		empty.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
		vbox.add_child(empty)
	elif _tab == Tab.ITEMS:
		for i in range(list.size()):
			var label := Label.new()
			var item: Dictionary = list[i]
			var shop_name: String = str(item.get("item", "???"))
			var item_id: String = shop_name.to_lower().replace(" ", "_").replace("-", "_").replace("/", "_")
			var held: int = Inventory.get_item_count(item_id)
			var held_str: String = " (%d)" % held if held > 0 else ""
			label.text = "%-18s%s %5d M" % [shop_name, held_str, int(item.get("cost", 0))]
			if i == _selected_index:
				label.text = "> " + label.text
				label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
				selected_label = label
			else:
				label.text = "  " + label.text
			vbox.add_child(label)
	else:
		var character = CharacterManager.get_active_character()
		var char_level: int = int(character.get("level", 1)) if character else 1
		var current_meseta: int = int(character.get("meseta", 0)) if character else 0

		for i in range(list.size()):
			var item: Dictionary = list[i]
			var technique_id: String = str(item.get("technique_id", ""))
			var level: int = int(item.get("level", 1))
			var cost: int = int(item.get("cost", 0))
			var disk_name: String = str(item.get("name", "???"))

			var current_tech_level: int = 0
			if character:
				current_tech_level = TechniqueManager.get_technique_level(character, technique_id)

			var required_level: int = TechniqueManager.get_disk_required_level(level)
			var cant_afford: bool = current_meseta < cost
			var too_low_level: bool = char_level < required_level
			var already_higher: bool = current_tech_level >= level

			var status_tag := ""
			if already_higher:
				status_tag = " [Lv.%d]" % current_tech_level
			elif current_tech_level > 0:
				status_tag = " [Lv.%d]" % current_tech_level
			if too_low_level:
				status_tag += " [Req.%d]" % required_level

			var label := Label.new()
			label.text = "%-22s %5d M%s" % [disk_name, cost, status_tag]

			if i == _selected_index:
				label.text = "> " + label.text
				if already_higher:
					label.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
				elif too_low_level:
					label.add_theme_color_override("font_color", ThemeColors.RESTRICT_LEVEL)
				elif cant_afford:
					label.add_theme_color_override("font_color", ThemeColors.WARNING)
				else:
					label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
				selected_label = label
			else:
				label.text = "  " + label.text
				if already_higher:
					label.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
				elif too_low_level:
					label.add_theme_color_override("font_color", ThemeColors.RESTRICT_LEVEL)
				elif cant_afford:
					label.add_theme_color_override("font_color", ThemeColors.WARNING)
			vbox.add_child(label)

	scroll.add_child(vbox)
	shop_panel.add_child(scroll)

	if selected_label != null:
		scroll.ensure_control_visible.call_deferred(selected_label)

	# Detail panel
	_refresh_detail()


func _refresh_detail() -> void:
	for child in detail_panel.get_children():
		child.queue_free()

	var list := _get_current_list()
	if list.is_empty() or _selected_index >= list.size():
		return

	if _tab == Tab.ITEMS:
		_refresh_item_detail(list[_selected_index])
	else:
		_refresh_disk_detail(list[_selected_index])


func _refresh_item_detail(item: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "── %s ──" % str(item.get("item", "???"))
	name_label.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(name_label)

	var cat_label := Label.new()
	cat_label.text = "Category: %s" % str(item.get("category", "unknown"))
	vbox.add_child(cat_label)

	var cost_label := Label.new()
	cost_label.text = "Cost: %d %s" % [int(item.get("cost", 0)), str(item.get("currency", "Meseta"))]
	cost_label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
	vbox.add_child(cost_label)

	var consumable = ConsumableRegistry.get_consumable(
		str(item.get("item", "")).to_lower().replace(" ", "_").replace("-", "_").replace("/", "_")
	)
	if consumable:
		var details_label := Label.new()
		details_label.text = consumable.details
		details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(details_label)

	detail_panel.add_child(vbox)


func _refresh_disk_detail(item: Dictionary) -> void:
	var technique_id: String = str(item.get("technique_id", ""))
	var level: int = int(item.get("level", 1))
	var tech: Dictionary = TechniqueManager.get_technique(technique_id)
	if tech.is_empty():
		return

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "── %s ──" % str(item.get("name", "???"))
	name_label.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(name_label)

	_add_line(vbox, "Element: %s" % str(tech.get("element", "none")).capitalize())
	_add_line(vbox, "Target: %s" % str(tech.get("target", "single")).capitalize())

	var power: int = int(tech.get("power", 0))
	if power > 0:
		var scaled_power: int = int(float(power) * (1.0 + float(level) / 10.0))
		_add_line(vbox, "Power: %d (Lv.%d)" % [scaled_power, level])

	var pp_cost: int = maxi(1, int(tech.get("pp", 5)) - int(float(level) / 5.0))
	_add_line(vbox, "PP Cost: %d" % pp_cost)

	var required_level: int = TechniqueManager.get_disk_required_level(level)
	var character = CharacterManager.get_active_character()
	var char_level: int = int(character.get("level", 1)) if character else 1
	var req_label := Label.new()
	req_label.text = "Req. Level: %d" % required_level
	if char_level < required_level:
		req_label.add_theme_color_override("font_color", ThemeColors.RESTRICT_LEVEL)
	vbox.add_child(req_label)

	if character:
		var current_level: int = TechniqueManager.get_technique_level(character, technique_id)
		if current_level > 0:
			var cur_label := Label.new()
			if current_level >= level:
				cur_label.text = "Known: Lv.%d (already higher)" % current_level
				cur_label.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
			else:
				cur_label.text = "Known: Lv.%d → Lv.%d" % [current_level, level]
				cur_label.add_theme_color_override("font_color", ThemeColors.EQUIPPABLE)
			vbox.add_child(cur_label)

	var sep := Label.new()
	sep.text = ""
	vbox.add_child(sep)
	var cost_label := Label.new()
	cost_label.text = "Price: %d M" % int(item.get("cost", 0))
	cost_label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
	vbox.add_child(cost_label)

	var note := Label.new()
	note.text = "Use from inventory to learn"
	note.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
	vbox.add_child(note)

	detail_panel.add_child(vbox)


func _add_line(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)


func _get_meseta_str() -> String:
	var character = CharacterManager.get_active_character()
	if character:
		return str(int(character.get("meseta", 0)))
	return "0"

extends Control
## Shop — buy consumables or technique disks, toggled with tabs.

enum Tab { ITEMS, DISKS, SELL }

const TAB_COUNT := 3
const TAB_NAMES := ["Items", "Disks", "Sell"]

var _tab: int = Tab.ITEMS
var _selected_index: int = 0

# Items tab data
var _shop_items: Array = []

# Disks tab data
var _disk_items: Array = []

# Sell tab data
var _sell_items: Array = []

var _mode_bar: HBoxContainer

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeBar/ModeLabel
@onready var shop_panel: PanelContainer = $Panel/VBox/HBox/ShopPanel
@onready var detail_panel: PanelContainer = $Panel/VBox/HBox/DetailPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	_mode_bar = mode_label.get_parent()
	PszStyle.style_menu(title_label, hint_label, [shop_panel, detail_panel])
	title_label.text = "Item Shop"
	_update_hint()
	_load_shop_items()
	_generate_disk_inventory()
	_generate_sell_list()
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


func _generate_sell_list() -> void:
	_sell_items.clear()
	for item_info in Inventory.get_all_items():
		var item_id: String = str(item_info.get("id", ""))
		var qty: int = int(item_info.get("quantity", 0))
		if qty <= 0:
			continue
		var sell_price: int = 10
		var item_name: String = str(item_info.get("name", item_id))
		var consumable = ConsumableRegistry.get_consumable(item_id)
		if consumable:
			item_name = consumable.name
			sell_price = maxi(int(consumable.sell_price), 1)
		_sell_items.append({
			"id": item_id, "name": item_name,
			"sell_price": sell_price, "quantity": qty,
		})


func _update_hint() -> void:
	if _tab == Tab.SELL:
		hint_label.text = "Left/Right: Category  Up/Down: Select  Enter: Sell  Esc: Leave"
	else:
		hint_label.text = "Left/Right: Category  Up/Down: Select  Enter: Buy  Esc: Leave"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_tab = wrapi(_tab - 1, 0, TAB_COUNT)
		_selected_index = 0
		if _tab == Tab.SELL:
			_generate_sell_list()
		_update_hint()
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_tab = wrapi(_tab + 1, 0, TAB_COUNT)
		_selected_index = 0
		if _tab == Tab.SELL:
			_generate_sell_list()
		_update_hint()
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
	match _tab:
		Tab.ITEMS: return _shop_items
		Tab.DISKS: return _disk_items
		Tab.SELL: return _sell_items
	return _shop_items


func _on_select() -> void:
	if _tab == Tab.ITEMS:
		_buy_item()
	elif _tab == Tab.DISKS:
		_buy_disk()
	else:
		_sell_selected()


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


func _sell_selected() -> void:
	if _sell_items.is_empty() or _selected_index >= _sell_items.size():
		return
	var item: Dictionary = _sell_items[_selected_index]
	var item_id: String = str(item.get("id", ""))
	var sell_price: int = int(item.get("sell_price", 0))
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	if not Inventory.remove_item(item_id, 1):
		hint_label.text = "Cannot sell that!"
		return

	character["meseta"] = int(character.get("meseta", 0)) + sell_price
	GameState.meseta = int(character["meseta"])
	hint_label.text = "Sold %s for %d M!" % [str(item.get("name", "???")), sell_price]
	_generate_sell_list()
	if _selected_index >= _sell_items.size():
		_selected_index = maxi(0, _sell_items.size() - 1)
	_refresh_display()


func _refresh_display() -> void:
	# Tab bar
	for child in _mode_bar.get_children():
		child.queue_free()
	var tab_bar := PszStyle.create_tab_bar(TAB_NAMES, _tab)
	_mode_bar.add_child(tab_bar)
	var meseta_lbl := PszStyle.create_meseta_label(_get_meseta())
	_mode_bar.add_child(meseta_lbl)

	# Shop panel — pill rows
	for child in shop_panel.get_children():
		child.queue_free()

	var list := _get_current_list()
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	var selected_pill: Control = null

	if list.is_empty():
		var empty_text := "(Nothing to sell)" if _tab == Tab.SELL else "(No items)" if _tab == Tab.ITEMS else "(No techniques available)"
		var pill := PszStyle.create_pill(empty_text, false, "", PszStyle.TEXT_MUTED)
		vbox.add_child(pill)
	elif _tab == Tab.SELL:
		for i in range(list.size()):
			var item: Dictionary = list[i]
			var sell_price: int = int(item.get("sell_price", 0))
			var qty: int = int(item.get("quantity", 1))
			var qty_str := " x%d" % qty if qty > 1 else ""
			var pill := PszStyle.create_pill(
				str(item.get("name", "???")) + qty_str,
				i == _selected_index, "%d M" % sell_price)
			vbox.add_child(pill)
			if i == _selected_index:
				selected_pill = pill
	elif _tab == Tab.ITEMS:
		for i in range(list.size()):
			var item: Dictionary = list[i]
			var shop_name: String = str(item.get("item", "???"))
			var item_id: String = shop_name.to_lower().replace(" ", "_").replace("-", "_").replace("/", "_")
			var held: int = Inventory.get_item_count(item_id)
			var held_str: String = " (%d)" % held if held > 0 else ""
			var pill := PszStyle.create_pill(
				shop_name + held_str,
				i == _selected_index, "%d M" % int(item.get("cost", 0)))
			vbox.add_child(pill)
			if i == _selected_index:
				selected_pill = pill
	else:
		# Disks tab
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

			var text_color := Color.TRANSPARENT
			if already_higher:
				text_color = PszStyle.TEXT_MUTED
			elif too_low_level:
				text_color = PszStyle.TEXT_WARNING
			elif cant_afford:
				text_color = PszStyle.TEXT_WARNING

			var status_tag := ""
			if current_tech_level > 0:
				status_tag = " [Lv.%d]" % current_tech_level
			if too_low_level:
				status_tag += " [Req.%d]" % required_level

			var pill := PszStyle.create_pill(
				disk_name + status_tag,
				i == _selected_index, "%d M" % cost, text_color)
			vbox.add_child(pill)
			if i == _selected_index:
				selected_pill = pill

	scroll.add_child(vbox)
	shop_panel.add_child(scroll)

	if selected_pill != null:
		scroll.ensure_control_visible.call_deferred(selected_pill)

	_refresh_detail()


func _refresh_detail() -> void:
	for child in detail_panel.get_children():
		child.queue_free()

	var list := _get_current_list()
	if list.is_empty() or _selected_index >= list.size():
		return

	if _tab == Tab.ITEMS:
		_refresh_item_detail(list[_selected_index])
	elif _tab == Tab.DISKS:
		_refresh_disk_detail(list[_selected_index])
	else:
		_refresh_sell_detail(list[_selected_index])


func _refresh_item_detail(item: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	vbox.add_child(PszStyle.detail_label(str(item.get("item", "???")), PszStyle.TITLE_BG))

	var cat_label := PszStyle.detail_label("Category: %s" % str(item.get("category", "unknown")))
	vbox.add_child(cat_label)

	var cost_label := PszStyle.detail_label(
		"Cost: %d %s" % [int(item.get("cost", 0)), str(item.get("currency", "Meseta"))],
		PszStyle.TEXT_HIGHLIGHT)
	vbox.add_child(cost_label)

	var consumable = ConsumableRegistry.get_consumable(
		str(item.get("item", "")).to_lower().replace(" ", "_").replace("-", "_").replace("/", "_")
	)
	if consumable:
		var details_label := PszStyle.detail_label(consumable.details)
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

	vbox.add_child(PszStyle.detail_label(str(item.get("name", "???")), PszStyle.TITLE_BG))
	vbox.add_child(PszStyle.detail_label("Element: %s" % str(tech.get("element", "none")).capitalize()))
	vbox.add_child(PszStyle.detail_label("Target: %s" % str(tech.get("target", "single")).capitalize()))

	var power: int = int(tech.get("power", 0))
	if power > 0:
		var scaled_power: int = int(float(power) * (1.0 + float(level) / 10.0))
		vbox.add_child(PszStyle.detail_label("Power: %d (Lv.%d)" % [scaled_power, level]))

	var pp_cost: int = maxi(1, int(tech.get("pp", 5)) - int(float(level) / 5.0))
	vbox.add_child(PszStyle.detail_label("PP Cost: %d" % pp_cost))

	var required_level: int = TechniqueManager.get_disk_required_level(level)
	var character = CharacterManager.get_active_character()
	var char_level: int = int(character.get("level", 1)) if character else 1
	var req_color := PszStyle.TEXT_WARNING if char_level < required_level else PszStyle.TEXT
	vbox.add_child(PszStyle.detail_label("Req. Level: %d" % required_level, req_color))

	if character:
		var current_level: int = TechniqueManager.get_technique_level(character, technique_id)
		if current_level > 0:
			if current_level >= level:
				vbox.add_child(PszStyle.detail_label("Known: Lv.%d (already higher)" % current_level, PszStyle.TEXT_MUTED))
			else:
				vbox.add_child(PszStyle.detail_label("Known: Lv.%d -> Lv.%d" % [current_level, level], PszStyle.TEXT_SUCCESS))

	vbox.add_child(PszStyle.detail_label(""))
	vbox.add_child(PszStyle.detail_label("Price: %d M" % int(item.get("cost", 0)), PszStyle.TEXT_HIGHLIGHT))
	vbox.add_child(PszStyle.detail_label("Use from inventory to learn", PszStyle.TEXT_MUTED))

	detail_panel.add_child(vbox)


func _refresh_sell_detail(item: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	vbox.add_child(PszStyle.detail_label(str(item.get("name", "???")), PszStyle.TITLE_BG))
	vbox.add_child(PszStyle.detail_label("Owned: %d" % int(item.get("quantity", 0))))
	vbox.add_child(PszStyle.detail_label(""))
	vbox.add_child(PszStyle.detail_label("Sell: %d M" % int(item.get("sell_price", 0)), PszStyle.TEXT_HIGHLIGHT))

	detail_panel.add_child(vbox)


func _get_meseta() -> int:
	var character = CharacterManager.get_active_character()
	if character:
		return int(character.get("meseta", 0))
	return 0

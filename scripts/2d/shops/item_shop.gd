extends Control
## Item shop — buy/sell consumables with two-column layout.

enum Mode { BUY, SELL }

var _mode: int = Mode.BUY
var _shop_items: Array = []
var _selected_index: int = 0

@onready var title_label: Label = $VBox/TitleLabel
@onready var mode_label: Label = $VBox/ModeBar/ModeLabel
@onready var shop_panel: PanelContainer = $VBox/HBox/ShopPanel
@onready var detail_panel: PanelContainer = $VBox/HBox/DetailPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "ITEM SHOP"
	_load_shop_items()
	_refresh_display()


func _load_shop_items() -> void:
	_shop_items = ShopManager.get_shop_inventory("item_shop")
	if _shop_items.is_empty():
		# Fallback: try other shop IDs
		for shop in ShopRegistry.get_all_shops():
			if "item" in shop.name.to_lower() or "consumable" in shop.description.to_lower():
				_shop_items = shop.items.duplicate()
				break


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected_index = wrapi(_selected_index - 1, 0, maxi(_get_current_list().size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_index = wrapi(_selected_index + 1, 0, maxi(_get_current_list().size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_mode = Mode.SELL if _mode == Mode.BUY else Mode.BUY
		_selected_index = 0
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_on_select()
		get_viewport().set_input_as_handled()


func _get_current_list() -> Array:
	if _mode == Mode.BUY:
		return _shop_items
	else:
		# Sell mode: show player inventory
		return Inventory.get_all_items()


func _on_select() -> void:
	var list := _get_current_list()
	if list.is_empty() or _selected_index >= list.size():
		return

	if _mode == Mode.BUY:
		var item := list[_selected_index] as Dictionary
		var item_name: String = item.get("item", "")
		var cost: int = int(item.get("cost", 0))
		if ShopManager.buy_item("item_shop", item_name):
			hint_label.text = "Bought %s for %d meseta!" % [item_name, cost]
		else:
			hint_label.text = "Not enough meseta!"
	else:
		# Sell mode
		var item := list[_selected_index] as Dictionary
		var item_id: String = item.get("id", "")
		# Estimate sell price as 1/4 buy price
		ShopManager.sell_item(item_id, 25)
		Inventory.remove_item(item_id, 1)
		hint_label.text = "Sold %s!" % item_id

	_refresh_display()


func _refresh_display() -> void:
	# Mode bar
	if _mode == Mode.BUY:
		mode_label.text = "[◄ BUY ►]    SELL    |  Meseta: %s" % _get_meseta_str()
	else:
		mode_label.text = "   BUY    [◄ SELL ►] |  Meseta: %s" % _get_meseta_str()

	hint_label.text = "[↑/↓] Select  [←/→] Buy/Sell  [ENTER] Confirm  [ESC] Leave"

	# Shop panel
	for child in shop_panel.get_children():
		child.queue_free()

	var list := _get_current_list()
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if list.is_empty():
		var empty := Label.new()
		empty.text = "  (No items)"
		empty.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
		vbox.add_child(empty)
	else:
		for i in range(list.size()):
			var label := Label.new()
			if _mode == Mode.BUY:
				var item: Dictionary = list[i]
				var shop_name: String = str(item.get("item", "???"))
				var item_id: String = shop_name.to_lower().replace(" ", "_").replace("-", "_").replace("/", "_")
				var held: int = Inventory.get_item_count(item_id)
				var held_str: String = " (%d)" % held if held > 0 else ""
				label.text = "%-18s%s %5d M" % [shop_name, held_str, int(item.get("cost", 0))]
			else:
				var item: Dictionary = list[i]
				label.text = "%-20s x%d" % [str(item.get("name", item.get("id", "???"))), int(item.get("quantity", 0))]

			if i == _selected_index:
				label.text = "> " + label.text
				label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
			else:
				label.text = "  " + label.text
			vbox.add_child(label)

	scroll.add_child(vbox)
	shop_panel.add_child(scroll)

	# Detail panel
	_refresh_detail()


func _refresh_detail() -> void:
	for child in detail_panel.get_children():
		child.queue_free()

	var list := _get_current_list()
	if list.is_empty() or _selected_index >= list.size():
		return

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	if _mode == Mode.BUY:
		var item: Dictionary = list[_selected_index]
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

		# Look up consumable details
		var consumable = ConsumableRegistry.get_consumable(
			str(item.get("item", "")).to_lower().replace(" ", "_").replace("-", "_").replace("/", "_")
		)
		if consumable:
			var details_label := Label.new()
			details_label.text = consumable.details
			details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(details_label)

	detail_panel.add_child(vbox)


func _get_meseta_str() -> String:
	var character = CharacterManager.get_active_character()
	if character:
		return str(int(character.get("meseta", 0)))
	return "0"

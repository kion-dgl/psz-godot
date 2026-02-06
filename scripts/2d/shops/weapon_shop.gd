extends Control
## Weapon shop — browse and buy weapons/armor with stat comparison.

var _items: Array = []
var _selected_index: int = 0

@onready var title_label: Label = $VBox/TitleLabel
@onready var list_panel: PanelContainer = $VBox/HBox/ListPanel
@onready var detail_panel: PanelContainer = $VBox/HBox/DetailPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "══════ WEAPON SHOP ══════"
	hint_label.text = "[↑/↓] Select  [ENTER] Buy  [ESC] Leave"
	_load_items()
	_refresh_display()


func _load_items() -> void:
	# Get weapon shop inventory
	_items = ShopManager.get_shop_inventory("weapon_shop")
	if _items.is_empty():
		for shop in ShopRegistry.get_all_shops():
			if "weapon" in shop.name.to_lower():
				_items = shop.items.duplicate()
				break
	# If still empty, show available weapons from registry
	if _items.is_empty():
		var weapons := WeaponRegistry.get_all_weapon_ids()
		for i in range(mini(weapons.size(), 20)):
			var w = WeaponRegistry.get_weapon(weapons[i])
			if w:
				_items.append({
					"item": w.name,
					"category": "weapon",
					"cost": w.resale_value * 3,
					"currency": "Meseta",
					"weapon_id": w.id
				})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected_index = wrapi(_selected_index - 1, 0, maxi(_items.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_index = wrapi(_selected_index + 1, 0, maxi(_items.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_buy_selected()
		get_viewport().set_input_as_handled()


func _buy_selected() -> void:
	if _items.is_empty() or _selected_index >= _items.size():
		return
	var item: Dictionary = _items[_selected_index]
	var cost: int = int(item.get("cost", 0))
	var character := CharacterManager.get_active_character()
	if character == null:
		return
	if int(character.get("meseta", 0)) < cost:
		hint_label.text = "Not enough meseta!"
		return
	character["meseta"] = int(character["meseta"]) - cost
	GameState.meseta = int(character["meseta"])
	hint_label.text = "Bought %s for %d meseta!" % [str(item.get("item", "???")), cost]
	_refresh_display()


func _refresh_display() -> void:
	for child in list_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var meseta_label := Label.new()
	meseta_label.text = "Meseta: %s" % _get_meseta_str()
	meseta_label.modulate = Color(1, 0.8, 0)
	vbox.add_child(meseta_label)

	var sep := Label.new()
	sep.text = "─────────────────────────────────"
	sep.modulate = Color(0.333, 0.333, 0.333)
	vbox.add_child(sep)

	if _items.is_empty():
		var empty := Label.new()
		empty.text = "  (No weapons available)"
		empty.modulate = Color(0.333, 0.333, 0.333)
		vbox.add_child(empty)
	else:
		for i in range(_items.size()):
			var item: Dictionary = _items[i]
			var label := Label.new()
			label.text = "%-22s %6d M" % [str(item.get("item", "???")), int(item.get("cost", 0))]
			if i == _selected_index:
				label.text = "> " + label.text
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + label.text
			vbox.add_child(label)

	scroll.add_child(vbox)
	list_panel.add_child(scroll)
	_refresh_detail()


func _refresh_detail() -> void:
	for child in detail_panel.get_children():
		child.queue_free()

	if _items.is_empty() or _selected_index >= _items.size():
		return

	var item: Dictionary = _items[_selected_index]
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "── %s ──" % str(item.get("item", "???"))
	name_label.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(name_label)

	# Try to look up weapon details
	var weapon_id: String = str(item.get("weapon_id", ""))
	if weapon_id.is_empty():
		weapon_id = str(item.get("item", "")).to_lower().replace(" ", "_")
	var weapon = WeaponRegistry.get_weapon(weapon_id)
	if weapon:
		_add_detail_line(vbox, "Type: %s" % weapon.get_weapon_type_name())
		_add_detail_line(vbox, "Rarity: %s" % weapon.get_rarity_string(), Color(1, 0.8, 0))
		_add_detail_line(vbox, "ATK: %d-%d" % [weapon.attack_base, weapon.attack_max])
		_add_detail_line(vbox, "ACC: %d" % weapon.accuracy_base)
		if not weapon.element.is_empty():
			_add_detail_line(vbox, "Element: %s Lv.%d" % [weapon.element, weapon.element_level])
		_add_detail_line(vbox, "Max Grind: +%d" % weapon.max_grind)
		_add_detail_line(vbox, "Req. Level: %d" % weapon.level)

	var cost_label := Label.new()
	cost_label.text = "\nPrice: %d Meseta" % int(item.get("cost", 0))
	cost_label.modulate = Color(1, 0.8, 0)
	vbox.add_child(cost_label)

	detail_panel.add_child(vbox)


func _add_detail_line(parent: VBoxContainer, text: String, color: Color = Color(0, 1, 0.533)) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	parent.add_child(label)


func _get_meseta_str() -> String:
	var character := CharacterManager.get_active_character()
	if character:
		return str(int(character.get("meseta", 0)))
	return "0"

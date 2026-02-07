extends Control
## Weapon shop — browse and buy weapons, armor, and units.

var _items: Array = []  # Array of dicts: {id, name, category, cost, sell_price}
var _selected_index: int = 0

## Shop weapon pool — basic and mid-tier weapons
const SHOP_WEAPON_IDS := [
	"saber", "blade", "daggers", "handgun", "cane", "rod", "wand",
	"clear_saber", "chrome_cutlass", "ein_blade", "red_saber",
]

## Shop armor pool
const SHOP_ARMOR_IDS := [
	"normal_frame", "common_armor", "battle_armor",
	"brigandine_armor", "asgard_frame",
]

## Shop unit pool — starter stat and resist units
const SHOP_UNIT_IDS := [
	"rookie_hp", "rookie_pp",
	"ace_power", "ace_guard", "ace_mind", "ace_hit", "ace_swift",
	"heat_resist_lv1", "ice_resist_lv1", "light_resist_lv1", "dark_resist_lv1",
]

@onready var title_label: Label = $VBox/TitleLabel
@onready var list_panel: PanelContainer = $VBox/HBox/ListPanel
@onready var detail_panel: PanelContainer = $VBox/HBox/DetailPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "══════ WEAPON SHOP ══════"
	hint_label.text = "[↑/↓] Select  [ENTER] Buy  [ESC] Leave"
	_generate_inventory()
	_refresh_display()


func _generate_inventory() -> void:
	_items.clear()

	# Weapons
	for wid in SHOP_WEAPON_IDS:
		var w = WeaponRegistry.get_weapon(wid)
		if w == null:
			continue
		var price: int = _weapon_price(w)
		_items.append({
			"id": w.id,
			"name": w.name,
			"category": "weapon",
			"cost": price,
			"sell_price": int(price * 0.25),
		})

	# Armors
	for aid in SHOP_ARMOR_IDS:
		var a = ArmorRegistry.get_armor(aid)
		if a == null:
			continue
		var price: int = _armor_price(a)
		_items.append({
			"id": a.id,
			"name": a.name,
			"category": "armor",
			"cost": price,
			"sell_price": int(price * 0.25),
		})

	# Units
	for uid in SHOP_UNIT_IDS:
		var u = UnitRegistry.get_unit(uid)
		if u == null:
			continue
		var price: int = _unit_price(u)
		_items.append({
			"id": u.id,
			"name": u.name,
			"category": "unit",
			"cost": price,
			"sell_price": int(price * 0.25),
		})


## Price formula: (ATK_base × 15) + (rarity - 1) × 500
func _weapon_price(w) -> int:
	var base: int = int(w.attack_base) * 15 + (int(w.rarity) - 1) * 500
	return maxi(base, 50)


## Price formula: (DEF_base × 12) + (rarity - 1) × 400 + slots × 500
func _armor_price(a) -> int:
	var base: int = int(a.defense_base) * 12 + (int(a.rarity) - 1) * 400 + int(a.max_slots) * 500
	return maxi(base, 50)


## Price formula: (effect_value × 100) + (rarity - 1) × 300
func _unit_price(u) -> int:
	var base: int = int(u.effect_value) * 100 + (int(u.rarity) - 1) * 300
	return maxi(base, 100)


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
	var item_id: String = str(item.get("id", ""))
	var character = CharacterManager.get_active_character()
	if character == null:
		return
	if int(character.get("meseta", 0)) < cost:
		hint_label.text = "Not enough meseta!"
		return
	if not Inventory.can_add_item(item_id):
		hint_label.text = "Inventory full!"
		return
	# Deduct meseta
	character["meseta"] = int(character["meseta"]) - cost
	GameState.meseta = int(character["meseta"])
	# Add item to inventory
	Inventory.add_item(item_id, 1)
	hint_label.text = "Bought %s for %d M!" % [str(item.get("name", "???")), cost]
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

	if _items.is_empty():
		var empty := Label.new()
		empty.text = "  (Nothing for sale)"
		empty.modulate = Color(0.333, 0.333, 0.333)
		vbox.add_child(empty)
	else:
		var last_cat := ""
		for i in range(_items.size()):
			var item: Dictionary = _items[i]
			var cat: String = str(item.get("category", ""))
			# Category headers
			if cat != last_cat:
				if not last_cat.is_empty():
					var spacer := Label.new()
					spacer.text = ""
					vbox.add_child(spacer)
				var header := Label.new()
				header.text = "── %s ──" % cat.to_upper()
				header.modulate = Color(0, 0.733, 0.8)
				vbox.add_child(header)
				last_cat = cat

			var label := Label.new()
			var held: int = int(Inventory._items.get(str(item.get("id", "")), 0))
			var held_str: String = " (%d)" % held if held > 0 else ""
			label.text = "%-20s%s %6d M" % [str(item.get("name", "???")), held_str, int(item.get("cost", 0))]
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
	var item_id: String = str(item.get("id", ""))
	var cat: String = str(item.get("category", ""))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "── %s ──" % str(item.get("name", "???"))
	name_label.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(name_label)

	if cat == "weapon":
		var w = WeaponRegistry.get_weapon(item_id)
		if w:
			_add_line(vbox, "Type: %s" % w.get_weapon_type_name())
			_add_line(vbox, "Rarity: %s" % w.get_rarity_string(), Color(1, 0.8, 0))
			_add_line(vbox, "ATK: %d-%d" % [w.attack_base, w.attack_max])
			_add_line(vbox, "ACC: %d" % w.accuracy_base)
			if not w.element.is_empty():
				_add_line(vbox, "Element: %s Lv.%d" % [w.element, w.element_level])
			_add_line(vbox, "Max Grind: +%d" % w.max_grind)
			_add_line(vbox, "Req. Level: %d" % w.level)
	elif cat == "armor":
		var a = ArmorRegistry.get_armor(item_id)
		if a:
			_add_line(vbox, "Rarity: %s" % a.get_rarity_string(), Color(1, 0.8, 0))
			_add_line(vbox, "DEF: %d-%d" % [a.defense_base, a.defense_max])
			_add_line(vbox, "EVA: %d-%d" % [a.evasion_base, a.evasion_max])
			_add_line(vbox, "Unit Slots: %d" % a.max_slots)
			_add_line(vbox, "Req. Level: %d" % a.level)
			# Resistances
			var resists: Array = []
			if a.resist_fire > 0: resists.append("Fire %d" % a.resist_fire)
			if a.resist_ice > 0: resists.append("Ice %d" % a.resist_ice)
			if a.resist_lightning > 0: resists.append("Ltn %d" % a.resist_lightning)
			if a.resist_light > 0: resists.append("Lgt %d" % a.resist_light)
			if a.resist_dark > 0: resists.append("Drk %d" % a.resist_dark)
			if not resists.is_empty():
				_add_line(vbox, "Resist: %s" % ", ".join(PackedStringArray(resists)))
	elif cat == "unit":
		var u = UnitRegistry.get_unit(item_id)
		if u:
			_add_line(vbox, "Rarity: %s" % ("*".repeat(int(u.rarity))), Color(1, 0.8, 0))
			_add_line(vbox, "Category: %s" % u.category)
			_add_line(vbox, "Effect: %s" % u.effect, Color(0.5, 1, 0.5))

	# Price / sell info
	var sep := Label.new()
	sep.text = ""
	vbox.add_child(sep)
	var cost_label := Label.new()
	cost_label.text = "Buy: %d M" % int(item.get("cost", 0))
	cost_label.modulate = Color(1, 0.8, 0)
	vbox.add_child(cost_label)
	var sell_label := Label.new()
	sell_label.text = "Sell: %d M" % int(item.get("sell_price", 0))
	sell_label.modulate = Color(0.5, 0.5, 0.5)
	vbox.add_child(sell_label)

	detail_panel.add_child(vbox)


func _add_line(parent: VBoxContainer, text: String, color: Color = Color(0, 1, 0.533)) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	parent.add_child(label)


func _get_meseta_str() -> String:
	var character = CharacterManager.get_active_character()
	if character:
		return str(int(character.get("meseta", 0)))
	return "0"

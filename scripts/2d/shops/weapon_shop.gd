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


## Build "Type Race" string for the active character (e.g., "Hunter Human").
func _get_class_use_string() -> String:
	var character = CharacterManager.get_active_character()
	if character == null:
		return ""
	var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	if class_data == null:
		return ""
	return "%s %s" % [class_data.type, class_data.race]


## Check equippability of an item. Returns {can_equip: bool, reason: String}.
func _check_equippability(item_id: String, cat: String) -> Dictionary:
	var character = CharacterManager.get_active_character()
	if character == null:
		return {"can_equip": false, "reason": ""}
	var class_str: String = _get_class_use_string()
	var char_level: int = int(character.get("level", 1))

	if cat == "weapon":
		var w = WeaponRegistry.get_weapon(item_id)
		if w:
			if not class_str.is_empty() and not w.can_be_used_by(class_str):
				return {"can_equip": false, "reason": "class"}
			if w.level > char_level:
				return {"can_equip": false, "reason": "level", "req_level": w.level}
	elif cat == "armor":
		var a = ArmorRegistry.get_armor(item_id)
		if a:
			if not class_str.is_empty() and not a.can_be_used_by(class_str):
				return {"can_equip": false, "reason": "class"}
			if a.level > char_level:
				return {"can_equip": false, "reason": "level", "req_level": a.level}

	return {"can_equip": true, "reason": ""}


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
	var cat: String = str(item.get("category", ""))
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	# Check class/level restrictions before purchase
	var equip_check: Dictionary = _check_equippability(item_id, cat)
	if not equip_check.get("can_equip", true):
		var reason: String = str(equip_check.get("reason", ""))
		if reason == "class":
			hint_label.text = "Your class cannot use this!"
		elif reason == "level":
			hint_label.text = "Requires level %d!" % int(equip_check.get("req_level", 1))
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

	var character = CharacterManager.get_active_character()
	var current_meseta: int = int(character.get("meseta", 0)) if character else 0

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var meseta_label := Label.new()
	meseta_label.text = "Meseta: %s" % _get_meseta_str()
	meseta_label.modulate = Color(1, 0.8, 0)
	vbox.add_child(meseta_label)

	var selected_label: Label = null

	if _items.is_empty():
		var empty := Label.new()
		empty.text = "  (Nothing for sale)"
		empty.modulate = Color(0.333, 0.333, 0.333)
		vbox.add_child(empty)
	else:
		var last_cat := ""
		for i in range(_items.size()):
			var item: Dictionary = _items[i]
			var item_id: String = str(item.get("id", ""))
			var cat: String = str(item.get("category", ""))
			var cost: int = int(item.get("cost", 0))
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
			var held: int = int(Inventory._items.get(item_id, 0))

			# Get rarity stars
			var stars := ""
			if cat == "weapon":
				var w = WeaponRegistry.get_weapon(item_id)
				if w:
					stars = " " + w.get_rarity_string()
			elif cat == "armor":
				var a = ArmorRegistry.get_armor(item_id)
				if a:
					stars = " " + a.get_rarity_string()
			elif cat == "unit":
				var u = UnitRegistry.get_unit(item_id)
				if u:
					stars = " " + u.get_rarity_string() if u.has_method("get_rarity_string") else " " + "*".repeat(int(u.rarity))

			# Show held count only for stackable items
			var held_str := ""
			if held > 1:
				held_str = " x%d" % held

			# Check restrictions for color-coding
			var equip_check: Dictionary = _check_equippability(item_id, cat)
			var can_equip: bool = equip_check.get("can_equip", true)
			var reason: String = str(equip_check.get("reason", ""))
			var cant_afford: bool = current_meseta < cost

			# Build label with restriction tag
			var restriction_tag := ""
			if not can_equip:
				if reason == "class":
					restriction_tag = " [Class]"
				elif reason == "level":
					restriction_tag = " [Lv.%d]" % int(equip_check.get("req_level", 1))

			label.text = "%-18s%s%s %6d M%s" % [str(item.get("name", "???")), stars, held_str, cost, restriction_tag]
			if i == _selected_index:
				label.text = "> " + label.text
				if not can_equip:
					label.modulate = Color(0.8, 0.267, 0.267)
				elif cant_afford:
					label.modulate = Color(0.8, 0.8, 0.267)
				else:
					label.modulate = Color(1, 0.8, 0)
				selected_label = label
			else:
				label.text = "  " + label.text
				if not can_equip:
					label.modulate = Color(0.5, 0.2, 0.2)
				elif cant_afford:
					label.modulate = Color(0.5, 0.5, 0.2)
			vbox.add_child(label)

	scroll.add_child(vbox)
	list_panel.add_child(scroll)

	# Scroll to selected item after layout settles
	if selected_label != null:
		scroll.ensure_control_visible.call_deferred(selected_label)

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

	# Equippability status
	var equip_check: Dictionary = _check_equippability(item_id, cat)
	if cat in ["weapon", "armor"]:
		var equip_status := Label.new()
		if equip_check.get("can_equip", true):
			equip_status.text = "Can equip"
			equip_status.modulate = Color(0.5, 1, 0.5)
		else:
			var reason: String = str(equip_check.get("reason", ""))
			if reason == "class":
				equip_status.text = "Cannot equip: class"
			elif reason == "level":
				equip_status.text = "Cannot equip: Lv.%d required" % int(equip_check.get("req_level", 1))
			else:
				equip_status.text = "Cannot equip"
			equip_status.modulate = Color(1, 0.267, 0.267)
		vbox.add_child(equip_status)

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

extends Control
## Weapon shop — browse and buy weapons, armor, and units via tabs.

const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")

enum Tab { WEAPONS, ARMOR, UNITS, SELL }

const TAB_NAMES := ["Weapons", "Armor", "Units", "Sell"]
const TAB_COUNT := 4

var _tab: int = Tab.WEAPONS
var _selected_index: int = 0
# Active modal (ConfirmDialog). Skip _unhandled_input + nav while open.
var _active_modal: Control = null

var _weapons: Array = []
var _armors: Array = []
var _units: Array = []
var _sell_items: Array = []

var _mode_bar: HBoxContainer
var _portrait: Control

# Cached pill nodes from the last _refresh_display, one entry per list item
# (null for section headers). Allows cursor moves to toggle selection styling
# without rebuilding the whole list — critical for hold-scroll performance
# because the weapon list can be large and rebuild+detail+registry lookups
# take several ms per cursor tick.
var _pill_nodes: Array = []

## Set true to show all weapon tiers in the shop (for testing)
const DEBUG_ALL_TIERS := true

## Shop weapon pool — PSO basic weapon tiers
const SHOP_WEAPON_TIER1 := [
	"saber", "sword", "dagger", "partisan",
	"handgun", "rifle", "mechgun", "rod", "wand",
	"d_fangs", "double_blade", "slicer",
]
const SHOP_WEAPON_TIER2 := [
	"brand", "gigush", "knife", "halberd",
	"autogun", "sniper", "assault", "pole", "staff",
	"spinner",
]
const SHOP_WEAPON_TIER3 := [
	"buster", "breaker", "blade", "glaive",
	"lockgun", "blaster", "repeater", "pillar", "baton",
	"cutter",
]
const SHOP_WEAPON_TIER4 := [
	"pallasch", "claymore", "edge", "berdys",
	"railgun", "beam", "gatling", "striker", "scepter",
	"sawcer",
]

## Shop armor pool — 3 tiers of each type
const SHOP_ARMOR_IDS := [
	"frame", "giga_frame", "soul_frame",
	"armor", "psy_armor", "cross_armor",
	"robe", "spirit_robe", "grand_robe",
]

## Slot roll weights: index = slot count, value = weight
## 0 slots: 35%, 1 slot: 30%, 2 slots: 10%, 3 slots: 20%, 4 slots: 5%
const ARMOR_SLOT_WEIGHTS := [35, 30, 10, 20, 5]

## Shop unit pool — starter stat and resist units
const SHOP_UNIT_IDS := [
	"rookie_hp", "rookie_pp",
	"ace_power", "ace_guard", "ace_mind", "ace_hit", "ace_swift",
	"heat_resist_lv1", "ice_resist_lv1", "light_resist_lv1", "dark_resist_lv1",
]

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeBar/ModeLabel
@onready var list_panel: PanelContainer = $Panel/VBox/HBox/ListPanel
@onready var detail_panel: PanelContainer = $Panel/VBox/HBox/DetailPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	_mode_bar = mode_label.get_parent()
	PszStyle.style_menu(title_label, hint_label, [list_panel, detail_panel])
	title_label.text = "Weapon Shop"
	_setup_portrait()
	_update_hint()
	_generate_inventory()
	_refresh_display()
	ShopPreviewSprite.attach(self, SHOP_PREVIEW_PATH)


const SHOP_PREVIEW_PATH := "res://assets/ui/shop-previews/weapon-shop.png"


func _setup_portrait() -> void:
	_portrait = PszStyle.setup_shop_portrait($Panel, list_panel, detail_panel, SHOP_PREVIEW_PATH)


func _generate_inventory() -> void:
	_weapons.clear()
	_armors.clear()
	_units.clear()

	var weapon_ids: Array = SHOP_WEAPON_TIER1.duplicate()
	if DEBUG_ALL_TIERS:
		weapon_ids.append_array(SHOP_WEAPON_TIER2)
		weapon_ids.append_array(SHOP_WEAPON_TIER3)
		weapon_ids.append_array(SHOP_WEAPON_TIER4)
	for wid in weapon_ids:
		var w = WeaponRegistry.get_weapon(wid)
		if w == null:
			continue
		var price: int = _weapon_price(w)
		_weapons.append({
			"id": w.id, "name": w.name, "category": "weapon",
			"cost": price, "sell_price": int(price * 0.25),
			"weapon_type": int(w.weapon_type), "weapon_type_name": w.get_weapon_type_name(),
			"rarity": int(w.rarity),
		})
	_weapons.sort_custom(func(a, b):
		if a["weapon_type"] != b["weapon_type"]:
			return a["weapon_type"] < b["weapon_type"]
		return a["rarity"] < b["rarity"]
	)

	for aid in SHOP_ARMOR_IDS:
		var a = ArmorRegistry.get_armor(aid)
		if a == null:
			continue
		var slots: int = _roll_armor_slots()
		var price: int = _armor_price(a)
		var slot_label: String = " [%d slot%s]" % [slots, "" if slots == 1 else "s"]
		_armors.append({
			"id": a.id, "name": a.name + slot_label, "category": "armor",
			"cost": price, "sell_price": int(price * 0.25),
			"rolled_slots": slots,
		})

	for uid in SHOP_UNIT_IDS:
		var u = UnitRegistry.get_unit(uid)
		if u == null:
			continue
		var price: int = _unit_price(u)
		_units.append({
			"id": u.id, "name": u.name, "category": "unit",
			"cost": price, "sell_price": int(price * 0.25),
		})

	_generate_sell_list()


func _generate_sell_list() -> void:
	_sell_items.clear()
	var equipped_ids: Array = []
	var character = CharacterManager.get_active_character()
	if character:
		var equip: Dictionary = character.get("equipment", {})
		for slot_key in equip:
			var eid: String = str(equip.get(slot_key, ""))
			if not eid.is_empty():
				equipped_ids.append(eid)

	for item_info in Inventory.get_all_items():
		var item_id: String = str(item_info.get("id", ""))
		var qty: int = int(item_info.get("quantity", 0))
		if qty <= 0:
			continue
		var sell_price: int = 0
		var item_name: String = str(item_info.get("name", item_id))
		var cat: String = "Item"
		var base_id: String = Inventory.get_base_id(item_id)
		var is_equipped: bool = item_id in equipped_ids

		var w = WeaponRegistry.get_weapon(base_id)
		if w:
			sell_price = maxi(int(_weapon_price(w) * 0.25), 1)
			item_name = w.name
			cat = "Weapon"
		else:
			var a = ArmorRegistry.get_armor(base_id)
			if a:
				sell_price = maxi(int(_armor_price(a) * 0.25), 1)
				item_name = a.name
				cat = "Armor"
			else:
				var u = UnitRegistry.get_unit(base_id)
				if u:
					sell_price = maxi(int(_unit_price(u) * 0.25), 1)
					item_name = u.name
					cat = "Unit"
				elif MagManager.is_mag(base_id):
					item_name = str(item_info.get("name", item_id))
					sell_price = 50
					cat = "Mag"
				elif MaterialRegistry.get_material(base_id) or ModifierRegistry.get_modifier(base_id):
					sell_price = 10
					cat = "Material"
				else:
					sell_price = 10
		_sell_items.append({
			"id": item_id, "name": item_name, "category": cat,
			"sell_price": sell_price, "quantity": qty,
			"equipped": is_equipped,
		})

	var cat_order := ["Weapon", "Armor", "Unit", "Mag", "Item", "Material"]
	_sell_items.sort_custom(func(a, b):
		var ca: int = cat_order.find(a.get("category", "Item"))
		var cb: int = cat_order.find(b.get("category", "Item"))
		if ca != cb:
			return ca < cb
		return str(a.get("name", "")) < str(b.get("name", ""))
	)


func _weapon_price(w) -> int:
	var base: int = int(w.attack_base) * 15 + (int(w.rarity) - 1) * 500
	return maxi(base, 50)


func _armor_price(a) -> int:
	var base: int = int(a.defense_base) * 12 + (int(a.rarity) - 1) * 400
	return maxi(base, 50)


func _roll_armor_slots() -> int:
	var total := 0
	for w in ARMOR_SLOT_WEIGHTS:
		total += w
	var roll := randi_range(0, total - 1)
	var cumulative := 0
	for i in range(ARMOR_SLOT_WEIGHTS.size()):
		cumulative += ARMOR_SLOT_WEIGHTS[i]
		if roll < cumulative:
			return i
	return 0


func _unit_price(u) -> int:
	var base: int = int(u.effect_value) * 100 + (int(u.rarity) - 1) * 300
	return maxi(base, 100)


func _update_hint() -> void:
	if _tab == Tab.SELL:
		hint_label.text = "Left/Right: Category  Up/Down: Select  Enter: Sell  Esc: Leave"
	else:
		hint_label.text = "Left/Right: Category  Up/Down: Select  Enter: Buy  Esc: Leave"


func _get_current_list() -> Array:
	match _tab:
		Tab.WEAPONS: return _weapons
		Tab.ARMOR: return _armors
		Tab.UNITS: return _units
		Tab.SELL: return _sell_items
	return _weapons


func _get_class_use_string() -> String:
	var character = CharacterManager.get_active_character()
	if character == null:
		return ""
	var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	if class_data == null:
		return ""
	return "%s %s" % [class_data.type, class_data.race]


func _check_equippability(item_id: String, cat: String) -> Dictionary:
	var character = CharacterManager.get_active_character()
	if character == null:
		return {"can_equip": false, "reason": ""}
	var class_str: String = _get_class_use_string()

	if cat == "weapon":
		var w = WeaponRegistry.get_weapon(item_id)
		if w:
			if not class_str.is_empty() and not w.can_be_used_by(class_str):
				return {"can_equip": false, "reason": "class"}
	elif cat == "armor":
		var a = ArmorRegistry.get_armor(item_id)
		if a:
			if not class_str.is_empty() and not a.can_be_used_by(class_str):
				return {"can_equip": false, "reason": "class"}

	return {"can_equip": true, "reason": ""}


## Affordance override: a weapon/armor/unit row is buyable only if the
## character's class can use it, can afford it, and has inventory room. Mirrors
## _buy_selected's guards (which key off the registry id, not a name-derived
## one), so the disabled-row rendering can't drift from what _buy_selected
## accepts.
func _can_buy(item: Dictionary) -> Dictionary:
	var item_id: String = str(item.get("id", ""))
	var cat: String = str(item.get("category", ""))
	if not _check_equippability(item_id, cat).get("can_equip", true):
		return {"ok": false, "reason": "Class can't use"}
	if _get_meseta() < int(item.get("cost", 0)):
		return {"ok": false, "reason": "Can't afford"}
	if not Inventory.can_add_item(item_id):
		return {"ok": false, "reason": "No room"}
	return {"ok": true, "reason": ""}


func _open_confirm_modal() -> void:
	var item_v: Variant = ShopNav.selected_item(self, _get_current_list())
	if item_v == null:
		return
	var item: Dictionary = item_v
	var prompt: String
	var on_yes: Callable
	if _tab == Tab.SELL:
		var sell_price: int = int(item.get("sell_price", 0))
		prompt = "Sell %s for %d M?" % [str(item.get("name", "???")), sell_price]
		on_yes = _sell_selected
	else:
		# Disabled row (greyed + reason in _refresh_display) → echo the reason
		# and open nothing, so the player never reaches a rejection.
		var verdict: Dictionary = _can_buy(item)
		if not verdict.get("ok", true):
			hint_label.text = str(verdict.get("reason", ""))
			SfxManager.play("res://assets/sfx/ui/menu_back.wav")
			return
		var cost: int = int(item.get("cost", 0))
		prompt = "Buy %s for %d M?" % [str(item.get("name", "???")), cost]
		on_yes = _buy_selected

	ShopNav.confirm(self, prompt, on_yes, _update_hint)


func _unhandled_input(event: InputEvent) -> void:
	ShopNav.handle(self, event, {
		"modal": _active_modal,
		"on_tab": func(dir: int) -> void: ShopNav.switch_shop_tab(self, dir, TAB_COUNT, Tab.SELL),
		"list_size": func() -> int: return _get_current_list().size(),
		"on_move": func(old_index: int) -> void:
			_update_hint()
			_update_selection(old_index),
		"on_accept": _open_confirm_modal,
	})


func _buy_selected() -> void:
	var list := _get_current_list()
	if list.is_empty() or _selected_index >= list.size():
		return
	var item: Dictionary = list[_selected_index]
	var cost: int = int(item.get("cost", 0))
	var item_id: String = str(item.get("id", ""))
	var cat: String = str(item.get("category", ""))
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var equip_check: Dictionary = _check_equippability(item_id, cat)
	if not equip_check.get("can_equip", true):
		hint_label.text = "Your class cannot use this!"
		return

	if int(character.get("meseta", 0)) < cost:
		hint_label.text = "Not enough meseta!"
		return
	if not Inventory.can_add_item(item_id):
		hint_label.text = "Inventory full!"
		return

	character["meseta"] = int(character["meseta"]) - cost
	GameState.meseta = int(character["meseta"])
	Inventory.add_item(item_id, 1)

	# Store rolled slot count for armor purchases
	if cat == "armor" and item.has("rolled_slots"):
		if not character.has("armor_slots"):
			character["armor_slots"] = {}
		character["armor_slots"][item_id] = int(item["rolled_slots"])

	hint_label.text = "Bought %s for %d M!" % [str(item.get("name", "???")), cost]
	_generate_sell_list()
	_refresh_display()


func _sell_selected() -> void:
	if _sell_items.is_empty() or _selected_index >= _sell_items.size():
		return
	var item: Dictionary = _sell_items[_selected_index]
	if item.get("equipped", false):
		hint_label.text = "Unequip first!"
		return
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
	_mode_bar.add_child(PszStyle.create_tab_bar(TAB_NAMES, _tab))
	_mode_bar.add_child(PszStyle.create_meseta_label(_get_meseta()))

	# List panel — pill rows
	for child in list_panel.get_children():
		child.queue_free()

	var list := _get_current_list()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	_pill_nodes.clear()
	_pill_nodes.resize(list.size())
	var selected_pill: Control = null

	if list.is_empty():
		var empty_text := "(Nothing to sell)" if _tab == Tab.SELL else "(Nothing for sale)"
		vbox.add_child(PszStyle.create_pill(empty_text, false, "", PszStyle.TEXT_MUTED))
	elif _tab == Tab.SELL:
		var last_cat := ""
		for i in range(list.size()):
			var item: Dictionary = list[i]
			var cat: String = str(item.get("category", ""))
			if cat != last_cat:
				last_cat = cat
				vbox.add_child(PszStyle.create_section_header(cat))
			var sell_price: int = int(item.get("sell_price", 0))
			var qty: int = int(item.get("quantity", 1))
			var qty_str := " x%d" % qty if qty > 1 else ""
			var sell_id: String = str(item.get("id", ""))
			var sell_icon: Texture2D = InventoryIcons.for_item(sell_id)
			var sell_icons: Array = [sell_icon] if sell_icon else []
			# Unified shop row (#368): [E] prefix + muted for equipped gear.
			var pill := PszStyle.shop_row(str(item.get("name", "???")) + qty_str, "%d M" % sell_price, {
				"icons": sell_icons,
				"equipped": bool(item.get("equipped", false)),
				"selected": i == _selected_index,
			})
			vbox.add_child(pill)
			_pill_nodes[i] = pill
			if i == _selected_index:
				selected_pill = pill
	else:
		var last_type_name := ""
		for i in range(list.size()):
			var item: Dictionary = list[i]
			var item_id: String = str(item.get("id", ""))
			var cost: int = int(item.get("cost", 0))

			# Section headers for weapon types
			if _tab == Tab.WEAPONS:
				var type_name: String = str(item.get("weapon_type_name", ""))
				if not type_name.is_empty() and type_name != last_type_name:
					last_type_name = type_name
					vbox.add_child(PszStyle.create_section_header(type_name))

			# Rarity stars + held count + can't-buy reason all live in the detail
			# panel — the row carries only name, price, and the one grey rule.

			# Unified shop row (#368): grey only when _can_buy rejects the row
			# (class / affordability / room — same verdict _buy_selected uses);
			# no per-reason colour split. The reason itself shows in the detail.
			var verdict: Dictionary = _can_buy(item)
			var buy_icon: Texture2D = InventoryIcons.for_item(item_id)
			var buy_icons: Array = [buy_icon] if buy_icon else []
			var pill := PszStyle.shop_row(str(item.get("name", "???")), "%d M" % cost, {
				"icons": buy_icons,
				"affordable": bool(verdict.get("ok", true)),
				"selected": i == _selected_index,
			})
			vbox.add_child(pill)
			_pill_nodes[i] = pill
			if i == _selected_index:
				selected_pill = pill

	scroll.add_child(vbox)
	list_panel.add_child(scroll)

	if selected_pill != null:
		scroll.ensure_control_visible.call_deferred(selected_pill)

	_refresh_detail()


# Lightweight cursor-move update: swap the selected stylebox on the affected
# pills and re-render the detail panel. Avoids the full list rebuild that
# _refresh_display does, which becomes a bottleneck under hold-to-scroll.
func _update_selection(old_index: int) -> void:
	if old_index >= 0 and old_index < _pill_nodes.size():
		var old_pill: Control = _pill_nodes[old_index]
		if old_pill:
			old_pill.add_theme_stylebox_override("panel", PszStyle.pill_style(false))
	if _selected_index >= 0 and _selected_index < _pill_nodes.size():
		var new_pill: Control = _pill_nodes[_selected_index]
		if new_pill:
			new_pill.add_theme_stylebox_override("panel", PszStyle.pill_style(true))
			# Keep the selected row scrolled into view.
			var parent: Node = new_pill.get_parent()
			while parent != null and not (parent is ScrollContainer):
				parent = parent.get_parent()
			if parent is ScrollContainer:
				(parent as ScrollContainer).ensure_control_visible.call_deferred(new_pill)
	_refresh_detail()


func _refresh_detail() -> void:
	for child in detail_panel.get_children():
		child.queue_free()

	var list := _get_current_list()
	if list.is_empty() or _selected_index >= list.size():
		return

	var item: Dictionary = list[_selected_index]
	var item_id: String = str(item.get("id", ""))
	var cat: String = str(item.get("category", ""))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	vbox.add_child(PszStyle.detail_label(str(item.get("name", "???")), PszStyle.TITLE_BG))

	if cat == "weapon":
		var w = WeaponRegistry.get_weapon(item_id)
		if w:
			vbox.add_child(PszStyle.detail_label("Type: %s" % w.get_weapon_type_name()))
			vbox.add_child(PszStyle.detail_label("Rarity: %s" % w.get_rarity_string(), PszStyle.TEXT_HIGHLIGHT))
			vbox.add_child(PszStyle.detail_label("ATK: %d-%d" % [w.attack_base, w.attack_max]))
			vbox.add_child(PszStyle.detail_label("ACC: %d" % w.accuracy_base))
			if not w.element.is_empty():
				vbox.add_child(PszStyle.detail_label("Element: %s Lv.%d" % [w.element, w.element_level]))
			vbox.add_child(PszStyle.detail_label("Max Grind: +%d" % w.max_grind))
	elif cat == "armor":
		var a = ArmorRegistry.get_armor(item_id)
		if a:
			vbox.add_child(PszStyle.detail_label("Rarity: %s" % a.get_rarity_string(), PszStyle.TEXT_HIGHLIGHT))
			vbox.add_child(PszStyle.detail_label("DEF: %d-%d" % [a.defense_base, a.defense_max]))
			vbox.add_child(PszStyle.detail_label("EVA: %d-%d" % [a.evasion_base, a.evasion_max]))
			vbox.add_child(PszStyle.detail_label("Unit Slots: %d" % a.max_slots))
			# Level requirement removed — will switch to stat requirements later
			var resists: Array = []
			if a.resist_fire > 0: resists.append("Fire %d" % a.resist_fire)
			if a.resist_ice > 0: resists.append("Ice %d" % a.resist_ice)
			if a.resist_lightning > 0: resists.append("Ltn %d" % a.resist_lightning)
			if a.resist_light > 0: resists.append("Lgt %d" % a.resist_light)
			if a.resist_dark > 0: resists.append("Drk %d" % a.resist_dark)
			if not resists.is_empty():
				vbox.add_child(PszStyle.detail_label("Resist: %s" % ", ".join(PackedStringArray(resists))))
	elif cat == "unit":
		var u = UnitRegistry.get_unit(item_id)
		if u:
			vbox.add_child(PszStyle.detail_label("Rarity: %s" % ("*".repeat(int(u.rarity))), PszStyle.TEXT_HIGHLIGHT))
			vbox.add_child(PszStyle.detail_label("Category: %s" % u.category))
			vbox.add_child(PszStyle.detail_label("Effect: %s" % u.effect, PszStyle.TEXT_SUCCESS))

	# Price info
	vbox.add_child(PszStyle.detail_label(""))
	if _tab == Tab.SELL:
		vbox.add_child(PszStyle.detail_label("Sell: %d M" % int(item.get("sell_price", 0)), PszStyle.TEXT_HIGHLIGHT))
		vbox.add_child(PszStyle.detail_label("Owned: %d" % int(item.get("quantity", 0))))
	else:
		vbox.add_child(PszStyle.detail_label("Buy: %d M" % int(item.get("cost", 0)), PszStyle.TEXT_HIGHLIGHT))
		vbox.add_child(PszStyle.detail_label("Sell: %d M" % int(item.get("sell_price", 0)), PszStyle.TEXT_MUTED))
		vbox.add_child(PszStyle.detail_label("You have: %d" % int(Inventory._items.get(item_id, 0))))

		# Equippability status
		if cat in ["weapon", "armor"]:
			var equip_check: Dictionary = _check_equippability(item_id, cat)
			if equip_check.get("can_equip", true):
				vbox.add_child(PszStyle.detail_label("Can equip", PszStyle.TEXT_SUCCESS))
			else:
				vbox.add_child(PszStyle.detail_label("Cannot equip: class", PszStyle.TEXT_DANGER))

		# Unified: surface the can't-buy reason (the row no longer tags it).
		var buy_verdict: Dictionary = _can_buy(item)
		if not buy_verdict.get("ok", true):
			vbox.add_child(PszStyle.detail_label(str(buy_verdict.get("reason", "")), PszStyle.TEXT_WARNING))

	detail_panel.add_child(vbox)


# ── Hold-to-repeat navigation (NavRepeat) ──────────────────────────────────────
var _nav: NavRepeat = null


func _process(delta: float) -> void:
	# Modal owns input + nav while open.
	if is_instance_valid(_active_modal):
		return
	if _nav == null:
		_nav = NavRepeat.new(["ui_up", "ui_down", "ui_left", "ui_right"], _on_nav_repeat)
	_nav.tick(delta)

# --- Shop scaffolding, inlined. These screens are standalone (extends Control)
# --- rather than sharing a ShopBase: a cross-script base class fails to
# --- resolve in the Android export at runtime (works in-editor and on every
# --- other platform). See the shop-dedup tracker.

## The active character's meseta (0 if no active character).
func _get_meseta() -> int:
	var character = CharacterManager.get_active_character()
	if character:
		return int(character.get("meseta", 0))
	return 0


## NavRepeat callback: re-emit a held nav action as a synthetic input event
## so this screen's own _unhandled_input handles it (hold-to-repeat nav).
func _on_nav_repeat(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_unhandled_input(ev)


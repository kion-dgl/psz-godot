extends Control
## Shop — buy consumables or technique disks, toggled with tabs.

const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")
const ShopDetail := preload("res://scripts/2d/shops/shop_detail.gd")

enum Tab { ITEMS, MATERIALS, DISKS, SELL }

const TAB_COUNT := 4
const TAB_NAMES := ["Items", "Materials", "Disks", "Sell"]

const MATERIAL_CATEGORIES := ["DEBUG Materials", "DEBUG Photons", "DEBUG Boards"]

var _tab: int = Tab.ITEMS
var _selected_index: int = 0
# Modal currently on screen (ConfirmDialog or QuantityDialog). While
# valid, _unhandled_input and _process bail so the modal's own _input
# fully owns navigation/accept/cancel and NavRepeat doesn't keep
# scrolling the underlying list.
var _active_modal: Control = null

# Items tab data (consumables only)
var _shop_items: Array = []

# Materials tab data
var _material_items: Array = []

# Disks tab data
var _disk_items: Array = []

# Sell tab data
var _sell_items: Array = []

# Cached pill nodes from the last _refresh_display, one per list row. Lets a
# cursor move re-style the selected row in place instead of rebuilding the whole
# list — a full rebuild recreates the ScrollContainer and resets it to the top,
# which made the scrollbar jump on every keypress (Kion playtest). Mirrors the
# weapon shop's incremental update.
var _pill_nodes: Array = []

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
	_setup_portrait()
	hint_label.hide() # Meseta is the only footer; confirmations remain in dialogs.
	_update_hint()
	_load_shop_items()
	_generate_disk_inventory()
	_generate_sell_list()
	_refresh_display()
	ShopPreviewSprite.attach(self, SHOP_PREVIEW_PATH)


const SHOP_PREVIEW_PATH := "res://assets/ui/shop-previews/item-shop.png"


func _setup_portrait() -> void:
	PszStyle.setup_shop_portrait($Panel, detail_panel, SHOP_PREVIEW_PATH)


func _load_shop_items() -> void:
	var all_items: Array = ShopManager.get_shop_inventory("item_shop")
	if all_items.is_empty():
		for shop in ShopRegistry.get_all_shops():
			if "item" in shop.name.to_lower() or "consumable" in shop.description.to_lower():
				all_items = shop.items.duplicate()
				break
	_shop_items.clear()
	_material_items.clear()
	for item in all_items:
		var cat: String = str(item.get("category", ""))
		if cat in MATERIAL_CATEGORIES:
			_material_items.append(item)
		else:
			_shop_items.append(item)


func _generate_disk_inventory() -> void:
	var character = CharacterManager.get_active_character()
	var char_level: int = int(character.get("level", 1)) if character else 1
	_disk_items = TechniqueManager.generate_shop_inventory(char_level)


func _generate_sell_list() -> void:
	_sell_items.clear()
	# Get equipped IDs to mark them
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
		var sell_price: int = 10
		var item_name: String = str(item_info.get("name", item_id))
		var cat: String = "Other"
		var is_equipped: bool = item_id in equipped_ids

		var base_id: String = Inventory.get_base_id(item_id)
		if WeaponRegistry.get_weapon(base_id):
			var w = WeaponRegistry.get_weapon(base_id)
			item_name = w.name
			sell_price = maxi(int(w.attack_base) * 4, 10)
			cat = "Weapon"
		elif ArmorRegistry.get_armor(base_id):
			var a = ArmorRegistry.get_armor(base_id)
			item_name = a.name
			sell_price = maxi(int(a.defense_base) * 4, 10)
			cat = "Armor"
		elif UnitRegistry.get_unit(base_id):
			var u = UnitRegistry.get_unit(base_id)
			item_name = u.name
			sell_price = maxi(int(u.effect_value) * 5, 10)
			cat = "Unit"
		elif MagManager.is_mag(base_id):
			item_name = str(item_info.get("name", item_id))
			sell_price = 50
			cat = "Mag"
		elif MaterialRegistry.get_material(base_id) or ModifierRegistry.get_modifier(base_id):
			cat = "Material"
		else:
			var consumable = ConsumableRegistry.get_consumable(base_id)
			if consumable:
				item_name = consumable.name
				sell_price = maxi(int(consumable.sell_price), 1)
			cat = "Item"
		_sell_items.append({
			"id": item_id, "name": item_name, "category": cat,
			"sell_price": sell_price, "quantity": qty,
			"equipped": is_equipped,
			# ✕ marker: gear/disks this character can never use (spec /states/shops,
			# /mechanics/equip-legality). Shared with the weapon shop's sell list.
			"cannot_use": ShopNav.sell_cannot_use(item_id),
			# Grey-without-✕: a disk already known at this level (or below the
			# required player level) — a temporary block, same predicate everywhere.
			"disabled": ShopNav.sell_disabled(item_id),
		})
	# No re-sort: keep Inventory.get_all_items() order so the sell list matches
	# the player's inventory/storage ordering (pickup or auto-sort).


func _update_hint() -> void:
	if _tab == Tab.SELL:
		hint_label.text = "Up/Down: Select  Enter: Sell  Esc: Leave"
	else:
		hint_label.text = "Up/Down: Select  Enter: Buy  Esc: Leave"


func _unhandled_input(event: InputEvent) -> void:
	ShopNav.handle(self, event, {
		"modal": _active_modal,
		"on_tab": func(dir: int) -> void: ShopNav.switch_shop_tab(self, dir, TAB_COUNT, Tab.SELL),
		"list_size": func() -> int: return _get_current_list().size(),
		"on_move": func(old_index: int) -> void:
			_update_hint()
			ShopNav.cursor_move(_pill_nodes, old_index, _selected_index, _refresh_detail),
		"on_accept": _open_confirm_modal,
	})


func _get_current_list() -> Array:
	match _tab:
		Tab.ITEMS: return _shop_items
		Tab.MATERIALS: return _material_items
		Tab.DISKS: return _disk_items
		Tab.SELL: return _sell_items
	return _shop_items


func _open_confirm_modal() -> void:
	var item_v: Variant = ShopNav.selected_item(self, _get_current_list())
	if item_v == null:
		return
	var item: Dictionary = item_v

	# DISKS and SELL: simple yes/no, qty=1.
	if _tab == Tab.DISKS:
		_open_disk_confirm(item)
		return
	if _tab == Tab.SELL:
		_open_sell_confirm(item)
		return

	# ITEMS / MATERIALS: affordability/room no longer grey the row, so an
	# unaffordable or full buy is blocked here with the shared info modal (denied
	# cue + reason) — unmissable and consistent with every other shop. Spec
	# /states/shops. A row greyed for capability (can't use it) is still buyable.
	var verdict: Dictionary = _can_buy(item)
	if not verdict.get("ok", true):
		ShopNav.deny(self, str(verdict.get("reason", "")), _update_hint)
		return

	# Bulk-buy aware: compute the maximum qty the player can both afford and
	# fit, route to QuantityDialog if > 1.
	_open_item_buy(item)


func _open_item_buy(item: Dictionary) -> void:
	var item_name: String = str(item.get("item", "???"))
	var cost: int = int(item.get("cost", 0))
	var item_id: String = item_name.to_lower().replace(" ", "_").replace("-", "_").replace("/", "_")

	var max_stack: int = Inventory.get_max_stack(item_id)
	var stack_room: int = Inventory.get_stack_room(item_id)
	var meseta_cap: int = (_get_meseta() / cost) if cost > 0 else max_stack
	var max_qty: int = mini(mini(max_stack, stack_room), meseta_cap)

	if max_qty <= 0:
		# Player can't afford even one or the stack is at max. Open an
		# info modal so the failure is unmissable — previously this was
		# a silent hint_label update with no modal, which felt like the
		# buy button was broken (psobb/dashgl playtest 2026-05-07).
		var msg: String = ShopNav.MSG_NOT_ENOUGH_MESETA if meseta_cap <= 0 else ShopNav.MSG_NO_ROOM
		hint_label.text = msg
		ShopNav.deny(self, msg, _update_hint)
		return

	var modal := QuantityDialog.new()
	modal.set_item(item_name, cost, max_qty)
	modal.ask("Buy %s?" % item_name)
	modal.confirmed_qty.connect(func(qty: int) -> void:
		_active_modal = null
		_buy_item(item_name, cost, qty)
	)
	modal.cancelled.connect(func() -> void:
		_active_modal = null
		_update_hint()
	)
	_active_modal = modal
	add_child(modal)


func _open_disk_confirm(item: Dictionary) -> void:
	var disk_name: String = str(item.get("name", "???"))
	var cost: int = int(item.get("cost", 0))
	# Pre-check meseta + room so a blocked buy goes STRAIGHT to the info modal,
	# the same as every other shop — instead of opening the buy confirm first and
	# only then failing with a second modal (Rozalin: disks had a double modal).
	if _get_meseta() < cost:
		ShopNav.deny(self, ShopNav.MSG_NOT_ENOUGH_MESETA, _update_hint)
		return
	var disk_id: String = "disk_%s_%d" % [str(item.get("technique_id", "")), int(item.get("level", 1))]
	if not Inventory.can_add_item(disk_id):
		ShopNav.deny(self, ShopNav.MSG_NO_ROOM, _update_hint)
		return
	ShopNav.confirm(self, "Buy %s for %d M?" % [disk_name, cost], _buy_disk, _update_hint)


func _open_sell_confirm(item: Dictionary) -> void:
	# Stacks (Monomate x5, materials) get the quantity picker; per-slot gear
	# collapses to a plain confirm — same flow as buying. #416.
	ShopNav.sell_confirm(self, item, _sell_selected, _update_hint)


func _buy_item(item_name: String, unit_cost: int, qty: int) -> void:
	if ShopManager.buy_item("item_shop", item_name, qty):
		var total: int = unit_cost * qty
		if qty == 1:
			hint_label.text = "Bought %s for %d meseta!" % [item_name, total]
		else:
			hint_label.text = "Bought %d× %s for %d meseta!" % [qty, item_name, total]
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
		ShopNav.deny(self, ShopNav.MSG_NOT_ENOUGH_MESETA, _update_hint)
		return

	var disk_id: String = "disk_%s_%d" % [technique_id, level]
	if not Inventory.can_add_item(disk_id):
		ShopNav.deny(self, ShopNav.MSG_NO_ROOM, _update_hint)
		return

	character["meseta"] = int(character["meseta"]) - cost
	GameState.meseta = int(character["meseta"])

	Inventory.add_item(disk_id, 1)
	var tech_name: String = str(TechniqueManager.TECHNIQUES.get(technique_id, {}).get("name", technique_id))
	hint_label.text = "Bought Disk: %s Lv.%d!" % [tech_name, level]
	_refresh_display()


func _sell_selected(qty: int = 1) -> void:
	if _sell_items.is_empty() or _selected_index >= _sell_items.size():
		return
	var item: Dictionary = _sell_items[_selected_index]
	if item.get("equipped", false):
		hint_label.text = "Unequip first!"
		return
	var item_id: String = str(item.get("id", ""))
	var unit_price: int = int(item.get("sell_price", 0))
	var sell_qty: int = clampi(qty, 1, int(item.get("quantity", 1)))
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	if not Inventory.remove_item(item_id, sell_qty):
		hint_label.text = "Cannot sell that!"
		return

	var total: int = unit_price * sell_qty
	character["meseta"] = int(character.get("meseta", 0)) + total
	GameState.meseta = int(character["meseta"])
	var item_name: String = str(item.get("name", "???"))
	if sell_qty > 1:
		hint_label.text = "Sold %d× %s for %d M!" % [sell_qty, item_name, total]
	else:
		hint_label.text = "Sold %s for %d M!" % [item_name, total]
	_generate_sell_list()
	if _selected_index >= _sell_items.size():
		_selected_index = maxi(0, _sell_items.size() - 1)
	_refresh_display()


## Rebuild the tab bar + balance label (the mode bar above the list).
func _refresh_mode_bar() -> void:
	for child in _mode_bar.get_children():
		child.queue_free()
	_mode_bar.add_child(PszStyle.create_tab_bar(TAB_NAMES, _tab))
	PszStyle.update_shop_balance(self, _get_meseta())


func _refresh_display() -> void:
	_refresh_mode_bar()

	# Shop panel — pill rows
	for child in shop_panel.get_children():
		child.queue_free()

	var list := _get_current_list()
	var scroll := PszStyle.make_list_scroll()
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	_pill_nodes.clear()
	_pill_nodes.resize(list.size())
	var selected_pill: Control = null

	if list.is_empty():
		var empty_text := "(Nothing to sell)" if _tab == Tab.SELL else "(No materials)" if _tab == Tab.MATERIALS else "(No items)" if _tab == Tab.ITEMS else "(No techniques available)"
		var pill := PszStyle.create_pill(empty_text, false, "", PszStyle.TEXT_MUTED)
		vbox.add_child(pill)
	elif _tab == Tab.SELL:
		for i in range(list.size()):
			var item: Dictionary = list[i]
			var sell_price: int = int(item.get("sell_price", 0))
			var qty: int = int(item.get("quantity", 1))
			var qty_str := " x%d" % qty if qty > 1 else ""
			var sell_id: String = str(item.get("id", ""))
			var sell_icon: Texture2D = InventoryIcons.for_item(sell_id)
			var sell_icons: Array = [sell_icon] if sell_icon else []
			# Through shop_row so the [E] equipped + ✕ cannot-use markers sit in the
			# leftmost slot, followed by the item icon and aligned item names.
			var pill := PszStyle.shop_row(str(item.get("name", "???")) + qty_str, "%d M" % sell_price, {
				"icons": sell_icons,
				"equipped": bool(item.get("equipped", false)),
				"cannot_use": bool(item.get("cannot_use", false)),
				"disabled": bool(item.get("disabled", false)),
				"selected": i == _selected_index,
			})
			vbox.add_child(pill)
			_pill_nodes[i] = pill
			if i == _selected_index:
				selected_pill = pill
	elif _tab == Tab.ITEMS or _tab == Tab.MATERIALS:
		for i in range(list.size()):
			var item: Dictionary = list[i]
			var shop_name: String = str(item.get("item", "???"))
			var item_id: String = shop_name.to_lower().replace(" ", "_").replace("-", "_").replace("/", "_")
			var buy_icon: Texture2D = InventoryIcons.for_item(item_id)
			var buy_icons: Array = [buy_icon] if buy_icon else []
			# Capability grey (spec /states/shops): grey when the character's
			# class/race can't use the consumable. Affordability and inventory
			# space do NOT grey — an unaffordable or maxed-stack row stays normal
			# and is blocked at accept with the info modal. (Consumable usable_by
			# is the extension point; no item populates it yet, so this is always
			# usable for now — the antidote/antipara-on-CAST case is the spec's
			# open question.)
			var cost: int = int(item.get("cost", 0))
			var pill := PszStyle.shop_row(shop_name, "%d M" % cost, {
				"icons": buy_icons,
				"disabled": not _can_use_item(item_id),
				"selected": i == _selected_index,
			})
			vbox.add_child(pill)
			_pill_nodes[i] = pill
			if i == _selected_index:
				selected_pill = pill
	else:
		# Disks tab
		var character = CharacterManager.get_active_character()

		for i in range(list.size()):
			var item: Dictionary = list[i]
			var technique_id: String = str(item.get("technique_id", ""))
			var level: int = int(item.get("level", 1))
			var cost: int = int(item.get("cost", 0))
			var disk_name: String = str(item.get("name", "???"))

			# Capability grey (spec /states/shops). Two tiers, matching gear:
			#   • ✕ marker (cannot_use) when the character's CLASS/RACE can never
			#     learn this disk — a CAST, a technique group the class can't learn,
			#     or a level beyond its cap. Permanent, like un-equippable gear.
			#   • plain grey (disabled) for a satisfiable block — already known at
			#     this level or higher, or below the required player level.
			# Affordability does NOT grey; an unaffordable disk stays normal and is
			# blocked at accept. Greyed disks are still buyable ("buy anyway").
			var class_blocked: bool = character != null \
				and not TechniqueManager.class_can_learn(character, technique_id, level)
			var learn_blocked: bool = character != null \
				and not TechniqueManager.can_learn(character, technique_id, level).get("allowed", false)

			var disk_icon: Texture2D = InventoryIcons.for_item("disk_%s_1" % technique_id, "Disk")
			var disk_icons: Array = [disk_icon] if disk_icon else []
			var pill := PszStyle.shop_row(disk_name, "%d M" % cost, {
				"icons": disk_icons,
				"cannot_use": class_blocked,
				"disabled": learn_blocked and not class_blocked,
				"selected": i == _selected_index,
			})
			vbox.add_child(pill)
			_pill_nodes[i] = pill
			if i == _selected_index:
				selected_pill = pill

	PszStyle.set_list_content(scroll, vbox)
	shop_panel.add_child(scroll)

	if selected_pill != null:
		PszStyle.scroll_selected_into_view(selected_pill)

	_refresh_detail()


## True if the active character's class/race can use the consumable `item_id`
## (capability grey, spec /states/shops). Non-consumables (materials, boards) and
## the no-character/-class case carry no restriction. Empty `usable_by` = all.
func _can_use_item(item_id: String) -> bool:
	var consumable = ConsumableRegistry.get_consumable(item_id)
	if consumable == null:
		return true
	var class_str: String = ShopNav.active_class_use_string()
	if class_str.is_empty():
		return true
	return consumable.can_be_used_by(class_str)


func _refresh_detail() -> void:
	PszStyle.clear_detail_panel(detail_panel)

	var list := _get_current_list()
	if list.is_empty() or _selected_index >= list.size():
		return

	if _tab == Tab.ITEMS or _tab == Tab.MATERIALS:
		_refresh_item_detail(list[_selected_index])
	elif _tab == Tab.DISKS:
		_refresh_disk_detail(list[_selected_index])
	else:
		_refresh_sell_detail(list[_selected_index])


func _refresh_item_detail(item: Dictionary) -> void:
	var raw_name: String = str(item.get("item", "???"))
	var item_id: String = raw_name.to_lower().replace(" ", "_").replace("-", "_").replace("/", "_")
	var held: int = Inventory.get_item_count(item_id)
	var ctx: Dictionary = ShopDetail.render_item_card(detail_panel, item_id, raw_name, {
		"held": held,
		"show_held": _tab != Tab.MATERIALS,
		"category_label": str(item.get("category", "")),
	})
	var fstats: Array = [{"label": "Cost", "value": "%d M" % int(item.get("cost", 0)), "tone": "gold"}]
	if _tab != Tab.MATERIALS:
		fstats.append({"label": "Held", "value": str(held)})
	var status_txt := ""
	var status_tone := "ok"
	if not _can_use_item(item_id):
		status_txt = "✕ Cannot use: class"
		status_tone = "blocked"
	else:
		var verdict: Dictionary = _can_buy(item)
		if not verdict.get("ok", true):
			status_txt = str(verdict.get("reason", ""))
			status_tone = "warn"
	ShopDetail.set_footer(ctx, fstats, status_txt, status_tone)


func _refresh_disk_detail(item: Dictionary) -> void:
	var technique_id: String = str(item.get("technique_id", ""))
	var level: int = int(item.get("level", 1))
	var tech: Dictionary = TechniqueManager.get_technique(technique_id)
	if tech.is_empty():
		return
	var ctx: Dictionary = ShopDetail.render_item_card(
		detail_panel, "disk_%s_%d" % [technique_id, level], str(item.get("name", "???")),
		{"technique_id": technique_id, "level": level})
	ShopDetail.add_prose(ctx, "Use from inventory to learn.", ShopDetail.C_SLATE_TEXT)

	var character = CharacterManager.get_active_character()
	var req_lv: int = TechniqueManager.get_disk_required_level(level)
	var char_lv: int = int(character.get("level", 1)) if character else 1
	var cur_lv: int = TechniqueManager.get_technique_level(character, technique_id) if character else 0
	var status_txt := "✓ Learnable"
	var status_tone := "ok"
	if character and not TechniqueManager.class_can_learn(character, technique_id, level):
		status_txt = "✕ Cannot learn: class"
		status_tone = "blocked"
	elif char_lv < req_lv:
		status_txt = "Requires Lv.%d" % req_lv
		status_tone = "warn"
	elif cur_lv >= level:
		status_txt = "Already known (Lv.%d)" % cur_lv
		status_tone = "neutral"
	ShopDetail.set_footer(ctx, [
		{"label": "Price", "value": "%d M" % int(item.get("cost", 0)), "tone": "gold"},
	], status_txt, status_tone)


func _refresh_sell_detail(item: Dictionary) -> void:
	var item_id: String = str(item.get("id", ""))
	var is_eq: bool = bool(item.get("equipped", false))
	var ctx: Dictionary = ShopDetail.render_item_card(detail_panel, item_id, str(item.get("name", "???")), {
		"held": int(item.get("quantity", 0)),
		"owned_instance": true,
		"is_equipped": is_eq,
	})
	var s_txt := "[E] Equipped — cannot sell" if is_eq else ("✕ Cannot use: class" if bool(item.get("cannot_use", false)) else "")
	var s_tone := "equipped" if is_eq else ("blocked" if bool(item.get("cannot_use", false)) else "neutral")
	ShopDetail.set_footer(ctx, [
		{"label": "Sell", "value": "%d M" % int(item.get("sell_price", 0)), "tone": "gold"},
		{"label": "Owned", "value": str(int(item.get("quantity", 0)))},
	], s_txt, s_tone)


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


## Buy-affordance check for a shop row. Returns {"ok": bool, "reason": String}.
## Mirrors ShopManager.buy_item's guards (currency, affordability, room).
func _can_buy(item: Dictionary) -> Dictionary:
	var currency: String = str(item.get("currency", "Meseta"))
	if currency != "Meseta":
		return {"ok": false, "reason": currency}
	var cost: int = int(item.get("cost", 0))
	if _get_meseta() < cost:
		return {"ok": false, "reason": "Can't afford"}
	var item_name: String = str(item.get("item", item.get("name", "")))
	var item_id: String = item_name.to_lower().replace(" ", "_").replace("-", "_").replace("/", "_")
	if not Inventory.can_add_item(item_id):
		return {"ok": false, "reason": "No room"}
	return {"ok": true, "reason": ""}


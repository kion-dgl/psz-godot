extends Control

const SHOP_PREVIEW_PATH := "res://assets/ui/shop-previews/storage-counter.png"
const SHOP_UI := preload("res://scripts/2d/shops/shop_ui.gd")
const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")

## Storage screen — 4 tabs grouped by content:
##     [Deposit Items] [Withdraw Items] [Deposit Meseta] [Withdraw Meseta]
##
## Each tab is unambiguous (no internal direction selector), so
## ui_left/ui_right cycles tabs without trapping the player in a
## "direction stuck on deposit" state — that was the regression psobb
## reported on 2026-05-07 (couldn't reach Withdraw Meseta).
##
## Within an items tab, ui_up/ui_down moves the selection. ui_accept
## opens the move/transfer modal. Meseta tabs have a single transfer
## action — accept opens a QuantityDialog so the player picks how much.

enum Tab { DEPOSIT_ITEMS, WITHDRAW_ITEMS, DEPOSIT_MESETA, WITHDRAW_MESETA }

const TAB_NAMES := ["Deposit Items", "Withdraw Items", "Deposit Meseta", "Withdraw Meseta"]

var _tab: int = Tab.DEPOSIT_ITEMS
var _selected_index: int = 0
var _inventory_items: Array = []
var _storage_items: Array = []

var _mode_bar: HBoxContainer
var _portrait: Control
var _active_modal: Control = null

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeBar/ModeLabel
@onready var inventory_panel: PanelContainer = $Panel/VBox/HBox/InventoryPanel
@onready var storage_panel: PanelContainer = $Panel/VBox/HBox/StoragePanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	_mode_bar = mode_label.get_parent()
	# Two-column content — item list (left) + detail panel (right), matching
	# the shop screens. The detail panel reuses the scene's previously-hidden
	# StoragePanel node (#368 storage-detail-consistency): selecting a row
	# shows stats for gear / effect + count for consumables, with rarity
	# stars in the detail rather than the row label.
	PszStyle.style_menu(title_label, hint_label, [inventory_panel, storage_panel])
	title_label.text = "Storage"
	storage_panel.visible = true
	inventory_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_panel.size_flags_stretch_ratio = 3.0
	storage_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_panel.size_flags_stretch_ratio = 2.0
	_setup_portrait()
	_load_items()
	_refresh_display()
	ShopPreviewSprite.attach(self, SHOP_PREVIEW_PATH)


func _setup_portrait() -> void:
	SHOP_UI.setup_portrait(self)


func _load_items() -> void:
	# Inventory iteration order is the source of truth — pickup order by
	# default, or category-sorted if the player has flipped Auto-Sort on.
	# Storage shows the same way for consistency.
	_inventory_items = Inventory.get_all_items()
	_storage_items = GameState.shared_storage.duplicate(true)


# ── Input ──────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	# No list_size/on_accept: up/down and accept belong to the per-tab
	# handlers below. sfx=false: _change_tab and the per-tab handlers play
	# their own (cancel stays silent here — storage predates the menu_back
	# convention; revisit with the key-drift pass).
	ShopNav.handle(self, event, {
		"modal": _active_modal,
		"sfx": false,
		"on_cancel": func() -> void: SceneManager.pop_scene({"storage_closed": true}),
		"on_tab": _change_tab,
		"on_other": func(ev: InputEvent) -> bool:
			if ev.is_action_pressed("palette_swap"):
				# Bumper buttons also cycle tabs (broader-stroke convention
				# from other game menus); identical to ui_right here.
				_change_tab(1)
				get_viewport().set_input_as_handled()
				return true
			# Per-tab handlers.
			if _is_items_tab():
				_handle_items_input(ev)
			else:
				_handle_meseta_input(ev)
			return false,
	})


func _change_tab(direction: int) -> void:
	_tab = wrapi(_tab + direction, 0, TAB_NAMES.size())
	_selected_index = 0
	_refresh_display()
	SfxManager.play("res://assets/sfx/ui/menu_move.wav")


func _handle_items_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		var max_idx: int = _current_list_size() - 1
		_selected_index = wrapi(_selected_index - 1, 0, maxi(max_idx + 1, 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		var max_idx: int = _current_list_size() - 1
		_selected_index = wrapi(_selected_index + 1, 0, maxi(max_idx + 1, 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_open_move_modal()
		get_viewport().set_input_as_handled()


func _handle_meseta_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_open_meseta_modal()
		get_viewport().set_input_as_handled()


# ── Tab predicates ─────────────────────────────────────────────────────────

func _is_items_tab() -> bool:
	return _tab == Tab.DEPOSIT_ITEMS or _tab == Tab.WITHDRAW_ITEMS


func _current_list() -> Array:
	# For items tabs: deposit shows inventory, withdraw shows storage.
	if _tab == Tab.DEPOSIT_ITEMS:
		return _inventory_items
	if _tab == Tab.WITHDRAW_ITEMS:
		return _storage_items
	return []


func _current_list_size() -> int:
	return _current_list().size()


# ── Modals ─────────────────────────────────────────────────────────────────

## Open a single-button info modal for blocking error states (inventory
## full, equipped item, etc.) so the failure is unmissable rather than a
## silent hint_label update.
func _open_info_modal(msg: String) -> void:
	hint_label.text = msg
	ShopNav.info(self, msg)


func _open_meseta_modal() -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var available: int
	var verb: String
	if _tab == Tab.DEPOSIT_MESETA:
		available = int(character.get("meseta", 0))
		verb = "Deposit"
		if available <= 0:
			_open_info_modal("No meseta to deposit!")
			return
	else:  # WITHDRAW_MESETA
		available = int(GameState.stored_meseta)
		verb = "Withdraw"
		if available <= 0:
			_open_info_modal("No meseta in storage!")
			return

	# QuantityDialog with cost=0 hides the "Total" line. The qty selector
	# lets the player pick how much to move (1..available) instead of
	# being forced to 100 M increments.
	var qty_modal := QuantityDialog.new()
	qty_modal.set_item("Meseta", 0, available, verb)
	qty_modal.ask("%s Meseta?" % verb)
	qty_modal.confirmed_qty.connect(func(qty: int) -> void:
		_active_modal = null
		_do_meseta_transfer(qty)
	)
	qty_modal.cancelled.connect(func() -> void:
		_active_modal = null
	)
	_active_modal = qty_modal
	add_child(qty_modal)


func _open_move_modal() -> void:
	var item_v: Variant = ShopNav.selected_item(self, _current_list())
	if item_v == null:
		return
	var item: Dictionary = item_v
	var item_id: String = str(item.get("id", ""))
	var item_name: String = str(item.get("name", item_id))
	var available_qty: int = int(item.get("quantity", 1))

	# Block storing currently-equipped gear. Same rule the shop's sell
	# flow enforces (item_shop.gd:_sell_selected) — equipped items can't
	# leave the inventory until the player unequips them first.
	if _tab == Tab.DEPOSIT_ITEMS and _is_equipped(item_id):
		_open_info_modal("Unequip first!")
		return

	# How many we can actually move:
	# - Deposit (inv → storage): cap at qty in inventory; storage has no
	#   max_stack so anything we have fits.
	# - Withdraw (storage → inv): cap at qty in storage AND
	#   Inventory.get_stack_room (max_stack - current count, or free
	#   slots for per-slot items).
	var max_qty: int
	if _tab == Tab.DEPOSIT_ITEMS:
		max_qty = available_qty
	else:
		var room: int = Inventory.get_stack_room(item_id)
		max_qty = mini(available_qty, room)
		if max_qty <= 0:
			_open_info_modal("Inventory full!")
			return

	var verb: String = "Store" if _tab == Tab.DEPOSIT_ITEMS else "Withdraw"

	# Per-slot items (weapons, armor, units, mags, disks) always move 1
	# at a time; QuantityDialog with max_qty=1 collapses to a confirm.
	if Inventory._is_per_slot(item_id) or max_qty <= 1:
		ShopNav.confirm(self, "%s %s?" % [verb, item_name], func() -> void: _do_item_move(1))
	else:
		var qty_modal := QuantityDialog.new()
		qty_modal.set_item(item_name, 0, max_qty, verb)
		qty_modal.ask("%s %s?" % [verb, item_name])
		qty_modal.confirmed_qty.connect(func(qty: int) -> void:
			_active_modal = null
			_do_item_move(qty)
		)
		qty_modal.cancelled.connect(func() -> void:
			_active_modal = null
		)
		_active_modal = qty_modal
		add_child(qty_modal)


# ── Actions ────────────────────────────────────────────────────────────────

func _do_meseta_transfer(amount: int) -> void:
	if amount <= 0:
		return
	var character = CharacterManager.get_active_character()
	if character == null:
		return
	if _tab == Tab.DEPOSIT_MESETA:
		var char_meseta: int = int(character.get("meseta", 0))
		var deposit: int = mini(amount, char_meseta)
		if deposit > 0:
			character["meseta"] = int(character["meseta"]) - deposit
			GameState.meseta = int(character["meseta"])
			GameState.stored_meseta += deposit
			hint_label.text = "Deposited %d M (Bank: %d M)" % [deposit, GameState.stored_meseta]
		else:
			hint_label.text = "No meseta to deposit!"
	else:
		var withdraw: int = mini(amount, GameState.stored_meseta)
		if withdraw > 0:
			GameState.stored_meseta -= withdraw
			character["meseta"] = int(character.get("meseta", 0)) + withdraw
			GameState.meseta = int(character["meseta"])
			hint_label.text = "Withdrew %d M (Bank: %d M)" % [withdraw, GameState.stored_meseta]
		else:
			hint_label.text = "No meseta in storage!"
	_refresh_display()


## Move `qty` of the selected item between inventory and storage. For
## per-slot items, qty must be 1; for stackable items qty is whatever
## the QuantityDialog returned.
func _do_item_move(qty: int) -> void:
	if qty <= 0:
		return
	if _tab == Tab.DEPOSIT_ITEMS:
		if _inventory_items.is_empty() or _selected_index >= _inventory_items.size():
			return
		var item: Dictionary = _inventory_items[_selected_index]
		var item_id: String = str(item.get("id", ""))
		var item_name: String = str(item.get("name", item_id))
		var move_qty: int = 1 if Inventory._is_per_slot(item_id) else qty
		var found := false
		for s_item in GameState.shared_storage:
			if str(s_item.get("id", "")) == item_id and not Inventory._is_per_slot(item_id):
				s_item["quantity"] = int(s_item.get("quantity", 0)) + move_qty
				found = true
				break
		if not found:
			GameState.shared_storage.append({"id": item_id, "name": item_name, "quantity": move_qty})
		Inventory.remove_item(item_id, move_qty)
		if move_qty > 1:
			hint_label.text = "Stored %d× %s." % [move_qty, item_name]
		else:
			hint_label.text = "Stored %s." % item_name
	else:  # WITHDRAW_ITEMS
		if _storage_items.is_empty() or _selected_index >= _storage_items.size():
			return
		var item: Dictionary = _storage_items[_selected_index]
		var item_id: String = str(item.get("id", ""))
		var item_name: String = str(item.get("name", item_id))
		var move_qty: int = 1 if Inventory._is_per_slot(item_id) else qty
		# Per-slot can_add_item is per copy; for stackable, add_item
		# silently clamps to max_stack — we already capped via stack_room.
		if Inventory._is_per_slot(item_id) and not Inventory.can_add_item(item_id):
			_open_info_modal("Inventory full!")
			return
		Inventory.add_item(item_id, move_qty)
		for s_item in GameState.shared_storage:
			if str(s_item.get("id", "")) == item_id:
				s_item["quantity"] = int(s_item.get("quantity", 0)) - move_qty
				if int(s_item["quantity"]) <= 0:
					GameState.shared_storage.erase(s_item)
				break
		if move_qty > 1:
			hint_label.text = "Withdrew %d× %s." % [move_qty, item_name]
		else:
			hint_label.text = "Withdrew %s." % item_name

	_load_items()
	_selected_index = clampi(_selected_index, 0, maxi(_current_list_size() - 1, 0))
	_refresh_display()


# ── Render ─────────────────────────────────────────────────────────────────

func _refresh_display() -> void:
	# Tab bar
	for child in _mode_bar.get_children():
		child.queue_free()
	_mode_bar.add_child(PszStyle.create_tab_bar(TAB_NAMES, _tab))

	if _is_items_tab():
		hint_label.text = "Left/Right: Switch Tab  Up/Down: Select  Enter: Move  Esc: Back"
	else:
		hint_label.text = "Left/Right: Switch Tab  Enter: Transfer  Esc: Back"

	_refresh_panel()
	_refresh_detail()


func _refresh_panel() -> void:
	var panel := inventory_panel
	for child in panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	if _is_items_tab():
		_render_items_panel(vbox)
	else:
		_render_meseta_panel(vbox)

	scroll.add_child(vbox)
	panel.add_child(scroll)


## Detail panel for the selected row — stats for gear, effect + count for
## consumables, with rarity stars here rather than in the row label (#368).
func _refresh_detail() -> void:
	PszStyle.clear_detail_panel(storage_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	if not _is_items_tab():
		vbox.add_child(PszStyle.detail_label(
			"Transfer meseta between your wallet and the bank.", PszStyle.TEXT_MUTED))
		storage_panel.add_child(vbox)
		return

	var items: Array = _current_list()
	if items.is_empty() or _selected_index < 0 or _selected_index >= items.size():
		storage_panel.add_child(vbox)
		return

	var item: Dictionary = items[_selected_index]
	var item_id: String = str(item.get("id", "???"))
	var norm_id: String = item_id.replace("-", "_").replace("/", "_")
	var weapon = WeaponRegistry.get_weapon(item_id)
	if weapon == null:
		weapon = WeaponRegistry.get_weapon(norm_id)
	var armor_data = ArmorRegistry.get_armor(item_id)
	if armor_data == null:
		armor_data = ArmorRegistry.get_armor(norm_id)
	var unit_data = UnitRegistry.get_unit(item_id)
	if unit_data == null:
		unit_data = UnitRegistry.get_unit(norm_id)

	var item_name: String = str(item.get("name", item_id))
	if weapon:
		item_name = weapon.name
	elif armor_data:
		item_name = armor_data.name
	vbox.add_child(PszStyle.detail_label(item_name, PszStyle.TITLE_BG))

	if weapon:
		vbox.add_child(PszStyle.detail_label(weapon.get_rarity_string(), PszStyle.TEXT_HIGHLIGHT))
		vbox.add_child(PszStyle.detail_label("Type: %s" % weapon.get_weapon_type_name()))
		vbox.add_child(PszStyle.detail_label("ATK: %d-%d" % [weapon.attack_base, weapon.attack_max]))
		vbox.add_child(PszStyle.detail_label("ACC: %d" % weapon.accuracy_base))
		if not weapon.element.is_empty():
			vbox.add_child(PszStyle.detail_label("Element: %s Lv.%d" % [weapon.element, weapon.element_level]))
		var character = CharacterManager.get_active_character()
		var grind: int = int(character.get("weapon_grinds", {}).get(item_id, 0)) if character else 0
		vbox.add_child(PszStyle.detail_label("Grind: +%d / +%d" % [grind, weapon.max_grind]))
	elif armor_data:
		vbox.add_child(PszStyle.detail_label(armor_data.get_rarity_string(), PszStyle.TEXT_HIGHLIGHT))
		vbox.add_child(PszStyle.detail_label("DEF: %d-%d" % [armor_data.defense_base, armor_data.defense_max]))
		vbox.add_child(PszStyle.detail_label("EVA: %d-%d" % [armor_data.evasion_base, armor_data.evasion_max]))
		vbox.add_child(PszStyle.detail_label("Unit Slots: %d" % armor_data.max_slots))
	elif unit_data:
		vbox.add_child(PszStyle.detail_label("*".repeat(int(unit_data.rarity)), PszStyle.TEXT_HIGHLIGHT))
		vbox.add_child(PszStyle.detail_label("Effect: %s" % unit_data.effect, PszStyle.TEXT_SUCCESS))
	else:
		# Consumable / material — effect + count.
		var consumable = ConsumableRegistry.get_consumable(norm_id)
		if consumable:
			var eff := PszStyle.detail_label(consumable.details)
			eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(eff)
		vbox.add_child(PszStyle.detail_label("Count: x%d" % int(item.get("quantity", 1))))

	vbox.add_child(PszStyle.detail_label(""))
	if _is_equipped(item_id):
		vbox.add_child(PszStyle.detail_label("Equipped — cannot deposit", PszStyle.TEXT_MUTED))
	else:
		vbox.add_child(PszStyle.detail_label("Storable", PszStyle.TEXT_SUCCESS))

	storage_panel.add_child(vbox)


func _render_meseta_panel(vbox: VBoxContainer) -> void:
	var character = CharacterManager.get_active_character()
	var wallet: int = int(character.get("meseta", 0)) if character else 0
	var bank: int = int(GameState.stored_meseta)

	vbox.add_child(PszStyle.create_section_header("WALLET: %d M" % wallet))
	vbox.add_child(PszStyle.create_section_header("BANK:   %d M" % bank))

	var pill_text: String
	if _tab == Tab.DEPOSIT_MESETA:
		pill_text = "Deposit Meseta…"
	else:
		pill_text = "Withdraw Meseta…"
	# Always selected — it's the only action on this tab.
	vbox.add_child(PszStyle.create_pill(pill_text, true))


func _render_items_panel(vbox: VBoxContainer) -> void:
	var items: Array = _current_list()
	var header: String
	if _tab == Tab.DEPOSIT_ITEMS:
		header = "INVENTORY (%d/40)" % Inventory.get_total_slots()
	else:
		header = "STORAGE (%d)" % _storage_items.size()
	vbox.add_child(PszStyle.create_section_header(header))

	if items.is_empty():
		vbox.add_child(PszStyle.create_pill("(Empty)", false, "", PszStyle.TEXT_MUTED))
		return

	var character = CharacterManager.get_active_character()
	var class_type_race := ""
	var char_level := 0
	var equipped_ids: Array = []
	if character:
		var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
		if class_data:
			class_type_race = "%s %s" % [class_data.type, class_data.race]
		char_level = int(character.get("level", 1))
		var equip: Dictionary = character.get("equipment", {})
		for slot_key in equip:
			var eid: String = str(equip.get(slot_key, ""))
			if not eid.is_empty():
				equipped_ids.append(eid)

	var pills_ref: Array = []
	for i in range(items.size()):
		var item: Dictionary = items[i]
		var item_id: String = str(item.get("id", "???"))
		var norm_id: String = item_id.replace("-", "_").replace("/", "_")
		var is_unresolved: bool = (item_id != norm_id)

		var weapon = WeaponRegistry.get_weapon(item_id)
		if weapon == null and is_unresolved:
			weapon = WeaponRegistry.get_weapon(norm_id)
		var armor_data = ArmorRegistry.get_armor(item_id)
		if armor_data == null and is_unresolved:
			armor_data = ArmorRegistry.get_armor(norm_id)

		var item_name: String = str(item.get("name", item_id))
		if is_unresolved:
			if weapon:
				item_name = weapon.name
			elif armor_data:
				item_name = armor_data.name
		var qty: int = int(item.get("quantity", 1))
		# Unified shop convention (#368): [E] is a PREFIX, matching every shop.
		var equip_prefix: String = "[E] " if item_id in equipped_ids else ""

		var grind_tag := ""
		if weapon and character:
			var grind: int = int(character.get("weapon_grinds", {}).get(item_id, 0))
			if grind > 0:
				grind_tag = " +%d" % grind

		# Rarity stars now live in the detail panel (#368); the row keeps the
		# weapon's grind level, which is part of its identity ("Saber +3").
		var display_name := equip_prefix + item_name + grind_tag
		var right_text := "x%d" % qty if qty > 1 else ""

		# Equipped items are locked from being moved into storage (see
		# _do_item_move); show muted to make the locked state legible.
		# Unified disabled style (#368): one grey for every can't-use state
		# (equipped/locked, class mismatch, under-level) — matching the shops,
		# no red/yellow split. Only genuinely-broken data (an id that won't
		# resolve to a weapon/armor) stays red as an error indicator.
		var text_color := Color.TRANSPARENT
		var is_locked_equipped: bool = item_id in equipped_ids
		if is_unresolved:
			text_color = PszStyle.TEXT_DANGER
		elif is_locked_equipped:
			text_color = PszStyle.TEXT_MUTED
		elif weapon and not class_type_race.is_empty():
			if not weapon.can_be_used_by(class_type_race) or char_level < weapon.level:
				text_color = PszStyle.TEXT_MUTED
		elif armor_data and not class_type_race.is_empty():
			if not armor_data.can_be_used_by(class_type_race) or char_level < armor_data.level:
				text_color = PszStyle.TEXT_MUTED

		var is_selected: bool = i == _selected_index
		var item_icon: Texture2D = InventoryIcons.for_item(item_id)
		var icons: Array = [item_icon] if item_icon else []
		var pill := PszStyle.create_pill_with_icons(icons, display_name, is_selected, right_text, text_color)
		vbox.add_child(pill)
		pills_ref.append(pill)

	if _selected_index >= 0 and _selected_index < pills_ref.size():
		var scroll := vbox.get_parent() as ScrollContainer
		if scroll != null:
			scroll.ensure_control_visible.call_deferred(pills_ref[_selected_index])


# ── Hold-to-repeat navigation (NavRepeat) ──────────────────────────────────
var _nav: NavRepeat = null


func _process(delta: float) -> void:
	if is_instance_valid(_active_modal):
		return
	if _nav == null:
		_nav = NavRepeat.new(["ui_up", "ui_down", "ui_left", "ui_right"], _on_nav_repeat)
	_nav.tick(delta)


# ── Equipped-item lock ─────────────────────────────────────────────────────
# Returns true if the active character has item_id in any equipment slot.
# Used both by _open_move_modal() (block storing equipped gear) and by the
# row renderer (grey out + tag with [E]). Same rule as item_shop's sell flow.
func _is_equipped(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	var character = CharacterManager.get_active_character()
	if character == null:
		return false
	var equip: Dictionary = character.get("equipment", {})
	for slot_key in equip.keys():
		if str(equip.get(slot_key, "")) == item_id:
			return true
	return false

# --- Shop scaffolding, inlined. These screens are standalone (extends Control)
# --- rather than sharing a ShopBase: a cross-script base class fails to
# --- resolve in the Android export at runtime (works in-editor and on every
# --- other platform). See the shop-dedup tracker.

## NavRepeat callback: re-emit a held nav action as a synthetic input event
## so this screen's own _unhandled_input handles it (hold-to-repeat nav).
func _on_nav_repeat(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_unhandled_input(ev)


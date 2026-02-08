extends Control
## Storage screen — move items and meseta between inventory and shared storage.

const CATEGORY_ORDER := ["Weapon", "Armor", "Unit", "Mag", "Disk", "Consumable", "Material", "Modifier", "Key Item", "Other"]

enum Mode { ITEMS, MESETA }

var _mode: int = Mode.ITEMS
var _selected_side: int = 0  # 0 = inventory, 1 = storage
var _selected_index: int = 0
var _inventory_items: Array = []
var _storage_items: Array = []
var _inv_labels: Array = []
var _sto_labels: Array = []

@onready var title_label: Label = $VBox/TitleLabel
@onready var inventory_panel: PanelContainer = $VBox/HBox/InventoryPanel
@onready var storage_panel: PanelContainer = $VBox/HBox/StoragePanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "STORAGE"
	_update_hint()
	_load_items()
	_refresh_display()


func _update_hint() -> void:
	if _mode == Mode.ITEMS:
		hint_label.text = "[←/→] Switch  [↑/↓] Select  [ENTER] Move  [M] Meseta  [ESC] Back"
	else:
		hint_label.text = "[←] Deposit  [→] Withdraw  [M] Items  [ESC] Back"


func _load_items() -> void:
	_inventory_items = Inventory.get_all_items()
	_inventory_items.sort_custom(func(a, b):
		var ca: int = CATEGORY_ORDER.find(_get_item_category(a.get("id", "")))
		var cb: int = CATEGORY_ORDER.find(_get_item_category(b.get("id", "")))
		if ca != cb:
			return ca < cb
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	_storage_items = GameState.shared_storage.duplicate(true)
	_storage_items.sort_custom(func(a, b):
		var ca: int = CATEGORY_ORDER.find(_get_item_category(a.get("id", "")))
		var cb: int = CATEGORY_ORDER.find(_get_item_category(b.get("id", "")))
		if ca != cb:
			return ca < cb
		return str(a.get("name", "")) < str(b.get("name", ""))
	)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_M:
		_mode = Mode.MESETA if _mode == Mode.ITEMS else Mode.ITEMS
		_selected_index = 0
		_update_hint()
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif _mode == Mode.MESETA:
		_handle_meseta_input(event)
	else:
		_handle_items_input(event)


func _handle_items_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_selected_side = 0
		_selected_index = clampi(_selected_index, 0, maxi(_inventory_items.size() - 1, 0))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_selected_side = 1
		_selected_index = clampi(_selected_index, 0, maxi(_storage_items.size() - 1, 0))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		var max_idx: int = _get_current_list_size() - 1
		_selected_index = wrapi(_selected_index - 1, 0, maxi(max_idx + 1, 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		var max_idx: int = _get_current_list_size() - 1
		_selected_index = wrapi(_selected_index + 1, 0, maxi(max_idx + 1, 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_move_item()
		get_viewport().set_input_as_handled()


func _handle_meseta_input(event: InputEvent) -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		return
	var amount := 100
	if event.is_action_pressed("ui_left"):
		# Deposit meseta
		var char_meseta: int = int(character.get("meseta", 0))
		var deposit: int = mini(amount, char_meseta)
		if deposit > 0:
			character["meseta"] = int(character["meseta"]) - deposit
			GameState.meseta = int(character["meseta"])
			GameState.stored_meseta += deposit
			hint_label.text = "Deposited %d M (Bank: %d M)" % [deposit, GameState.stored_meseta]
		else:
			hint_label.text = "No meseta to deposit!"
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		# Withdraw meseta
		var withdraw: int = mini(amount, GameState.stored_meseta)
		if withdraw > 0:
			GameState.stored_meseta -= withdraw
			character["meseta"] = int(character.get("meseta", 0)) + withdraw
			GameState.meseta = int(character["meseta"])
			hint_label.text = "Withdrew %d M (Bank: %d M)" % [withdraw, GameState.stored_meseta]
		else:
			hint_label.text = "No meseta in storage!"
		_refresh_display()
		get_viewport().set_input_as_handled()


func _get_current_list_size() -> int:
	if _selected_side == 0:
		return _inventory_items.size()
	else:
		return _storage_items.size()


func _move_item() -> void:
	if _selected_side == 0:
		# Move from inventory to storage
		if _inventory_items.is_empty() or _selected_index >= _inventory_items.size():
			return
		var item: Dictionary = _inventory_items[_selected_index]
		var item_id: String = str(item.get("id", ""))
		# Add to shared storage (merge if stackable and already stored)
		var found := false
		for s_item in GameState.shared_storage:
			if str(s_item.get("id", "")) == item_id and not Inventory._is_per_slot(item_id):
				s_item["quantity"] = int(s_item.get("quantity", 0)) + 1
				found = true
				break
		if not found:
			GameState.shared_storage.append({"id": item_id, "name": item.get("name", item_id), "quantity": 1})
		Inventory.remove_item(item_id, 1)
		hint_label.text = "Stored %s." % item.get("name", item_id)
	else:
		# Move from storage to inventory
		if _storage_items.is_empty() or _selected_index >= _storage_items.size():
			return
		var item: Dictionary = _storage_items[_selected_index]
		var item_id: String = str(item.get("id", ""))
		if not Inventory.can_add_item(item_id):
			hint_label.text = "Inventory full!"
			return
		Inventory.add_item(item_id, 1)
		# Reduce from shared storage
		for s_item in GameState.shared_storage:
			if str(s_item.get("id", "")) == item_id:
				s_item["quantity"] = int(s_item.get("quantity", 0)) - 1
				if int(s_item["quantity"]) <= 0:
					GameState.shared_storage.erase(s_item)
				break
		hint_label.text = "Withdrew %s." % item.get("name", item_id)

	_load_items()
	_selected_index = clampi(_selected_index, 0, maxi(_get_current_list_size() - 1, 0))
	_refresh_display()


func _refresh_display() -> void:
	_refresh_panel(inventory_panel, _inventory_items, "INVENTORY (%d/40)" % Inventory.get_total_slots(), 0)
	_refresh_panel(storage_panel, _storage_items, "STORAGE (%d)" % _storage_items.size(), 1)


func _refresh_panel(panel: PanelContainer, items: Array, header_text: String, side: int) -> void:
	for child in panel.get_children():
		child.queue_free()

	var labels_ref: Array = []
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)

	# Header
	var header := Label.new()
	if _mode == Mode.MESETA:
		var character = CharacterManager.get_active_character()
		if side == 0:
			var char_meseta: int = int(character.get("meseta", 0)) if character else 0
			header.text = "── WALLET: %d M ──" % char_meseta
		else:
			header.text = "── BANK: %d M ──" % GameState.stored_meseta
		header.modulate = ThemeColors.TEXT_HIGHLIGHT
	else:
		header.text = "── %s ──" % header_text
		if _selected_side == side:
			header.modulate = ThemeColors.TEXT_HIGHLIGHT
		else:
			header.modulate = ThemeColors.HEADER
	vbox.add_child(header)

	if _mode == Mode.MESETA:
		var info := Label.new()
		if side == 0:
			info.text = "\n  [←] Deposit 100 M"
		else:
			info.text = "\n  [→] Withdraw 100 M"
		info.modulate = ThemeColors.TEXT_SECONDARY
		vbox.add_child(info)
	elif items.is_empty():
		var empty := Label.new()
		empty.text = "  (Empty)"
		empty.modulate = ThemeColors.TEXT_SECONDARY
		vbox.add_child(empty)
	else:
		# Get character info for equip checks
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

		var current_category := ""
		for i in range(items.size()):
			var item: Dictionary = items[i]
			var item_id: String = str(item.get("id", "???"))
			var norm_id: String = item_id.replace("-", "_").replace("/", "_")
			var is_unresolved: bool = (item_id != norm_id)

			# Category header
			var cat: String = _get_item_category(item_id)
			if cat != current_category:
				current_category = cat
				var cat_label := Label.new()
				cat_label.text = "── %s ──" % cat
				cat_label.modulate = ThemeColors.HEADER
				vbox.add_child(cat_label)

			# Resolve weapon/armor data
			var weapon = WeaponRegistry.get_weapon(item_id)
			if weapon == null and is_unresolved:
				weapon = WeaponRegistry.get_weapon(norm_id)
			var armor_data = ArmorRegistry.get_armor(item_id)
			if armor_data == null and is_unresolved:
				armor_data = ArmorRegistry.get_armor(norm_id)

			var label := Label.new()
			var item_name: String = str(item.get("name", item_id))
			if is_unresolved:
				if weapon:
					item_name = weapon.name
				elif armor_data:
					item_name = armor_data.name
			var qty: int = int(item.get("quantity", 1))
			var equip_tag: String = " [E]" if item_id in equipped_ids else ""

			# Add grind level for weapons
			var grind_tag := ""
			if weapon and character:
				var grind: int = int(character.get("weapon_grinds", {}).get(item_id, 0))
				if grind > 0:
					grind_tag = " +%d" % grind

			# Stars and type for weapons/armor
			var suffix := ""
			if weapon:
				suffix = "%s %s [%s]" % [grind_tag, weapon.get_rarity_string(), weapon.get_weapon_type_name()]
			elif armor_data:
				suffix = " %s [%s]" % [armor_data.get_rarity_string(), armor_data.get_type_name()]

			if qty > 1:
				label.text = "%-18s x%d%s%s" % [item_name, qty, equip_tag, suffix]
			else:
				label.text = "%s%s%s" % [item_name, equip_tag, suffix]

			if _selected_side == side and i == _selected_index:
				label.text = "> " + label.text
				label.modulate = ThemeColors.TEXT_HIGHLIGHT
			else:
				label.text = "  " + label.text
				if is_unresolved:
					label.modulate = ThemeColors.RESTRICT_ID
				elif weapon and not class_type_race.is_empty():
					if not weapon.can_be_used_by(class_type_race):
						label.modulate = ThemeColors.RESTRICT_CLASS
					elif char_level < weapon.level:
						label.modulate = ThemeColors.RESTRICT_LEVEL
				elif armor_data and not class_type_race.is_empty():
					if not armor_data.can_be_used_by(class_type_race):
						label.modulate = ThemeColors.RESTRICT_CLASS
					elif char_level < armor_data.level:
						label.modulate = ThemeColors.RESTRICT_LEVEL
			vbox.add_child(label)
			labels_ref.append(label)

	scroll.add_child(vbox)
	panel.add_child(scroll)

	# Scroll to selected
	if _selected_side == side and _selected_index >= 0 and _selected_index < labels_ref.size():
		scroll.ensure_control_visible.call_deferred(labels_ref[_selected_index])


func _get_item_category(item_id: String) -> String:
	var norm_id: String = item_id.replace("-", "_").replace("/", "_")
	if WeaponRegistry.get_weapon(item_id) or WeaponRegistry.get_weapon(norm_id):
		return "Weapon"
	if ArmorRegistry.get_armor(item_id) or ArmorRegistry.get_armor(norm_id):
		return "Armor"
	if UnitRegistry.get_unit(item_id) or UnitRegistry.get_unit(norm_id):
		return "Unit"
	if ResourceLoader.exists("res://data/mags/%s.tres" % item_id) or ResourceLoader.exists("res://data/mags/%s.tres" % norm_id):
		return "Mag"
	if item_id.begins_with("disk_"):
		return "Disk"
	if ConsumableRegistry.get_consumable(item_id) or ConsumableRegistry.get_consumable(norm_id):
		return "Consumable"
	if CombatManager.MATERIAL_STAT_MAP.has(item_id) or MaterialRegistry.get_material(item_id):
		return "Material"
	if ModifierRegistry.get_modifier(item_id) or ModifierRegistry.get_modifier(norm_id):
		return "Modifier"
	var item_data = ItemRegistry.get_item(item_id)
	if item_data == null:
		item_data = ItemRegistry.get_item(norm_id)
	if item_data:
		return "Key Item"
	return "Other"

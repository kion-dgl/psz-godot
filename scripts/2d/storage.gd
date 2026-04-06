extends Control
## Storage screen — move items and meseta between inventory and shared storage.

const CATEGORY_ORDER := ["Weapon", "Armor", "Unit", "Mag", "Disk", "Consumable", "Material", "Modifier", "Key Item", "Other"]

enum Tab { ITEMS, MESETA }

const TAB_NAMES := ["Store Items", "Store Meseta"]

var _tab: int = Tab.ITEMS
var _selected_side: int = 0  # 0 = inventory, 1 = storage (items tab)
var _selected_index: int = 0
var _meseta_action: int = 0  # 0 = deposit, 1 = withdraw (meseta tab)
var _inventory_items: Array = []
var _storage_items: Array = []

var _mode_bar: HBoxContainer
var _portrait: Control

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeBar/ModeLabel
@onready var inventory_panel: PanelContainer = $Panel/VBox/HBox/InventoryPanel
@onready var storage_panel: PanelContainer = $Panel/VBox/HBox/StoragePanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	_mode_bar = mode_label.get_parent()
	PszStyle.style_menu(title_label, hint_label, [inventory_panel, storage_panel])
	title_label.text = "Storage"
	_setup_portrait()
	_load_items()
	_refresh_display()


func _setup_portrait() -> void:
	var data := SceneManager.get_transition_data()
	var model_path: String = data.get("npc_model_path", "")
	if model_path.is_empty():
		return
	# Make panel fullscreen
	var panel: PanelContainer = $Panel
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	var fs := StyleBoxFlat.new()
	fs.bg_color = PszStyle.BG
	fs.content_margin_left = 12.0
	fs.content_margin_top = 8.0
	fs.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", fs)

	# Wrap VBox in outer HBox: left menu (3/5) + right portrait (2/5)
	var vbox := panel.get_child(0) as VBoxContainer
	panel.remove_child(vbox)
	var outer := HBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_stretch_ratio = 3.0
	outer.add_child(vbox)

	# Right: just portrait (no detail panel for storage)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 2.0
	right.add_theme_constant_override("separation", 0)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = 1.0
	right.add_child(spacer)
	_portrait = PszStyle.create_npc_portrait(model_path)
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portrait.size_flags_stretch_ratio = 1.0
	right.add_child(_portrait)
	outer.add_child(right)
	panel.add_child(outer)


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
		SceneManager.pop_scene({"storage_closed": true})
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_tab = Tab.MESETA if _tab == Tab.ITEMS else Tab.ITEMS
		_selected_index = 0
		_meseta_action = 0
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif _tab == Tab.ITEMS:
		_handle_items_input(event)
	else:
		_handle_meseta_input(event)


func _handle_items_input(event: InputEvent) -> void:
	if event.is_action_pressed("palette_swap"):
		# Switch between inventory and storage panels
		_selected_side = 1 - _selected_side
		_selected_index = clampi(_selected_index, 0, maxi(_get_current_list_size() - 1, 0))
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
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		_meseta_action = 1 - _meseta_action
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_do_meseta_transfer()
		get_viewport().set_input_as_handled()


func _do_meseta_transfer() -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		return
	var amount := 100
	if _meseta_action == 0:
		# Deposit
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
		# Withdraw
		var withdraw: int = mini(amount, GameState.stored_meseta)
		if withdraw > 0:
			GameState.stored_meseta -= withdraw
			character["meseta"] = int(character.get("meseta", 0)) + withdraw
			GameState.meseta = int(character["meseta"])
			hint_label.text = "Withdrew %d M (Bank: %d M)" % [withdraw, GameState.stored_meseta]
		else:
			hint_label.text = "No meseta in storage!"
	_refresh_display()


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
	# Tab bar
	for child in _mode_bar.get_children():
		child.queue_free()
	_mode_bar.add_child(PszStyle.create_tab_bar(TAB_NAMES, _tab))

	if _tab == Tab.ITEMS:
		hint_label.text = "Left/Right: Switch Tab  TAB: Switch Panel  Up/Down: Select  Enter: Move  Esc: Back"
	else:
		hint_label.text = "Left/Right: Switch Tab  Up/Down: Select  Enter: Transfer 100M  Esc: Back"

	_refresh_items_panel(inventory_panel, _inventory_items, "INVENTORY (%d/40)" % Inventory.get_total_slots(), 0)
	_refresh_items_panel(storage_panel, _storage_items, "STORAGE (%d)" % _storage_items.size(), 1)


func _refresh_items_panel(panel: PanelContainer, items: Array, header_text: String, side: int) -> void:
	for child in panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	var pills_ref: Array = []

	# Header
	if _tab == Tab.MESETA:
		var character = CharacterManager.get_active_character()
		if side == 0:
			var char_meseta: int = int(character.get("meseta", 0)) if character else 0
			vbox.add_child(PszStyle.create_section_header("WALLET: %d M" % char_meseta))
		else:
			vbox.add_child(PszStyle.create_section_header("BANK: %d M" % GameState.stored_meseta))
	else:
		var header_color := PszStyle.TEXT_HIGHLIGHT if _selected_side == side else PszStyle.TITLE_BG
		vbox.add_child(PszStyle.create_section_header(header_text))

	if _tab == Tab.MESETA:
		# Meseta mode: show deposit/withdraw options
		if side == 0:
			var pill := PszStyle.create_pill("Deposit 100 M", _meseta_action == 0)
			vbox.add_child(pill)
		else:
			var pill := PszStyle.create_pill("Withdraw 100 M", _meseta_action == 1)
			vbox.add_child(pill)
	elif items.is_empty():
		vbox.add_child(PszStyle.create_pill("(Empty)", false, "", PszStyle.TEXT_MUTED))
	else:
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

			var cat: String = _get_item_category(item_id)
			if cat != current_category:
				current_category = cat
				vbox.add_child(PszStyle.create_section_header(cat))

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
			var equip_tag: String = " [E]" if item_id in equipped_ids else ""

			var grind_tag := ""
			if weapon and character:
				var grind: int = int(character.get("weapon_grinds", {}).get(item_id, 0))
				if grind > 0:
					grind_tag = " +%d" % grind

			var suffix := ""
			if weapon:
				suffix = "%s %s" % [grind_tag, weapon.get_rarity_string()]
			elif armor_data:
				suffix = " %s" % armor_data.get_rarity_string()

			var display_name := item_name + equip_tag + suffix
			var right_text := "x%d" % qty if qty > 1 else ""

			# Determine text color based on equippability
			var text_color := Color.TRANSPARENT
			if is_unresolved:
				text_color = PszStyle.TEXT_DANGER
			elif weapon and not class_type_race.is_empty():
				if not weapon.can_be_used_by(class_type_race):
					text_color = PszStyle.TEXT_DANGER
				elif char_level < weapon.level:
					text_color = PszStyle.TEXT_WARNING
			elif armor_data and not class_type_race.is_empty():
				if not armor_data.can_be_used_by(class_type_race):
					text_color = PszStyle.TEXT_DANGER
				elif char_level < armor_data.level:
					text_color = PszStyle.TEXT_WARNING

			var is_selected: bool = _selected_side == side and i == _selected_index
			var pill := PszStyle.create_pill(display_name, is_selected, right_text, text_color)
			vbox.add_child(pill)
			pills_ref.append(pill)

	scroll.add_child(vbox)
	panel.add_child(scroll)

	if _tab == Tab.ITEMS and _selected_side == side and _selected_index >= 0 and _selected_index < pills_ref.size():
		scroll.ensure_control_visible.call_deferred(pills_ref[_selected_index])


func _get_item_category(item_id: String) -> String:
	var norm_id: String = item_id.replace("-", "_").replace("/", "_")
	if WeaponRegistry.get_weapon(item_id) or WeaponRegistry.get_weapon(norm_id):
		return "Weapon"
	if ArmorRegistry.get_armor(item_id) or ArmorRegistry.get_armor(norm_id):
		return "Armor"
	if UnitRegistry.get_unit(item_id) or UnitRegistry.get_unit(norm_id):
		return "Unit"
	if MagManager.is_mag(item_id) or MagManager.is_mag(norm_id):
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

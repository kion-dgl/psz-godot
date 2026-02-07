extends Control
## Inventory screen — 40-slot grid with item details and actions.

var _selected_index: int = 0
var _items: Array = []

@onready var title_label: Label = $VBox/TitleLabel
@onready var grid_panel: PanelContainer = $VBox/HBox/GridPanel
@onready var detail_panel: PanelContainer = $VBox/HBox/DetailPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "══════ INVENTORY ══════"
	hint_label.text = "[↑/↓] Select  [ENTER] Use/Equip  [D] Drop  [ESC] Back"
	_refresh_items()
	_refresh_display()


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
		_use_selected()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_D:
		_drop_selected()
		get_viewport().set_input_as_handled()


func _refresh_items() -> void:
	_items = Inventory.get_all_items()


func _use_selected() -> void:
	if _items.is_empty() or _selected_index >= _items.size():
		return
	var item: Dictionary = _items[_selected_index]
	var item_id: String = item.get("id", "")
	if Inventory.use_item(item_id):
		hint_label.text = "Used %s!" % item_id
		_refresh_items()
		_selected_index = clampi(_selected_index, 0, maxi(_items.size() - 1, 0))
		_refresh_display()
	else:
		hint_label.text = "Can't use that item."


func _drop_selected() -> void:
	if _items.is_empty() or _selected_index >= _items.size():
		return
	var item: Dictionary = _items[_selected_index]
	var item_id: String = item.get("id", "")
	Inventory.remove_item(item_id, 1)
	hint_label.text = "Dropped %s." % item_id
	_refresh_items()
	_selected_index = clampi(_selected_index, 0, maxi(_items.size() - 1, 0))
	_refresh_display()


func _refresh_display() -> void:
	# Grid panel
	for child in grid_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var slot_count := "%d/40 slots" % _items.size()
	var header := Label.new()
	header.text = slot_count
	header.modulate = Color(0.333, 0.333, 0.333)
	vbox.add_child(header)

	# Get equipped item IDs for marking
	var equipped_ids: Array = []
	var character = CharacterManager.get_active_character()
	if character:
		var equip: Dictionary = character.get("equipment", {})
		for slot_key in equip:
			var eid: String = str(equip.get(slot_key, ""))
			if not eid.is_empty():
				equipped_ids.append(eid)

	if _items.is_empty():
		var empty := Label.new()
		empty.text = "\n  (Inventory is empty)"
		empty.modulate = Color(0.333, 0.333, 0.333)
		vbox.add_child(empty)
	else:
		for i in range(_items.size()):
			var item: Dictionary = _items[i]
			var label := Label.new()
			var item_id: String = item.get("id", "???")
			var item_name: String = item.get("name", item_id)
			var qty: int = int(item.get("quantity", 1))
			var equip_tag: String = " [E]" if item_id in equipped_ids else ""

			if qty > 1:
				label.text = "%-24s x%d%s" % [item_name, qty, equip_tag]
			else:
				label.text = "%s%s" % [item_name, equip_tag]

			if i == _selected_index:
				label.text = "> " + label.text
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + label.text
			vbox.add_child(label)

	scroll.add_child(vbox)
	grid_panel.add_child(scroll)

	# Detail panel
	_refresh_detail()


func _refresh_detail() -> void:
	for child in detail_panel.get_children():
		child.queue_free()

	if _items.is_empty() or _selected_index >= _items.size():
		return

	var item: Dictionary = _items[_selected_index]
	var item_id: String = item.get("id", "")
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var item_name: String = item.get("name", item_id)

	var name_label := Label.new()
	name_label.text = "── %s ──" % item_name
	name_label.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(name_label)

	var qty_label := Label.new()
	qty_label.text = "Quantity: %d" % int(item.get("quantity", 1))
	vbox.add_child(qty_label)

	# Check if equipped
	var character2 = CharacterManager.get_active_character()
	if character2:
		var equip2: Dictionary = character2.get("equipment", {})
		for slot_key in equip2:
			if str(equip2.get(slot_key, "")) == item_id:
				var equip_label := Label.new()
				equip_label.text = "[Equipped]"
				equip_label.modulate = Color(1, 0.8, 0)
				vbox.add_child(equip_label)
				break

	# Look up item data from registries
	var item_data = ItemRegistry.get_item(item_id)
	if item_data:
		var type_label := Label.new()
		type_label.text = "Type: %s" % item_data.get_type_name()
		vbox.add_child(type_label)
		if not item_data.description.is_empty():
			var desc_label := Label.new()
			desc_label.text = item_data.description
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(desc_label)

	var consumable = ConsumableRegistry.get_consumable(item_id)
	if consumable:
		var details := Label.new()
		details.text = consumable.details
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(details)

	# Weapon details
	var weapon = WeaponRegistry.get_weapon(item_id)
	if weapon:
		_add_detail_line(vbox, "Type: %s" % weapon.get_weapon_type_name())
		_add_detail_line(vbox, "ATK: %d" % weapon.attack_base)
		_add_detail_line(vbox, "ACC: %d" % weapon.accuracy_base)
		if not weapon.element.is_empty() and weapon.element != "None":
			_add_detail_line(vbox, "Element: %s" % weapon.element)
		_add_detail_line(vbox, "Rarity: %s" % weapon.get_rarity_string())

	# Armor details
	var armor = ArmorRegistry.get_armor(item_id)
	if armor:
		_add_detail_line(vbox, "Type: %s" % armor.get_type_name())
		_add_detail_line(vbox, "DEF: %d" % armor.defense_base)
		_add_detail_line(vbox, "EVA: %d" % armor.evasion_base)

	# Unit details
	var unit = UnitRegistry.get_unit(item_id)
	if unit:
		_add_detail_line(vbox, "Type: Unit")
		if unit.effect and not str(unit.effect).is_empty():
			_add_detail_line(vbox, "Effect: %s" % unit.effect)

	detail_panel.add_child(vbox)


func _add_detail_line(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)

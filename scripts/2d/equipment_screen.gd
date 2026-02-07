extends Control
## Equipment screen — view and manage equipped items (weapon, frame, unit1-4, mag).

const EQUIPMENT_SLOTS := ["weapon", "frame", "mag", "unit1", "unit2", "unit3", "unit4"]
const SLOT_NAMES := ["Weapon", "Frame", "Mag", "Unit 1", "Unit 2", "Unit 3", "Unit 4"]

var _selected_slot: int = 0
var _choosing_item: bool = false
var _equippable_items: Array = []  # Array of {id, name} for current slot
var _selected_item: int = 0

@onready var title_label: Label = $VBox/TitleLabel
@onready var equip_panel: PanelContainer = $VBox/HBox/EquipPanel
@onready var stats_panel: PanelContainer = $VBox/HBox/StatsPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "══════ EQUIPMENT ══════"
	hint_label.text = "[↑/↓] Select Slot  [ENTER] Equip/Unequip  [ESC] Back"
	_refresh_display()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _choosing_item:
			_choosing_item = false
			hint_label.text = "[↑/↓] Select Slot  [ENTER] Equip/Unequip  [ESC] Back"
			_refresh_display()
		else:
			SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		if _choosing_item:
			_selected_item = wrapi(_selected_item - 1, 0, maxi(_equippable_items.size(), 1))
		else:
			_selected_slot = wrapi(_selected_slot - 1, 0, EQUIPMENT_SLOTS.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if _choosing_item:
			_selected_item = wrapi(_selected_item + 1, 0, maxi(_equippable_items.size(), 1))
		else:
			_selected_slot = wrapi(_selected_slot + 1, 0, EQUIPMENT_SLOTS.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _choosing_item:
			_equip_selected_item()
		else:
			_toggle_equip()
		get_viewport().set_input_as_handled()


func _toggle_equip() -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		return
	var equipment: Dictionary = character.get("equipment", {})
	var slot_key: String = EQUIPMENT_SLOTS[_selected_slot]
	var current: String = str(equipment.get(slot_key, ""))

	if not current.is_empty():
		# Unequip — item stays in inventory
		equipment[slot_key] = ""
		var info: Dictionary = Inventory._lookup_item(current)
		hint_label.text = "Unequipped %s" % info.name
		_refresh_display()
	else:
		# Open item selection for this slot
		_open_item_selection()


func _open_item_selection() -> void:
	var slot_key: String = EQUIPMENT_SLOTS[_selected_slot]
	_equippable_items.clear()

	# Get character's currently equipped items to exclude them
	var character = CharacterManager.get_active_character()
	if character == null:
		return
	var equipment: Dictionary = character.get("equipment", {})
	var equipped_ids: Array = []
	for s in EQUIPMENT_SLOTS:
		var eid: String = str(equipment.get(s, ""))
		if not eid.is_empty():
			equipped_ids.append(eid)

	# Scan inventory for items matching this slot type
	for item_id in Inventory._items:
		if item_id in equipped_ids:
			continue  # Already equipped in another slot
		if _item_fits_slot(item_id, slot_key):
			var info: Dictionary = Inventory._lookup_item(item_id)
			_equippable_items.append({"id": item_id, "name": info.name})

	if _equippable_items.is_empty():
		hint_label.text = "No %s in inventory!" % SLOT_NAMES[_selected_slot].to_lower()
		_refresh_display()
		return

	_choosing_item = true
	_selected_item = 0
	hint_label.text = "[↑/↓] Select Item  [ENTER] Equip  [ESC] Cancel"
	_refresh_display()


func _item_fits_slot(item_id: String, slot_key: String) -> bool:
	match slot_key:
		"weapon":
			return WeaponRegistry.has_weapon(item_id)
		"frame":
			return ArmorRegistry.has_armor(item_id)
		"unit1", "unit2", "unit3", "unit4":
			return UnitRegistry.get_unit(item_id) != null
		"mag":
			var mag_path := "res://data/mags/%s.tres" % item_id
			return ResourceLoader.exists(mag_path)
	return false


func _equip_selected_item() -> void:
	if _equippable_items.is_empty() or _selected_item >= _equippable_items.size():
		return
	var character = CharacterManager.get_active_character()
	if character == null:
		return
	var equipment: Dictionary = character.get("equipment", {})
	var slot_key: String = EQUIPMENT_SLOTS[_selected_slot]
	var item: Dictionary = _equippable_items[_selected_item]

	equipment[slot_key] = item.id
	_choosing_item = false
	hint_label.text = "Equipped %s!" % item.name
	_refresh_display()


func _refresh_display() -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var equipment: Dictionary = character.get("equipment", {})

	# Equipment slots panel
	for child in equip_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = "── Equipment Slots ──"
	header.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(header)

	if _choosing_item:
		# Show item selection list
		var slot_label := Label.new()
		slot_label.text = "Select %s:" % SLOT_NAMES[_selected_slot]
		slot_label.modulate = Color(0, 0.733, 0.8)
		vbox.add_child(slot_label)

		for i in range(_equippable_items.size()):
			var item: Dictionary = _equippable_items[i]
			var label := Label.new()
			var detail_str := _get_item_brief(str(item.get("id", "")))
			if detail_str.is_empty():
				label.text = item.name
			else:
				label.text = "%-16s %s" % [str(item.get("name", "")), detail_str]
			if i == _selected_item:
				label.text = "> " + label.text
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + label.text
			vbox.add_child(label)
	else:
		# Show equipment slots
		for i in range(EQUIPMENT_SLOTS.size()):
			var slot_key: String = EQUIPMENT_SLOTS[i]
			var equipped: String = str(equipment.get(slot_key, ""))
			var slot_name: String = SLOT_NAMES[i]

			var item_display: String = "[Empty]"
			if not equipped.is_empty():
				var info: Dictionary = Inventory._lookup_item(equipped)
				item_display = info.name

			var label := Label.new()
			label.text = "%-8s %s" % [slot_name, item_display]
			if i == _selected_slot:
				label.text = "> " + label.text
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + label.text
				if equipped.is_empty():
					label.modulate = Color(0.333, 0.333, 0.333)

			vbox.add_child(label)

	equip_panel.add_child(vbox)

	# Stats panel
	_refresh_stats()


func _get_item_brief(item_id: String) -> String:
	var w = WeaponRegistry.get_weapon(item_id)
	if w:
		return "ATK %d" % w.attack_base
	var a = ArmorRegistry.get_armor(item_id)
	if a:
		return "DEF %d" % a.defense_base
	var u = UnitRegistry.get_unit(item_id)
	if u:
		return u.effect
	return ""


func _refresh_stats() -> void:
	for child in stats_panel.get_children():
		child.queue_free()

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	if class_data == null:
		return

	var level: int = int(character.get("level", 1))
	var base_stats: Dictionary = class_data.get_stats_at_level(level)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var stat_header := Label.new()
	stat_header.text = "── Stats ──"
	stat_header.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(stat_header)

	var name_label := Label.new()
	name_label.text = "%s  %s Lv.%d" % [
		str(character.get("name", "???")),
		str(character.get("class_id", "???")),
		level
	]
	name_label.modulate = Color(1, 0.8, 0)
	vbox.add_child(name_label)

	var sep := Label.new()
	sep.text = ""
	vbox.add_child(sep)

	for stat_name in ["hp", "pp", "attack", "defense", "accuracy", "evasion", "technique"]:
		var display: String = stat_name.to_upper().substr(0, 3)
		match stat_name:
			"technique": display = "TEC"
			"accuracy": display = "ACC"
			"evasion": display = "EVA"
			"defense": display = "DEF"
			"attack": display = "ATK"
		var val: int = base_stats.get(stat_name, 0)
		var stat_label := Label.new()
		stat_label.text = "  %-4s %d" % [display, val]
		vbox.add_child(stat_label)

	stats_panel.add_child(vbox)

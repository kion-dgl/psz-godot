extends Control
## Inventory screen — 40-slot grid with item details and actions.

const CATEGORY_ORDER := ["Weapon", "Armor", "Unit", "Mag", "Disk", "Consumable", "Material", "Modifier", "Key Item", "Other"]

var _selected_index: int = 0
var _items: Array = []
var _item_labels: Array = []  # maps item index -> Label node for scroll-to

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
	_items.sort_custom(func(a, b):
		var ca: int = CATEGORY_ORDER.find(_get_item_category(a.get("id", "")))
		var cb: int = CATEGORY_ORDER.find(_get_item_category(b.get("id", "")))
		if ca != cb:
			return ca < cb
		return str(a.get("name", "")) < str(b.get("name", ""))
	)


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
	elif CombatManager.MATERIAL_STAT_MAP.has(item_id):
		var result: Dictionary = CombatManager.use_material(item_id)
		hint_label.text = result.get("message", "Can't use that item.")
		_refresh_items()
		_selected_index = clampi(_selected_index, 0, maxi(_items.size() - 1, 0))
		_refresh_display()
	elif item_id.begins_with("disk_"):
		_use_disk(item_id)
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


func _use_disk(item_id: String) -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		hint_label.text = "No active character!"
		return
	# Parse disk ID: disk_<tech_id>_<level>
	var parts: PackedStringArray = item_id.split("_", false, 2)
	if parts.size() < 3:
		hint_label.text = "Invalid disk!"
		return
	var tech_id: String = parts[1]
	var level: int = int(parts[2])
	var disk := {"technique_id": tech_id, "level": level}
	var result: Dictionary = TechniqueManager.use_disk(character, disk)
	if result.get("success", false):
		Inventory.remove_item(item_id, 1)
		hint_label.text = str(result.get("message", "Learned!"))
		_refresh_items()
		_selected_index = clampi(_selected_index, 0, maxi(_items.size() - 1, 0))
		_refresh_display()
	else:
		hint_label.text = str(result.get("message", "Can't use that disk."))


func _refresh_display() -> void:
	# Grid panel
	for child in grid_panel.get_children():
		child.queue_free()
	_item_labels.clear()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var slot_count := "%d/40 slots" % Inventory.get_total_slots()
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

	# Get class info for equip checks
	var class_type_race := ""
	var char_level := 0
	if character:
		var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
		if class_data:
			class_type_race = "%s %s" % [class_data.type, class_data.race]
		char_level = int(character.get("level", 1))

	if _items.is_empty():
		var empty := Label.new()
		empty.text = "\n  (Inventory is empty)"
		empty.modulate = Color(0.333, 0.333, 0.333)
		vbox.add_child(empty)
	else:
		var current_category := ""
		for i in range(_items.size()):
			var item: Dictionary = _items[i]
			var item_id: String = item.get("id", "???")
			var norm_id: String = item_id.replace("-", "_").replace("/", "_")
			var is_unresolved: bool = (item_id != norm_id)

			# Category header
			var cat: String = _get_item_category(item_id)
			if cat != current_category:
				current_category = cat
				var cat_label := Label.new()
				cat_label.text = "── %s ──" % cat
				cat_label.modulate = Color(0, 0.733, 0.8)
				vbox.add_child(cat_label)

			# Try to resolve weapon/armor data (raw ID first, then normalized)
			var weapon = WeaponRegistry.get_weapon(item_id)
			if weapon == null and is_unresolved:
				weapon = WeaponRegistry.get_weapon(norm_id)
			var armor_data = ArmorRegistry.get_armor(item_id)
			if armor_data == null and is_unresolved:
				armor_data = ArmorRegistry.get_armor(norm_id)

			var label := Label.new()
			var item_name: String = item.get("name", item_id)
			# Use proper name from registry for unresolved items
			if is_unresolved:
				if weapon:
					item_name = weapon.name
				elif armor_data:
					item_name = armor_data.name
			var qty: int = int(item.get("quantity", 1))
			var equip_tag: String = " [E]" if item_id in equipped_ids else ""

			# Add stars and type for weapons/armor
			var suffix := ""
			if weapon:
				suffix = " %s [%s]" % [weapon.get_rarity_string(), weapon.get_weapon_type_name()]
			elif armor_data:
				suffix = " %s [%s]" % [armor_data.get_rarity_string(), armor_data.get_type_name()]

			if qty > 1:
				label.text = "%-20s x%d%s%s" % [item_name, qty, equip_tag, suffix]
			else:
				label.text = "%s%s%s" % [item_name, equip_tag, suffix]

			if i == _selected_index:
				label.text = "> " + label.text
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + label.text
				# Color coding for equippability and unresolved refs
				if is_unresolved:
					label.modulate = Color(0.7, 0.3, 0.7)  # magenta — mismatched ID
				elif weapon and not class_type_race.is_empty():
					if not weapon.can_be_used_by(class_type_race):
						label.modulate = Color(0.5, 0.2, 0.2)  # dim red — wrong class
					elif char_level < weapon.level:
						label.modulate = Color(0.7, 0.5, 0.15)  # dim orange — level too low
				elif armor_data and not class_type_race.is_empty():
					if not armor_data.can_be_used_by(class_type_race):
						label.modulate = Color(0.5, 0.2, 0.2)
					elif char_level < armor_data.level:
						label.modulate = Color(0.7, 0.5, 0.15)
			vbox.add_child(label)
			_item_labels.append(label)

	scroll.add_child(vbox)
	grid_panel.add_child(scroll)

	# Scroll to selected item after layout
	if _selected_index >= 0 and _selected_index < _item_labels.size():
		scroll.ensure_control_visible.call_deferred(_item_labels[_selected_index])

	# Detail panel
	_refresh_detail()


func _refresh_detail() -> void:
	for child in detail_panel.get_children():
		child.queue_free()

	if _items.is_empty() or _selected_index >= _items.size():
		return

	var item: Dictionary = _items[_selected_index]
	var item_id: String = item.get("id", "")
	var norm_id: String = item_id.replace("-", "_").replace("/", "_")
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

	# Unresolved reference warning
	if item_id != norm_id:
		var warn_label := Label.new()
		warn_label.text = "[Mismatched ID: %s]" % item_id
		warn_label.modulate = Color(0.7, 0.3, 0.7)
		vbox.add_child(warn_label)

	# Look up item data from registries (try raw then normalized)
	var item_data = ItemRegistry.get_item(item_id)
	if item_data == null:
		item_data = ItemRegistry.get_item(norm_id)
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
	if consumable == null:
		consumable = ConsumableRegistry.get_consumable(norm_id)
	if consumable:
		var details := Label.new()
		details.text = consumable.details
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(details)

	# Get class info for equip restriction display
	var class_type_race := ""
	var char_level := 0
	if character2:
		var class_data = ClassRegistry.get_class_data(str(character2.get("class_id", "")))
		if class_data:
			class_type_race = "%s %s" % [class_data.type, class_data.race]
		char_level = int(character2.get("level", 1))

	# Weapon details
	var weapon = WeaponRegistry.get_weapon(item_id)
	if weapon == null:
		weapon = WeaponRegistry.get_weapon(norm_id)
	if weapon:
		_add_detail_line(vbox, "Type: %s" % weapon.get_weapon_type_name())
		_add_detail_line(vbox, "ATK: %d" % weapon.attack_base)
		_add_detail_line(vbox, "ACC: %d" % weapon.accuracy_base)
		if not weapon.element.is_empty() and weapon.element != "None":
			_add_detail_line(vbox, "Element: %s" % weapon.element)
		_add_detail_line(vbox, "Rarity: %s" % weapon.get_rarity_string())
		if weapon.level > 0:
			var lvl_label := Label.new()
			lvl_label.text = "Req. Lv: %d" % weapon.level
			if char_level < weapon.level:
				lvl_label.modulate = Color(0.7, 0.5, 0.15)
			vbox.add_child(lvl_label)
		if not weapon.usable_by.is_empty() and not class_type_race.is_empty():
			if not weapon.can_be_used_by(class_type_race):
				var restrict_label := Label.new()
				restrict_label.text = "[Cannot equip — wrong class]"
				restrict_label.modulate = Color(0.5, 0.2, 0.2)
				vbox.add_child(restrict_label)

	# Armor details
	var armor = ArmorRegistry.get_armor(item_id)
	if armor == null:
		armor = ArmorRegistry.get_armor(norm_id)
	if armor:
		_add_detail_line(vbox, "Type: %s" % armor.get_type_name())
		_add_detail_line(vbox, "DEF: %d" % armor.defense_base)
		_add_detail_line(vbox, "EVA: %d" % armor.evasion_base)
		_add_detail_line(vbox, "Rarity: %s" % armor.get_rarity_string())
		if armor.level > 0:
			var lvl_label := Label.new()
			lvl_label.text = "Req. Lv: %d" % armor.level
			if char_level < armor.level:
				lvl_label.modulate = Color(0.7, 0.5, 0.15)
			vbox.add_child(lvl_label)
		if not armor.usable_by.is_empty() and not class_type_race.is_empty():
			if not armor.can_be_used_by(class_type_race):
				var restrict_label := Label.new()
				restrict_label.text = "[Cannot equip — wrong class]"
				restrict_label.modulate = Color(0.5, 0.2, 0.2)
				vbox.add_child(restrict_label)

	# Unit details
	var unit = UnitRegistry.get_unit(item_id)
	if unit == null:
		unit = UnitRegistry.get_unit(norm_id)
	if unit:
		_add_detail_line(vbox, "Type: Unit")
		if unit.effect and not str(unit.effect).is_empty():
			_add_detail_line(vbox, "Effect: %s" % unit.effect)

	# Disk details
	if item_id.begins_with("disk_"):
		var parts: PackedStringArray = item_id.split("_", false, 2)
		if parts.size() >= 3:
			var tech_id: String = parts[1]
			var level: int = int(parts[2])
			var tech: Dictionary = TechniqueManager.get_technique(tech_id)
			if not tech.is_empty():
				_add_detail_line(vbox, "Type: Technique Disk")
				_add_detail_line(vbox, "Element: %s" % str(tech.get("element", "none")).capitalize())
				_add_detail_line(vbox, "Target: %s" % str(tech.get("target", "single")).capitalize())
				var power: int = int(tech.get("power", 0))
				if power > 0:
					var scaled_power: int = int(float(power) * (1.0 + float(level) / 10.0))
					_add_detail_line(vbox, "Power: %d (Lv.%d)" % [scaled_power, level])
				var pp_cost: int = maxi(1, int(tech.get("pp", 5)) - int(float(level) / 5.0))
				_add_detail_line(vbox, "PP Cost: %d" % pp_cost)
				var required_level: int = TechniqueManager.get_disk_required_level(level)
				var req_label := Label.new()
				req_label.text = "Req. Level: %d" % required_level
				if char_level < required_level:
					req_label.modulate = Color(0.7, 0.5, 0.15)
				vbox.add_child(req_label)
				if character2:
					var current_tech_level: int = TechniqueManager.get_technique_level(character2, tech_id)
					if current_tech_level > 0:
						var cur_label := Label.new()
						if current_tech_level >= level:
							cur_label.text = "Known: Lv.%d (already higher)" % current_tech_level
							cur_label.modulate = Color(0.5, 0.5, 0.5)
						else:
							cur_label.text = "Known: Lv.%d → Lv.%d" % [current_tech_level, level]
							cur_label.modulate = Color(0.5, 1, 0.5)
						vbox.add_child(cur_label)

	# Material details
	if CombatManager.MATERIAL_STAT_MAP.has(item_id):
		var mat = MaterialRegistry.get_material(item_id)
		if mat:
			_add_detail_line(vbox, "Type: Material")
			if not mat.details.is_empty():
				var detail_label := Label.new()
				detail_label.text = mat.details
				detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				vbox.add_child(detail_label)
		var stat_name: String = CombatManager.MATERIAL_STAT_MAP[item_id]
		if stat_name == "reset":
			_add_detail_line(vbox, "Resets all material bonuses")
		else:
			_add_detail_line(vbox, "Stat: %s +2" % stat_name.capitalize())
		var character3 = CharacterManager.get_active_character()
		if character3:
			var used: int = int(character3.get("materials_used", 0))
			_add_detail_line(vbox, "Materials used: %d/%d" % [used, CombatManager.MAX_MATERIALS])

	detail_panel.add_child(vbox)


func _get_item_category(item_id: String) -> String:
	# Normalize ID for registry lookups (save data may have hyphens/slashes)
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


func _add_detail_line(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)

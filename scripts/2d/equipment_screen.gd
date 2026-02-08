extends Control
## Equipment screen — view and manage equipped items (weapon, frame, units, mag).
## Unit slots are dynamic based on equipped armor's max_slots.

const ALL_SLOTS := ["weapon", "frame", "mag", "unit1", "unit2", "unit3", "unit4"]
const ALL_SLOT_NAMES := ["Weapon", "Frame", "Mag", "Unit 1", "Unit 2", "Unit 3", "Unit 4"]
const UNEQUIP_SENTINEL := "__unequip__"
const UNIT_CATEGORY_TO_BONUS := {
	"Power": "atk", "Guard": "def", "HP": "hp", "PP": "pp",
	"Hit": "acc", "Mind": "tech", "Swift": "eva",
}

var _selected_slot: int = 0
var _choosing_item: bool = false
var _equippable_items: Array = []  # Array of {id, name} for current slot
var _selected_item: int = 0

@onready var title_label: Label = $VBox/TitleLabel
@onready var equip_panel: PanelContainer = $VBox/HBox/EquipPanel
@onready var stats_panel: PanelContainer = $VBox/HBox/StatsPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "EQUIPMENT"
	hint_label.text = "[↑/↓] Select Slot  [ENTER] Equip/Unequip  [ESC] Back"
	_refresh_display()


## Compute visible slots based on equipped armor's max_slots.
func _get_visible_slots() -> Array:
	var slots: Array = ["weapon", "frame", "mag"]
	var character = CharacterManager.get_active_character()
	if character == null:
		return slots
	var frame_id: String = str(character.get("equipment", {}).get("frame", ""))
	if frame_id.is_empty():
		return slots
	var armor = ArmorRegistry.get_armor(frame_id)
	if armor == null:
		return slots
	for i in range(armor.max_slots):
		slots.append("unit%d" % (i + 1))
	return slots


## Display names matching _get_visible_slots().
func _get_visible_slot_names() -> Array:
	var names: Array = ["Weapon", "Frame", "Mag"]
	var character = CharacterManager.get_active_character()
	if character == null:
		return names
	var frame_id: String = str(character.get("equipment", {}).get("frame", ""))
	if frame_id.is_empty():
		return names
	var armor = ArmorRegistry.get_armor(frame_id)
	if armor == null:
		return names
	for i in range(armor.max_slots):
		names.append("Unit %d" % (i + 1))
	return names


func _unhandled_input(event: InputEvent) -> void:
	var visible_slots: Array = _get_visible_slots()
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
			_selected_slot = wrapi(_selected_slot - 1, 0, visible_slots.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if _choosing_item:
			_selected_item = wrapi(_selected_item + 1, 0, maxi(_equippable_items.size(), 1))
		else:
			_selected_slot = wrapi(_selected_slot + 1, 0, visible_slots.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _choosing_item:
			_equip_selected_item()
		else:
			_open_item_selection()
		get_viewport().set_input_as_handled()


## Always open item selection — no immediate unequip on ENTER.
func _open_item_selection() -> void:
	var visible_slots: Array = _get_visible_slots()
	var visible_names: Array = _get_visible_slot_names()
	if _selected_slot >= visible_slots.size():
		return
	var slot_key: String = visible_slots[_selected_slot]
	_equippable_items.clear()

	var character = CharacterManager.get_active_character()
	if character == null:
		return
	var equipment: Dictionary = character.get("equipment", {})
	var current_equipped: String = str(equipment.get(slot_key, ""))

	# Collect IDs equipped in OTHER slots (to exclude from list)
	var other_equipped_ids: Array = []
	for s in visible_slots:
		if s == slot_key:
			continue
		var eid: String = str(equipment.get(s, ""))
		if not eid.is_empty():
			other_equipped_ids.append(eid)

	# If slot has an equipped item, show it first with [Equipped] tag
	if not current_equipped.is_empty():
		var info: Dictionary = Inventory._lookup_item(current_equipped)
		_equippable_items.append({"id": current_equipped, "name": info.name, "equipped": true})

	# Scan inventory for items matching this slot type (exclude items in other slots)
	for item_id in Inventory._items:
		if item_id == current_equipped:
			continue  # Already shown as [Equipped]
		if item_id in other_equipped_ids:
			continue
		if _item_fits_slot(item_id, slot_key):
			var info: Dictionary = Inventory._lookup_item(item_id)
			_equippable_items.append({"id": item_id, "name": info.name, "equipped": false})

	# Append Unequip sentinel if slot is occupied
	if not current_equipped.is_empty():
		_equippable_items.append({"id": UNEQUIP_SENTINEL, "name": "── Unequip ──", "equipped": false})

	if _equippable_items.is_empty():
		hint_label.text = "No %s in inventory!" % visible_names[_selected_slot].to_lower()
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


## Clear unit slots beyond max_slots of new armor (or all if no armor).
func _auto_unequip_excess_units(equipment: Dictionary, new_max_slots: int) -> void:
	for i in range(4):
		if i >= new_max_slots:
			equipment["unit%d" % (i + 1)] = ""


func _equip_selected_item() -> void:
	if _equippable_items.is_empty() or _selected_item >= _equippable_items.size():
		return
	var character = CharacterManager.get_active_character()
	if character == null:
		return
	var equipment: Dictionary = character.get("equipment", {})
	var visible_slots: Array = _get_visible_slots()
	if _selected_slot >= visible_slots.size():
		return
	var slot_key: String = visible_slots[_selected_slot]
	var item: Dictionary = _equippable_items[_selected_item]
	var item_id: String = str(item.get("id", ""))

	# Unequip sentinel
	if item_id == UNEQUIP_SENTINEL:
		var old_id: String = str(equipment.get(slot_key, ""))
		equipment[slot_key] = ""
		# If unequipping frame, clear ALL unit slots
		if slot_key == "frame":
			_auto_unequip_excess_units(equipment, 0)
		_choosing_item = false
		if not old_id.is_empty():
			var info: Dictionary = Inventory._lookup_item(old_id)
			hint_label.text = "Unequipped %s" % info.name
		else:
			hint_label.text = "Unequipped."
		_refresh_display()
		return

	# Selecting the already-equipped item — no-op, just close
	if item.get("equipped", false):
		_choosing_item = false
		hint_label.text = "[↑/↓] Select Slot  [ENTER] Equip/Unequip  [ESC] Back"
		_refresh_display()
		return

	# Equip new item
	equipment[slot_key] = item_id

	# If equipping a new frame, auto-unequip units beyond new armor's max_slots
	if slot_key == "frame":
		var armor = ArmorRegistry.get_armor(item_id)
		var new_max: int = armor.max_slots if armor else 0
		_auto_unequip_excess_units(equipment, new_max)

	_choosing_item = false
	hint_label.text = "Equipped %s!" % item.name
	_refresh_display()


func _refresh_display() -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var equipment: Dictionary = character.get("equipment", {})
	var visible_slots: Array = _get_visible_slots()
	var visible_names: Array = _get_visible_slot_names()

	# Clamp selected slot to visible range
	if _selected_slot >= visible_slots.size():
		_selected_slot = maxi(visible_slots.size() - 1, 0)

	# Equipment slots panel
	for child in equip_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = "── Equipment Slots ──"
	header.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(header)

	if _choosing_item:
		# Show item selection list
		var slot_label := Label.new()
		slot_label.text = "Select %s:" % visible_names[_selected_slot]
		slot_label.add_theme_color_override("font_color", ThemeColors.HEADER)
		vbox.add_child(slot_label)

		for i in range(_equippable_items.size()):
			var item: Dictionary = _equippable_items[i]
			var label := Label.new()
			var item_id: String = str(item.get("id", ""))
			var is_equipped: bool = item.get("equipped", false)
			var is_unequip: bool = item_id == UNEQUIP_SENTINEL

			if is_unequip:
				label.text = item.name
			else:
				var detail_str := _get_item_brief(item_id)
				var tag: String = " [Equipped]" if is_equipped else ""
				if detail_str.is_empty():
					label.text = "%s%s" % [item.name, tag]
				else:
					label.text = "%-16s %s%s" % [str(item.get("name", "")), detail_str, tag]

			if i == _selected_item:
				label.text = "> " + label.text
				if is_equipped:
					label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
				elif is_unequip:
					label.add_theme_color_override("font_color", ThemeColors.DANGER)
				else:
					label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
			else:
				label.text = "  " + label.text
				if is_equipped:
					label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
				elif is_unequip:
					label.add_theme_color_override("font_color", ThemeColors.DANGER)
			vbox.add_child(label)
	else:
		# Show equipment slots (dynamic based on armor)
		for i in range(visible_slots.size()):
			var slot_key: String = visible_slots[i]
			var equipped: String = str(equipment.get(slot_key, ""))
			var slot_name: String = visible_names[i]

			var item_display: String = "[Empty]"
			if not equipped.is_empty():
				var info: Dictionary = Inventory._lookup_item(equipped)
				item_display = info.name
				# Show grind level for weapons
				if slot_key == "weapon":
					var grind: int = int(character.get("weapon_grinds", {}).get(equipped, 0))
					if grind > 0:
						item_display += " +%d" % grind

			var label := Label.new()
			label.text = "%-8s %s" % [slot_name, item_display]
			if i == _selected_slot:
				label.text = "> " + label.text
				label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
			else:
				label.text = "  " + label.text
				if equipped.is_empty():
					label.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)

			vbox.add_child(label)

	equip_panel.add_child(vbox)

	# Stats panel
	_refresh_stats()


func _get_item_brief(item_id: String) -> String:
	var w = WeaponRegistry.get_weapon(item_id)
	if w:
		var character = CharacterManager.get_active_character()
		var grind: int = int(character.get("weapon_grinds", {}).get(item_id, 0)) if character else 0
		if grind > 0:
			return "ATK %d (+%d)" % [w.attack_base + grind, grind]
		return "ATK %d" % w.attack_base
	var a = ArmorRegistry.get_armor(item_id)
	if a:
		return "DEF %d  Slots:%d" % [a.defense_base, a.max_slots]
	var u = UnitRegistry.get_unit(item_id)
	if u:
		return u.effect
	return ""


## Calculate equipment stat bonuses for a given equipment dict and character.
func _calc_equip_bonuses(equip: Dictionary, character: Dictionary) -> Dictionary:
	var bonuses := {"hp": 0, "pp": 0, "atk": 0, "def": 0, "acc": 0, "eva": 0, "tech": 0}

	# Weapon bonuses (with grind)
	var weapon_id: String = str(equip.get("weapon", ""))
	if not weapon_id.is_empty():
		var weapon = WeaponRegistry.get_weapon(weapon_id)
		if weapon:
			var grind: int = int(character.get("weapon_grinds", {}).get(weapon_id, 0))
			bonuses["atk"] += weapon.get_attack_at_grind(grind)
			bonuses["acc"] += weapon.get_accuracy_at_grind(grind)

	# Armor bonuses
	var frame_id: String = str(equip.get("frame", ""))
	if not frame_id.is_empty():
		var armor = ArmorRegistry.get_armor(frame_id)
		if armor:
			bonuses["def"] += int(armor.defense_base)
			bonuses["eva"] += int(armor.evasion_base)

	# Unit bonuses
	for slot in ["unit1", "unit2", "unit3", "unit4"]:
		var unit_id: String = str(equip.get(slot, ""))
		if not unit_id.is_empty():
			var unit = UnitRegistry.get_unit(unit_id)
			if unit:
				var bonus_key: String = UNIT_CATEGORY_TO_BONUS.get(unit.category, "")
				if not bonus_key.is_empty() and bonus_key in bonuses:
					bonuses[bonus_key] += int(unit.effect_value)

	# Material bonuses
	var mat_bonuses: Dictionary = character.get("material_bonuses", {})
	var mat_map := {"attack": "atk", "defense": "def", "accuracy": "acc", "evasion": "eva", "technique": "tech", "hp": "hp", "pp": "pp"}
	for mat_key in mat_map:
		bonuses[mat_map[mat_key]] += int(mat_bonuses.get(mat_key, 0))

	return bonuses


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
	var equipment: Dictionary = character.get("equipment", {})
	var current_bonuses: Dictionary = _calc_equip_bonuses(equipment, character)

	# Build preview bonuses if browsing items
	var preview_bonuses: Dictionary = {}
	var has_preview: bool = false
	if _choosing_item and _equippable_items.size() > 0 and _selected_item < _equippable_items.size():
		var item: Dictionary = _equippable_items[_selected_item]
		var item_id: String = str(item.get("id", ""))
		var is_equipped: bool = item.get("equipped", false)
		if not is_equipped:
			var visible_slots: Array = _get_visible_slots()
			if _selected_slot < visible_slots.size():
				var slot_key: String = visible_slots[_selected_slot]
				var preview_equip: Dictionary = equipment.duplicate()
				if item_id == UNEQUIP_SENTINEL:
					preview_equip[slot_key] = ""
					if slot_key == "frame":
						for i in range(4):
							preview_equip["unit%d" % (i + 1)] = ""
				else:
					preview_equip[slot_key] = item_id
					if slot_key == "frame":
						var armor = ArmorRegistry.get_armor(item_id)
						var new_max: int = armor.max_slots if armor else 0
						for i in range(4):
							if i >= new_max:
								preview_equip["unit%d" % (i + 1)] = ""
				preview_bonuses = _calc_equip_bonuses(preview_equip, character)
				has_preview = true

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var stat_header := Label.new()
	stat_header.text = "── Stats ──"
	stat_header.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(stat_header)

	var name_label := Label.new()
	name_label.text = "%s  %s Lv.%d" % [
		str(character.get("name", "???")),
		str(character.get("class_id", "???")),
		level
	]
	name_label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
	vbox.add_child(name_label)

	var sep := Label.new()
	sep.text = ""
	vbox.add_child(sep)

	var stat_order := ["hp", "pp", "attack", "defense", "accuracy", "evasion", "technique"]
	var display_names := ["HP", "PP", "ATK", "DEF", "ACC", "EVA", "TEC"]
	var bonus_keys := ["hp", "pp", "atk", "def", "acc", "eva", "tech"]

	for i in range(stat_order.size()):
		var base: int = int(base_stats.get(stat_order[i], 0))
		var cur_bonus: int = int(current_bonuses.get(bonus_keys[i], 0))
		var effective: int = base + cur_bonus
		var stat_label := Label.new()

		if has_preview:
			var pre_bonus: int = int(preview_bonuses.get(bonus_keys[i], 0))
			var preview_val: int = base + pre_bonus
			var diff: int = preview_val - effective
			if diff > 0:
				stat_label.text = "  %-4s %d → %d (+%d)" % [display_names[i], effective, preview_val, diff]
				stat_label.add_theme_color_override("font_color", ThemeColors.STAT_POSITIVE)
			elif diff < 0:
				stat_label.text = "  %-4s %d → %d (%d)" % [display_names[i], effective, preview_val, diff]
				stat_label.add_theme_color_override("font_color", ThemeColors.STAT_NEGATIVE)
			else:
				stat_label.text = "  %-4s %d" % [display_names[i], effective]
		else:
			stat_label.text = "  %-4s %d" % [display_names[i], effective]

		vbox.add_child(stat_label)

	stats_panel.add_child(vbox)

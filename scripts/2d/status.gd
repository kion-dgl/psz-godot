extends Control
## Status screen — full character stat breakdown.

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var content_panel: PanelContainer = $Panel/VBox/HBox/ContentPanel
@onready var stats_panel: PanelContainer = $Panel/VBox/HBox/StatsPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	title_label.text = "CHARACTER STATUS"
	hint_label.text = "[ESC] Back"
	_refresh_display()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()


func _refresh_display() -> void:
	_refresh_info()
	_refresh_stats()


func _refresh_info() -> void:
	for child in content_panel.get_children():
		child.queue_free()

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "── %s ──" % str(character.get("name", "???"))
	name_label.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(name_label)

	var class_id: String = str(character.get("class_id", "???"))
	var class_data = ClassRegistry.get_class_data(class_id)
	var class_name_str: String = class_data.name if class_data else class_id

	var class_label := Label.new()
	class_label.text = "Class: %s" % class_name_str
	vbox.add_child(class_label)

	var level: int = int(character.get("level", 1))
	var level_label := Label.new()
	level_label.text = "Level: %d" % level
	vbox.add_child(level_label)

	# EXP bar
	var exp_progress: Dictionary = CharacterManager.get_exp_progress()
	var exp_label := Label.new()
	var current_exp: int = int(exp_progress.get("current", 0))
	var needed_exp: int = int(exp_progress.get("needed", 1))
	var exp_percent: float = float(exp_progress.get("percent", 0.0))
	var exp_filled := int(exp_percent / 100.0 * 20)
	exp_label.text = "EXP %s %d/%d" % [
		"█".repeat(exp_filled) + "░".repeat(20 - exp_filled),
		current_exp, needed_exp
	]
	vbox.add_child(exp_label)

	# HP
	var hp: int = int(character.get("hp", 0))
	var max_hp: int = int(character.get("max_hp", 1))
	var hp_ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var hp_filled := int(hp_ratio * 20)
	var hp_label := Label.new()
	hp_label.text = "HP  %s %d/%d" % [
		"█".repeat(hp_filled) + "░".repeat(20 - hp_filled), hp, max_hp
	]
	if hp_ratio < 0.25:
		hp_label.add_theme_color_override("font_color", ThemeColors.DANGER)
	vbox.add_child(hp_label)

	# PP
	var pp: int = int(character.get("pp", 0))
	var max_pp: int = int(character.get("max_pp", 1))
	var pp_ratio := clampf(float(pp) / float(max_pp), 0.0, 1.0)
	var pp_filled := int(pp_ratio * 20)
	var pp_label := Label.new()
	pp_label.text = "PP  %s %d/%d" % [
		"█".repeat(pp_filled) + "░".repeat(20 - pp_filled), pp, max_pp
	]
	vbox.add_child(pp_label)

	# Meseta
	var meseta_label := Label.new()
	meseta_label.text = "Meseta: %d" % int(character.get("meseta", 0))
	meseta_label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
	vbox.add_child(meseta_label)

	# Equipment section
	var sep := Label.new()
	sep.text = ""
	vbox.add_child(sep)

	var equip_header := Label.new()
	equip_header.text = "── EQUIPMENT ──"
	equip_header.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(equip_header)

	var equipment: Dictionary = character.get("equipment", {})
	var slots := ["weapon", "frame", "mag", "unit1", "unit2", "unit3", "unit4"]
	var slot_names := ["Weapon", "Frame", "Mag", "Unit 1", "Unit 2", "Unit 3", "Unit 4"]
	for i in range(slots.size()):
		var slot_label := Label.new()
		var item_id: String = str(equipment.get(slots[i], ""))
		if item_id.is_empty():
			slot_label.text = "  %-8s [Empty]" % slot_names[i]
			slot_label.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
		else:
			var item_name := _get_item_name(slots[i], item_id)
			# Show grind level for weapons
			if slots[i] == "weapon":
				var grind: int = int(character.get("weapon_grinds", {}).get(item_id, 0))
				if grind > 0:
					item_name += " +%d" % grind
			slot_label.text = "  %-8s %s" % [slot_names[i], item_name]
		vbox.add_child(slot_label)

	content_panel.add_child(vbox)


func _refresh_stats() -> void:
	for child in stats_panel.get_children():
		child.queue_free()

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = "── STATS ──"
	header.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(header)

	var stats: Dictionary = character.get("stats", {})
	var stat_order := ["hp", "pp", "atk", "def", "acc", "eva", "tech"]
	var stat_names := ["HP", "PP", "ATK", "DEF", "ACC", "EVA", "TECH"]

	for i in range(stat_order.size()):
		var key: String = stat_order[i]
		var value: int = int(stats.get(key, 0))
		var label := Label.new()
		label.text = "  %-6s %d" % [stat_names[i], value]
		vbox.add_child(label)

	# Equipment bonuses
	var equip_bonuses := _calculate_equipment_bonuses(character)
	if not equip_bonuses.is_empty():
		var sep := Label.new()
		sep.text = ""
		vbox.add_child(sep)

		var bonus_header := Label.new()
		bonus_header.text = "── EQUIP BONUS ──"
		bonus_header.add_theme_color_override("font_color", ThemeColors.HEADER)
		vbox.add_child(bonus_header)

		for key in equip_bonuses:
			if int(equip_bonuses[key]) != 0:
				var label := Label.new()
				label.text = "  %-6s +%d" % [key.to_upper(), int(equip_bonuses[key])]
				label.add_theme_color_override("font_color", ThemeColors.EQUIPPABLE)
				vbox.add_child(label)

	# Effective stats
	var sep2 := Label.new()
	sep2.text = ""
	vbox.add_child(sep2)

	var eff_header := Label.new()
	eff_header.text = "── EFFECTIVE ──"
	eff_header.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
	vbox.add_child(eff_header)

	for i in range(stat_order.size()):
		var key: String = stat_order[i]
		var base: int = int(stats.get(key, 0))
		var bonus: int = int(equip_bonuses.get(key, 0))
		var label := Label.new()
		label.text = "  %-6s %d" % [stat_names[i], base + bonus]
		vbox.add_child(label)

	stats_panel.add_child(vbox)


func _calculate_equipment_bonuses(character: Dictionary) -> Dictionary:
	var bonuses := {"hp": 0, "pp": 0, "atk": 0, "def": 0, "acc": 0, "eva": 0, "tech": 0}
	var equipment: Dictionary = character.get("equipment", {})

	# Weapon bonuses (with grind)
	var weapon_id: String = str(equipment.get("weapon", ""))
	if not weapon_id.is_empty():
		var weapon = WeaponRegistry.get_weapon(weapon_id)
		if weapon:
			var grind: int = int(character.get("weapon_grinds", {}).get(weapon_id, 0))
			bonuses["atk"] += weapon.get_attack_at_grind(grind)
			bonuses["acc"] += weapon.get_accuracy_at_grind(grind)

	# Frame bonuses
	var frame_id: String = str(equipment.get("frame", ""))
	if not frame_id.is_empty():
		var armor = ArmorRegistry.get_armor(frame_id)
		if armor:
			bonuses["def"] += int(armor.defense_base)
			bonuses["eva"] += int(armor.evasion_base)

	# Unit bonuses
	for slot in ["unit1", "unit2", "unit3", "unit4"]:
		var unit_id: String = str(equipment.get(slot, ""))
		if not unit_id.is_empty():
			var unit = UnitRegistry.get_unit(unit_id)
			if unit:
				var effect: String = str(unit.effect).to_lower()
				var value: int = int(unit.effect_value)
				if effect in bonuses:
					bonuses[effect] += value

	return bonuses


func _get_item_name(slot_type: String, item_id: String) -> String:
	if slot_type == "weapon":
		var weapon = WeaponRegistry.get_weapon(item_id)
		return weapon.name if weapon else item_id
	elif slot_type == "frame":
		var armor = ArmorRegistry.get_armor(item_id)
		return armor.name if armor else item_id
	elif slot_type == "mag":
		var mag_path := "res://data/mags/%s.tres" % item_id
		if ResourceLoader.exists(mag_path):
			var mag = load(mag_path)
			if mag:
				return mag.name
		return item_id
	else:
		var unit = UnitRegistry.get_unit(item_id)
		return unit.name if unit else item_id

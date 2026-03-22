extends Control
## Status screen — full character stat breakdown.

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var content_panel: PanelContainer = $Panel/VBox/HBox/ContentPanel
@onready var stats_panel: PanelContainer = $Panel/VBox/HBox/StatsPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	PszStyle.style_menu(title_label, hint_label, [content_panel, stats_panel])
	title_label.text = "Character Status"
	hint_label.text = "Esc: Back"
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

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	var class_id: String = str(character.get("class_id", "???"))
	var class_data = ClassRegistry.get_class_data(class_id)
	var class_name_str: String = class_data.name if class_data else class_id

	# Character header
	vbox.add_child(PszStyle.create_section_header(str(character.get("name", "???"))))
	vbox.add_child(PszStyle.create_pill("Class: %s" % class_name_str, false))

	var level: int = int(character.get("level", 1))
	vbox.add_child(PszStyle.create_pill("Level: %d" % level, false))

	# EXP bar
	var exp_progress: Dictionary = CharacterManager.get_exp_progress()
	var current_exp: int = int(exp_progress.get("current", 0))
	var needed_exp: int = int(exp_progress.get("needed", 1))
	var exp_ratio: float = clampf(float(exp_progress.get("percent", 0.0)) / 100.0, 0.0, 1.0)
	vbox.add_child(PszStyle.create_bar("EXP", exp_ratio, "%d/%d" % [current_exp, needed_exp],
		Color(0.30, 0.55, 0.85)))

	# HP bar
	var hp: int = int(character.get("hp", 0))
	var max_hp: int = int(character.get("max_hp", 1))
	var hp_ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var hp_fill_color := Color(0.80, 0.20, 0.20) if hp_ratio < 0.25 else Color(0.20, 0.70, 0.30)
	vbox.add_child(PszStyle.create_bar("HP", hp_ratio, "%d/%d" % [hp, max_hp], hp_fill_color))

	# PP bar
	var pp: int = int(character.get("pp", 0))
	var max_pp: int = int(character.get("max_pp", 1))
	var pp_ratio := clampf(float(pp) / float(max_pp), 0.0, 1.0)
	vbox.add_child(PszStyle.create_bar("PP", pp_ratio, "%d/%d" % [pp, max_pp],
		Color(0.30, 0.50, 0.80)))

	# Meseta
	vbox.add_child(PszStyle.create_pill("Meseta", false, "%d" % int(character.get("meseta", 0)), PszStyle.TEXT_MESETA))

	# Equipment section
	vbox.add_child(PszStyle.create_section_header("Equipment"))

	var equipment: Dictionary = character.get("equipment", {})
	var slots := ["weapon", "frame", "mag", "unit1", "unit2", "unit3", "unit4"]
	var slot_names := ["Weapon", "Frame", "Mag", "Unit 1", "Unit 2", "Unit 3", "Unit 4"]
	for i in range(slots.size()):
		var item_id: String = str(equipment.get(slots[i], ""))
		if item_id.is_empty():
			vbox.add_child(PszStyle.create_pill(slot_names[i], false, "[Empty]", PszStyle.TEXT_MUTED))
		else:
			var item_name := _get_item_name(slots[i], item_id)
			if slots[i] == "weapon":
				var grind: int = int(character.get("weapon_grinds", {}).get(item_id, 0))
				if grind > 0:
					item_name += " +%d" % grind
			vbox.add_child(PszStyle.create_pill(slot_names[i], false, item_name))

	scroll.add_child(vbox)
	content_panel.add_child(scroll)


func _refresh_stats() -> void:
	for child in stats_panel.get_children():
		child.queue_free()

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	vbox.add_child(PszStyle.create_section_header("Base Stats"))

	var stats: Dictionary = character.get("stats", {})
	var stat_order := ["atk", "def", "acc", "eva", "tech"]
	var stat_names := ["ATK", "DEF", "ACC", "EVA", "TECH"]

	for i in range(stat_order.size()):
		var key: String = stat_order[i]
		var value: int = int(stats.get(key, 0))
		vbox.add_child(PszStyle.create_pill(stat_names[i], false, str(value)))

	# Effective stats
	var equip_bonuses := _calculate_equipment_bonuses(character)
	vbox.add_child(PszStyle.create_section_header("Effective"))
	for i in range(stat_order.size()):
		var key: String = stat_order[i]
		var base: int = int(stats.get(key, 0))
		var bonus: int = int(equip_bonuses.get(key, 0))
		vbox.add_child(PszStyle.create_pill(stat_names[i], false, str(base + bonus), PszStyle.TEXT_HIGHLIGHT))

	scroll.add_child(vbox)
	stats_panel.add_child(scroll)


func _calculate_equipment_bonuses(character: Dictionary) -> Dictionary:
	var bonuses := {"hp": 0, "pp": 0, "atk": 0, "def": 0, "acc": 0, "eva": 0, "tech": 0}
	var equipment: Dictionary = character.get("equipment", {})

	# Weapon bonuses (with grind)
	var weapon_id: String = str(equipment.get("weapon", ""))
	if not weapon_id.is_empty():
		var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(weapon_id))
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

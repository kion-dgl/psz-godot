extends Control
## Inventory screen — 40-slot grid with item details and actions.

const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")

const CATEGORY_ORDER := ["Weapon", "Armor", "Unit", "Mag", "Disk", "Consumable", "Material", "Modifier", "Key Item", "Other"]

var _selected_index: int = 0
var _items: Array = []
var _item_pills: Array = []  # maps item index -> pill Control for scroll-to

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var grid_panel: PanelContainer = $Panel/VBox/HBox/GridPanel
@onready var detail_panel: PanelContainer = $Panel/VBox/HBox/DetailPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	PszStyle.style_menu(title_label, hint_label, [grid_panel, detail_panel])
	title_label.text = "Inventory"
	hint_label.text = "Up/Down: Select  Enter: Use/Equip  D: Drop  Esc: Back"
	_refresh_items()
	_refresh_display()


func _unhandled_input(event: InputEvent) -> void:
	# sfx=false: these list screens predate the shop menu sfx convention.
	ShopNav.handle(self, event, {
		"sfx": false,
		"list_size": func() -> int: return _items.size(),
		"on_move": func(_old: int) -> void: _refresh_display(),
		"on_accept": _use_selected,
		"on_other": func(ev: InputEvent) -> bool:
			if ev.is_action_pressed("action_3"):
				_drop_selected()
				get_viewport().set_input_as_handled()
				return true
			return false,
	})


func _refresh_items() -> void:
	# Inventory iteration order is the source of truth — pickup order by
	# default, or sorted if the player has Auto-Sort Inventory on (or
	# triggered Sort manually from the start menu).
	_items = Inventory.get_all_items()


func _use_selected() -> void:
	if _items.is_empty() or _selected_index >= _items.size():
		return
	var item: Dictionary = _items[_selected_index]
	var item_id: String = item.get("id", "")
	if MagManager.is_mag(item_id):
		SceneManager.push_scene("res://scenes/2d/mag_feeder.tscn", {"mag_id": item_id})
		return
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
	# Prevent dropping equipped items
	var character = CharacterManager.get_active_character()
	if character:
		var equip: Dictionary = character.get("equipment", {})
		for slot_key in equip:
			if str(equip.get(slot_key, "")) == item_id:
				hint_label.text = "Unequip first!"
				return
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
	# Grid panel — pill rows
	for child in grid_panel.get_children():
		child.queue_free()
	_item_pills.clear()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	var slot_count := "%d/40 slots" % Inventory.get_total_slots()
	vbox.add_child(PszStyle.create_section_header(slot_count))

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
		vbox.add_child(PszStyle.create_pill("(Inventory is empty)", false, "", PszStyle.TEXT_MUTED))
	else:
		var current_category := ""
		var current_weapon_type := -1
		for i in range(_items.size()):
			var item: Dictionary = _items[i]
			var item_id: String = item.get("id", "???")
			var norm_id: String = item_id.replace("-", "_").replace("/", "_")
			var is_unresolved: bool = (item_id != norm_id)

			# Category header — Inventory autoload owns the canonical
			# id→category mapping (#215-C9).
			var cat: String = Inventory.get_item_category(item_id)
			if cat != current_category:
				current_category = cat
				current_weapon_type = -1
				vbox.add_child(PszStyle.create_section_header(cat))

			# Weapon type sub-header
			var weapon = WeaponRegistry.get_weapon(item_id)
			if weapon == null and is_unresolved:
				weapon = WeaponRegistry.get_weapon(norm_id)
			if cat == "Weapon" and weapon:
				if int(weapon.weapon_type) != current_weapon_type:
					current_weapon_type = int(weapon.weapon_type)

			var armor_data = ArmorRegistry.get_armor(item_id)
			if armor_data == null and is_unresolved:
				armor_data = ArmorRegistry.get_armor(norm_id)

			var item_name: String = item.get("name", item_id)
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

			# Stars and type suffix
			var suffix := ""
			if weapon:
				suffix = "%s %s" % [grind_tag, weapon.get_rarity_string()]
			elif armor_data:
				suffix = " %s" % armor_data.get_rarity_string()

			var display_name := item_name + equip_tag + suffix
			var right_text := "x%d" % qty if qty > 1 else ""

			# Color coding for equippability
			var text_color := Color.TRANSPARENT
			if item_id in equipped_ids:
				text_color = PszStyle.TEXT_MUTED
			elif is_unresolved:
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

			var pill := PszStyle.create_pill(display_name, i == _selected_index, right_text, text_color)
			vbox.add_child(pill)
			_item_pills.append(pill)

	scroll.add_child(vbox)
	grid_panel.add_child(scroll)

	# Scroll to selected item after layout
	if _selected_index >= 0 and _selected_index < _item_pills.size():
		scroll.ensure_control_visible.call_deferred(_item_pills[_selected_index])

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

	vbox.add_child(PszStyle.detail_label(item_name, PszStyle.TITLE_BG))
	vbox.add_child(PszStyle.detail_label("Quantity: %d" % int(item.get("quantity", 1))))

	# Check if equipped
	var character2 = CharacterManager.get_active_character()
	if character2:
		var equip2: Dictionary = character2.get("equipment", {})
		for slot_key in equip2:
			if str(equip2.get(slot_key, "")) == item_id:
				vbox.add_child(PszStyle.detail_label("[Equipped]", PszStyle.TEXT_HIGHLIGHT))
				break

	# Unresolved reference warning
	if item_id != norm_id:
		vbox.add_child(PszStyle.detail_label("[Mismatched ID: %s]" % item_id, PszStyle.TEXT_DANGER))

	# Look up item data from registries
	var item_data = ItemRegistry.get_item(item_id)
	if item_data == null:
		item_data = ItemRegistry.get_item(norm_id)
	if item_data:
		vbox.add_child(PszStyle.detail_label("Type: %s" % item_data.get_type_name()))
		if not item_data.description.is_empty():
			var desc_label := PszStyle.detail_label(item_data.description)
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(desc_label)

	var consumable = ConsumableRegistry.get_consumable(item_id)
	if consumable == null:
		consumable = ConsumableRegistry.get_consumable(norm_id)
	if consumable:
		var details := PszStyle.detail_label(consumable.details)
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
		vbox.add_child(PszStyle.detail_label("Type: %s" % weapon.get_weapon_type_name()))
		var grind: int = int(character2.get("weapon_grinds", {}).get(item_id, 0)) if character2 else 0
		if grind > 0:
			vbox.add_child(PszStyle.detail_label("ATK: %d (+%d)" % [weapon.attack_base + grind, grind]))
		else:
			vbox.add_child(PszStyle.detail_label("ATK: %d" % weapon.attack_base))
		vbox.add_child(PszStyle.detail_label("ACC: %d" % weapon.accuracy_base))
		if not weapon.element.is_empty() and weapon.element != "None":
			vbox.add_child(PszStyle.detail_label("Element: %s" % weapon.element))
		vbox.add_child(PszStyle.detail_label("Rarity: %s" % weapon.get_rarity_string()))
		if weapon.level > 0:
			var lvl_color := PszStyle.TEXT_WARNING if char_level < weapon.level else PszStyle.TEXT
			vbox.add_child(PszStyle.detail_label("Req. Lv: %d" % weapon.level, lvl_color))
		if not weapon.usable_by.is_empty() and not class_type_race.is_empty():
			if not weapon.can_be_used_by(class_type_race):
				vbox.add_child(PszStyle.detail_label("[Cannot equip — wrong class]", PszStyle.TEXT_DANGER))

		# Weapon stats (photon attributes) — always shown, defaults to 0%
		if character2:
			var ws: Dictionary = character2.get("weapon_stats", {}).get(item_id, {})
			var el: String = str(ws.get("element", ""))
			var el_level: int = int(ws.get("element_level", 0))
			if not el.is_empty() and el_level > 0:
				vbox.add_child(PszStyle.detail_label("Element: %s Lv.%d" % [el.capitalize(), el_level], PszStyle.TEXT_SUCCESS))
				var specials := {"fire": "Burn", "ice": "Freeze", "lightning": "Stun", "dark": "Devil", "light": "Sleep"}
				var special: String = specials.get(el, "")
				if not special.is_empty():
					var chance: int = 10 + 10 * el_level
					vbox.add_child(PszStyle.detail_label("Special: %s (%d%%)" % [special, chance], PszStyle.TEXT_WARNING))
			var attr_keys := ["native_pct", "beast_pct", "machine_pct", "dark_pct", "hit_pct"]
			var attr_names := ["Native", "Beast", "Machine", "Dark", "Hit"]
			for ai in range(attr_keys.size()):
				var pct: int = int(ws.get(attr_keys[ai], 0))
				var attr_color := PszStyle.TEXT_SUCCESS if pct > 0 else PszStyle.TEXT_MUTED
				vbox.add_child(PszStyle.detail_label("%s: %d%%" % [attr_names[ai], pct], attr_color))

	# Armor details
	var armor = ArmorRegistry.get_armor(item_id)
	if armor == null:
		armor = ArmorRegistry.get_armor(norm_id)
	if armor:
		vbox.add_child(PszStyle.detail_label("Type: %s" % armor.get_type_name()))
		vbox.add_child(PszStyle.detail_label("DEF: %d" % armor.defense_base))
		vbox.add_child(PszStyle.detail_label("EVA: %d" % armor.evasion_base))
		vbox.add_child(PszStyle.detail_label("Rarity: %s" % armor.get_rarity_string()))
		if armor.level > 0:
			var lvl_color := PszStyle.TEXT_WARNING if char_level < armor.level else PszStyle.TEXT
			vbox.add_child(PszStyle.detail_label("Req. Lv: %d" % armor.level, lvl_color))
		if not armor.usable_by.is_empty() and not class_type_race.is_empty():
			if not armor.can_be_used_by(class_type_race):
				vbox.add_child(PszStyle.detail_label("[Cannot equip — wrong class]", PszStyle.TEXT_DANGER))

	# Unit details
	var unit = UnitRegistry.get_unit(item_id)
	if unit == null:
		unit = UnitRegistry.get_unit(norm_id)
	if unit:
		vbox.add_child(PszStyle.detail_label("Type: Unit"))
		if unit.effect and not str(unit.effect).is_empty():
			vbox.add_child(PszStyle.detail_label("Effect: %s" % unit.effect, PszStyle.TEXT_SUCCESS))

	# Mag details
	if MagManager.is_mag(item_id):
		var character3 = CharacterManager.get_active_character()
		if character3:
			var mag_state: Dictionary = MagManager.get_mag_state(character3, item_id)
			if not mag_state.is_empty():
				var mag_level: int = MagManager.get_level(mag_state)
				var form_id: String = str(mag_state.get("form_id", "mag"))
				var form = MagManager.get_mag_form(form_id)
				vbox.add_child(PszStyle.detail_label("Type: Mag"))
				if form:
					vbox.add_child(PszStyle.detail_label("Form: %s (Stage %s)" % [form.name, str(form.stage)]))
					if not str(form.photon_blast).is_empty():
						vbox.add_child(PszStyle.detail_label("P. Blast: %s" % str(form.photon_blast), PszStyle.TEXT_SUCCESS))
				vbox.add_child(PszStyle.detail_label("Level: %d" % mag_level))
				var stats_dict: Dictionary = mag_state.get("stats", {})
				for stat_key in ["power", "guard", "hit", "mind"]:
					var raw: int = int(stats_dict.get(stat_key, 0))
					var stat_lvl: int = int(raw / MagManager.STATS_PER_LEVEL)
					vbox.add_child(PszStyle.detail_label("%s: %d" % [stat_key.capitalize(), stat_lvl]))

	# Disk details
	if item_id.begins_with("disk_"):
		var parts: PackedStringArray = item_id.split("_", false, 2)
		if parts.size() >= 3:
			var tech_id: String = parts[1]
			var level: int = int(parts[2])
			var tech: Dictionary = TechniqueManager.get_technique(tech_id)
			if not tech.is_empty():
				vbox.add_child(PszStyle.detail_label("Type: Technique Disk"))
				vbox.add_child(PszStyle.detail_label("Element: %s" % str(tech.get("element", "none")).capitalize()))
				vbox.add_child(PszStyle.detail_label("Target: %s" % str(tech.get("target", "single")).capitalize()))
				var power: int = int(tech.get("power", 0))
				if power > 0:
					var scaled_power: int = int(float(power) * (1.0 + float(level) / 10.0))
					vbox.add_child(PszStyle.detail_label("Power: %d (Lv.%d)" % [scaled_power, level]))
				var pp_cost: int = maxi(1, int(tech.get("pp", 5)) - int(float(level) / 5.0))
				vbox.add_child(PszStyle.detail_label("PP Cost: %d" % pp_cost))
				var required_level: int = TechniqueManager.get_disk_required_level(level)
				var req_color := PszStyle.TEXT_WARNING if char_level < required_level else PszStyle.TEXT
				vbox.add_child(PszStyle.detail_label("Req. Level: %d" % required_level, req_color))
				if character2:
					var current_tech_level: int = TechniqueManager.get_technique_level(character2, tech_id)
					if current_tech_level > 0:
						if current_tech_level >= level:
							vbox.add_child(PszStyle.detail_label("Known: Lv.%d (already higher)" % current_tech_level, PszStyle.TEXT_MUTED))
						else:
							vbox.add_child(PszStyle.detail_label("Known: Lv.%d -> Lv.%d" % [current_tech_level, level], PszStyle.TEXT_SUCCESS))

	# Material details
	if CombatManager.MATERIAL_STAT_MAP.has(item_id):
		var mat = MaterialRegistry.get_material(item_id)
		if mat:
			vbox.add_child(PszStyle.detail_label("Type: Material"))
			if not mat.details.is_empty():
				var detail_lbl := PszStyle.detail_label(mat.details)
				detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				vbox.add_child(detail_lbl)
		var stat_name: String = CombatManager.MATERIAL_STAT_MAP[item_id]
		if stat_name == "reset":
			vbox.add_child(PszStyle.detail_label("Resets all material bonuses"))
		else:
			vbox.add_child(PszStyle.detail_label("Stat: %s +2" % stat_name.capitalize()))
		var character3 = CharacterManager.get_active_character()
		if character3:
			var used: int = int(character3.get("materials_used", 0))
			vbox.add_child(PszStyle.detail_label("Materials used: %d/%d" % [used, CombatManager.MAX_MATERIALS]))

	detail_panel.add_child(vbox)

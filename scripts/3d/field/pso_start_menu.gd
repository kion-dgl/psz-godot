extends CanvasLayer
## PSO-style start menu — global autoload, non-pausing overlay with L-shaped backdrop.
## Player can walk around with analog stick while d-pad navigates menu.
## Toggle with Start/ESC.  Sub-views: Items, Equip, Techs, Palette, Mags, Quest, System.
## Registered as autoload so it works in both field and city.

signal closed()

# ── Layout ──────────────────────────────────────────────────────────────────────
const VIEWPORT_W := 1280.0
const VIEWPORT_H := 720.0
const LEFT_W := 240.0       # Left backdrop strip
const BOTTOM_H := 320.0     # Bottom backdrop strip
const PAD := 12.0           # Inner padding

# ── Colors ──────────────────────────────────────────────────────────────────────
const C_BACKDROP := Color(0.16, 0.24, 0.39, 0.82)
const C_BACKDROP_BORDER := Color(0.39, 0.59, 0.82, 0.6)
const C_PANEL := Color(0.78, 0.84, 0.92, 0.92)
const C_PANEL_BORDER := Color(0.47, 0.63, 0.82, 0.7)
const C_TEXT := Color(0.10, 0.15, 0.25)
const C_TEXT_MUTED := Color(0.29, 0.35, 0.47)
const C_TEXT_LIGHT := Color(0.91, 0.93, 0.97)
const C_SELECT := Color(0.88, 0.53, 0.13)
const C_SELECT_TEXT := Color.WHITE
const C_HP := Color(0.16, 0.72, 0.28)
const C_PP := Color(0.16, 0.47, 0.85)
const C_LABEL_BG := Color(0.20, 0.29, 0.47, 0.9)
const C_ICON_BG := Color(0.91, 0.93, 0.96)
const C_ICON_FG := Color(0.17, 0.23, 0.31)

const FONT_SIZE := 15
const FONT_SIZE_SM := 13
const FONT_SIZE_XS := 11
const FONT_SIZE_LG := 17

# ── State ───────────────────────────────────────────────────────────────────────
enum Mode { MAIN, ITEMS, EQUIP, EQUIP_PICK, TECHS, PALETTE, PALETTE_PICK, MAGS, MAG_FEED, QUEST, SYSTEM, OPTIONS }

var _mode: Mode = Mode.MAIN
var _menu_idx: int = 0
var _info_page: int = 0
var _sub_idx: int = 0
var _equip_slot_idx: int = 0
var _equip_item_idx: int = 0
var _pal_page_idx: int = 0
var _pal_slot_idx: int = 0
var _mag_idx: int = 0
var _mag_feed_idx: int = 0
var _options_idx: int = 0
var _item_scroll: int = 0  # Scroll offset for items list

var _canvas: Control  # Child control for drawing
var _is_open: bool = false
var _icon_cache: Dictionary = {}  # action_id → Texture2D

## Menu labels built dynamically — Techs hidden for Cast race
func _get_menu_labels() -> Array:
	var labels: Array = ["Items", "Equip"]
	if _can_use_techs():
		labels.append("Techs")
	labels.append_array(["Palette", "Mags", "Quest", "System"])
	return labels

func _get_menu_descs() -> Array:
	var descs: Array = ["Use items.", "Equip weapons and armor."]
	if _can_use_techs():
		descs.append("Cast techniques.")
	descs.append_array(["Edit the action palette.", "Feed and manage your Mag.", "View current quest objectives.", "System settings and options."])
	return descs

func _can_use_techs() -> bool:
	var ch := _get_character()
	var class_id: String = str(ch.get("class_id", ""))
	var class_data = ClassRegistry.get_class_data(class_id)
	if class_data and class_data.race == "Cast":
		return false
	return true
const SYSTEM_LABELS := ["Save", "Return to Title", "Options"]
const SYSTEM_DESCS := ["Save your progress.", "Return to the title screen.", "Adjust game settings."]
## Equipment slots are built dynamically based on equipped armor's max_slots
const TYPE_ICONS := {"weapon": "W", "armor": "A", "shield": "S", "unit": "U", "tool": "T", "tech": "M", "material": "R", "mag": "G"}
const TYPE_COLORS := {
	"weapon": Color(0.8, 0.27, 0.27), "armor": Color(0.27, 0.53, 0.8),
	"shield": Color(0.27, 0.67, 0.67), "unit": Color(0.53, 0.27, 0.67),
	"tool": Color(0.27, 0.67, 0.27), "tech": Color(0.67, 0.27, 0.8),
	"material": Color(0.67, 0.53, 0.2), "mag": Color(0.8, 0.53, 0.27),
}


func _ready() -> void:
	layer = 150
	name = "PsoStartMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	# Pre-cache all action icons
	for action in ActionPalette.ALL_ACTIONS:
		var aid: String = str(action.get("id", ""))
		var icon: Texture2D = ActionPalette.get_action_icon(aid)
		if icon:
			_icon_cache[aid] = icon
	print("[PsoStartMenu] Ready — layer %d, cached %d icons" % [layer, _icon_cache.size()])

	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_menu)
	add_child(_canvas)


func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	_mode = Mode.MAIN
	_menu_idx = 0
	_canvas.queue_redraw()
	print("[PsoStartMenu] Opened")


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	closed.emit()


func is_open() -> bool:
	return _is_open


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


# ── Input ───────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	# Open menu from anywhere with ESC/pause (only when closed)
	if not _is_open:
		if event.is_action_pressed("pause"):
			open()
			get_viewport().set_input_as_handled()
		return

	var handled := true
	match _mode:
		Mode.MAIN:
			handled = _input_main(event)
		Mode.ITEMS:
			handled = _input_list(event, _get_inventory().size())
		Mode.EQUIP:
			handled = _input_list(event, _get_equip_slots().size())
		Mode.EQUIP_PICK:
			handled = _input_equip_pick(event)
		Mode.TECHS:
			handled = _input_list(event, _get_techniques().size())
		Mode.PALETTE:
			handled = _input_palette(event)
		Mode.PALETTE_PICK:
			handled = _input_palette_pick(event)
		Mode.MAGS:
			handled = _input_list(event, _get_mags().size())
		Mode.MAG_FEED:
			handled = _input_list(event, _get_feed_items().size())
		Mode.QUEST:
			handled = _input_back(event)
		Mode.SYSTEM:
			handled = _input_system(event)
		Mode.OPTIONS:
			handled = _input_options(event)

	if handled:
		_canvas.queue_redraw()
		get_viewport().set_input_as_handled()


func _input_main(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_up", true):
		_menu_idx = wrapi(_menu_idx - 1, 0, _get_menu_labels().size())
		return true
	elif event.is_action_pressed("ui_down", true):
		_menu_idx = wrapi(_menu_idx + 1, 0, _get_menu_labels().size())
		return true
	elif event.is_action_pressed("ui_left", true):
		_info_page = wrapi(_info_page - 1, 0, 4)
		return true
	elif event.is_action_pressed("ui_right", true):
		_info_page = wrapi(_info_page + 1, 0, 4)
		return true
	elif event.is_action_pressed("ui_accept"):
		_enter_sub(_menu_idx)
		return true
	elif event.is_action_pressed("ui_cancel"):
		close()
		return true
	return false


func _input_list(event: InputEvent, count: int) -> bool:
	if event.is_action_pressed("ui_up", true) and count > 0:
		_sub_idx = wrapi(_sub_idx - 1, 0, count)
		return true
	elif event.is_action_pressed("ui_down", true) and count > 0:
		_sub_idx = wrapi(_sub_idx + 1, 0, count)
		return true
	elif event.is_action_pressed("ui_accept"):
		_sub_accept()
		return true
	elif event.is_action_pressed("ui_cancel"):
		_go_back()
		return true
	return false


func _input_equip_pick(event: InputEvent) -> bool:
	var candidates := _get_equip_candidates(_equip_slot_idx)
	if event.is_action_pressed("ui_up", true) and candidates.size() > 0:
		_equip_item_idx = wrapi(_equip_item_idx - 1, 0, candidates.size())
		return true
	elif event.is_action_pressed("ui_down", true) and candidates.size() > 0:
		_equip_item_idx = wrapi(_equip_item_idx + 1, 0, candidates.size())
		return true
	elif event.is_action_pressed("ui_accept"):
		_do_equip()
		return true
	elif event.is_action_pressed("ui_cancel"):
		_mode = Mode.EQUIP
		return true
	return false


func _do_equip() -> void:
	var slots := _get_equip_slots()
	if _equip_slot_idx >= slots.size():
		_mode = Mode.EQUIP
		return
	var candidates := _get_equip_candidates(_equip_slot_idx)
	if _equip_item_idx >= candidates.size():
		_mode = Mode.EQUIP
		return

	var ch := _get_character()
	if ch.is_empty():
		_mode = Mode.EQUIP
		return

	var equip: Dictionary = ch.get("equipment", {})
	var slot_key: String = str(slots[_equip_slot_idx].get("key", ""))
	var item: Dictionary = candidates[_equip_item_idx]
	var item_id: String = str(item.get("id", ""))

	if item_id == "__unequip__":
		equip[slot_key] = ""
		if slot_key == "frame":
			for i in range(4):
				equip["unit%d" % (i + 1)] = ""
	elif item.get("equipped", false):
		pass  # Already equipped, no-op
	else:
		equip[slot_key] = item_id
		if slot_key == "frame":
			var armor = ArmorRegistry.get_armor(item_id)
			var new_max: int = armor.max_slots if armor else 0
			for i in range(4):
				if i >= new_max:
					equip["unit%d" % (i + 1)] = ""

	ch["equipment"] = equip

	# Notify player of weapon/mag changes
	var player_node = get_tree().get_first_node_in_group("player")
	if slot_key == "weapon" and player_node and player_node.has_method("refresh_weapon"):
		player_node.refresh_weapon()
	if slot_key == "mag" and player_node and player_node.has_method("refresh_mag"):
		player_node.refresh_mag()

	_mode = Mode.EQUIP
	_sub_idx = _equip_slot_idx


func _input_palette(event: InputEvent) -> bool:
	var total_slots: int = ActionPalette.pages.size() * 3
	var flat_idx: int = _pal_page_idx * 3 + _pal_slot_idx
	if event.is_action_pressed("ui_up", true):
		flat_idx = wrapi(flat_idx - 1, 0, total_slots)
		_pal_page_idx = flat_idx / 3
		_pal_slot_idx = flat_idx % 3
		return true
	elif event.is_action_pressed("ui_down", true):
		flat_idx = wrapi(flat_idx + 1, 0, total_slots)
		_pal_page_idx = flat_idx / 3
		_pal_slot_idx = flat_idx % 3
		return true
	elif event.is_action_pressed("ui_accept"):
		_mode = Mode.PALETTE_PICK
		_sub_idx = 0
		return true
	elif event.is_action_pressed("ui_cancel"):
		_mode = Mode.MAIN
		return true
	return false


func _input_palette_pick(event: InputEvent) -> bool:
	var actions := _get_palette_actions()
	if event.is_action_pressed("ui_up", true) and actions.size() > 0:
		_sub_idx = wrapi(_sub_idx - 1, 0, actions.size())
		return true
	elif event.is_action_pressed("ui_down", true) and actions.size() > 0:
		_sub_idx = wrapi(_sub_idx + 1, 0, actions.size())
		return true
	elif event.is_action_pressed("ui_accept"):
		if _sub_idx < actions.size():
			var action: Dictionary = actions[_sub_idx]
			var action_id: String = str(action.get("id", ""))
			if _is_palette_action_available(action_id):
				ActionPalette.set_action(_pal_page_idx, _pal_slot_idx, action_id)
				_mode = Mode.PALETTE
		return true
	elif event.is_action_pressed("ui_cancel"):
		_mode = Mode.PALETTE
		return true
	return false


func _input_system(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_up", true):
		_sub_idx = wrapi(_sub_idx - 1, 0, SYSTEM_LABELS.size())
		return true
	elif event.is_action_pressed("ui_down", true):
		_sub_idx = wrapi(_sub_idx + 1, 0, SYSTEM_LABELS.size())
		return true
	elif event.is_action_pressed("ui_accept"):
		match _sub_idx:
			0: SaveManager.save_game()
			1:
				SaveManager.save_game()
				close()
				SceneManager.goto_scene("res://scenes/2d/title.tscn")
			2:
				_mode = Mode.OPTIONS
				_options_idx = 0
		return true
	elif event.is_action_pressed("ui_cancel"):
		_mode = Mode.MAIN
		return true
	return false


func _input_options(event: InputEvent) -> bool:
	var opts := _get_options_list()
	if event.is_action_pressed("ui_up", true) and opts.size() > 0:
		_options_idx = wrapi(_options_idx - 1, 0, opts.size())
		return true
	elif event.is_action_pressed("ui_down", true) and opts.size() > 0:
		_options_idx = wrapi(_options_idx + 1, 0, opts.size())
		return true
	elif event.is_action_pressed("ui_accept"):
		_toggle_option(_options_idx)
		return true
	elif event.is_action_pressed("ui_cancel"):
		_mode = Mode.SYSTEM
		_sub_idx = 2
		return true
	return false


func _get_options_list() -> Array:
	var on := "ON"
	var off := "OFF"
	return [
		"Floor Collision: %s" % (on if DebugConfig.show_floor_collision else off),
		"Gate Dots: %s" % (on if DebugConfig.show_gate_dots else off),
		"Hitboxes: %s" % (on if DebugConfig.show_hitboxes else off),
		"Combo Timing: %s" % (on if DebugConfig.show_combo_timing else off),
		"Time + Room: %s" % (on if DebugConfig.show_time_room else off),
		"Frame Profiler: %s" % (on if DebugConfig.profile_frames else off),
	]


func _toggle_option(idx: int) -> void:
	match idx:
		0: DebugConfig.show_floor_collision = not DebugConfig.show_floor_collision
		1: DebugConfig.show_gate_dots = not DebugConfig.show_gate_dots
		2: DebugConfig.show_hitboxes = not DebugConfig.show_hitboxes
		3: DebugConfig.show_combo_timing = not DebugConfig.show_combo_timing
		4:
			DebugConfig.show_time_room = not DebugConfig.show_time_room
			TimeManager.show_hud(DebugConfig.show_time_room)
		5:
			DebugConfig.profile_frames = not DebugConfig.profile_frames


func _input_back(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		_mode = Mode.MAIN
		return true
	return false


func _enter_sub(idx: int) -> void:
	_sub_idx = 0
	var labels := _get_menu_labels()
	if idx >= labels.size():
		return
	var label: String = labels[idx]
	match label:
		"Items": _mode = Mode.ITEMS
		"Equip": _mode = Mode.EQUIP; _equip_slot_idx = 0
		"Techs": _mode = Mode.TECHS
		"Palette": _mode = Mode.PALETTE; _pal_page_idx = 0; _pal_slot_idx = 0
		"Mags": _mode = Mode.MAGS; _mag_idx = 0
		"Quest": _mode = Mode.QUEST
		"System": _mode = Mode.SYSTEM


func _sub_accept() -> void:
	match _mode:
		Mode.ITEMS:
			var inv := _get_inventory()
			if _sub_idx < inv.size():
				var item: Dictionary = inv[_sub_idx]
				if item.get("usable", false):
					Inventory.use_item(str(item.get("id", "")))
		Mode.EQUIP:
			var slots := _get_equip_slots()
			_equip_slot_idx = _sub_idx
			_equip_item_idx = 0
			if _equip_slot_idx < slots.size():
				_mode = Mode.EQUIP_PICK
		Mode.TECHS:
			var techs := _get_techniques()
			if _sub_idx < techs.size():
				var tech: Dictionary = techs[_sub_idx]
				if tech.get("learned", false) and _is_in_field():
					var tech_id: String = str(tech.get("id", ""))
					var player_node = get_tree().get_first_node_in_group("player")
					if player_node and player_node.has_method("_cast_technique"):
						player_node._cast_technique(tech_id)
		Mode.MAGS:
			_mag_idx = _sub_idx
			_mag_feed_idx = 0
			_sub_idx = 0
			_mode = Mode.MAG_FEED
		Mode.MAG_FEED:
			pass  # TODO: feed mag


func _go_back() -> void:
	match _mode:
		Mode.EQUIP_PICK: _mode = Mode.EQUIP
		Mode.PALETTE_PICK: _mode = Mode.PALETTE
		Mode.MAG_FEED: _mode = Mode.MAGS
		Mode.OPTIONS: _mode = Mode.SYSTEM; _sub_idx = 2
		_: _mode = Mode.MAIN


# ── Data helpers ────────────────────────────────────────────────────────────────
func _get_character() -> Dictionary:
	var ch = CharacterManager.get_active_character()
	return ch if ch else {}


const CATEGORY_ORDER := ["Weapon", "Armor", "Unit", "Mag", "Disk", "Consumable", "Material", "Modifier", "Key Item", "Other"]

func _get_inventory() -> Array:
	## Returns inventory sorted by category (matching inventory_screen.gd)
	var items := Inventory.get_all_items()
	items.sort_custom(func(a, b):
		var id_a: String = str(a.get("id", ""))
		var id_b: String = str(b.get("id", ""))
		var ca: int = CATEGORY_ORDER.find(_get_item_category(id_a))
		var cb: int = CATEGORY_ORDER.find(_get_item_category(id_b))
		if ca == -1: ca = 99
		if cb == -1: cb = 99
		if ca != cb:
			return ca < cb
		if ca == 0:  # Weapon — sub-sort by type then rarity
			var wa = WeaponRegistry.get_weapon(id_a)
			var wb = WeaponRegistry.get_weapon(id_b)
			if wa and wb:
				if int(wa.weapon_type) != int(wb.weapon_type):
					return int(wa.weapon_type) < int(wb.weapon_type)
				return int(wa.rarity) < int(wb.rarity)
		if ca == 1:  # Armor — sub-sort by rarity
			var aa = ArmorRegistry.get_armor(id_a)
			var ab_armor = ArmorRegistry.get_armor(id_b)
			if aa and ab_armor:
				return int(aa.rarity) < int(ab_armor.rarity)
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	# Add category and equipped flags
	var ch := _get_character()
	var equipped_ids: Array = []
	if not ch.is_empty():
		var equip: Dictionary = ch.get("equipment", {})
		for key in equip:
			var eid: String = str(equip.get(key, ""))
			if not eid.is_empty():
				equipped_ids.append(eid)
	for item in items:
		var item_id: String = str(item.get("id", ""))
		item["category"] = _get_item_category(item_id)
		item["equipped"] = item_id in equipped_ids
	return items


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
	return "Other"


func _get_techniques() -> Array:
	## Returns all techniques the character's class can use (same list as palette techs).
	## Learned techs show their level, unlearned ones show as disabled.
	var ch := _get_character()
	if ch.is_empty():
		return []
	var class_id: String = str(ch.get("class_id", ""))
	var class_data = ClassRegistry.get_class_data(class_id)
	if class_data == null or class_data.technique_limits.is_empty():
		return []
	var learned: Dictionary = ch.get("techniques", {})
	var result: Array = []
	for tech_id in TechniqueManager.TECHNIQUES:
		var data: Dictionary = TechniqueManager.TECHNIQUES[tech_id]
		var group: String = str(data.get("group", ""))
		if not class_data.technique_limits.has(group):
			continue
		var max_level: int = int(class_data.technique_limits.get(group, 0))
		if max_level <= 0:
			continue
		var current_level: int = int(learned.get(tech_id, 0))
		result.append({
			"id": tech_id,
			"name": str(data.get("name", tech_id)),
			"level": current_level,
			"max_level": max_level,
			"pp": int(data.get("pp", 0)),
			"learned": current_level > 0,
		})
	return result


func _count_equipped_units(equip: Dictionary) -> int:
	var count: int = 0
	for i in range(4):
		if not str(equip.get("unit%d" % (i + 1), "")).is_empty():
			count += 1
	return count


func _is_in_field() -> bool:
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("_is_in_city"):
		return not player._is_in_city()
	return false


func _get_equip_slots() -> Array:
	## Build equipment slot list dynamically based on armor's max_slots
	var ch := _get_character()
	var equip: Dictionary = ch.get("equipment", {})
	var slots: Array = []

	# Weapon
	slots.append({"label": "Weapon", "key": "weapon", "type": "weapon", "item": str(equip.get("weapon", ""))})
	# Frame (armor)
	var frame_id: String = str(equip.get("frame", ""))
	slots.append({"label": "Frame", "key": "frame", "type": "armor", "item": frame_id})

	# Unit slots — count depends on equipped armor's max_slots
	var unit_count: int = 0
	if not frame_id.is_empty():
		var armor_data = ArmorRegistry.get_armor(frame_id) if ArmorRegistry.has_method("get_armor") else null
		if armor_data and "max_slots" in armor_data:
			unit_count = int(armor_data.max_slots)
	for i in range(unit_count):
		var key: String = "unit%d" % (i + 1)
		slots.append({"label": "Unit %d" % (i + 1), "key": key, "type": "unit", "item": str(equip.get(key, ""))})

	# Mag
	slots.append({"label": "Mag", "key": "mag", "type": "mag", "item": str(equip.get("mag", ""))})
	return slots


func _get_equip_candidates(slot_idx: int) -> Array:
	## Build equippable item list for the given slot, matching equipment_screen.gd logic.
	var slots := _get_equip_slots()
	if slot_idx >= slots.size():
		return []
	var slot_key: String = str(slots[slot_idx].get("key", ""))
	var ch := _get_character()
	if ch.is_empty():
		return []
	var equip: Dictionary = ch.get("equipment", {})
	var current_equipped: String = str(equip.get(slot_key, ""))

	# IDs equipped in OTHER slots (exclude from candidates)
	var other_ids: Array = []
	for s in slots:
		var sk: String = str(s.get("key", ""))
		if sk == slot_key:
			continue
		var eid: String = str(equip.get(sk, ""))
		if not eid.is_empty():
			other_ids.append(eid)

	var result: Array = []
	# Show currently equipped first
	if not current_equipped.is_empty():
		var info: Dictionary = Inventory._lookup_item(current_equipped)
		result.append({"id": current_equipped, "name": str(info.get("name", current_equipped)), "equipped": true})

	# Scan inventory for matching items
	for item_id in Inventory._items:
		if item_id == current_equipped:
			continue
		if item_id in other_ids:
			continue
		if _item_fits_slot(item_id, slot_key):
			var info: Dictionary = Inventory._lookup_item(item_id)
			result.append({"id": item_id, "name": str(info.get("name", item_id)), "equipped": false})

	# Unequip option if slot is occupied
	if not current_equipped.is_empty():
		result.append({"id": "__unequip__", "name": "-- Unequip --", "equipped": false})

	return result


func _item_fits_slot(item_id: String, slot_key: String) -> bool:
	match slot_key:
		"weapon":
			var base_id: String = Inventory.get_base_id(item_id)
			var weapon = WeaponRegistry.get_weapon(base_id)
			if weapon == null:
				return false
			var character = CharacterManager.get_active_character()
			if character:
				var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
				if class_data and not class_data.can_equip_weapon_type(weapon.weapon_type):
					return false
			return true
		"frame":
			return ArmorRegistry.has_armor(item_id)
		"unit1", "unit2", "unit3", "unit4":
			return UnitRegistry.get_unit(item_id) != null
		"mag":
			return MagManager.is_mag(item_id)
	return false


func _get_mags() -> Array:
	## Scan inventory for all mags, matching mag_list.gd logic.
	var ch := _get_character()
	if ch.is_empty():
		return []
	var equipped_mag: String = str(ch.get("equipment", {}).get("mag", ""))
	var result: Array = []
	for item_id in Inventory._items:
		if not MagManager.is_mag(item_id):
			continue
		var mag_state: Dictionary = MagManager.get_mag_state(ch, item_id)
		var form_id := "mag"
		var level := 0
		if not mag_state.is_empty():
			form_id = str(mag_state.get("form_id", "mag"))
			level = MagManager.get_level(mag_state)
		var form = MagManager.get_mag_form(form_id)
		var form_name: String = form.name if form else "Mag"
		result.append({
			"id": item_id,
			"name": "%s Lv.%d" % [form_name, level],
			"level": level,
			"form_id": form_id,
			"equipped": item_id == equipped_mag,
			"type": "mag",
		})
	# Equipped first, then by level descending
	result.sort_custom(func(a, b):
		if a.equipped != b.equipped:
			return a.equipped
		return int(a.level) > int(b.level)
	)
	return result


func _get_feed_items() -> Array:
	var items := Inventory.get_all_items()
	return items.filter(func(i): return str(i.get("type", "")) in ["consumable", "material"])


func _get_palette_actions() -> Array:
	## Returns all assignable actions from ActionPalette.ALL_ACTIONS
	var result: Array = []
	for action in ActionPalette.ALL_ACTIONS:
		result.append(action)
	return result


func _is_palette_action_available(action_id: String) -> bool:
	if not TechniqueManager.TECHNIQUES.has(action_id):
		return true  # Non-technique actions always available
	var character = CharacterManager.get_active_character()
	if character == null:
		return false
	return TechniqueManager.get_technique_level(character, action_id) > 0


# ── Drawing ─────────────────────────────────────────────────────────────────────
func _draw_menu() -> void:
	var c := _canvas
	var font := ThemeDB.fallback_font
	var vp := Vector2(VIEWPORT_W, VIEWPORT_H)

	# L-shaped backdrop
	c.draw_rect(Rect2(0, 0, LEFT_W, vp.y - BOTTOM_H), C_BACKDROP)
	c.draw_rect(Rect2(LEFT_W, vp.y - BOTTOM_H, vp.x - LEFT_W, BOTTOM_H), C_BACKDROP)
	c.draw_rect(Rect2(0, vp.y - BOTTOM_H, LEFT_W, BOTTOM_H), C_BACKDROP)
	# Borders (right edge of left strip, top edge of bottom strip)
	c.draw_line(Vector2(LEFT_W, 0), Vector2(LEFT_W, vp.y - BOTTOM_H), C_BACKDROP_BORDER, 1.5)
	c.draw_line(Vector2(LEFT_W, vp.y - BOTTOM_H), Vector2(vp.x, vp.y - BOTTOM_H), C_BACKDROP_BORDER, 1.5)

	# Character status (always visible)
	_draw_status(c, font, Vector2(PAD, PAD))

	match _mode:
		Mode.MAIN: _draw_main(c, font)
		Mode.ITEMS: _draw_items(c, font)
		Mode.EQUIP, Mode.EQUIP_PICK: _draw_equip(c, font)
		Mode.TECHS: _draw_techs(c, font)
		Mode.PALETTE, Mode.PALETTE_PICK: _draw_palette(c, font)
		Mode.MAGS, Mode.MAG_FEED: _draw_mags(c, font)
		Mode.QUEST: _draw_quest(c, font)
		Mode.SYSTEM: _draw_system(c, font)
		Mode.OPTIONS: _draw_options(c, font)


func _draw_status(c: Control, font: Font, pos: Vector2) -> void:
	var ch := _get_character()
	var w: float = LEFT_W - PAD * 2
	_draw_inner_panel(c, Rect2(pos, Vector2(w, 60)))

	var name_str: String = str(ch.get("name", "Player"))
	c.draw_string(font, pos + Vector2(12, 20), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, C_TEXT)

	# HP bar
	var hp: float = float(ch.get("hp", 100))
	var max_hp: float = float(ch.get("max_hp", 100))
	var hp_pct: float = clampf(hp / maxf(max_hp, 1), 0, 1)
	_draw_bar(c, Rect2(pos.x + 30, pos.y + 28, w - 42, 10), hp_pct, C_HP)
	c.draw_string(font, pos + Vector2(8, 38), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_TEXT_MUTED)

	# PP bar
	var pp: float = float(ch.get("pp", 50))
	var max_pp: float = float(ch.get("max_pp", 50))
	var pp_pct: float = clampf(pp / maxf(max_pp, 1), 0, 1)
	_draw_bar(c, Rect2(pos.x + 30, pos.y + 42, w - 42, 10), pp_pct, C_PP)
	c.draw_string(font, pos + Vector2(8, 52), "PP", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_TEXT_MUTED)


func _draw_bar(c: Control, rect: Rect2, pct: float, color: Color) -> void:
	c.draw_rect(rect, Color(0, 0, 0, 0.15))
	if pct > 0:
		c.draw_rect(Rect2(rect.position, Vector2(rect.size.x * pct, rect.size.y)), color)


func _draw_main(c: Control, font: Font) -> void:
	var left_x := PAD
	var left_w: float = LEFT_W - PAD * 2
	var y := PAD + 68.0

	# Menu list
	_draw_inner_panel(c, Rect2(left_x, y, left_w, _get_menu_labels().size() * 28 + 8))
	for i in range(_get_menu_labels().size()):
		var iy: float = y + 4 + i * 28
		if i == _menu_idx:
			c.draw_rect(Rect2(left_x + 2, iy, left_w - 4, 26), C_SELECT)
		var col: Color = C_SELECT_TEXT if i == _menu_idx else C_TEXT
		c.draw_string(font, Vector2(left_x + 14, iy + 19), _get_menu_labels()[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_LG, col)

	# Description
	var desc_y: float = y + _get_menu_labels().size() * 28 + 18
	_draw_inner_panel(c, Rect2(left_x, desc_y, left_w, 36))
	c.draw_string(font, Vector2(left_x + 12, desc_y + 22), _get_menu_descs()[_menu_idx], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, C_TEXT)

	# Info panel (bottom right)
	_draw_info_panel(c, font)


func _draw_info_panel(c: Control, font: Font) -> void:
	var px: float = VIEWPORT_W - 470.0
	var py: float = VIEWPORT_H - BOTTOM_H + 5
	var pw: float = 440.0
	var ph: float = BOTTOM_H - 10.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))

	# Page selector
	var page_label := "L %d/4 R" % [_info_page + 1]
	c.draw_string(font, Vector2(px + pw / 2 - 30, py + 20), page_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, C_TEXT)

	# Stat rows — pull real data from character + class + equipment
	var ch := _get_character()
	var class_id: String = str(ch.get("class_id", ""))
	var class_data = ClassRegistry.get_class_data(class_id)
	var level: int = int(ch.get("level", 1))
	var equip: Dictionary = ch.get("equipment", {})

	# Base stats from class at current level
	var base_hp: int = class_data.get_stat_at_level("hp", level) if class_data else 0
	var base_pp: int = class_data.get_stat_at_level("pp", level) if class_data else 0
	var base_atk: int = class_data.get_stat_at_level("attack", level) if class_data else 0
	var base_def: int = class_data.get_stat_at_level("defense", level) if class_data else 0
	var base_acc: int = class_data.get_stat_at_level("accuracy", level) if class_data else 0
	var base_eva: int = class_data.get_stat_at_level("evasion", level) if class_data else 0
	var base_mst: int = class_data.get_stat_at_level("technique", level) if class_data else 0

	# Equipment bonuses
	var weapon_id: String = str(equip.get("weapon", ""))
	var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(weapon_id)) if not weapon_id.is_empty() else null
	var weapon_grind: int = int(ch.get("weapon_grinds", {}).get(weapon_id, 0))
	var weapon_atk: int = weapon.get_attack_at_grind(weapon_grind) if weapon else 0
	var weapon_acc: int = weapon.get_accuracy_at_grind(weapon_grind) if weapon else 0
	var weapon_name: String = weapon.name if weapon else "--"

	var frame_id: String = str(equip.get("frame", ""))
	var armor = ArmorRegistry.get_armor(frame_id) if not frame_id.is_empty() else null
	var armor_def: int = int(armor.defense_base) if armor else 0
	var armor_eva: int = int(armor.evasion_base) if armor else 0
	var frame_name: String = armor.name if armor else "--"

	# Material bonuses
	var mat_bonuses: Dictionary = ch.get("material_bonuses", {})

	# EXP progress
	var exp_progress: Dictionary = CharacterManager.get_exp_progress() if CharacterManager.has_method("get_exp_progress") else {}
	var to_next: String = str(exp_progress.get("needed", "---"))

	# Weapon special
	var ws: Dictionary = ch.get("weapon_stats", {}).get(weapon_id, {})
	var special_el: String = str(ws.get("element", ""))
	var special_str: String = special_el.capitalize() if not special_el.is_empty() else "--"

	var pages := [
		[["Lv", str(level)], ["Type", class_data.name if class_data else class_id], ["Exp Pts", str(ch.get("experience", 0))], ["To Next Lv", to_next], ["Meseta", str(ch.get("meseta", 0))]],
		[["ATP", str(base_atk + weapon_atk + int(mat_bonuses.get("attack", 0)))], ["ATA", str(base_acc + weapon_acc + int(mat_bonuses.get("accuracy", 0)))], ["Weapon", weapon_name], ["Grind", "+%d" % weapon_grind if weapon_grind > 0 else "--"], ["Special", special_str]],
		[["DFP", str(base_def + armor_def + int(mat_bonuses.get("defense", 0)))], ["EVP", str(base_eva + armor_eva + int(mat_bonuses.get("evasion", 0)))], ["Frame", frame_name], ["Slots", str(armor.max_slots) if armor else "0"], ["Units", "%d / %d" % [_count_equipped_units(equip), armor.max_slots if armor else 0]]],
		[["MST", str(base_mst + int(mat_bonuses.get("technique", 0)))], ["HP", "%d / %d" % [int(ch.get("hp", base_hp)), base_hp + int(mat_bonuses.get("hp", 0))]], ["PP", "%d / %d" % [int(ch.get("pp", base_pp)), base_pp + int(mat_bonuses.get("pp", 0))]]],
	]
	var rows: Array = pages[_info_page] if _info_page < pages.size() else []
	for i in range(rows.size()):
		var ry: float = py + 38 + i * 26
		c.draw_string(font, Vector2(px + 16, ry), str(rows[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, C_TEXT_MUTED)
		c.draw_string(font, Vector2(px + pw - 16, ry), str(rows[i][1]), HORIZONTAL_ALIGNMENT_RIGHT, -1, FONT_SIZE, C_TEXT)


func _draw_items(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Items")
	var inv := _get_inventory()

	# Draw item list with category headers
	var px: float = 5.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 300.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))

	# Slot count header
	c.draw_string(font, Vector2(px + 10, py + 14), "%d/40 slots" % Inventory.get_total_slots(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, C_TEXT_MUTED)

	# Keep selected item in view
	var visible_rows: int = int((ph - 24) / 22)
	if _sub_idx < _item_scroll:
		_item_scroll = _sub_idx
	elif _sub_idx >= _item_scroll + visible_rows:
		_item_scroll = _sub_idx - visible_rows + 1
	_item_scroll = clampi(_item_scroll, 0, maxi(inv.size() - visible_rows, 0))

	var draw_y: float = py + 20
	var current_cat := ""

	for i in range(inv.size()):
		var item: Dictionary = inv[i]
		var cat: String = str(item.get("category", "Other"))

		# Category header
		if cat != current_cat:
			current_cat = cat
			if i >= _item_scroll:
				if draw_y < py + ph - 6:
					c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 18), Color(0.12, 0.16, 0.28))
					c.draw_string(font, Vector2(px + 8, draw_y + 13), cat, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, C_TEXT_LIGHT)
					draw_y += 20

		if i < _item_scroll:
			continue
		if draw_y > py + ph - 6:
			break

		var is_sel: bool = i == _sub_idx
		# White row background, yellow/orange for selected
		if is_sel:
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 20), C_SELECT)
		else:
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 20), Color(1, 1, 1, 0.85))
		var col: Color = C_SELECT_TEXT if is_sel else C_TEXT

		# Equipped badge — colored pill
		if item.get("equipped", false):
			var badge_color: Color = Color(0.2, 0.5, 0.9) if not is_sel else Color(1, 1, 1, 0.3)
			c.draw_rect(Rect2(px + 4, draw_y + 4, 14, 12), badge_color)
			c.draw_string(font, Vector2(px + 6, draw_y + 14), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)

		# Item name
		var item_name: String = str(item.get("name", ""))
		c.draw_string(font, Vector2(px + 20, draw_y + 14), item_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, col)

		# Quantity
		var qty: int = int(item.get("quantity", 1))
		if qty > 1:
			c.draw_string(font, Vector2(px + pw - 40, draw_y + 14), "x%d" % qty, HORIZONTAL_ALIGNMENT_RIGHT, -1, FONT_SIZE_XS, Color(col, 0.7))

		draw_y += 22

	# Description
	var desc: String = ""
	if _sub_idx < inv.size():
		var item: Dictionary = inv[_sub_idx]
		var item_id: String = str(item.get("id", ""))
		desc = str(item.get("name", ""))
		# Try to get details from registries
		var weapon = WeaponRegistry.get_weapon(item_id)
		if weapon:
			desc += "\nATK: %d  ACC: %d" % [weapon.attack_base, weapon.accuracy_base]
			if not weapon.element.is_empty() and weapon.element != "None":
				desc += "\nElement: %s" % weapon.element
		var armor = ArmorRegistry.get_armor(item_id)
		if armor:
			desc += "\nDEF: %d  EVA: %d\nSlots: %d" % [armor.defense_base, armor.evasion_base, armor.max_slots]
		var consumable = ConsumableRegistry.get_consumable(item_id)
		if consumable and not str(consumable.details).is_empty():
			desc += "\n%s" % str(consumable.details)
	_draw_bottom_desc(c, font, desc)


func _draw_equip(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Equip")
	var slots := _get_equip_slots()
	var items: Array = []
	for s in slots:
		var item_name: String = str(s.get("item", ""))
		if item_name.is_empty():
			item_name = "--"
		items.append({"name": str(s.get("label", "")) + ":  " + item_name, "type": str(s.get("type", ""))})
	var idx: int = _sub_idx if _mode == Mode.EQUIP else _equip_slot_idx
	if idx >= slots.size():
		idx = 0
	_draw_bottom_list(c, font, items, idx)

	if _mode == Mode.EQUIP_PICK:
		_draw_equip_picker(c, font)
	else:
		var desc: String = ""
		var desc_idx: int = _sub_idx if _sub_idx < slots.size() else 0
		if desc_idx < slots.size():
			var item_id: String = str(slots[desc_idx].get("item", ""))
			if not item_id.is_empty():
				# Try to get item description from registries
				var wdata = WeaponRegistry.get_weapon(item_id) if WeaponRegistry.has_method("get_weapon") else null
				var adata = ArmorRegistry.get_armor(item_id) if ArmorRegistry.has_method("get_armor") else null
				if wdata and "name" in wdata:
					desc = "%s\nATP: %s" % [str(wdata.name), str(wdata.attack_base if "attack_base" in wdata else "?")]
				elif adata and "name" in adata:
					desc = "%s\nDFP: %s  Slots: %s" % [str(adata.name), str(adata.defense_base if "defense_base" in adata else "?"), str(adata.max_slots if "max_slots" in adata else 0)]
				else:
					desc = item_id
			else:
				desc = "Nothing equipped.\n\n[Enter] Equip"
		_draw_bottom_desc(c, font, desc)


func _draw_equip_picker(c: Control, font: Font) -> void:
	var candidates := _get_equip_candidates(_equip_slot_idx)
	var px: float = 310.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 200.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	for i in range(candidates.size()):
		var iy: float = py + 4 + i * 24
		if i == _equip_item_idx:
			c.draw_rect(Rect2(px + 2, iy, pw - 4, 22), C_SELECT)
		var col: Color = C_SELECT_TEXT if i == _equip_item_idx else C_TEXT
		c.draw_string(font, Vector2(px + 10, iy + 16), str(candidates[i].get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, col)


func _draw_techs(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Techs")
	var techs := _get_techniques()
	var in_field: bool = _is_in_field()

	# Draw tech list
	var px: float = 5.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 300.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))

	var scroll_offset: int = maxi(0, _sub_idx - 11)
	for i in range(techs.size()):
		var draw_i: int = i - scroll_offset
		if draw_i < 0:
			continue
		var iy: float = py + 4 + draw_i * 24
		if iy > py + ph - 6:
			break
		var tech: Dictionary = techs[i]
		var is_sel: bool = i == _sub_idx
		var learned: bool = tech.get("learned", false)

		if is_sel:
			c.draw_rect(Rect2(px + 2, iy, pw - 4, 22), C_SELECT)

		var col: Color
		if is_sel:
			col = C_SELECT_TEXT
		elif not learned:
			col = Color(0.5, 0.5, 0.5)
		else:
			col = C_TEXT

		# Tech icon
		var icon: Texture2D = _icon_cache.get(str(tech.get("id", "")), null) as Texture2D
		if icon:
			if not learned:
				c.draw_texture_rect(icon, Rect2(px + 6, iy + 1, 20, 20), false, Color(0.4, 0.4, 0.4))
			else:
				c.draw_texture_rect(icon, Rect2(px + 6, iy + 1, 20, 20), false)

		# Tech name
		var level_str: String = "Lv%d" % tech.level if learned else "--"
		c.draw_string(font, Vector2(px + 30, iy + 16), str(tech.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, col)
		c.draw_string(font, Vector2(px + pw - 80, iy + 16), level_str, HORIZONTAL_ALIGNMENT_RIGHT, -1, FONT_SIZE_XS, col)
		c.draw_string(font, Vector2(px + pw - 30, iy + 16), "%dPP" % tech.pp, HORIZONTAL_ALIGNMENT_RIGHT, -1, FONT_SIZE_XS, col)

	# Description
	var desc: String = ""
	if _sub_idx < techs.size():
		var tech: Dictionary = techs[_sub_idx]
		var td: Dictionary = TechniqueManager.TECHNIQUES.get(str(tech.get("id", "")), {})
		desc = str(td.get("name", ""))
		desc += "\n%s element" % str(td.get("element", "none")).capitalize()
		desc += "\nPP: %d" % int(td.get("pp", 0))
		desc += "\nTarget: %s" % str(td.get("target", "single")).capitalize()
		desc += "\nMax Level: %d" % tech.max_level
		if tech.get("learned", false):
			desc += "\nCurrent: Lv %d" % tech.level
			if in_field:
				desc += "\n\n[Enter] Cast"
			else:
				desc += "\n\n(Only in field)"
		else:
			desc += "\n\nNot yet learned"
	_draw_bottom_desc(c, font, desc)


func _draw_palette(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Palette")

	# Draw all pages inline in the bottom-left list
	var px: float = 5.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 300.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))

	var slot_keys := ["X", "A", "B"]
	var draw_y: float = py + 4
	var flat_idx: int = 0  # Global index across all pages for selection tracking
	var selected_flat: int = _pal_page_idx * 3 + _pal_slot_idx

	for page_i in range(ActionPalette.pages.size()):
		# Page header
		c.draw_string(font, Vector2(px + 10, draw_y + 14), "Page %d" % [page_i + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, C_TEXT_MUTED)
		draw_y += 18

		var page: Array = ActionPalette.pages[page_i]
		for slot_i in range(page.size()):
			if draw_y > py + ph - 4:
				break
			var action_id: String = str(page[slot_i])
			var action_data: Dictionary = ActionPalette.get_action_data(action_id)
			var label: String = str(action_data.get("label", action_id))
			var is_sel: bool = flat_idx == selected_flat

			if is_sel:
				c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 24), C_SELECT)
			var col: Color = C_SELECT_TEXT if is_sel else C_TEXT

			# Slot key badge
			c.draw_rect(Rect2(px + 8, draw_y + 3, 20, 18), Color(0.16, 0.24, 0.31, 0.7))
			c.draw_string(font, Vector2(px + 13, draw_y + 17), slot_keys[slot_i] if slot_i < 3 else "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

			# Action icon
			var icon: Texture2D = _icon_cache.get(action_id, null) as Texture2D
			if icon:
				c.draw_texture_rect(icon, Rect2(px + 32, draw_y + 2, 20, 20), false)

			# Action name
			c.draw_string(font, Vector2(px + 56, draw_y + 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, col)

			draw_y += 26
			flat_idx += 1

		draw_y += 4  # Gap between pages

	# Description / picker
	if _mode == Mode.PALETTE_PICK:
		_draw_palette_picker(c, font)
	else:
		var page: Array = ActionPalette.pages[_pal_page_idx] if _pal_page_idx < ActionPalette.pages.size() else []
		var current_id: String = str(page[_pal_slot_idx]) if _pal_slot_idx < page.size() else ""
		var current_data: Dictionary = ActionPalette.get_action_data(current_id)
		var current_label: String = str(current_data.get("label", current_id))
		_draw_bottom_desc(c, font, "Page %d Slot %d:\n%s\n\n[Enter] Change\n[Left/Right] Page" % [_pal_page_idx + 1, _pal_slot_idx + 1, current_label])


func _draw_palette_picker(c: Control, font: Font) -> void:
	var actions := _get_palette_actions()
	var page: Array = ActionPalette.pages[_pal_page_idx] if _pal_page_idx < ActionPalette.pages.size() else []
	var current_id: String = str(page[_pal_slot_idx]) if _pal_slot_idx < page.size() else ""
	var px: float = 310.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 200.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	var scroll_offset: int = maxi(0, _sub_idx - 12)  # Simple scroll for long lists
	for i in range(actions.size()):
		var draw_i: int = i - scroll_offset
		if draw_i < 0:
			continue
		var iy: float = py + 4 + draw_i * 22
		if iy > py + ph - 4:
			break
		var action: Dictionary = actions[i]
		var action_id: String = str(action.get("id", ""))
		var action_label: String = str(action.get("label", action_id))
		var available: bool = _is_palette_action_available(action_id)
		if i == _sub_idx:
			c.draw_rect(Rect2(px + 2, iy, pw - 4, 20), C_SELECT)
		var col: Color
		if i == _sub_idx:
			col = C_SELECT_TEXT
		elif not available:
			col = Color(0.5, 0.5, 0.5)
		else:
			col = C_TEXT
		# Action icon
		var icon: Texture2D = _icon_cache.get(action_id, null) as Texture2D
		if icon:
			c.draw_texture_rect(icon, Rect2(px + 6, iy + 1, 18, 18), false)
		c.draw_string(font, Vector2(px + 28, iy + 15), action_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, col)
		# Checkmark for currently assigned action
		if action_id == current_id:
			c.draw_string(font, Vector2(px + pw - 20, iy + 15), "\u2713", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_XS, Color(0.3, 0.8, 0.3) if i != _sub_idx else C_SELECT_TEXT)


func _draw_mags(c: Control, font: Font) -> void:
	if _mode == Mode.MAG_FEED:
		_draw_section_label(c, font, "Feed Mag")
		var feed := _get_feed_items()
		_draw_bottom_list(c, font, feed, _sub_idx)
		var desc: String = ""
		if _sub_idx < feed.size():
			var item: Dictionary = feed[_sub_idx]
			desc = str(item.get("name", ""))
			var consumable = ConsumableRegistry.get_consumable(str(item.get("id", "")))
			if consumable and not str(consumable.details).is_empty():
				desc += "\n%s" % str(consumable.details)
			var qty: int = int(item.get("quantity", 0))
			if qty > 1:
				desc += "\n\nx%d" % qty
		_draw_bottom_desc(c, font, desc)
	else:
		_draw_section_label(c, font, "Mags")
		var mags := _get_mags()
		# Draw mag list with equipped badge
		var items: Array = []
		for m in mags:
			var tag: String = " [E]" if m.get("equipped", false) else ""
			items.append({"name": str(m.get("name", "")) + tag, "type": "mag", "equipped": m.get("equipped", false)})
		_draw_bottom_list(c, font, items, _sub_idx)
		# Mag detail
		var desc: String = ""
		if _sub_idx < mags.size():
			var mag: Dictionary = mags[_sub_idx]
			var ch := _get_character()
			var mag_state: Dictionary = MagManager.get_mag_state(ch, str(mag.get("id", ""))) if not ch.is_empty() else {}
			if not mag_state.is_empty():
				var form_id: String = str(mag_state.get("form_id", "mag"))
				var form = MagManager.get_mag_form(form_id)
				if form:
					desc += "Form: %s\n" % form.name
					if not str(form.photon_blast).is_empty():
						desc += "P.Blast: %s\n" % str(form.photon_blast)
				var stats_dict: Dictionary = mag_state.get("stats", {})
				for stat_key in ["power", "guard", "hit", "mind"]:
					var raw: int = int(stats_dict.get(stat_key, 0))
					var stat_lvl: int = int(raw / MagManager.STATS_PER_LEVEL)
					desc += "%s: %d\n" % [stat_key.capitalize(), stat_lvl]
				desc += "\n\n[Enter] Feed"
		_draw_bottom_desc(c, font, desc)


func _draw_quest(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Quest")
	var px: float = 5.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 505.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	# TODO: pull real quest data from session
	c.draw_string(font, Vector2(px + 16, py + 30), "No active quest.", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, C_TEXT_MUTED)


func _draw_system(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "System")
	var items: Array = []
	for s in SYSTEM_LABELS:
		items.append({"name": s, "type": "tool"})
	_draw_bottom_list(c, font, items, _sub_idx)
	var desc: String = SYSTEM_DESCS[_sub_idx] if _sub_idx < SYSTEM_DESCS.size() else ""
	_draw_bottom_desc(c, font, desc)


func _draw_options(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Options")
	var opts := _get_options_list()
	var items: Array = []
	for o in opts:
		items.append({"name": o, "type": "tool"})
	_draw_bottom_list(c, font, items, _options_idx)
	_draw_bottom_desc(c, font, "Toggle debug settings.\n\n[Enter] Toggle\n[Esc] Back")


# ── Draw helpers ────────────────────────────────────────────────────────────────
func _draw_inner_panel(c: Control, rect: Rect2) -> void:
	c.draw_rect(rect, C_PANEL)
	c.draw_rect(rect, C_PANEL_BORDER, false, 1.5)


func _draw_section_label(c: Control, font: Font, text: String) -> void:
	var lx := PAD
	var ly := PAD + 68.0
	var lw: float = LEFT_W - PAD * 2
	c.draw_rect(Rect2(lx, ly, lw, 28), C_LABEL_BG)
	c.draw_string(font, Vector2(lx + 12, ly + 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, C_TEXT_LIGHT)


func _draw_bottom_list(c: Control, font: Font, items: Array, selected: int) -> void:
	var px: float = 5.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 300.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	for i in range(items.size()):
		var iy: float = py + 4 + i * 22
		if iy > py + ph - 4:
			break
		if i == selected:
			c.draw_rect(Rect2(px + 2, iy, pw - 4, 20), C_SELECT)
		var col: Color = C_SELECT_TEXT if i == selected else C_TEXT
		var item_name: String = str(items[i].get("name", ""))
		var item_type: String = str(items[i].get("type", ""))
		# Type icon
		var icon_letter: String = TYPE_ICONS.get(item_type, "?")
		var icon_color: Color = TYPE_COLORS.get(item_type, Color.GRAY) if i != selected else Color(1, 1, 1, 0.4)
		c.draw_rect(Rect2(px + 6, iy + 2, 16, 16), icon_color)
		c.draw_string(font, Vector2(px + 9, iy + 15), icon_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)
		# Count
		var qty: int = int(items[i].get("quantity", 0))
		var qty_str: String = "x%d" % qty if qty > 1 else ""
		c.draw_string(font, Vector2(px + 28, iy + 15), item_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, col)
		if not qty_str.is_empty():
			c.draw_string(font, Vector2(px + pw - 40, iy + 15), qty_str, HORIZONTAL_ALIGNMENT_RIGHT, -1, FONT_SIZE_XS, Color(col, 0.7))


func _draw_bottom_desc(c: Control, font: Font, text: String) -> void:
	var px: float = 310.0
	var py: float = VIEWPORT_H - 305.0
	var pw: float = 200.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	# Simple multi-line text
	var lines := text.split("\n")
	for i in range(lines.size()):
		c.draw_string(font, Vector2(px + 12, py + 20 + i * 18), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SM, C_TEXT)

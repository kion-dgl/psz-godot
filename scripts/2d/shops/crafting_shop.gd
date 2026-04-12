extends Control
## Synthesis Shop — craft weapons from materials, learn rare boards.

enum Mode { CRAFT, BOARDS }

const TAB_NAMES := ["Craft", "Boards"]
const PHOTON_OPTIONS := ["Im Photon", "El Photon", "Ban Photon", "Ray Photon", "Zon Photon", "Megi Photon", "Gra Photon"]
const PHOTON_IDS := ["im_photon", "el_photon", "ban_photon", "ray_photon", "zon_photon", "megi_photon", "gra_photon"]

## Photon ID → element + special attack tiers (tier 1-4, rolled by weapon rarity)
const PHOTON_ELEMENT := {
	"ban_photon": {"element": "fire", "tiers": ["Heat", "Fire", "Flame", "Burning"], "desc": "Fire bonus damage"},
	"ray_photon": {"element": "ice", "tiers": ["Ice", "Frost", "Freeze", "Blizzard"], "desc": "Chance to freeze"},
	"zon_photon": {"element": "lightning", "tiers": ["Shock", "Thunder", "Storm", "Tempest"], "desc": "Lightning bonus damage"},
	"megi_photon": {"element": "dark", "tiers": ["Dim", "Shadow", "Dark", "Hell"], "desc": "Chance to instant kill"},
	"gra_photon": {"element": "light", "tiers": ["Heart", "Mind", "Soul", "Geist"], "desc": "TP/PP drain on hit"},
	"el_photon": {"element": "none", "tiers": ["Draw", "Drain", "Fill", "Gush"], "desc": "HP drain on hit"},
}

## Tier roll weights by weapon rarity (index 0-3 = tier 1-4)
const TIER_WEIGHTS := {
	1: [70, 25, 5, 0],
	2: [55, 30, 12, 3],
	3: [40, 35, 18, 7],
	4: [25, 35, 25, 15],
	5: [15, 30, 30, 25],
	6: [5, 20, 40, 35],
	7: [0, 10, 40, 50],
}

## Enemy type names for attribute display
const ENEMY_TYPES := ["Native", "Beast", "Machine", "Dark", "Hit"]

## Photon → roll bonus ranges for attributes (base roll is 0-15 for each)
const PHOTON_BONUS := {
	"im_photon": {},
	"el_photon": {"hit": 35},
	"ban_photon": {"native": 25, "beast": 25},
	"ray_photon": {"native": 25, "beast": 25},
	"zon_photon": {"machine": 35},
	"megi_photon": {"dark": 35},
	"gra_photon": {"dark": 20, "native": 20},
}

var _mode: int = Mode.CRAFT
var _selected_index: int = 0
var _board_items: Array = []       # Array of {id, name, rarity}
var _craft_recipes: Array = []     # Array of {recipe, is_default, weapon_type, weapon_type_name, rarity, stars}

var _selecting_photon: bool = false
var _photon_index: int = 0
var _pending_recipe_index: int = -1
var _showing_result: bool = false
var _result_popup: PanelContainer

var _mode_bar_parent: Control
var _tab_row: HBoxContainer
var _portrait: Control

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeLabel
@onready var content_panel: PanelContainer = $Panel/VBox/ContentPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	_mode_bar_parent = mode_label.get_parent()
	PszStyle.style_menu(title_label, hint_label, [content_panel])
	title_label.text = "Synthesis Shop"
	_setup_portrait()
	hint_label.text = "Left/Right: Switch Mode  Up/Down: Select  Enter: Confirm  Esc: Leave"
	_build_lists()
	_refresh_display()


func _setup_portrait() -> void:
	var data := SceneManager.get_transition_data()
	var model_path: String = data.get("npc_model_path", "")
	if model_path.is_empty():
		return
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

	var vbox := panel.get_child(0) as VBoxContainer
	panel.remove_child(vbox)
	var outer := HBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_stretch_ratio = 3.0
	outer.add_child(vbox)

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


func _build_lists() -> void:
	_board_items.clear()
	_craft_recipes.clear()

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	# Find non-default recipe boards in inventory
	var all_items: Array = Inventory.get_all_items()
	for item in all_items:
		var item_id: String = item.get("id", "")
		var recipe = RecipeRegistry.get_recipe(item_id)
		if recipe and not recipe.is_default:
			_board_items.append({
				"id": recipe.id,
				"name": recipe.name,
				"rarity": recipe.rarity,
				"quantity": item.get("quantity", 1),
			})

	# Build craft list with weapon metadata for sorting
	for recipe in RecipeRegistry.get_all_recipes():
		if recipe.is_default:
			_add_craft_entry(recipe, true)

	# Learned rare recipes — count uses per recipe (duplicates = multiple uses)
	var learned_ids: Array = character.get("learned_recipes", [])
	var rare_counts: Dictionary = {}
	for recipe_id in learned_ids:
		rare_counts[recipe_id] = int(rare_counts.get(recipe_id, 0)) + 1
	for recipe_id in rare_counts:
		var recipe = RecipeRegistry.get_recipe(recipe_id)
		if recipe and not recipe.is_default:
			_add_craft_entry(recipe, false, int(rare_counts[recipe_id]))

	# Sort by weapon_type then rarity (rare boards mixed into their category)
	_craft_recipes.sort_custom(func(a, b):
		if a["weapon_type"] != b["weapon_type"]:
			return a["weapon_type"] < b["weapon_type"]
		return a["rarity"] < b["rarity"]
	)


func _add_craft_entry(recipe: RecipeBoardData, is_default: bool, uses: int = 0) -> void:
	var weapon = WeaponRegistry.get_weapon(recipe.output_weapon_id)
	var wtype: int = int(weapon.weapon_type) if weapon else 99
	var wtype_name: String = weapon.get_weapon_type_name() if weapon else ""
	var w_rarity: int = int(weapon.rarity) if weapon else int(recipe.rarity)
	var stars: String = weapon.get_rarity_string() if weapon else ""
	_craft_recipes.append({
		"recipe": recipe,
		"is_default": is_default,
		"weapon_type": wtype,
		"weapon_type_name": wtype_name,
		"rarity": w_rarity,
		"stars": stars,
		"uses": uses,
	})


func _unhandled_input(event: InputEvent) -> void:
	if _showing_result:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
			SfxManager.play("res://assets/sfx/ui/menu_select.wav")
			_dismiss_result_popup()
			get_viewport().set_input_as_handled()
		return

	if _selecting_photon:
		_handle_photon_input(event)
		return

	if event.is_action_pressed("ui_cancel"):
		SfxManager.play("res://assets/sfx/ui/menu_back.wav")
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_mode = Mode.BOARDS if _mode == Mode.CRAFT else Mode.CRAFT
		_selected_index = 0
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		var max_items: int = _craft_recipes.size() if _mode == Mode.CRAFT else _board_items.size()
		_selected_index = wrapi(_selected_index - 1, 0, maxi(max_items, 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		var max_items: int = _craft_recipes.size() if _mode == Mode.CRAFT else _board_items.size()
		_selected_index = wrapi(_selected_index + 1, 0, maxi(max_items, 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _mode == Mode.CRAFT:
			_craft_selected()
		else:
			_learn_selected()
		get_viewport().set_input_as_handled()


func _handle_photon_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SfxManager.play("res://assets/sfx/ui/menu_back.wav")
		_selecting_photon = false
		_pending_recipe_index = -1
		hint_label.text = "Left/Right: Switch Mode  Up/Down: Select  Enter: Confirm  Esc: Leave"
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_photon_index = wrapi(_photon_index - 1, 0, PHOTON_OPTIONS.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_photon_index = wrapi(_photon_index + 1, 0, PHOTON_OPTIONS.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_confirm_craft_with_photon()
		get_viewport().set_input_as_handled()


func _learn_selected() -> void:
	if _board_items.is_empty() or _selected_index >= _board_items.size():
		return

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var board_info: Dictionary = _board_items[_selected_index]
	var board_id: String = board_info["id"]

	Inventory.remove_item(board_id, 1)

	if not character.has("learned_recipes"):
		character["learned_recipes"] = []
	character["learned_recipes"].append(board_id)

	var uses: int = character["learned_recipes"].count(board_id)
	hint_label.text = "Learned %s! (%d use%s)" % [board_info["name"], uses, "" if uses == 1 else "s"]
	_build_lists()
	_selected_index = mini(_selected_index, maxi(_board_items.size() - 1, 0))
	_refresh_display()


func _craft_selected() -> void:
	if _craft_recipes.is_empty() or _selected_index >= _craft_recipes.size():
		return

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var entry: Dictionary = _craft_recipes[_selected_index]
	var recipe: RecipeBoardData = entry["recipe"]

	if int(character.get("meseta", 0)) < recipe.craft_cost:
		hint_label.text = "Not enough meseta! Need %d M" % recipe.craft_cost
		return

	for ingredient in recipe.ingredients:
		var owned: int = Inventory.get_item_count(ingredient["item_id"])
		if owned < int(ingredient["quantity"]):
			var mat = MaterialRegistry.get_material(ingredient["item_id"])
			var mat_name: String = mat.name if mat else ingredient["item_id"]
			hint_label.text = "Not enough %s!" % mat_name
			return

	# All synthesis requires a photon crystal
	_selecting_photon = true
	_photon_index = 0
	_pending_recipe_index = _selected_index
	hint_label.text = "Choose a photon crystal  Up/Down: Select  Enter: Confirm  Esc: Back"
	_refresh_display()


func _confirm_craft_with_photon() -> void:
	if _pending_recipe_index < 0 or _pending_recipe_index >= _craft_recipes.size():
		_selecting_photon = false
		return

	var entry: Dictionary = _craft_recipes[_pending_recipe_index]
	var recipe: RecipeBoardData = entry["recipe"]
	var photon_id: String = PHOTON_IDS[_photon_index]

	if not Inventory.has_item(photon_id):
		hint_label.text = "You don't have %s!" % PHOTON_OPTIONS[_photon_index]
		return

	_execute_craft(recipe, photon_id, entry["is_default"])
	_selecting_photon = false
	_pending_recipe_index = -1


func _execute_craft(recipe: RecipeBoardData, photon_id: String, is_default: bool) -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	character["meseta"] = int(character["meseta"]) - recipe.craft_cost
	GameState.meseta = int(character["meseta"])

	for ingredient in recipe.ingredients:
		Inventory.remove_item(ingredient["item_id"], int(ingredient["quantity"]))

	# Always consume photon
	Inventory.remove_item(photon_id, 1)

	# Each crafted weapon gets a unique instance ID
	var inst_id: String = Inventory.add_weapon(recipe.output_weapon_id)
	if inst_id.is_empty():
		hint_label.text = "Inventory full!"
		return

	# Roll special attack tier and element from photon
	var rolled: Dictionary = _roll_attributes(photon_id)
	var weapon = WeaponRegistry.get_weapon(recipe.output_weapon_id)
	var w_rarity: int = int(weapon.rarity) if weapon else 1
	var element_info: Dictionary = PHOTON_ELEMENT.get(photon_id, {})
	var element_name: String = str(element_info.get("element", ""))
	var special_prefix := ""
	var special_tier := 0

	if not element_info.is_empty() and element_info.has("tiers"):
		special_tier = _roll_special_tier(w_rarity)
		var tiers: Array = element_info.tiers
		if special_tier < tiers.size():
			special_prefix = str(tiers[special_tier])

	# Store prefix in weapon_elements for display name
	if not special_prefix.is_empty():
		if not character.has("weapon_elements"):
			character["weapon_elements"] = {}
		character["weapon_elements"][inst_id] = photon_id

	if not character.has("weapon_specials"):
		character["weapon_specials"] = {}
	if not special_prefix.is_empty():
		character["weapon_specials"][inst_id] = {"prefix": special_prefix, "tier": special_tier}

	print("[Craft] photon=%s element=%s special=%s tier=%d rolled=%s" % [photon_id, element_name, special_prefix, special_tier, rolled])

	if not character.has("weapon_stats"):
		character["weapon_stats"] = {}
	character["weapon_stats"][inst_id] = {
		"photon_id": photon_id,
		"element": element_name,
		"element_level": special_tier + 1,
		"native_pct": rolled["native"],
		"beast_pct": rolled["beast"],
		"machine_pct": rolled["machine"],
		"dark_pct": rolled["dark"],
		"hit_pct": rolled["hit"],
	}

	# Consume rare board recipe (single-use)
	if not is_default:
		var learned: Array = character.get("learned_recipes", [])
		var idx: int = learned.find(recipe.id)
		if idx >= 0:
			learned.remove_at(idx)

	_build_lists()
	_selected_index = mini(_selected_index, maxi(_craft_recipes.size() - 1, 0))
	_show_result_popup(inst_id, photon_id, recipe.craft_cost)


func _roll_special_tier(rarity: int) -> int:
	var weights: Array = TIER_WEIGHTS.get(clampi(rarity, 1, 7), TIER_WEIGHTS[1])
	var total := 0
	for w in weights:
		total += int(w)
	var roll := randi_range(0, total - 1)
	var cumulative := 0
	for i in range(weights.size()):
		cumulative += int(weights[i])
		if roll < cumulative:
			return i
	return 0


func _roll_attributes(photon_id: String) -> Dictionary:
	var result := {"native": 0, "beast": 0, "machine": 0, "dark": 0, "hit": 0}
	var bonus: Dictionary = PHOTON_BONUS.get(photon_id, {})
	for attr in result:
		result[attr] = randi_range(0, 15)
		var bonus_max: int = int(bonus.get(attr, 0))
		if bonus_max > 0:
			result[attr] += randi_range(0, bonus_max)
	return result


func _get_element_level(rarity: int) -> int:
	# Randomly rolled; higher rarity weapons are more likely to get higher levels.
	# Lv3 chance: rarity 1-3 = 5%, 4-5 = 15%, 6-7 = 30%
	# Lv2 chance: rarity 1-3 = 20%, 4-5 = 40%, 6-7 = 50%
	var roll := randf()
	var lv3_chance := 0.05
	var lv2_chance := 0.20
	if rarity >= 6:
		lv3_chance = 0.30
		lv2_chance = 0.50
	elif rarity >= 4:
		lv3_chance = 0.15
		lv2_chance = 0.40
	if roll < lv3_chance:
		return 3
	elif roll < lv3_chance + lv2_chance:
		return 2
	return 1


func _show_result_popup(weapon_id: String, photon_id: String, cost: int) -> void:
	_showing_result = true
	var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(weapon_id))
	var weapon_name: String = weapon.name if weapon else Inventory.get_base_id(weapon_id)
	# Prepend special prefix
	var character_for_name = CharacterManager.get_active_character()
	if character_for_name:
		var special: Dictionary = character_for_name.get("weapon_specials", {}).get(weapon_id, {})
		var prefix: String = str(special.get("prefix", ""))
		if not prefix.is_empty():
			weapon_name = prefix + " " + weapon_name

	# Build popup panel
	_result_popup = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.18, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.7, 1.0, 0.8)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 24.0
	style.content_margin_top = 16.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 16.0
	_result_popup.add_theme_stylebox_override("panel", style)

	_result_popup.set_anchors_preset(Control.PRESET_CENTER)
	_result_popup.offset_left = -180
	_result_popup.offset_right = 180
	_result_popup.offset_top = -160
	_result_popup.offset_bottom = 160
	_result_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result_popup.grow_vertical = Control.GROW_DIRECTION_BOTH

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	# Title
	var title := Label.new()
	title.text = "%s Created!" % weapon_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	if weapon:
		_add_spec(vbox, "Type", weapon.get_weapon_type_name())
		_add_spec(vbox, "Rarity", weapon.get_rarity_string(), PszStyle.TEXT_HIGHLIGHT)
		_add_spec(vbox, "ATK", "%d - %d" % [weapon.attack_base, weapon.attack_max])
		_add_spec(vbox, "ACC", "%d - %d" % [weapon.accuracy_base, weapon.accuracy_max])
		_add_spec(vbox, "Max Grind", "+%d" % weapon.max_grind)
		if weapon.is_ranged():
			_add_spec(vbox, "Req. ACC", "%d" % weapon.accuracy_base)
		elif weapon.is_tech_weapon():
			_add_spec(vbox, "Req. MST", "%d" % weapon.level)
		else:
			_add_spec(vbox, "Req. ATK", "%d" % weapon.attack_base)

		# Special attack from photon
		var photon_info: Dictionary = PHOTON_ELEMENT.get(photon_id, {})
		if not photon_info.is_empty():
			var char_special: Dictionary = character_for_name.get("weapon_specials", {}).get(weapon_id, {}) if character_for_name else {}
			var sp_prefix: String = str(char_special.get("prefix", ""))
			var sp_tier: int = int(char_special.get("tier", 0))
			if not sp_prefix.is_empty():
				_add_spec(vbox, "Special", "%s (Tier %d)" % [sp_prefix, sp_tier + 1], PszStyle.TEXT_SUCCESS)
			_add_spec(vbox, "Element", str(photon_info.get("element", "")).capitalize(), PszStyle.TEXT_WARNING)
			_add_spec(vbox, "Effect", str(photon_info.get("desc", "")), PszStyle.TEXT_MUTED)

		# Hit attributes vs enemy types (rolled values)
		var sep2 := HSeparator.new()
		sep2.add_theme_constant_override("separation", 4)
		vbox.add_child(sep2)

		var attr_label := Label.new()
		attr_label.text = "Attributes"
		attr_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		attr_label.add_theme_color_override("font_color", PszStyle.TEXT_MUTED)
		attr_label.add_theme_font_size_override("font_size", 13)
		vbox.add_child(attr_label)

		var character_for_attrs = CharacterManager.get_active_character()
		var ws2: Dictionary = character_for_attrs.get("weapon_stats", {}).get(weapon_id, {}) if character_for_attrs else {}
		var attr_keys := ["native", "beast", "machine", "dark", "hit"]
		var attr_names := ["Native", "Beast", "Machine", "Dark", "Hit"]
		for i in range(attr_keys.size()):
			var pct: int = int(ws2.get(attr_keys[i] + "_pct", 0))
			var color := PszStyle.TEXT_MUTED
			if pct > 0:
				color = PszStyle.TEXT_SUCCESS
			_add_spec(vbox, attr_names[i], "%d%%" % pct, color)

	# Cost
	var sep3 := HSeparator.new()
	sep3.add_theme_constant_override("separation", 4)
	vbox.add_child(sep3)
	_add_spec(vbox, "Cost", "%d M" % cost, PszStyle.TEXT_MESETA)

	# Dismiss hint
	var dismiss := Label.new()
	dismiss.text = "[Enter / Esc] Close"
	dismiss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dismiss.add_theme_color_override("font_color", PszStyle.TEXT_MUTED)
	dismiss.add_theme_font_size_override("font_size", 12)
	vbox.add_child(dismiss)

	_result_popup.add_child(vbox)
	add_child(_result_popup)
	hint_label.text = ""


func _add_spec(parent: VBoxContainer, label_text: String, value_text: String, value_color: Color = PszStyle.TEXT_WHITE) -> void:
	var hbox := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", PszStyle.TEXT_MUTED)
	lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_color_override("font_color", value_color)
	val.add_theme_font_size_override("font_size", 14)
	hbox.add_child(val)
	parent.add_child(hbox)


func _dismiss_result_popup() -> void:
	_showing_result = false
	if is_instance_valid(_result_popup):
		_result_popup.queue_free()
		_result_popup = null
	_refresh_display()


func _refresh_display() -> void:
	mode_label.visible = false

	if not is_instance_valid(_tab_row):
		_tab_row = HBoxContainer.new()
		_tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_tab_row.add_theme_constant_override("separation", 8)
		_mode_bar_parent.add_child(_tab_row)
		_mode_bar_parent.move_child(_tab_row, mode_label.get_index() + 1)
	for child in _tab_row.get_children():
		child.queue_free()
	_tab_row.add_child(PszStyle.create_tab_bar(TAB_NAMES, _mode))
	_tab_row.add_child(PszStyle.create_meseta_label(_get_meseta()))

	for child in content_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	var selected_pill: Control = null

	if _selecting_photon:
		vbox.add_child(PszStyle.create_section_header("Select photon crystal:"))
		for i in range(PHOTON_OPTIONS.size()):
			var option_name: String = PHOTON_OPTIONS[i]
			var has_it: bool = Inventory.has_item(PHOTON_IDS[i])
			var text_color := Color.TRANSPARENT
			if not has_it:
				text_color = PszStyle.TEXT_DANGER
			var count_text: String = "x%d" % Inventory.get_item_count(PHOTON_IDS[i])
			var pill := PszStyle.create_pill(option_name, i == _photon_index, count_text, text_color)
			vbox.add_child(pill)
			if i == _photon_index:
				selected_pill = pill
	elif _mode == Mode.BOARDS:
		vbox.add_child(PszStyle.create_section_header("Use a rare board to learn a special recipe."))

		if _board_items.is_empty():
			vbox.add_child(PszStyle.create_pill("(No recipe boards in inventory)", false, "", PszStyle.TEXT_MUTED))
		else:
			for i in range(_board_items.size()):
				var b: Dictionary = _board_items[i]
				var stars: String = ""
				for s in range(b["rarity"]):
					stars += "★"
				var pill := PszStyle.create_pill(
					"%s %s" % [b["name"], stars],
					i == _selected_index)
				vbox.add_child(pill)
				if i == _selected_index:
					selected_pill = pill
	else:
		# Craft mode — grouped by weapon type with section headers
		if _craft_recipes.is_empty():
			vbox.add_child(PszStyle.create_pill("(No recipes available)", false, "", PszStyle.TEXT_MUTED))
		else:
			var last_type_name: String = ""
			for i in range(_craft_recipes.size()):
				var entry: Dictionary = _craft_recipes[i]
				var recipe: RecipeBoardData = entry["recipe"]
				var is_def: bool = entry["is_default"]
				var type_name: String = entry["weapon_type_name"]
				var stars: String = entry["stars"]

				# Section headers by weapon type
				if not type_name.is_empty() and type_name != last_type_name:
					last_type_name = type_name
					vbox.add_child(PszStyle.create_section_header(type_name))

				var can_craft: bool = _can_craft_recipe(recipe)
				var text_color := Color.TRANSPARENT
				if not can_craft:
					text_color = PszStyle.TEXT_DANGER

				var ing_parts: PackedStringArray = []
				for ingredient in recipe.ingredients:
					var mat = MaterialRegistry.get_material(ingredient["item_id"])
					var mat_name: String = mat.name if mat else ingredient["item_id"]
					var owned: int = Inventory.get_item_count(ingredient["item_id"])
					var needed: int = int(ingredient["quantity"])
					ing_parts.append("%s %d/%d" % [mat_name, owned, needed])

				var weapon_name: String = recipe.name.replace(" Board", "")
				var uses_tag: String = ""
				if not is_def:
					var uses_left: int = int(entry.get("uses", 0))
					uses_tag = " [x%d]" % uses_left
				var pill := PszStyle.create_pill(
					"%s %s%s  (%s)" % [weapon_name, stars, uses_tag, ", ".join(ing_parts)],
					i == _selected_index, "%d M" % recipe.craft_cost, text_color)
				vbox.add_child(pill)
				if i == _selected_index:
					selected_pill = pill

	scroll.add_child(vbox)
	content_panel.add_child(scroll)

	if selected_pill != null:
		scroll.ensure_control_visible.call_deferred(selected_pill)


func _can_craft_recipe(recipe: RecipeBoardData) -> bool:
	var character = CharacterManager.get_active_character()
	if character == null:
		return false
	if int(character.get("meseta", 0)) < recipe.craft_cost:
		return false
	for ingredient in recipe.ingredients:
		if Inventory.get_item_count(ingredient["item_id"]) < int(ingredient["quantity"]):
			return false
	return true


func _get_meseta() -> int:
	var character = CharacterManager.get_active_character()
	if character:
		return int(character.get("meseta", 0))
	return 0

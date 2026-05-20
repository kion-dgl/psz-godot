extends Control
## Tekker — grind weapons and identify unknown weapons.

const SHOP_PREVIEW_PATH := "res://assets/ui/shop-previews/custom-shop.png"

enum Mode { GRIND, IDENTIFY }

const TAB_NAMES := ["Grind", "Identify"]

var _mode: int = Mode.GRIND
var _selected_index: int = 0
var _grindable_weapons: Array = []  # Array of {id, name, grind, max_grind, rarity}
var _unidentified_weapons: Array = []  # Array of {id, name, rarity}

var _mode_bar_parent: Control  # Parent of mode_label for tab bar rebuilding
var _tab_row: HBoxContainer    # Persistent tab bar container
var _portrait: Control
var _grinder_info: VBoxContainer  # Grinder counts + stat preview panel

## Grinder requirements by weapon rarity
const GRINDER_FOR_RARITY := {
	1: "monogrinder", 2: "monogrinder", 3: "monogrinder",
	4: "digrinder", 5: "digrinder",
	6: "trigrinder", 7: "trigrinder",
}

const RARITY_COST_MULT := {1: 1.0, 2: 1.5, 3: 2.0, 4: 3.0, 5: 4.0, 6: 6.0, 7: 10.0}

const IDENTIFY_COST := {5: 1000, 6: 2500, 7: 5000}

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeLabel
@onready var content_panel: PanelContainer = $Panel/VBox/ContentPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	_mode_bar_parent = mode_label.get_parent()
	PszStyle.style_menu(title_label, hint_label, [content_panel])
	title_label.text = "Tekker"
	_setup_portrait()
	hint_label.text = "Left/Right: Switch Mode  Up/Down: Select  Enter: Confirm  Esc: Leave"
	_build_lists()
	_refresh_display()
	ShopPreviewSprite.attach(self, SHOP_PREVIEW_PATH)


func _setup_portrait() -> void:
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

	# Right: just portrait (no detail panel for tekker)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 2.0
	right.add_theme_constant_override("separation", 0)
	# Grinder info panel (above portrait)
	# Right column: grinder info takes the full vertical space; the shop
	# preview is added separately as an absolute overlay (see
	# ShopPreviewSprite.attach below).
	_grinder_info = VBoxContainer.new()
	_grinder_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grinder_info.add_theme_constant_override("separation", 4)
	right.add_child(_grinder_info)

	outer.add_child(right)
	panel.add_child(outer)


func _build_lists() -> void:
	_grindable_weapons.clear()
	_unidentified_weapons.clear()

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	# Grindable: weapons in inventory (use instance ID, not base ID)
	var all_items: Array = Inventory.get_all_items()
	for item in all_items:
		var inst_id: String = item.get("id", "")
		var weapon = WeaponRegistry.get_weapon(inst_id)
		if weapon and weapon.max_grind > 0:
			var current_grind: int = int(character.get("weapon_grinds", {}).get(inst_id, 0))
			if current_grind < weapon.max_grind:
				_grindable_weapons.append({
					"id": inst_id,
					"name": item.get("name", weapon.name),
					"grind": current_grind,
					"max_grind": weapon.max_grind,
					"rarity": weapon.rarity,
				})

	# Unidentified weapons
	for weapon_id in character.get("unidentified_weapons", []):
		var weapon = WeaponRegistry.get_weapon(weapon_id)
		if weapon:
			_unidentified_weapons.append({
				"id": weapon.id,
				"name": weapon.name,
				"rarity": weapon.rarity,
			})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SfxManager.play("res://assets/sfx/ui/menu_back.wav")
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		_mode = Mode.IDENTIFY if _mode == Mode.GRIND else Mode.GRIND
		_selected_index = 0
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		var max_items: int = _grindable_weapons.size() if _mode == Mode.GRIND else _unidentified_weapons.size()
		var dir: int = -1 if event.is_action_pressed("ui_up") else 1
		_selected_index = wrapi(_selected_index + dir, 0, maxi(max_items, 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		SfxManager.play("res://assets/sfx/ui/menu_select.wav")
		if _mode == Mode.GRIND:
			_grind_selected()
		else:
			_identify_selected()
		get_viewport().set_input_as_handled()


func _grind_selected() -> void:
	if _grindable_weapons.is_empty() or _selected_index >= _grindable_weapons.size():
		return

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var weapon_info: Dictionary = _grindable_weapons[_selected_index]
	var weapon_id: String = weapon_info["id"]
	var current_grind: int = weapon_info["grind"]
	var rarity: int = weapon_info["rarity"]

	# Check grinder requirement
	var grinder_id: String = GRINDER_FOR_RARITY.get(rarity, "monogrinder")
	if not Inventory.has_item(grinder_id):
		var grinder_name: String = grinder_id.replace("_", " ").capitalize()
		hint_label.text = "Need a %s to grind this weapon!" % grinder_name
		return

	# Calculate cost
	var cost := int((200 + current_grind * 100) * RARITY_COST_MULT.get(rarity, 1.0))
	if int(character.get("meseta", 0)) < cost:
		hint_label.text = "Not enough meseta! Need %d M" % cost
		return

	# Grind always succeeds in PSZ
	character["meseta"] = int(character["meseta"]) - cost
	GameState.meseta = int(character["meseta"])
	Inventory.remove_item(grinder_id, 1)

	if not character.has("weapon_grinds"):
		character["weapon_grinds"] = {}
	character["weapon_grinds"][weapon_id] = current_grind + 1

	hint_label.text = "Ground %s to +%d! (-%d M)" % [weapon_info["name"], current_grind + 1, cost]
	_build_lists()
	_selected_index = mini(_selected_index, maxi(_grindable_weapons.size() - 1, 0))
	_refresh_display()


func _identify_selected() -> void:
	if _unidentified_weapons.is_empty() or _selected_index >= _unidentified_weapons.size():
		return

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var weapon_info: Dictionary = _unidentified_weapons[_selected_index]
	var weapon_id: String = weapon_info["id"]
	var rarity: int = weapon_info["rarity"]

	var cost: int = IDENTIFY_COST.get(rarity, 1000)
	if int(character.get("meseta", 0)) < cost:
		hint_label.text = "Not enough meseta! Need %d M" % cost
		return

	# Deduct meseta
	character["meseta"] = int(character["meseta"]) - cost
	GameState.meseta = int(character["meseta"])

	# Remove from unidentified list
	var unid_list: Array = character.get("unidentified_weapons", [])
	var idx: int = unid_list.find(weapon_id)
	if idx >= 0:
		unid_list.remove_at(idx)

	# Add to inventory
	Inventory.add_item(weapon_id, 1)

	hint_label.text = "Identified %s! (-%d M)" % [weapon_info["name"], cost]
	_build_lists()
	_selected_index = mini(_selected_index, maxi(_unidentified_weapons.size() - 1, 0))
	_refresh_display()


func _refresh_display() -> void:
	# Tab bar — mode_label is direct child of VBox, so we hide it and
	# reuse a persistent HBoxContainer for the tab bar
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

	# Content panel — pill rows
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

	if _mode == Mode.GRIND:
		vbox.add_child(PszStyle.create_section_header("Grinding increases a weapon's attack power."))

		if _grindable_weapons.is_empty():
			vbox.add_child(PszStyle.create_pill("(No grindable weapons in inventory)", false, "", PszStyle.TEXT_MUTED))
		else:
			for i in range(_grindable_weapons.size()):
				var w: Dictionary = _grindable_weapons[i]
				var grinder_id: String = GRINDER_FOR_RARITY.get(w["rarity"], "monogrinder")
				var has_grinder: bool = Inventory.has_item(grinder_id)
				var cost := int((200 + w["grind"] * 100) * RARITY_COST_MULT.get(w["rarity"], 1.0))

				var text_color := Color.TRANSPARENT
				if not has_grinder:
					text_color = PszStyle.TEXT_DANGER

				var pill := PszStyle.create_pill(
					"%s  +%d/%d  [%s]" % [w["name"], w["grind"], w["max_grind"], grinder_id.replace("_", " ")],
					i == _selected_index, "%d M" % cost, text_color)
				vbox.add_child(pill)
				if i == _selected_index:
					selected_pill = pill
	else:
		vbox.add_child(PszStyle.create_section_header("Identify unknown weapons (5-7 star rarity)."))

		if _unidentified_weapons.is_empty():
			vbox.add_child(PszStyle.create_pill("(No unidentified weapons)", false, "", PszStyle.TEXT_MUTED))
		else:
			for i in range(_unidentified_weapons.size()):
				var w: Dictionary = _unidentified_weapons[i]
				var cost: int = IDENTIFY_COST.get(w["rarity"], 1000)
				var pill := PszStyle.create_pill(
					"%s  %s star" % [w["name"], str(w["rarity"])],
					i == _selected_index, "%d M" % cost)
				vbox.add_child(pill)
				if i == _selected_index:
					selected_pill = pill

	scroll.add_child(vbox)
	content_panel.add_child(scroll)

	if selected_pill != null:
		scroll.ensure_control_visible.call_deferred(selected_pill)

	_update_grinder_info()


func _update_grinder_info() -> void:
	if not _grinder_info:
		return
	for child in _grinder_info.get_children():
		child.queue_free()

	# Grinder counts
	var header := Label.new()
	header.text = "Grinders"
	header.add_theme_color_override("font_color", PszStyle.TEXT_HIGHLIGHT)
	header.add_theme_font_size_override("font_size", PszStyle.FONT_ITEM)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grinder_info.add_child(header)

	var grinders := ["monogrinder", "digrinder", "trigrinder"]
	var grinder_labels := ["Monogrinder", "Digrinder", "Trigrinder"]
	for i in range(grinders.size()):
		var count: int = Inventory.get_item_count(grinders[i])
		var color: Color = PszStyle.TEXT if count > 0 else PszStyle.TEXT_MUTED
		var lbl := Label.new()
		lbl.text = "%s: %d" % [grinder_labels[i], count]
		lbl.add_theme_color_override("font_color", color)
		lbl.add_theme_font_size_override("font_size", PszStyle.FONT_DETAIL)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_grinder_info.add_child(lbl)

	# Stat preview for selected weapon (grind mode only)
	if _mode == Mode.GRIND and not _grindable_weapons.is_empty() and _selected_index < _grindable_weapons.size():
		var sep := HSeparator.new()
		sep.add_theme_constant_override("separation", 6)
		_grinder_info.add_child(sep)

		var w: Dictionary = _grindable_weapons[_selected_index]
		var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(w["id"]))
		if weapon:
			var cur_grind: int = w["grind"]
			var cur_atk: int = weapon.get_attack_at_grind(cur_grind)
			var cur_acc: int = weapon.get_accuracy_at_grind(cur_grind)
			var next_atk: int = weapon.get_attack_at_grind(cur_grind + 1)
			var next_acc: int = weapon.get_accuracy_at_grind(cur_grind + 1)

			var preview_header := Label.new()
			preview_header.text = "After Grind"
			preview_header.add_theme_color_override("font_color", PszStyle.TEXT_HIGHLIGHT)
			preview_header.add_theme_font_size_override("font_size", PszStyle.FONT_DETAIL)
			preview_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_grinder_info.add_child(preview_header)

			var atk_diff: int = next_atk - cur_atk
			var acc_diff: int = next_acc - cur_acc

			var atk_lbl := Label.new()
			atk_lbl.text = "ATK: %d → %d (+%d)" % [cur_atk, next_atk, atk_diff]
			atk_lbl.add_theme_color_override("font_color", PszStyle.TEXT_SUCCESS if atk_diff > 0 else PszStyle.TEXT)
			atk_lbl.add_theme_font_size_override("font_size", PszStyle.FONT_DETAIL)
			atk_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_grinder_info.add_child(atk_lbl)

			var acc_lbl := Label.new()
			acc_lbl.text = "ACC: %d → %d (+%d)" % [cur_acc, next_acc, acc_diff]
			acc_lbl.add_theme_color_override("font_color", PszStyle.TEXT_SUCCESS if acc_diff > 0 else PszStyle.TEXT)
			acc_lbl.add_theme_font_size_override("font_size", PszStyle.FONT_DETAIL)
			acc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_grinder_info.add_child(acc_lbl)


func _get_meseta() -> int:
	var character = CharacterManager.get_active_character()
	if character:
		return int(character.get("meseta", 0))
	return 0


# ── Hold-to-repeat navigation (NavRepeat) ──────────────────────────────────────
var _nav: NavRepeat = null


func _process(delta: float) -> void:
	if _nav == null:
		_nav = NavRepeat.new(["ui_up", "ui_down", "ui_left", "ui_right"], _on_nav_repeat)
	_nav.tick(delta)


func _on_nav_repeat(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_unhandled_input(ev)

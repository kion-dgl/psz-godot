extends Control
## Tekker — grind weapons to raise their attack power.

const SHOP_PREVIEW_PATH := "res://assets/ui/shop-previews/custom-shop.png"
const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")

# Grind is the only mode — PSZ has no PSO-style weapon identification (no
# special-attack mechanic to unlock), so the Identify tab was removed.
enum Mode { GRIND }

const TAB_NAMES := ["Grind"]

var _mode: int = Mode.GRIND
var _selected_index: int = 0
var _grindable_weapons: Array = []  # Array of {id, name, grind, max_grind, rarity}

var _mode_bar_parent: Control  # Parent of mode_label for tab bar rebuilding
var _tab_row: HBoxContainer    # Persistent tab bar container
var _detail_panel: PanelContainer  # Shared right-column detail card

## Grinder requirements by weapon rarity
const GRINDER_FOR_RARITY := {
	1: "monogrinder", 2: "monogrinder", 3: "monogrinder",
	4: "digrinder", 5: "digrinder",
	6: "trigrinder", 7: "trigrinder",
}

const RARITY_COST_MULT := {1: 1.0, 2: 1.5, 3: 2.0, 4: 3.0, 5: 4.0, 6: 6.0, 7: 10.0}

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeLabel
@onready var content_panel: PanelContainer = $Panel/VBox/ContentPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	_mode_bar_parent = mode_label.get_parent()
	PszStyle.style_menu(title_label, hint_label, [content_panel])
	title_label.text = "Tekker"
	_setup_portrait()
	hint_label.text = "Up/Down: Select  Enter: Grind  Esc: Leave"
	_build_lists()
	_refresh_display()
	ShopPreviewSprite.attach(self, SHOP_PREVIEW_PATH)


func _setup_portrait() -> void:
	# Shared layout: list left (3/5), detail card top-right (2/5) stopping 10px
	# above the portrait. The grinder counts + after-grind preview render into
	# this card (see _update_grinder_info) — same scaffold as every other shop.
	_detail_panel = PszStyle.setup_shop_portrait($Panel, null, SHOP_PREVIEW_PATH)


func _build_lists() -> void:
	_grindable_weapons.clear()

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


func _unhandled_input(event: InputEvent) -> void:
	# Single mode (Grind) — no tab switching.
	ShopNav.handle(self, event, {
		"list_size": func() -> int: return _grindable_weapons.size(),
		"on_move": func(_old: int) -> void: _refresh_display(),
		"on_accept": func() -> void: _grind_selected(),
	})


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
				text_color = PszStyle.TEXT_MUTED  # unified disabled style (#368)

			var pill := PszStyle.create_pill(
				"%s  +%d/%d  [%s]" % [w["name"], w["grind"], w["max_grind"], grinder_id.replace("_", " ")],
				i == _selected_index, "%d M" % cost, text_color)
			vbox.add_child(pill)
			if i == _selected_index:
				selected_pill = pill

	scroll.add_child(vbox)
	content_panel.add_child(scroll)

	if selected_pill != null:
		scroll.ensure_control_visible.call_deferred(selected_pill)

	_update_grinder_info()


func _update_grinder_info() -> void:
	if not is_instance_valid(_detail_panel):
		return
	PszStyle.clear_detail_panel(_detail_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	# Grinder counts on hand.
	vbox.add_child(PszStyle.detail_label("Grinders", PszStyle.TITLE_BG))
	var grinders := ["monogrinder", "digrinder", "trigrinder"]
	var grinder_labels := ["Monogrinder", "Digrinder", "Trigrinder"]
	for i in range(grinders.size()):
		var count: int = Inventory.get_item_count(grinders[i])
		var color: Color = PszStyle.TEXT if count > 0 else PszStyle.TEXT_MUTED
		vbox.add_child(PszStyle.detail_label("%s: %d" % [grinder_labels[i], count], color))

	# After-grind stat preview + cost for the selected weapon.
	if not _grindable_weapons.is_empty() and _selected_index < _grindable_weapons.size():
		var w: Dictionary = _grindable_weapons[_selected_index]
		var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(w["id"]))
		if weapon:
			var cur_grind: int = w["grind"]
			var cur_atk: int = weapon.get_attack_at_grind(cur_grind)
			var cur_acc: int = weapon.get_accuracy_at_grind(cur_grind)
			var next_atk: int = weapon.get_attack_at_grind(cur_grind + 1)
			var next_acc: int = weapon.get_accuracy_at_grind(cur_grind + 1)
			var atk_diff: int = next_atk - cur_atk
			var acc_diff: int = next_acc - cur_acc

			vbox.add_child(PszStyle.detail_label("After Grind", PszStyle.TITLE_BG))
			vbox.add_child(PszStyle.detail_label(
				"ATK: %d → %d (+%d)" % [cur_atk, next_atk, atk_diff],
				PszStyle.TEXT_SUCCESS if atk_diff > 0 else PszStyle.TEXT))
			vbox.add_child(PszStyle.detail_label(
				"ACC: %d → %d (+%d)" % [cur_acc, next_acc, acc_diff],
				PszStyle.TEXT_SUCCESS if acc_diff > 0 else PszStyle.TEXT))

			var cost := int((200 + cur_grind * 100) * RARITY_COST_MULT.get(w["rarity"], 1.0))
			vbox.add_child(PszStyle.detail_label("Cost: %d M" % cost, PszStyle.TEXT_MESETA))

	_detail_panel.add_child(vbox)


# ── Hold-to-repeat navigation (NavRepeat) ──────────────────────────────────────
var _nav: NavRepeat = null


func _process(delta: float) -> void:
	if _nav == null:
		_nav = NavRepeat.new(["ui_up", "ui_down", "ui_left", "ui_right"], _on_nav_repeat)
	_nav.tick(delta)

# --- Shop scaffolding, inlined. These screens are standalone (extends Control)
# --- rather than sharing a ShopBase: a cross-script base class fails to
# --- resolve in the Android export at runtime (works in-editor and on every
# --- other platform). See the shop-dedup tracker.

## The active character's meseta (0 if no active character).
func _get_meseta() -> int:
	var character = CharacterManager.get_active_character()
	if character:
		return int(character.get("meseta", 0))
	return 0


## NavRepeat callback: re-emit a held nav action as a synthetic input event
## so this screen's own _unhandled_input handles it (hold-to-repeat nav).
func _on_nav_repeat(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_unhandled_input(ev)


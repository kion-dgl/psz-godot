extends Control
## Tekker — grind weapons to raise their attack power.

const SHOP_PREVIEW_PATH := "res://assets/ui/shop-previews/custom-shop.png"
const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")
const ShopDetail := preload("res://scripts/2d/shops/shop_detail.gd")

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
const Grinding := preload("res://scripts/utils/weapon_grinding.gd")
const GRINDER_FOR_RARITY = Grinding.GRINDER_FOR_RARITY
const RARITY_COST_MULT = Grinding.RARITY_COST_MULT

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

	var result := Grinding.apply(str(_grindable_weapons[_selected_index]["id"]))
	hint_label.text = result.message
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
	PszStyle.update_shop_balance(self, _get_meseta())

	# Content panel — pill rows
	for child in content_panel.get_children():
		child.queue_free()

	var scroll := PszStyle.make_list_scroll()
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

	PszStyle.set_list_content(scroll, vbox)
	content_panel.add_child(scroll)

	if selected_pill != null:
		PszStyle.scroll_into_view(selected_pill)

	_update_grinder_info()


func _update_grinder_info() -> void:
	if not is_instance_valid(_detail_panel):
		return
	if _grindable_weapons.is_empty() or _selected_index >= _grindable_weapons.size():
		_render_empty_grinder_card()
		return
	var w: Dictionary = _grindable_weapons[_selected_index]
	var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(str(w["id"])))
	if weapon == null:
		_render_empty_grinder_card()
		return
	var cur_grind: int = int(w["grind"])
	var title_txt := "%s +%d" % [w["name"], cur_grind] if cur_grind > 0 else str(w["name"])
	var ctx := ShopDetail.open_card(_detail_panel, title_txt, {
		"icon": InventoryIcons.for_weapon_type(int(weapon.weapon_type)),
		"rarity": int(w["rarity"]),
	})
	ShopDetail.add_sub_meta(ctx, weapon.get_weapon_type_name(), "Max Grind +%d" % int(w["max_grind"]))
	ShopDetail.add_delta_rows(ctx, _grind_delta_rows(str(w["id"]), weapon, cur_grind))
	var req_id: String = GRINDER_FOR_RARITY.get(int(w["rarity"]), "monogrinder")
	var req_held: int = Inventory.get_item_count(req_id)
	ShopDetail.add_kv_row(ctx, "Requires", "%s (%d held)" % [req_id.capitalize(), req_held],
		ShopDetail.C_UP_TEXT if req_held > 0 else ShopDetail.C_DOWN_TEXT)
	ShopDetail.add_kv_row(ctx, "Grinders", "Mono:%d · Di:%d · Tri:%d" % [
		Inventory.get_item_count("monogrinder"),
		Inventory.get_item_count("digrinder"),
		Inventory.get_item_count("trigrinder"),
	], ShopDetail.C_SLATE_TEXT)
	var cost := int((200 + cur_grind * 100) * RARITY_COST_MULT.get(w["rarity"], 1.0))
	var status := "✓ Ready (+%d → +%d)" % [cur_grind, cur_grind + 1]
	var tone := "ok"
	if req_held <= 0:
		status = "Missing %s" % req_id.capitalize()
		tone = "blocked"
	elif _get_meseta() < cost:
		status = "Not enough meseta"
		tone = "warn"
	ShopDetail.set_footer(ctx, [{"label": "Cost", "value": "%d M" % cost, "tone": "gold"}], status, tone)


func _grind_delta_rows(inst_id: String, weapon, cur_grind: int) -> Array:
	var cur_atk: int = weapon.get_attack_at_grind(cur_grind)
	var next_atk: int = weapon.get_attack_at_grind(cur_grind + 1)
	var cur_acc: int = weapon.get_accuracy_at_grind(cur_grind)
	var next_acc: int = weapon.get_accuracy_at_grind(cur_grind + 1)
	var atk_diff: int = next_atk - cur_atk
	var acc_diff: int = next_acc - cur_acc
	var rows := [
		{"label": "Grind", "value": "+%d → +%d (+1)" % [cur_grind, cur_grind + 1], "positive": true},
		{"label": "Weapon ATK", "value": "%d → %d (+%d)" % [cur_atk, next_atk, atk_diff], "positive": atk_diff > 0},
	]
	var character = CharacterManager.get_active_character()
	if character != null and str(character.get("equipment", {}).get("weapon", "")) == inst_id:
		var totals: Dictionary = ShopDetail.calc_effective_stats(character)
		var tot_atk: int = int(totals["atk"])
		rows.append({"label": "Total ATK", "value": "%d → %d (+%d)" % [tot_atk, tot_atk + atk_diff, atk_diff], "positive": atk_diff > 0})
	var acc_sign := "+%d" % acc_diff if acc_diff > 0 else "±0"
	rows.append({"label": "Weapon ACC", "value": "%d → %d (%s)" % [cur_acc, next_acc, acc_sign], "positive": acc_diff > 0})
	return rows


func _render_empty_grinder_card() -> void:
	var ctx := ShopDetail.open_card(_detail_panel, "Weapon Grind")
	ShopDetail.add_sub_meta(ctx, "Grinders Held", "")
	for pair in [["Monogrinder", "monogrinder"], ["Digrinder", "digrinder"], ["Trigrinder", "trigrinder"]]:
		var cnt: int = Inventory.get_item_count(pair[1])
		ShopDetail.add_kv_row(ctx, pair[0], "×%d" % cnt, ShopDetail.C_VAL_TEXT if cnt > 0 else ShopDetail.C_SLATE_TEXT)


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
	return GameState.meseta


## NavRepeat callback: re-emit a held nav action as a synthetic input event
## so this screen's own _unhandled_input handles it (hold-to-repeat nav).
func _on_nav_repeat(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_unhandled_input(ev)


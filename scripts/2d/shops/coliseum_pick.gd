extends Control
## Coliseum Master — debug enemy lab (kion): pick any enemy from the roster and
## warp alone with it into the coliseum arena (stage s00a_nr2) for 1:1 combat
## testing, the in-game counterpart of the #/enemy-room web tool. The shell quest
## (`debug_coliseum`) provides the session/report frame; ColiseumRoster builds the
## synthesized 1:1 field sections (one enemy + a room-clear telepipe home).

const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")
const FIELD_SCENE := "res://scenes/3d/field/valley_field.tscn"
const SHELL_QUEST_ID := "debug_coliseum"

var _selected_index: int = 0
var _rows: Array = []
var _detail_panel: PanelContainer = null
var _active_modal: Control = null
# Cached pill nodes (one per row) so a cursor move re-styles the selected row in
# place rather than rebuilding the list (Kion playtest) — mirrors the other shops.
var _pill_nodes: Array = []

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeLabel
@onready var content_panel: PanelContainer = $Panel/VBox/ContentPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	PszStyle.style_menu(title_label, hint_label, [content_panel])
	title_label.text = "Coliseum Master"
	_detail_panel = PszStyle.setup_shop_portrait($Panel, null, "")
	hint_label.text = "Up/Down: Select  Enter: Battle  Esc: Leave"
	_rows = ColiseumRoster.roster_rows()
	_refresh_display()


func _unhandled_input(event: InputEvent) -> void:
	ShopNav.handle(self, event, {
		"modal": _active_modal,
		"list_size": func() -> int: return _rows.size(),
		"on_move": func(_old_index: int) -> void:
			ShopNav.cursor_move(_pill_nodes, _old_index, _selected_index, _refresh_detail),
		"on_accept": _open_confirm,
	})


func _open_confirm() -> void:
	var row_v: Variant = ShopNav.selected_item(self, _rows)
	if row_v == null:
		return
	var row: Dictionary = row_v
	ShopNav.confirm(self, "Battle %s in the coliseum?" % str(row["name"]),
		func() -> void: _start_battle(str(row["id"])))


## Warp: quest session shell from the on-disk debug quest, then our synthesized
## 1:1 sections override its cells, then straight into the field. goto_scene
## clears the shop overlay stack itself, so no pop is needed first.
func _start_battle(enemy_id: String) -> void:
	SessionManager.enter_quest(SHELL_QUEST_ID, "normal")
	SessionManager.set_field_sections(ColiseumRoster.make_sections(enemy_id))
	SceneManager.goto_scene(FIELD_SCENE, {
		"current_cell_pos": "0,0", "spawn_edge": "", "keys_collected": {}})


func _refresh_display() -> void:
	mode_label.visible = false
	for child in content_panel.get_children():
		child.queue_free()

	var scroll := PszStyle.make_list_scroll()
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	_pill_nodes.clear()
	_pill_nodes.resize(_rows.size())
	var selected_pill: Control = null
	for i in range(_rows.size()):
		var row: Dictionary = _rows[i]
		var badges: Array = []
		if bool(row["is_boss"]):
			badges.append("Boss")
		if bool(row["is_rare"]):
			badges.append("Rare")
		var right: String = " · ".join(badges) if not badges.is_empty() else str(row["archetype"])
		var pill := PszStyle.shop_row(str(row["name"]), right, {"selected": i == _selected_index})
		vbox.add_child(pill)
		_pill_nodes[i] = pill
		if i == _selected_index:
			selected_pill = pill

	scroll.add_child(vbox)
	content_panel.add_child(scroll)
	if selected_pill != null:
		PszStyle.scroll_selected_into_view(selected_pill)
	_refresh_detail()


## The selected enemy's detail card — element, HP, archetype, and its attack kinds
## (the delivery behaviors the 1:1 run is about to exercise).
func _refresh_detail() -> void:
	if not is_instance_valid(_detail_panel):
		return
	PszStyle.clear_detail_panel(_detail_panel)
	if _selected_index < 0 or _selected_index >= _rows.size():
		return
	var row: Dictionary = _rows[_selected_index]
	var kinds: Array = row["kinds"]
	kinds.sort()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.add_child(PszStyle.detail_label(str(row["name"]), PszStyle.TITLE_BG))
	vbox.add_child(PszStyle.detail_label("Element: %s" % str(row["element"])))
	vbox.add_child(PszStyle.detail_label("HP: %d" % int(row["hp"])))
	vbox.add_child(PszStyle.detail_label("Archetype: %s" % str(row["archetype"])))
	vbox.add_child(PszStyle.detail_label("Attacks: %s" % ", ".join(PackedStringArray(kinds)),
		PszStyle.TEXT_HIGHLIGHT))
	_detail_panel.add_child(vbox)


# ── Hold-to-repeat navigation (NavRepeat) ──────────────────────────────────────
var _nav: NavRepeat = null


func _process(delta: float) -> void:
	# Modal owns input + nav while open.
	if is_instance_valid(_active_modal):
		return
	if _nav == null:
		_nav = NavRepeat.new(["ui_up", "ui_down"], _on_nav_repeat)
	_nav.tick(delta)


# --- Shop scaffolding, inlined. These screens are standalone (extends Control)
# --- rather than sharing a ShopBase: a cross-script base class fails to
# --- resolve in the Android export at runtime (works in-editor and on every
# --- other platform). See the shop-dedup tracker.

## NavRepeat callback: re-emit a held nav action as a synthetic input event
## so this screen's own _unhandled_input handles it (hold-to-repeat nav).
func _on_nav_repeat(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_unhandled_input(ev)

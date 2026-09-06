extends Control
## Coliseum Master — debug enemy lab (kion): pick any enemy from the roster and
## warp alone with it into the coliseum arena (stage s00a_nr2) for 1:1 combat
## testing, the in-game counterpart of the #/enemy-room web tool. Normal enemies
## and bosses sit on separate tabs; within a tab rows group by behavior type and
## order by the areas they appear in (kion playtest). The shell quest
## (`debug_coliseum`) provides the session/report frame; ColiseumRoster builds
## the synthesized 1:1 field sections (one enemy + a room-clear telepipe home).

const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")
const FIELD_SCENE := "res://scenes/3d/field/valley_field.tscn"
const SHELL_QUEST_ID := "debug_coliseum"
const TAB_NAMES := ["Enemies", "Bosses"]
const TAB_COUNT := 2

var _selected_index: int = 0
var _tab: int = 0
var _rows: Array = []          # selectable rows for the active tab
var _groups: Array = []        # grouped_roster() result for the active tab
var _detail_panel: PanelContainer = null
var _active_modal: Control = null
# Cached pill nodes (one per SELECTABLE row) so a cursor move re-styles the
# selected row in place rather than rebuilding the list (Kion playtest) — group
# headers interleave in the list but stay out of this array, keeping indexes
# aligned with _rows. Mirrors the other shops.
var _pill_nodes: Array = []
var _tab_row: HBoxContainer

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeLabel
@onready var content_panel: PanelContainer = $Panel/VBox/ContentPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	PszStyle.style_menu(title_label, hint_label, [content_panel])
	title_label.text = "Coliseum Master"
	_detail_panel = PszStyle.setup_shop_portrait($Panel, null, "")
	hint_label.text = "Up/Down: Select  ←/→: Tab  Enter: Battle  Esc: Leave"
	_load_tab(0)


func _unhandled_input(event: InputEvent) -> void:
	ShopNav.handle(self, event, {
		"modal": _active_modal,
		"list_size": func() -> int: return _rows.size(),
		"on_move": func(_old_index: int) -> void:
			ShopNav.cursor_move(_pill_nodes, _old_index, _selected_index, _refresh_detail),
		"on_tab": func(dir: int) -> void: _load_tab(_tab + dir),
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
## 1:1 sections override its cells, then straight into the field (spawn at the
## arena's south entrance). goto_scene clears the shop overlay stack itself, so
## no pop is needed first.
func _start_battle(enemy_id: String) -> void:
	SessionManager.enter_quest(SHELL_QUEST_ID, "normal")
	SessionManager.set_field_sections(ColiseumRoster.make_sections(enemy_id))
	SceneManager.goto_scene(FIELD_SCENE, ColiseumRoster.warp_data())


func _load_tab(tab: int) -> void:
	_tab = wrapi(tab, 0, TAB_COUNT)
	_selected_index = 0
	_groups = ColiseumRoster.grouped_roster(_tab == 1)
	_rows = []
	for g in _groups:
		_rows.append_array(g["rows"])
	_refresh_display()


func _refresh_display() -> void:
	mode_label.visible = false
	if not is_instance_valid(_tab_row):
		_tab_row = HBoxContainer.new()
		_tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_tab_row.add_theme_constant_override("separation", 8)
		mode_label.get_parent().add_child(_tab_row)
		mode_label.get_parent().move_child(_tab_row, mode_label.get_index() + 1)
	for child in _tab_row.get_children():
		child.queue_free()
	_tab_row.add_child(PszStyle.create_tab_bar(TAB_NAMES, _tab))

	for child in content_panel.get_children():
		child.queue_free()

	var scroll := PszStyle.make_list_scroll()
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	_pill_nodes.clear()
	_pill_nodes.resize(_rows.size())
	var selected_pill: Control = null
	var row_idx := 0
	for g in _groups:
		vbox.add_child(_group_header(g))
		for row in g["rows"]:
			var pill := _row_pill(row, row_idx == _selected_index)
			vbox.add_child(pill)
			_pill_nodes[row_idx] = pill
			if row_idx == _selected_index:
				selected_pill = pill
			row_idx += 1

	scroll.add_child(vbox)
	content_panel.add_child(scroll)
	if selected_pill != null:
		PszStyle.scroll_selected_into_view(selected_pill)
	elif _rows.is_empty():
		var empty := Label.new()
		empty.text = "(No %s in the roster)" % TAB_NAMES[_tab].to_lower()
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(empty)
	_refresh_detail()


## A group's header: behavior archetype + up to three areas its members appear
## in. The label ellipsizes and never drives the panel's minimum width — wide
## headers (rappy-family types appear everywhere) used to inflate the min size
## and push the shop panel off the left screen edge (kion playtest).
func _group_header(group: Dictionary) -> Control:
	var areas := {}
	for row in group["rows"]:
		for area in row["areas"]:
			areas[area] = true
	var shown: Array = areas.keys()
	if shown.size() > 3:
		shown = shown.slice(0, 3)
		shown.append("…")
	var label := Label.new()
	label.text = "%s  ·  %s" % [str(group["archetype"]).capitalize(), " / ".join(shown)]
	label.add_theme_font_size_override("font_size", PszStyle.FONT_TAB)
	label.add_theme_color_override("font_color", PszStyle.TEXT_HIGHLIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	return label


func _row_pill(row: Dictionary, selected: bool) -> PanelContainer:
	var badges: Array = []
	if bool(row["is_rare"]):
		badges.append("Rare")
	var right: String = " · ".join(badges) if not badges.is_empty() else str(row["element"])
	return PszStyle.shop_row(str(row["name"]), right, {"selected": selected})


## The selected enemy's detail card — element, HP, areas, archetype, and its
## attack kinds (the delivery behaviors the 1:1 run is about to exercise).
func _refresh_detail() -> void:
	if not is_instance_valid(_detail_panel):
		return
	PszStyle.clear_detail_panel(_detail_panel)
	if _selected_index < 0 or _selected_index >= _rows.size():
		return
	var row: Dictionary = _rows[_selected_index]
	var kinds: Array = row["kinds"]
	kinds.sort()
	var areas: Array = row["areas"]
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.add_child(PszStyle.detail_label(str(row["name"]), PszStyle.TITLE_BG))
	vbox.add_child(PszStyle.detail_label("Element: %s" % str(row["element"])))
	vbox.add_child(PszStyle.detail_label("HP: %d" % int(row["hp"])))
	vbox.add_child(PszStyle.detail_label("Found in: %s" % ", ".join(PackedStringArray(areas))))
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
		_nav = NavRepeat.new(["ui_up", "ui_down", "ui_left", "ui_right"], _on_nav_repeat)
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

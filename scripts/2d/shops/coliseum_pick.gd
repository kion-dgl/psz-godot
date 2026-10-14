extends Control
## Coliseum Master — debug enemy lab (kion): pick any enemy from the roster and
## warp alone with it into the coliseum arena (stage s00a_nr2) for 1:1 combat
## testing, the in-game counterpart of the #/enemy-room web tool. Normal enemies
## and bosses sit on separate tabs; within a tab rows group by area and
## show model, attribute, and behavior (kion playtest). The shell quest
## (`debug_coliseum`) provides the session/report frame; ColiseumRoster builds
## the synthesized 1:1 field sections (one enemy + a room-clear telepipe home).

const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")
const FIELD_SCENE := "res://scenes/3d/field/valley_field.tscn"
const SHELL_QUEST_ID := "debug_coliseum"
const TrapTests := preload("res://scripts/2d/shops/coliseum_traps.gd")
const TAB_NAMES := ["Enemies", "Bosses", "Mixed Groups", "Traps"]
const TAB_COUNT := 4

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
	_setup_level_controls()
	hint_label.text = "↑↓ Select  ←→ Tab  Enter Battle\nP / LB: Player Lv  E / RB: Enemy Lv  Esc Leave"
	_load_tab(0)


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(_active_modal):
		if event.is_action_pressed("palette_swap") or (event is InputEventKey and event.pressed and event.keycode == KEY_P):
			_edit_level(true)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("quest_log") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
			_edit_level(false)
			get_viewport().set_input_as_handled()
			return
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
	if row.has("trap_kind"):
		ShopNav.confirm(self, "Test %s?\nThe return telepipe is available immediately." % str(row.name),
			func() -> void: _start_battle(row))
		return
	var place := "the coliseum"
	if not str(row.get("quest_id", "")).is_empty() or not (row.get("arena", {}) as Dictionary).is_empty():
		place = "its arena"
	ShopNav.confirm(self, "Battle %s Lv.%d in %s?\nPlayer Lv.%d" % [str(row["name"]), ColiseumRoster.row_level(row), place, _player_level()],
		func() -> void: _start_battle(row))


## Warp: quest session shell from the on-disk debug quest, then our synthesized
## 1:1 sections override its cells, then straight into the field (spawn at the
## arena's south entrance). goto_scene clears the shop overlay stack itself, so
## no pop is needed first.
func _start_battle(row: Dictionary) -> void:
	# Bosses with an arena quest load that quest verbatim (the scripted actions —
	# Reyburn's flight phases, arena geometry — only make sense in their own
	# stages); boss VARIATIONS (the mothers) get a synthesized solo cell in their
	# arena; everything else fights 1:1 in the coliseum.
	if row.has("trap_kind"):
		SessionManager.enter_quest(SHELL_QUEST_ID, "normal")
		SessionManager.set_field_sections(TrapTests.sections(row))
		SceneManager.goto_scene(FIELD_SCENE, ColiseumRoster.warp_data())
		return
	var quest_id := str(row.get("quest_id", ""))
	if not quest_id.is_empty():
		SessionManager.enter_quest(quest_id, "normal")
		ColiseumRoster.apply_level_override()
		var sections: Array = SessionManager.get_field_sections()
		var start_pos := str(sections[0].get("start_pos", "0,0")) if sections.size() > 0 else "0,0"
		SceneManager.goto_scene(FIELD_SCENE, {
			"current_cell_pos": start_pos, "spawn_edge": "", "keys_collected": {}})
		return
	SessionManager.enter_quest(SHELL_QUEST_ID, "normal")
	ColiseumRoster.apply_level_override()
	if not (row.get("arena", {}) as Dictionary).is_empty():
		SessionManager.set_field_sections(ColiseumRoster.make_arena_sections(row))
		SceneManager.goto_scene(FIELD_SCENE, {
			"current_cell_pos": "0,0", "spawn_edge": "", "keys_collected": {}})
		return
	SessionManager.set_field_sections(ColiseumRoster.make_sections(str(row["id"])))
	SceneManager.goto_scene(FIELD_SCENE, ColiseumRoster.warp_data())


func _load_tab(tab: int) -> void:
	_tab = wrapi(tab, 0, TAB_COUNT)
	_selected_index = 0
	if _tab == 3: _groups = TrapTests.groups()
	else: _groups = ColiseumRoster.mixed_roster() if _tab == 2 else ColiseumRoster.grouped_roster(_tab == 1)
	hint_label.text = "↑↓ Select  ←→ Tab  Enter Test  Esc Leave\nOne trap per visit · Return telepipe always available" if _tab == 3 else "↑↓ Select  ←→ Tab  Enter Battle\nP / LB: Player Lv  E / RB: Enemy Lv  Esc Leave"
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

	var list := VBoxContainer.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_child(_column_row(["Trap", ""] if _tab == 3 else ["Encounter", "Level"], true))
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
	list.add_child(scroll)
	content_panel.add_child(list)
	if selected_pill != null:
		PszStyle.scroll_selected_into_view(selected_pill)
	elif _rows.is_empty():
		var empty := Label.new()
		empty.text = "(No %s in the roster)" % TAB_NAMES[_tab].to_lower()
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(empty)
	_refresh_detail()


## Area sections remain outside the selectable row index.
func _group_header(group: Dictionary) -> Control:
	var label := Label.new()
	label.text = "%s  ·  %d" % [str(group["name"]), group["rows"].size()]
	label.add_theme_font_size_override("font_size", PszStyle.FONT_TAB)
	label.add_theme_color_override("font_color", PszStyle.TEXT_HIGHLIGHT)
	return label


func _column_row(values: Array, heading: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PszStyle.pill_style(false))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 12)
	var weights := [3.0, 1.0]
	for i in values.size():
		var label := Label.new()
		label.text = str(values[i])
		label.tooltip_text = label.text
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = weights[i]
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_size_override("font_size", PszStyle.FONT_TAB if heading else PszStyle.FONT_ITEM)
		label.add_theme_color_override("font_color", PszStyle.TEXT_HIGHLIGHT if heading else PszStyle.TEXT)
		cells.add_child(label)
	panel.add_child(cells)
	return panel


func _row_pill(row: Dictionary, selected: bool) -> PanelContainer:
	var values := [str(row["name"]), "Test" if row.has("trap_kind") else "Lv.%d" % ColiseumRoster.row_level(row)]
	var pill := _column_row(values)
	pill.add_theme_stylebox_override("panel", PszStyle.pill_style(selected))
	return pill


## The selected enemy's detail card — element, HP, areas, archetype, and its
## attack kinds (the delivery behaviors the 1:1 run is about to exercise).
func _refresh_detail() -> void:
	if not is_instance_valid(_detail_panel):
		return
	PszStyle.clear_detail_panel(_detail_panel)
	if _selected_index < 0 or _selected_index >= _rows.size():
		return
	var row: Dictionary = _rows[_selected_index]
	if row.has("trap_kind"):
		_refresh_trap_detail(row)
		return
	var kinds: Array = row["kinds"]
	kinds.sort()
	var areas: Array = row["areas"]
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.add_child(PszStyle.detail_label("%s%s  ·  Lv.%d  ·  HP: %d" % [str(row["name"]),
		" (Rare)" if bool(row["is_rare"]) else "", ColiseumRoster.row_level(row), ColiseumRoster.row_hp(row)], PszStyle.TITLE_BG))
	vbox.add_child(PszStyle.detail_label(("Enemies: %s" if _tab == 2 else "Found in: %s") % ", ".join(PackedStringArray(areas))))
	vbox.add_child(PszStyle.detail_label("Attacks: %s" % ", ".join(PackedStringArray(kinds)), PszStyle.TEXT_HIGHLIGHT))
	vbox.add_child(PszStyle.detail_label("%s · %s" % [str(row.get("element", "")).capitalize(), str(row["archetype"])]))
	if row.has("model"): vbox.add_child(PszStyle.detail_label("Model: %s" % row.model))
	_detail_panel.add_child(vbox)
	_refresh_level_controls()


func _refresh_trap_detail(row: Dictionary) -> void:
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	details.add_child(PszStyle.detail_label(str(row.name), PszStyle.TITLE_BG))
	var description := PszStyle.detail_label(str(row.hint))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(description)
	var exit_hint := PszStyle.detail_label("No enemies. Use the telepipe beside the entrance whenever you want to leave.", PszStyle.TEXT_HIGHLIGHT)
	exit_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(exit_hint)
	_detail_panel.add_child(details)
	_refresh_level_controls()


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


var _player_level_button: Button
var _enemy_level_button: Button

func _setup_level_controls() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_player_level_button = Button.new()
	_enemy_level_button = Button.new()
	for button in [_player_level_button, _enemy_level_button]:
		button.focus_mode = Control.FOCUS_NONE
		row.add_child(button)
	_player_level_button.pressed.connect(func(): _edit_level(true))
	_enemy_level_button.pressed.connect(func(): _edit_level(false))
	var body := title_label.get_parent()
	body.add_child(row)
	body.move_child(row, 1)
	_refresh_level_controls()

func _player_level() -> int:
	var character = CharacterManager.get_active_character()
	return int(character.level) if character else 1

func _refresh_level_controls() -> void:
	_player_level_button.text = "Player Lv.%d" % _player_level()
	_enemy_level_button.visible = _tab != 3
	_enemy_level_button.text = "Enemy: Auto" if ColiseumRoster.selected_enemy_level == 0 else "Enemy Lv.%d" % ColiseumRoster.selected_enemy_level

func _edit_level(player_level: bool) -> void:
	if is_instance_valid(_active_modal) or (_tab == 3 and not player_level): return
	var title := "Player Level · refills HP/PP; saved with character" if player_level else "Enemy Level · Auto uses arena defaults"
	_active_modal = DebugLevelDialog.edit(self, title,
		_player_level() if player_level else ColiseumRoster.selected_enemy_level, not player_level,
		func(level: int):
			if player_level: CharacterManager.set_debug_level(level)
			else: ColiseumRoster.selected_enemy_level = level
			_refresh_display())
	_active_modal.tree_exited.connect(func(): _active_modal = null)

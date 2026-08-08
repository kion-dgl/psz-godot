extends Control
## Warp Teleporter — PSZ-styled area selection menu.
## Supports quest mode (single area), and free-explore (unlocked areas only).

const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")

const AREAS := [
	{"id": "gurhacia", "name": "Valley"},
	{"id": "rioh", "name": "Snowfield"},
	{"id": "ozette", "name": "Wetlands"},
	{"id": "paru", "name": "Forgotten City"},
	{"id": "makara", "name": "Ruins"},
	{"id": "arca", "name": "Moon Facility"},
	{"id": "dark", "name": "Dark Shrine"},
	{"id": "tower", "name": "Eternal Tower"},
]

# PSZ palette
const BG_COLOR := Color(0.0, 0.0, 0.0, 0.5)
const PANEL_COLOR := Color(0.66, 0.80, 0.91)
const BORDER_COLOR := Color(0.48, 0.63, 0.75)
const TITLE_BG := Color(0.16, 0.16, 0.22)
const TITLE_COLOR := Color(1.0, 1.0, 1.0)
const ITEM_COLOR := Color(0.1, 0.1, 0.17)
const ITEM_BG := Color(1.0, 1.0, 1.0, 0.85)
const SELECTED_BG_A := Color(0.94, 0.63, 0.13)
const SELECTED_BG_B := Color(0.97, 0.78, 0.25)
const SELECTED_BORDER := Color(0.82, 0.5, 0.06)
const SEPARATOR_COLOR := Color(0.48, 0.63, 0.75, 0.5)
const HINT_COLOR := Color(0.1, 0.1, 0.17)
const HINT_BG := Color(1.0, 1.0, 1.0, 0.7)
const SCANLINE_COLOR := Color(0.47, 0.63, 0.78, 0.08)
const FONT_SIZE_TITLE := 16
const FONT_SIZE_ITEM := 14
const FONT_SIZE_HINT := 11

var _selected_area: int = 0
var _quest_mode: bool = false
var _quest_area_id: String = ""
var _visible_areas: Array = []
var _bg: ColorRect
var _panel: Control

# Section-selector mode: shown when a suspended field session exists, so
# the player can pick which sub-area (Valley A / E / B etc) to drop back
# into. Replaces the area list with section labels derived from each
# section's first cell.stage_id. _visible_areas entries in this mode
# carry an extra "section_idx" field; _warp_to_field branches on the
# mode to call resume_session + a section-aware goto instead of the
# normal enter_field path.
var _section_select_mode: bool = false


func _ready() -> void:
	var data: Dictionary = SceneManager.get_transition_data()
	_quest_mode = data.get("quest_mode", false)
	_quest_area_id = str(data.get("area_id", ""))
	_section_select_mode = data.get("section_select", false)

	_build_visible_areas()

	# Dim background
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	# Centered panel
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var panel_h: float = 42.0 + _visible_areas.size() * 26.0 + 34.0
	_panel.size = Vector2(280, panel_h)
	_panel.position = Vector2(-140, -panel_h * 0.5)
	add_child(_panel)

	_panel.draw.connect(_draw_panel)
	_panel.queue_redraw()


func _build_visible_areas() -> void:
	_visible_areas.clear()
	if _section_select_mode:
		_build_section_options()
	elif _quest_mode and not _quest_area_id.is_empty():
		for area in AREAS:
			if str(area["id"]) == _quest_area_id:
				_visible_areas.append(area)
				break
	else:
		# Free Roam (spec /states/quest-vs-field): list every unlocked field at
		# the sections the player has reached. A field with retained run-state
		# expands into one resume entry per visited section (Valley A, Valley E,
		# …); an untouched field gets a single fresh entry. This is what keeps
		# OTHER areas selectable after entering one — switching free fields must
		# not hide them, and each field's progress is retained per area.
		for area in AREAS:
			var aid: String = str(area["id"])
			if not _is_area_unlocked(aid):
				continue
			if SessionManager.has_free_roam_field(aid):
				var sections: Array = SessionManager.get_free_roam_field_sections(aid)
				for sidx in SessionManager.get_free_roam_visited_section_indices(aid):
					var first_stage_id: String = ""
					if sidx < sections.size():
						var cells: Array = sections[sidx].get("cells", [])
						if cells.size() > 0:
							first_stage_id = str(cells[0].get("stage_id", ""))
					_visible_areas.append({
						"id": aid,
						"name": derive_section_label(str(area["name"]), first_stage_id, sidx),
						"section_idx": sidx,
						"resume": true,
					})
			else:
				_visible_areas.append(area)


## Build the section-picker entries from the SUSPENDED session.
## Reads visited section indices from SessionManager and labels each one
## by deriving the sub-area letter (a/b/c/d/e) from the first cell's
## stage_id. e.g. s01a_sa1 → "Valley A", s01e_ia1 → "Valley E".
##
## Falls back gracefully when stage_id doesn't fit the pattern (just
## says "Section N+1") so unusual quests still produce a usable list.
func _build_section_options() -> void:
	var sections: Array = SessionManager.get_suspended_field_sections()
	var area_id: String = SessionManager.get_suspended_area_id()
	# AREA_CONFIG lives in grid_generator with the canonical display name.
	var area_name: String = ""
	for area in AREAS:
		if str(area["id"]) == area_id:
			area_name = str(area["name"])
			break
	if area_name.is_empty():
		area_name = "Field"
	for section_idx in SessionManager.get_visited_section_indices():
		if section_idx >= sections.size():
			continue
		var section: Dictionary = sections[section_idx]
		var cells: Array = section.get("cells", [])
		var first_stage_id: String = ""
		if cells.size() > 0:
			first_stage_id = str(cells[0].get("stage_id", ""))
		var label: String = derive_section_label(area_name, first_stage_id, section_idx)
		_visible_areas.append({
			"id": "section_%d" % section_idx,
			"name": label,
			"section_idx": section_idx,
		})


## Pure helper — picks the friendly label for a single section in the
## section-selector list. Pulled out as a static so the test runner can
## exercise the stage_id parsing without instantiating the scene.
##
## Stage IDs look like `s<area_num><sub_letter>_<room_code>` — e.g.
## `s01a_sa1` → sub "a", `s01e_ia1` → sub "e". Char index 3 is the sub-
## area letter when the prefix is exactly 3 chars (s + 2-digit area).
##
## Falls back to `<area_name> — Section <N+1>` when stage_id doesn't fit
## the pattern (empty, too short, doesn't start with `s`, or non-alpha
## sub-letter), so an unusual quest still renders a usable list entry.
static func derive_section_label(area_name: String, first_stage_id: String,
		section_idx: int) -> String:
	var fallback: String = "%s — Section %d" % [area_name, section_idx + 1]
	if first_stage_id.length() < 4 or first_stage_id[0] != "s":
		return fallback
	var sub_letter: String = first_stage_id.substr(3, 1).to_upper()
	if sub_letter.length() != 1 or sub_letter < "A" or sub_letter > "Z":
		return fallback
	return "%s %s" % [area_name, sub_letter]


func _is_area_unlocked(area_id: String) -> bool:
	# Testing toggle (start menu -> Debug). Deliberately separate from "Unlock
	# All Missions": that marks every quest complete, which is a save-state
	# change you then have to undo. This only affects what the warp lists.
	if DebugConfig.unlock_all_areas:
		return true
	if area_id == "gurhacia":
		return true
	# An area unlocks when a completed quest cleared it (quest.area_id == area_id).
	for completed_id in GameState.completed_missions:
		var quest: Dictionary = QuestLoader.load_quest(str(completed_id))
		if not quest.is_empty() and str(quest.get("area_id", "")) == area_id:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if _visible_areas.is_empty():
		if event.is_action_pressed("ui_cancel"):
			SceneManager.pop_scene()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected_area = wrapi(_selected_area - 1, 0, _visible_areas.size())
		_panel.queue_redraw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_area = wrapi(_selected_area + 1, 0, _visible_areas.size())
		_panel.queue_redraw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_warp_to_field()
		get_viewport().set_input_as_handled()


func _warp_to_field() -> void:
	var area: Dictionary = _visible_areas[_selected_area]
	var area_id: String = str(area["id"])

	if _section_select_mode:
		_resume_suspended_section(area)
		return
	if _quest_mode:
		SessionManager.start_accepted_quest()
		_enter_3d_field()
		return

	# Picking a different area than where a telepipe is dropped abandons that
	# pipe. Same-area picks keep it — the city-side telepipe pad still returns
	# the player to the exact drop cell; here, picking a section resumes at that
	# section's start (the player's explicit choice), so we don't force the pipe
	# cell. Cancel before enter_free_roam_field/enter_field so no stale pointer.
	if TelepipeManager.is_active() and str(TelepipeManager.get_state().get("area_id", "")) != area_id:
		TelepipeManager.cancel("area_changed")

	if bool(area.get("resume", false)) and SessionManager.has_free_roam_field(area_id):
		_resume_free_roam_field(area_id, int(area.get("section_idx", 0)))
	else:
		_enter_fresh_field(area_id)


## Section-selector: drop back into a chosen sub-area of the SUSPENDED quest
## session. resume_session restores the run; the player always lands at the
## section's own start_pos and walks from there. Cleared rooms persist via the
## hydrated section state.
func _resume_suspended_section(area: Dictionary) -> void:
	var section_idx: int = int(area.get("section_idx", 0))
	var sections: Array = SessionManager.get_suspended_field_sections()
	if section_idx >= sections.size():
		return
	# Move the suspended pointer to the picked section BEFORE resume so the
	# field controller's get_current_section() returns what the player chose.
	SessionManager._suspended_session["current_section"] = section_idx
	SessionManager.resume_session()
	_goto_field(sections[section_idx], SessionManager.get_section_state(section_idx))


## Resume a retained FREE field at the chosen section from the per-area store.
func _resume_free_roam_field(area_id: String, section_idx: int) -> void:
	SessionManager.enter_free_roam_field(area_id)
	SessionManager.set_current_section(section_idx)
	var sections: Array = SessionManager.get_field_sections()
	var section: Dictionary = sections[section_idx] if section_idx < sections.size() else sections[0]
	_goto_field(section, SessionManager.get_section_state(section_idx))


## Start a fresh expedition into a free field (hand-authored quest or generated).
##
## NOT yet switched to always-generate. GridGenerator cannot currently build
## these areas: it never rotates a room while laying the main path, only accepts
## rooms with exactly two doors in their authored orientation, and _validate_gates
## then rejects any room with a door facing an empty grid cell. All 200 attempts
## fail for every area and section, and the fallback is a fixed 5-room line with
## no objects — so generating here today would be strictly worse than replaying
## the static field. See the PR for the diagnosis.
func _enter_fresh_field(area_id: String) -> void:
	SessionManager.enter_field(area_id, "normal")
	var quest := QuestLoader.pick_field_quest(area_id)
	var sections: Array
	if not quest.is_empty() and quest.has("sections"):
		sections = quest["sections"]
	else:
		sections = GridGenerator.new().generate_field("normal", area_id)["sections"]
	SessionManager.set_field_sections(sections)
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
		"current_cell_pos": str(sections[0]["start_pos"]),
		"spawn_edge": "",
		"keys_collected": {},
	})


## Load the field scene at a section's start, hydrating its saved cell state
## (keys / gates / visited / cell_states) so cleared rooms stay cleared.
func _goto_field(section: Dictionary, section_state: Dictionary) -> void:
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
		"current_cell_pos": str(section.get("start_pos", "")),
		"spawn_edge": "",
		"keys_collected": section_state.get("keys_collected", {}),
		"gates_opened": section_state.get("gates_opened", {}),
		"visited_cells": section_state.get("visited_cells", {}),
		"cell_states": section_state.get("cell_states", {}),
	})


func _enter_3d_field() -> void:
	var session: Dictionary = SessionManager.get_session()
	var field_area_id: String = str(session.get("area_id", "gurhacia"))
	var sections: Array = SessionManager.get_field_sections()

	if sections.is_empty():
		SceneManager.goto_scene("res://scenes/2d/field.tscn")
		return

	if GridGenerator.AREA_CONFIG.has(field_area_id):
		var section_idx: int = SessionManager.get_current_section()
		var section: Dictionary = sections[section_idx] if section_idx < sections.size() else sections[0]
		SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
			"current_cell_pos": str(section.get("start_pos", "")),
			"spawn_edge": "",
			"keys_collected": {},
		})
	else:
		SceneManager.goto_scene("res://scenes/2d/field.tscn")


func _draw_panel() -> void:
	var font := ThemeDB.fallback_font
	var pw: float = _panel.size.x
	var ph: float = _panel.size.y
	var rect := Rect2(Vector2.ZERO, _panel.size)
	var pad := 12.0

	# Panel background — pale icy blue
	_panel.draw_rect(rect, PANEL_COLOR)
	_panel.draw_rect(rect, BORDER_COLOR, false, 2.0)

	# Scanline overlay
	for sy in range(0, int(ph), 4):
		_panel.draw_rect(Rect2(0, sy + 2, pw, 2), SCANLINE_COLOR)

	# Title bar — dark navy
	var title_h := 32.0
	_panel.draw_rect(Rect2(0, 0, pw, title_h), TITLE_BG)
	_panel.draw_string(font, Vector2(pad, 22.0), "Warp Teleporter",
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_TITLE, TITLE_COLOR)

	# Area list
	var y := title_h + 10.0
	var item_h := 26.0
	for i in range(_visible_areas.size()):
		var area: Dictionary = _visible_areas[i]
		var area_name: String = str(area["name"])
		var item_rect := Rect2(pad - 2.0, y, pw - (pad - 2.0) * 2, item_h - 3.0)

		if i == _selected_area:
			_panel.draw_rect(item_rect, SELECTED_BG_A)
			_panel.draw_rect(Rect2(item_rect.position.x + item_rect.size.x * 0.5,
				item_rect.position.y, item_rect.size.x * 0.5, item_rect.size.y), SELECTED_BG_B)
			_panel.draw_rect(item_rect, SELECTED_BORDER, false, 2.0)
		else:
			_panel.draw_rect(item_rect, ITEM_BG)
			_panel.draw_rect(item_rect, Color(0.59, 0.71, 0.82, 0.4), false, 1.0)

		_panel.draw_string(font, Vector2(pad + 8.0, y + 17.0), area_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_ITEM, ITEM_COLOR)
		y += item_h

	# Hint bar at bottom
	var hint := "Select a destination."
	var hint_rect := Rect2(pad - 2.0, ph - 24.0, pw - (pad - 2.0) * 2, 20.0)
	_panel.draw_rect(hint_rect, HINT_BG)
	var hint_w: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_HINT).x
	_panel.draw_string(font, Vector2((pw - hint_w) * 0.5, ph - 10.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_HINT, HINT_COLOR)

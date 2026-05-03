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
]

## Story mission that must be completed to unlock each warp area.
const AREA_UNLOCK_MISSIONS := {
	"rioh": "waltz_of_rage",
	"ozette": "devilish_return",
	"paru": "a_small_friend",
	"makara": "fallen_flowers",
	"arca": "ana_s_request",
	"dark": "mother_s_memory",
}

## Display area name → area_id mapping (for quest-based unlock checks).
const AREA_NAME_TO_ID := {
	"Valley": "gurhacia",
	"Snowfield": "rioh",
	"Wetlands": "ozette",
	"Forgotten City": "paru",
	"Ruins": "makara",
	"Moon Facility": "arca",
	"Dark Shrine": "dark",
}

# PSZ palette (matches field_pause_menu.gd)
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
		for area in AREAS:
			if _is_area_unlocked(str(area["id"])):
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
		var label: String = "%s — Section %d" % [area_name, section_idx + 1]
		# Try to extract a sub-area letter from the first cell's stage_id.
		# Stage IDs look like s<area_num><sub_letter>_<room_code> — for
		# example "s01a_sa1" → sub "a", "s01e_ia1" → sub "e". Char index
		# 3 is the sub-area letter when the prefix is 3 chars long.
		var cells: Array = section.get("cells", [])
		if cells.size() > 0:
			var stage_id: String = str(cells[0].get("stage_id", ""))
			if stage_id.length() >= 4 and stage_id[0] == "s":
				var sub_letter: String = stage_id.substr(3, 1).to_upper()
				if sub_letter.length() == 1 and sub_letter >= "A" and sub_letter <= "Z":
					label = "%s %s" % [area_name, sub_letter]
		_visible_areas.append({
			"id": "section_%d" % section_idx,
			"name": label,
			"section_idx": section_idx,
		})


func _is_area_unlocked(area_id: String) -> bool:
	if area_id == "gurhacia":
		return true
	# Check story mission unlock
	var mission_id: String = AREA_UNLOCK_MISSIONS.get(area_id, "")
	if not mission_id.is_empty() and GameState.is_mission_completed(mission_id):
		return true
	for completed_id in GameState.completed_missions:
		# Check story missions by area name
		var mission = MissionRegistry.get_mission(str(completed_id))
		if mission and AREA_NAME_TO_ID.get(mission.area, "") == area_id:
			return true
		# Check guild quests by area_id
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

	# Section-selector path: pick which sub-area of the suspended session
	# to drop back into. resume_session restores the session, then
	# get_section_state hydrates the cell_states / keys / gates for the
	# chosen section so cleared rooms stay cleared. Player always lands
	# at the section's own start_pos — they walk from there to wherever
	# their telepipe is, or to the next gate, etc.
	if _section_select_mode:
		var section_idx: int = int(area.get("section_idx", 0))
		var sections: Array = SessionManager.get_suspended_field_sections()
		if section_idx >= sections.size():
			return
		var section: Dictionary = sections[section_idx]
		# Move the suspended session's current_section pointer to the
		# selected one BEFORE resume_session, so the field controller's
		# get_current_section() returns what the player picked.
		SessionManager._suspended_session["current_section"] = section_idx
		SessionManager.resume_session()
		var section_state: Dictionary = SessionManager.get_section_state(section_idx)
		SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
			"current_cell_pos": str(section.get("start_pos", "")),
			"spawn_edge": "",
			"keys_collected": section_state.get("keys_collected", {}),
			"gates_opened": section_state.get("gates_opened", {}),
			"visited_cells": section_state.get("visited_cells", {}),
			"cell_states": section_state.get("cell_states", {}),
		})
		return

	if _quest_mode:
		SessionManager.start_accepted_quest()
		_enter_3d_field()
		return

	# Telepipe resume: if the player has a suspended session AND picked the
	# same area where their telepipe is dropped, resume that session and
	# restore the saved cell state instead of starting a fresh expedition.
	# This is what makes "drop telepipe → city → city teleporter → same
	# area" preserve cleared rooms (issue #103). The telepipe stays active
	# and gets re-spawned in its original cell by the field controller.
	print("[TelepipeDEBUG] warp_to_field area=%s tp_active=%s suspended=%s" % [
		area_id, str(TelepipeManager.is_active()), str(SessionManager.has_suspended_session())])
	if TelepipeManager.is_active():
		var tp_state: Dictionary = TelepipeManager.get_state()
		print("[TelepipeDEBUG]   tp_state area=%s section=%d cell=%s" % [
			str(tp_state.get("area_id", "?")),
			int(tp_state.get("section_idx", -1)),
			str(tp_state.get("cell_pos", "?"))])
		if tp_state.get("area_id", "") == area_id and SessionManager.has_suspended_session():
			print("[TelepipeDEBUG]   RESUMING suspended session")
			SessionManager.resume_session()
			# Resume the cell state for the telepipe's section so the room
			# the player drops back into has the same cleared/looted state.
			var section_idx: int = int(tp_state.get("section_idx", 0))
			var section_state: Dictionary = SessionManager.get_section_state(section_idx)
			print("[TelepipeDEBUG]   restoring section %d, cell_states keys=%s, target=%s" % [
				section_idx, str(section_state.get("cell_states", {}).keys()), str(tp_state.get("cell_pos", "0,0"))])
			SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
				"current_cell_pos": str(tp_state.get("cell_pos", "0,0")),
				"spawn_edge": "",
				"keys_collected": section_state.get("keys_collected", {}),
				"gates_opened": section_state.get("gates_opened", {}),
				"visited_cells": section_state.get("visited_cells", {}),
				"cell_states": section_state.get("cell_states", {}),
			})
			return
		# Different area — the telepipe (and the suspended session it points
		# at) is being abandoned. Cancel before enter_field clears section
		# states; otherwise the manager would be holding a stale pointer.
		print("[TelepipeDEBUG]   area mismatch or no suspended session, cancelling")
		TelepipeManager.cancel("area_changed")

	SessionManager.enter_field(area_id, "normal")

	# Try hand-authored field quest first, fall back to procedural generation
	var quest := QuestLoader.pick_field_quest(area_id)
	var sections: Array
	if not quest.is_empty() and quest.has("sections"):
		sections = quest["sections"]
	else:
		var gen := GridGenerator.new()
		var field: Dictionary = gen.generate_field("normal", area_id)
		sections = field["sections"]

	SessionManager.set_field_sections(sections)
	var first_section: Dictionary = sections[0]
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
		"current_cell_pos": str(first_section["start_pos"]),
		"spawn_edge": "",
		"keys_collected": {},
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

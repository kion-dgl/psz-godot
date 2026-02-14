extends Control
## Guild counter — accept missions and quests.

## Each entry: { "type": "mission"|"quest", "id": String, "name": String,
##   "area": String, "is_main": bool, "available": bool,
##   "requires": Array, "rewards": Dictionary, "quest_id": String }
var _entries: Array = []
var _selected_index: int = 0
var _selecting_difficulty: bool = false
var _selected_difficulty: int = 0

const DIFFICULTIES := ["Normal", "Hard", "Super-Hard"]

## Progression order by area
const AREA_ORDER := {
	"Gurhacia Valley": 0,
	"Rioh Snowfield": 1,
	"Ozette Wetland": 2,
	"Oblivion City Paru": 3,
	"Makura Ruins": 4, "Makara Ruins": 4,
	"Arca Plant": 5,
	"Dark Shrine": 6,
	"Eternal Tower": 7,
}

## area_id → display area name
const AREA_DISPLAY := {
	"gurhacia": "Gurhacia Valley",
	"rioh": "Rioh Snowfield",
	"ozette": "Ozette Wetland",
	"paru": "Oblivion City Paru",
	"makara": "Makara Ruins",
	"arca": "Arca Plant",
	"dark": "Dark Shrine",
	"tower": "Eternal Tower",
}

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var list_panel: PanelContainer = $Panel/VBox/HBox/ListPanel
@onready var detail_panel: PanelContainer = $Panel/VBox/HBox/DetailPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	title_label.text = "GUILD COUNTER"
	hint_label.text = "[↑/↓] Select  [ENTER] Accept  [ESC] Leave"
	_load_entries()
	_refresh_display()
	# Show quest status hints
	if SessionManager.has_completed_quest():
		var cq: Dictionary = SessionManager.get_completed_quest()
		hint_label.text = "Quest \"%s\" complete! Press ENTER to report." % str(cq.get("name", ""))


func _has_active_quest() -> bool:
	return SessionManager.has_accepted_quest() or SessionManager.has_suspended_session() \
		or SessionManager.has_completed_quest()


func _load_entries() -> void:
	_entries.clear()

	# When a quest is active, only show report or cancel — no other entries
	if SessionManager.has_completed_quest():
		var cq: Dictionary = SessionManager.get_completed_quest()
		_entries.append({
			"type": "report",
			"id": str(cq.get("quest_id", "")),
			"name": "Report: %s" % str(cq.get("name", "Quest")),
			"area": "",
			"is_main": false,
			"requires": [],
			"rewards": {},
			"available": true,
		})
		return

	if SessionManager.has_accepted_quest() or SessionManager.has_suspended_session():
		var quest_name := ""
		if SessionManager.has_accepted_quest():
			quest_name = str(SessionManager.get_accepted_quest().get("name", "Quest"))
		else:
			quest_name = str(SessionManager._suspended_session.get("quest_id", "Quest"))
		_entries.append({
			"type": "cancel",
			"id": "",
			"name": "Cancel Quest: %s" % quest_name,
			"area": "",
			"is_main": false,
			"requires": [],
			"rewards": {},
			"available": true,
		})
		return

	# Normal mode — load missions and quests
	var missions := MissionRegistry.get_all_missions()
	missions.sort_custom(func(a, b):
		var aa: int = AREA_ORDER.get(a.area, 99)
		var ab: int = AREA_ORDER.get(b.area, 99)
		if aa != ab: return aa < ab
		if a.is_main != b.is_main: return a.is_main
		return a.name < b.name
	)
	for mission in missions:
		_entries.append({
			"type": "mission",
			"id": mission.id,
			"name": mission.name,
			"area": mission.area,
			"is_main": mission.is_main,
			"requires": mission.requires,
			"rewards": mission.rewards,
		})

	# Load quests
	var quest_ids := QuestLoader.list_quests()
	for qid in quest_ids:
		var quest := QuestLoader.load_quest(qid)
		if quest.is_empty():
			continue
		var area_id: String = quest.get("area_id", "gurhacia")
		_entries.append({
			"type": "quest",
			"id": qid,
			"quest_id": qid,
			"name": quest.get("name", qid),
			"description": quest.get("description", ""),
			"area": AREA_DISPLAY.get(area_id, area_id),
			"is_main": false,
			"requires": [],
			"rewards": {},
		})

	_update_availability()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _selecting_difficulty:
			_selecting_difficulty = false
			_refresh_display()
		else:
			SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		if _selecting_difficulty:
			_selected_difficulty = wrapi(_selected_difficulty - 1, 0, DIFFICULTIES.size())
		else:
			_selected_index = wrapi(_selected_index - 1, 0, maxi(_entries.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if _selecting_difficulty:
			_selected_difficulty = wrapi(_selected_difficulty + 1, 0, DIFFICULTIES.size())
		else:
			_selected_index = wrapi(_selected_index + 1, 0, maxi(_entries.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _selecting_difficulty:
			_accept_entry()
		elif not _entries.is_empty() and _selected_index < _entries.size():
			var entry_type: String = str(_entries[_selected_index]["type"])
			if entry_type == "report":
				_report_quest()
				return
			elif entry_type == "cancel":
				SessionManager.cancel_accepted_quest()
				hint_label.text = "Quest cancelled."
				_selected_index = 0
				_load_entries()
				_refresh_display()
				return
			else:
				_selecting_difficulty = true
				_selected_difficulty = 0
		_refresh_display()
		get_viewport().set_input_as_handled()


func _update_availability() -> void:
	for i in range(_entries.size()):
		var entry: Dictionary = _entries[i]
		if entry["type"] == "quest":
			entry["available"] = true
			continue
		# Mission availability logic
		var requires: Array = entry["requires"]
		if requires.is_empty():
			var area_idx: int = AREA_ORDER.get(entry["area"], 0)
			if area_idx == 0:
				entry["available"] = true
			else:
				var prev_completed := false
				for e in _entries:
					if e["type"] != "mission":
						continue
					var e_area: int = AREA_ORDER.get(e["area"], 99)
					if e_area == area_idx - 1 and GameState.is_mission_completed(e["id"]):
						prev_completed = true
						break
				entry["available"] = prev_completed
		else:
			var all_met := true
			for req in requires:
				if not GameState.is_mission_completed(req):
					all_met = false
					break
			entry["available"] = all_met


func _accept_entry() -> void:
	if _entries.is_empty() or _selected_index >= _entries.size():
		return
	var entry: Dictionary = _entries[_selected_index]
	if entry["type"] == "report":
		_report_quest()
		return
	if not entry.get("available", true):
		hint_label.text = "Mission locked! Complete earlier missions first."
		_selecting_difficulty = false
		_refresh_display()
		return
	var difficulty: String = DIFFICULTIES[_selected_difficulty].to_lower().replace(" ", "-")
	if entry["type"] == "quest":
		# Block if another quest is already active
		if _has_active_quest():
			hint_label.text = "Complete your current quest first."
			_selecting_difficulty = false
			_refresh_display()
			return
		# Accept quest — don't start session yet, player must walk to warp
		var area_id: String = AREA_DISPLAY.keys()[AREA_DISPLAY.values().find(entry["area"])] \
			if AREA_DISPLAY.values().has(entry["area"]) else "gurhacia"
		SessionManager.accept_quest(entry["quest_id"], difficulty)
		hint_label.text = "Quest accepted! Head to %s warp." % entry["area"]
		_selecting_difficulty = false
		_refresh_display()
		# Brief delay then pop back to city
		await get_tree().create_timer(1.5).timeout
		SceneManager.pop_scene()
	else:
		# Missions go directly to field as before
		SessionManager.enter_mission(entry["id"], difficulty)
		SceneManager.goto_scene("res://scenes/2d/field.tscn")


func _report_quest() -> void:
	var data: Dictionary = SessionManager.report_quest()
	if data.is_empty():
		return
	# Mark quest completed in GameState
	var quest_id: String = str(data.get("quest_id", ""))
	if not quest_id.is_empty():
		GameState.complete_mission(quest_id)
	# Show completion message
	hint_label.text = "Quest complete! EXP: %d  Meseta: %d" % [
		int(data.get("total_exp", 0)), int(data.get("total_meseta", 0))]
	_selected_index = 0
	_selecting_difficulty = false
	_load_entries()
	_refresh_display()


func _refresh_display() -> void:
	for child in list_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected_control: Control = null

	if _selecting_difficulty and not _entries.is_empty():
		var entry: Dictionary = _entries[_selected_index]
		var header := Label.new()
		header.text = "── %s ──\n\nSelect Difficulty:" % entry["name"]
		header.add_theme_color_override("font_color", ThemeColors.HEADER)
		vbox.add_child(header)

		for i in range(DIFFICULTIES.size()):
			var label := Label.new()
			if i == _selected_difficulty:
				label.text = "> " + DIFFICULTIES[i]
				label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
				selected_control = label
			else:
				label.text = "  " + DIFFICULTIES[i]
			vbox.add_child(label)
		hint_label.text = "[↑/↓] Select Difficulty  [ENTER] Accept  [ESC] Back"
	else:
		if _entries.is_empty():
			var empty := Label.new()
			empty.text = "  (No missions available)"
			empty.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
			vbox.add_child(empty)
		else:
			var last_area := ""
			for i in range(_entries.size()):
				var entry: Dictionary = _entries[i]
				# Area headers
				var area: String = entry["area"]
				if area != last_area:
					if not last_area.is_empty():
						var spacer := Label.new()
						spacer.text = ""
						vbox.add_child(spacer)
					var area_header := Label.new()
					area_header.text = "── %s ──" % area
					area_header.add_theme_color_override("font_color", ThemeColors.HEADER)
					vbox.add_child(area_header)
					last_area = area
				var label := Label.new()
				var unlocked: bool = entry.get("available", true)
				var entry_type: String = str(entry["type"])
				var completed: bool = entry_type == "mission" and GameState.is_mission_completed(entry["id"])
				var status_tag: String = ""
				if entry_type == "report":
					status_tag = " [REPORT]"
				elif entry_type == "cancel":
					status_tag = ""
				elif entry_type == "quest":
					status_tag = " [QUEST]"
				elif completed:
					status_tag = " [CLEAR]"
				elif not unlocked:
					status_tag = " [LOCKED]"
				label.text = "%-24s%s" % [entry["name"], status_tag]
				if i == _selected_index:
					label.text = "> " + label.text
					label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
					selected_control = label
				else:
					label.text = "  " + label.text
					if entry_type == "report":
						label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
					elif entry_type == "cancel":
						label.add_theme_color_override("font_color", ThemeColors.DANGER)
					elif not unlocked:
						label.add_theme_color_override("font_color", ThemeColors.TEXT_SECONDARY)
					elif completed:
						label.add_theme_color_override("font_color", ThemeColors.COMPLETED)
					elif entry_type == "quest":
						label.add_theme_color_override("font_color", ThemeColors.QUEST)
				vbox.add_child(label)
		hint_label.text = "[↑/↓] Select  [ENTER] Choose  [ESC] Leave"

	scroll.add_child(vbox)
	list_panel.add_child(scroll)

	# Scroll to selected item after layout
	if selected_control:
		scroll.ensure_control_visible.call_deferred(selected_control)

	# Detail panel
	_refresh_detail()


func _refresh_detail() -> void:
	for child in detail_panel.get_children():
		child.queue_free()

	if _entries.is_empty() or _selected_index >= _entries.size():
		return

	var entry: Dictionary = _entries[_selected_index]
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "── %s ──" % entry["name"]
	name_label.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(name_label)

	var area_label := Label.new()
	area_label.text = "Area: %s" % entry["area"]
	vbox.add_child(area_label)

	if entry["type"] == "quest":
		var type_label := Label.new()
		type_label.text = "Type: Quest"
		type_label.add_theme_color_override("font_color", ThemeColors.QUEST)
		vbox.add_child(type_label)
		var desc: String = str(entry.get("description", ""))
		if not desc.is_empty():
			var desc_label := Label.new()
			desc_label.text = desc
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(desc_label)
	else:
		var type_label := Label.new()
		type_label.text = "Type: %s" % ("Main Story" if entry["is_main"] else "Side Quest")
		vbox.add_child(type_label)

		var requires: Array = entry["requires"]
		if not requires.is_empty():
			var req_names := PackedStringArray()
			for req_id in requires:
				var req_mission = MissionRegistry.get_mission(req_id)
				req_names.append(req_mission.name if req_mission else req_id)
			var req_label := Label.new()
			req_label.text = "Requires: %s" % ", ".join(req_names)
			req_label.add_theme_color_override("font_color", ThemeColors.DANGER)
			vbox.add_child(req_label)

		# Rewards
		var rewards: Dictionary = entry["rewards"]
		if not rewards.is_empty():
			var sep := Label.new()
			sep.text = ""
			vbox.add_child(sep)
			var rewards_header := Label.new()
			rewards_header.text = "Rewards:"
			rewards_header.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
			vbox.add_child(rewards_header)
			for diff_key in rewards:
				var reward: Dictionary = rewards[diff_key]
				var r := Label.new()
				r.text = "  %s: %s x%s, %s M" % [
					str(diff_key).capitalize(),
					str(reward.get("item", "???")),
					str(reward.get("quantity", 1)),
					str(reward.get("meseta", 0)),
				]
				vbox.add_child(r)

	detail_panel.add_child(vbox)

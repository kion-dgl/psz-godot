extends Control
## Guild counter — accept and report quests.

## Each entry: { "type": "quest"|"report"|"cancel", "id": String, "name": String,
##   "area": String, "available": bool, "quest_id": String }
var _entries: Array = []
var _selected_index: int = 0
var _selecting_difficulty: bool = false
var _selected_difficulty: int = 0

var _portrait: Control
var _active_modal: Control = null

const DIFFICULTIES := ["Normal", "Hard", "Super-Hard"]

## Quest numbering (matches GitHub issue order)
const QUEST_ORDER := {
	"search_and_rescue": 1,
	"the_paru_pact": 2,
	"apothecary_supply": 3,
	"static_in_the_snow": 4,
	"deep_ore_extraction": 5,
	"messages_from_the_past": 6,
	"native_research": 7,
	"seek_my_mentor": 8,
	"claiming_a_stake": 9,
	"poisoned_water": 10,
	"finding_ogi": 11,
	"rescue_at_makara": 12,
	"arca_plant_a": 13,
	"arca_plant_b": 14,
	"dark_shrine": 15,
}

## area_id → display area name
const AREA_DISPLAY := {
	"gurhacia": "Valley",
	"rioh": "Snowfield",
	"ozette": "Wetlands",
	"paru": "Forgotten City",
	"makara": "Ruins",
	"arca": "Moon Facility",
	"dark": "Dark Shrine",
}

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeBar/ModeLabel
@onready var list_panel: PanelContainer = $Panel/VBox/HBox/ListPanel
@onready var detail_panel: PanelContainer = $Panel/VBox/HBox/DetailPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	var _mode_bar: HBoxContainer = mode_label.get_parent()
	PszStyle.style_menu(title_label, hint_label, [list_panel, detail_panel])
	title_label.text = "Guild Counter"
	_setup_portrait()
	hint_label.text = "Up/Down: Select  Enter: Accept  Esc: Leave"
	_load_entries()
	_refresh_display()
	# Show quest status hints
	if SessionManager.has_completed_quest():
		var cq: Dictionary = SessionManager.get_completed_quest()
		hint_label.text = "Quest \"%s\" complete! Press ENTER to report." % str(cq.get("name", ""))


func _setup_portrait() -> void:
	var data := SceneManager.get_transition_data()
	var model_path: String = data.get("npc_model_path", "")
	if model_path.is_empty():
		return
	_portrait = PszStyle.setup_shop_portrait($Panel, list_panel, detail_panel, model_path)


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

	# Load numbered quests
	var quest_ids := QuestLoader.list_quests()
	for qid in quest_ids:
		if qid == "hello_quest" or qid == "manifest":
			continue
		var quest := QuestLoader.load_quest(qid)
		if quest.is_empty():
			continue
		var area_id: String = quest.get("area_id", "gurhacia")
		var display_name: String = quest.get("name", qid)
		var quest_number: int = QUEST_ORDER.get(qid, 0)
		if quest_number > 0:
			display_name = "%d. %s" % [quest_number, display_name]
		_entries.append({
			"type": "quest",
			"id": qid,
			"quest_id": qid,
			"name": display_name,
			"description": quest.get("description", ""),
			"area": AREA_DISPLAY.get(area_id, area_id),
			"is_main": false,
			"requires": [],
			"rewards": {},
			"_sort_order": quest_number,
			"available": true,
		})
	_entries.sort_custom(func(a, b):
		return a.get("_sort_order", 99) < b.get("_sort_order", 99)
	)


func _unhandled_input(event: InputEvent) -> void:
	# Modal owns input while open.
	if is_instance_valid(_active_modal):
		return
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
			# Difficulty already chosen — confirm before locking in the quest.
			_open_accept_modal()
		elif not _entries.is_empty() and _selected_index < _entries.size():
			var entry_type: String = str(_entries[_selected_index]["type"])
			if entry_type == "report":
				_open_report_modal()
				return
			elif entry_type == "cancel":
				_open_cancel_modal()
				return
			else:
				_selecting_difficulty = true
				_selected_difficulty = 0
		_refresh_display()
		get_viewport().set_input_as_handled()


func _open_accept_modal() -> void:
	if _entries.is_empty() or _selected_index >= _entries.size():
		return
	var entry: Dictionary = _entries[_selected_index]
	if entry.get("type", "") != "quest":
		_accept_entry()
		return
	# Pre-flight: don't open a confirm if we'd just bounce off "complete
	# your current quest first" or "Quest locked!".
	if not entry.get("available", true):
		hint_label.text = "Quest locked!"
		_selecting_difficulty = false
		_refresh_display()
		return
	if _has_active_quest():
		hint_label.text = "Complete your current quest first."
		_selecting_difficulty = false
		_refresh_display()
		return
	var diff_name: String = DIFFICULTIES[_selected_difficulty]
	var modal := ConfirmDialog.new()
	modal.ask("Accept %s on %s?" % [str(entry.get("name", "this quest")), diff_name])
	modal.confirmed.connect(func() -> void:
		_active_modal = null
		_accept_entry()
	)
	modal.cancelled.connect(func() -> void:
		_active_modal = null
	)
	_active_modal = modal
	add_child(modal)


func _open_report_modal() -> void:
	if _entries.is_empty() or _selected_index >= _entries.size():
		return
	var entry: Dictionary = _entries[_selected_index]
	# The report entry's name is "Report: <quest name>". Drop the prefix
	# for a cleaner prompt.
	var name_str: String = str(entry.get("name", "this quest"))
	if name_str.begins_with("Report: "):
		name_str = name_str.substr("Report: ".length())
	var modal := ConfirmDialog.new()
	modal.ask("Report %s now?" % name_str)
	modal.confirmed.connect(func() -> void:
		_active_modal = null
		_report_quest()
	)
	modal.cancelled.connect(func() -> void:
		_active_modal = null
	)
	_active_modal = modal
	add_child(modal)


func _open_cancel_modal() -> void:
	if _entries.is_empty() or _selected_index >= _entries.size():
		return
	var entry: Dictionary = _entries[_selected_index]
	var name_str: String = str(entry.get("name", "this quest"))
	if name_str.begins_with("Cancel Quest: "):
		name_str = name_str.substr("Cancel Quest: ".length())
	var modal := ConfirmDialog.new()
	modal.ask("Cancel %s? Progress will be lost." % name_str)
	modal.confirmed.connect(func() -> void:
		_active_modal = null
		SessionManager.cancel_accepted_quest()
		hint_label.text = "Quest cancelled."
		_selected_index = 0
		_load_entries()
		_refresh_display()
	)
	modal.cancelled.connect(func() -> void:
		_active_modal = null
	)
	_active_modal = modal
	add_child(modal)


func _accept_entry() -> void:
	if _entries.is_empty() or _selected_index >= _entries.size():
		return
	var entry: Dictionary = _entries[_selected_index]
	if entry["type"] == "report":
		_report_quest()
		return
	if not entry.get("available", true):
		hint_label.text = "Quest locked!"
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
		_selecting_difficulty = false
		SceneManager.pop_scene({"quest_accepted": true})


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
	# Auto-save after quest completion so progress isn't lost
	SaveManager.auto_save()
	_selected_index = 0
	_selecting_difficulty = false
	_load_entries()
	_refresh_display()


func _refresh_display() -> void:
	# List panel — pill rows
	for child in list_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	var selected_pill: Control = null

	if _selecting_difficulty and not _entries.is_empty():
		var entry: Dictionary = _entries[_selected_index]
		vbox.add_child(PszStyle.create_section_header(entry["name"]))
		vbox.add_child(PszStyle.detail_label(""))
		vbox.add_child(PszStyle.detail_label("Select Difficulty:"))

		for i in range(DIFFICULTIES.size()):
			var pill := PszStyle.create_pill(DIFFICULTIES[i], i == _selected_difficulty)
			vbox.add_child(pill)
			if i == _selected_difficulty:
				selected_pill = pill
		hint_label.text = "Up/Down: Select Difficulty  Enter: Accept  Esc: Back"
	else:
		if _entries.is_empty():
			vbox.add_child(PszStyle.create_pill("(No quests available)", false, "", PszStyle.TEXT_MUTED))
		else:
			for i in range(_entries.size()):
				var entry: Dictionary = _entries[i]
				var unlocked: bool = entry.get("available", true)
				var entry_type: String = str(entry["type"])
				var completed: bool = entry_type == "quest" and GameState.is_mission_completed(entry["id"])
				var status_tag: String = ""
				if entry_type == "report":
					status_tag = " [REPORT]"
				elif entry_type == "cancel":
					status_tag = ""
				elif completed:
					status_tag = " [CLEAR]"
				elif not unlocked:
					status_tag = " [LOCKED]"

				# Determine text color
				var text_color := Color.TRANSPARENT
				if entry_type == "report":
					text_color = PszStyle.TEXT_HIGHLIGHT
				elif entry_type == "cancel":
					text_color = PszStyle.TEXT_DANGER
				elif not unlocked:
					text_color = PszStyle.TEXT_MUTED
				elif completed:
					text_color = PszStyle.TEXT_CLEAR
				elif entry_type == "quest":
					text_color = PszStyle.TEXT_QUEST

				var pill := PszStyle.create_pill(
					entry["name"] + status_tag, i == _selected_index, "", text_color)
				vbox.add_child(pill)
				if i == _selected_index:
					selected_pill = pill
		hint_label.text = "Up/Down: Select  Enter: Choose  Esc: Leave"

	scroll.add_child(vbox)
	list_panel.add_child(scroll)

	# Scroll to selected item after layout
	if selected_pill:
		scroll.ensure_control_visible.call_deferred(selected_pill)

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

	vbox.add_child(PszStyle.detail_label(entry["name"], PszStyle.TITLE_BG))

	if not str(entry["area"]).is_empty():
		vbox.add_child(PszStyle.detail_label("Area: %s" % entry["area"]))

	vbox.add_child(PszStyle.detail_label("Type: Quest", PszStyle.TEXT_QUEST))
	var desc: String = str(entry.get("description", ""))
	if not desc.is_empty():
		var desc_label := PszStyle.detail_label(desc)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_label)

	detail_panel.add_child(vbox)


# ── Hold-to-repeat navigation (NavRepeat) ──────────────────────────────────────
var _nav: NavRepeat = null


func _process(delta: float) -> void:
	# Modal owns input + nav while open.
	if is_instance_valid(_active_modal):
		return
	if _nav == null:
		_nav = NavRepeat.new(["ui_up", "ui_down", "ui_left", "ui_right"], _on_nav_repeat)
	_nav.tick(delta)


func _on_nav_repeat(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_unhandled_input(ev)

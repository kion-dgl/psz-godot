extends Control
## Guild counter — accept and report quests.

## Each entry: { "type": "quest"|"report"|"cancel", "id": String, "name": String,
##   "area": String, "available": bool, "quest_id": String }
var _entries: Array = []
var _selected_index: int = 0

var _active_modal: Control = null

## Difficulty is hardcoded to Normal for now. The per-quest difficulty picker
## was removed (difficulty will move to character-select, PSO-GC style); the
## unlock/scaling infrastructure (GameState.unlocked_difficulties,
## enemy/drop/reward tiers) stays in place, dormant, keyed on this value.
## Spec: /states/difficulty-unlock.
const DEFAULT_DIFFICULTY := "normal"

const AREA_DISPLAY := {
	"gurhacia": "Valley",
	"rioh": "Snowfield",
	"ozette": "Wetlands",
	"paru": "Forgotten City",
	"makara": "Ruins",
	"arca": "Moon Facility",
	"eternal_tower": "Eternal Tower",
	"tower": "Eternal Tower",
	"dark": "Dark Shrine",
	"dark_shrine": "Dark Shrine",
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
	ShopPreviewSprite.attach(self, SHOP_PREVIEW_PATH)
	# Show quest status hints
	if SessionManager.has_completed_quest():
		var cq: Dictionary = SessionManager.get_completed_quest()
		hint_label.text = "Quest \"%s\" complete! Press ENTER to report." % str(cq.get("name", ""))


const SHOP_PREVIEW_PATH := "res://assets/ui/shop-previews/quest-counter.png"


func _setup_portrait() -> void:
	PszStyle.setup_shop_portrait($Panel, detail_panel, SHOP_PREVIEW_PATH)


func _has_active_quest() -> bool:
	# Only a QUEST blocks accepting another (#359). A suspended FREE-FIELD
	# session must NOT block — leaving a free field via StartWarp suspends the
	# session (to preserve cleared rooms), and accept_quest already abandons
	# that field session (#239). Using has_suspended_session() here (any type)
	# wrongly locked the guild after a free-field trip. Same fix the cancel
	# lock got in #239; this is the accept-block path that was missed.
	return SessionManager.has_accepted_quest() or SessionManager.has_suspended_quest() \
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

	# Cancel-only lock applies to QUEST runs only — a suspended free-field
	# session falls through to the normal quest list (#239 bug 2; accepting
	# a quest abandons the field run via accept_quest).
	if SessionManager.has_accepted_quest() or SessionManager.has_suspended_quest():
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

	# Load every quest. Visibility rule (per user spec): all quests show in the
	# list; locked or beta-disabled ones are marked unavailable with a "needs"
	# annotation instead of being hidden.
	var quest_ids := QuestLoader.list_quests()
	for qid in quest_ids:
		if qid == "hello_quest" or qid == "manifest":
			continue
		var quest := QuestLoader.load_quest(qid)
		if quest.is_empty():
			continue
		var area_id: String = str(quest.get("area_id", "gurhacia"))
		var display_name: String = str(quest.get("name", qid))

		## Beta/in-progress flag — show but hard-lock
		var is_beta: bool = bool(quest.get("disabled", false))

		## Compute availability from parent_quest dependency. Wrap raw value
		## in str() because a JSON `null` lands here as the Variant null, and
		## a typed `String` assignment would error.
		var available: bool = true
		var parent_raw: Variant = quest.get("parent_quest", "")
		var parent_id: String = str(parent_raw) if parent_raw != null else ""
		var parent_name: String = ""
		if not parent_id.is_empty():
			available = GameState.is_mission_completed(parent_id)
			var parent_quest: Dictionary = QuestLoader.load_quest(parent_id)
			parent_name = str(parent_quest.get("name", parent_id))

		## Also enforce hard-lock required_quests
		var required_quests: Array = quest.get("required_quests", [])
		for req_id in required_quests:
			if not GameState.is_mission_completed(str(req_id)):
				available = false
				var req_quest: Dictionary = QuestLoader.load_quest(str(req_id))
				var req_name: String = str(req_quest.get("name", req_id))
				if not parent_name.is_empty():
					parent_name += ", \"%s\"" % req_name
				else:
					parent_name = "\"%s\"" % req_name

		# Beta/in-progress overrides availability and replaces the parent note.
		if is_beta:
			available = false
			parent_name = "in-progress build"

		_entries.append({
			"type": "quest",
			"id": qid,
			"quest_id": qid,
			"name": display_name,
			"description": str(quest.get("description", "")),
			"area": AREA_DISPLAY.get(area_id, area_id),
			"is_main": false,
			"requires": [],
			"rewards": {},
			"_parent_id": parent_id,
			"available": available,
			"parent_name": parent_name,
		})
	_entries = _manifest_sort_entries(_entries)


## Order quest entries by manifest.json position — the manifest is the
## canonical progression order (search_and_rescue → ... → dark_castle).
## Non-quest entries (report/cancel) stay at the front in their original
## order. Quests missing from the manifest are appended at the end.
func _manifest_sort_entries(entries: Array) -> Array:
	var manifest_order := {}
	var fa := FileAccess.open("res://data/quests/manifest.json", FileAccess.READ)
	if fa:
		var j := JSON.new()
		if j.parse(fa.get_as_text()) == OK and j.data is Array:
			var arr: Array = j.data
			for i in range(arr.size()):
				manifest_order[str(arr[i])] = i
	var passthrough: Array = []
	var quest_entries: Array = []
	for e in entries:
		if e.get("type", "") != "quest":
			passthrough.append(e)
		else:
			quest_entries.append(e)
	# Stable sort by manifest position; missing entries go to the end.
	var unknown_index := manifest_order.size()
	quest_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ai: int = int(manifest_order.get(str(a.get("quest_id", "")), unknown_index))
		var bi: int = int(manifest_order.get(str(b.get("quest_id", "")), unknown_index))
		return ai < bi
	)
	var result: Array = passthrough.duplicate()
	result.append_array(quest_entries)
	return result


func _unhandled_input(event: InputEvent) -> void:
	# Modal owns input while open.
	if is_instance_valid(_active_modal):
		return
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected_index = wrapi(_selected_index - 1, 0, maxi(_entries.size(), 1))
		_refresh_display()
		SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_index = wrapi(_selected_index + 1, 0, maxi(_entries.size(), 1))
		_refresh_display()
		SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if not _entries.is_empty() and _selected_index < _entries.size():
			var entry_type: String = str(_entries[_selected_index]["type"])
			if entry_type == "report":
				_open_report_modal()
				return
			elif entry_type == "cancel":
				_open_cancel_modal()
				return
			else:
				# Quest: confirm directly — difficulty is implied Normal now.
				_open_accept_modal()
				return
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
		_refresh_display()
		return
	if _has_active_quest():
		hint_label.text = "Complete your current quest first."
		_refresh_display()
		return
	var modal := ConfirmDialog.new()
	modal.ask("Accept %s?" % str(entry.get("name", "this quest")))
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
		_refresh_display()
		return
	if entry["type"] == "quest":
		# Block if another quest is already active
		if _has_active_quest():
			hint_label.text = "Complete your current quest first."
			_refresh_display()
			return
		# Accept quest — don't start session yet, player must walk to warp.
		# Difficulty is implied Normal (picker removed; see DEFAULT_DIFFICULTY).
		SessionManager.accept_quest(entry["quest_id"], DEFAULT_DIFFICULTY)
		SceneManager.pop_scene({"quest_accepted": true})


func _report_quest() -> void:
	var data: Dictionary = SessionManager.report_quest()
	if data.is_empty():
		return
	# Mark quest completed in GameState
	var quest_id: String = str(data.get("quest_id", ""))
	if not quest_id.is_empty():
		GameState.complete_mission(quest_id)
	# SessionManager.report_quest still tracks difficulty unlocks in GameState
	# (dormant infra), but with the picker gone we don't surface the unlock
	# message — there's no Hard/Super-Hard to select yet.
	# Show completion message
	var msg := "Quest complete! EXP: %d  Meseta: %d" % [
		int(data.get("total_exp", 0)), int(data.get("total_meseta", 0))]
	msg += _format_rewards(data.get("rewards_granted", {}))
	hint_label.text = msg
	# Auto-save after quest completion so progress isn't lost
	SaveManager.auto_save()
	_selected_index = 0
	_load_entries()
	_refresh_display()


## Render the rewards_granted dict from SessionManager.report_quest as a
## hint-label suffix, e.g. "  Reward: 100 Meseta, Monomate x2".
func _format_rewards(granted: Dictionary) -> String:
	if granted.is_empty():
		return ""
	var parts: Array[String] = []
	var meseta: int = int(granted.get("meseta", 0))
	if meseta > 0:
		parts.append("%d Meseta" % meseta)
	for entry in granted.get("items", []):
		var item_id: String = str(entry.get("id", ""))
		var consumable = ConsumableRegistry.get_consumable(item_id)
		var item_name: String = str(consumable.name) if consumable else item_id.capitalize()
		parts.append("%s x%d" % [item_name, int(entry.get("quantity", 1))])
	if parts.is_empty():
		return ""
	return "  Reward: %s" % ", ".join(parts)


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
	if not entry.get("available", true):
		var parent_name: String = str(entry.get("parent_name", ""))
		if not parent_name.is_empty():
			if not desc.is_empty():
				desc += "\n\n"
			desc += "[LOCKED] Complete \"%s\" to unlock." % parent_name
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

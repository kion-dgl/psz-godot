extends Control
## Guild counter — accept and complete missions.

var _missions: Array = []
var _available: Array = []  # bool per mission — is it unlocked?
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

@onready var title_label: Label = $VBox/TitleLabel
@onready var list_panel: PanelContainer = $VBox/HBox/ListPanel
@onready var detail_panel: PanelContainer = $VBox/HBox/DetailPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "══════ GUILD COUNTER ══════"
	hint_label.text = "[↑/↓] Select  [ENTER] Accept  [ESC] Leave"
	_load_missions()
	_refresh_display()


func _load_missions() -> void:
	_missions = MissionRegistry.get_all_missions()
	# Sort by area progression, then main missions first
	_missions.sort_custom(func(a, b):
		var aa: int = AREA_ORDER.get(a.area, 99)
		var ab: int = AREA_ORDER.get(b.area, 99)
		if aa != ab: return aa < ab
		if a.is_main != b.is_main: return a.is_main
		return a.name < b.name
	)
	# Determine which missions are unlocked
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
			_selected_index = wrapi(_selected_index - 1, 0, maxi(_missions.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if _selecting_difficulty:
			_selected_difficulty = wrapi(_selected_difficulty + 1, 0, DIFFICULTIES.size())
		else:
			_selected_index = wrapi(_selected_index + 1, 0, maxi(_missions.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _selecting_difficulty:
			_accept_mission()
		else:
			_selecting_difficulty = true
			_selected_difficulty = 0
		_refresh_display()
		get_viewport().set_input_as_handled()


func _update_availability() -> void:
	_available.clear()
	# First mission in each area is always unlocked; later ones require the previous
	for i in range(_missions.size()):
		var mission = _missions[i]
		if mission.requires.is_empty():
			# No explicit requires — unlock based on previous area being completed
			var area_idx: int = AREA_ORDER.get(mission.area, 0)
			if area_idx == 0:
				_available.append(true)  # First area always available
			else:
				# Check if any mission from the previous area is completed
				var prev_completed := false
				for m in _missions:
					var m_area: int = AREA_ORDER.get(m.area, 99)
					if m_area == area_idx - 1 and GameState.is_mission_completed(m.id):
						prev_completed = true
						break
				_available.append(prev_completed)
		else:
			# Has explicit requirements
			var all_met := true
			for req in mission.requires:
				if not GameState.is_mission_completed(req):
					all_met = false
					break
			_available.append(all_met)


func _accept_mission() -> void:
	if _missions.is_empty() or _selected_index >= _missions.size():
		return
	if not _available[_selected_index]:
		hint_label.text = "Mission locked! Complete earlier missions first."
		_selecting_difficulty = false
		_refresh_display()
		return
	var mission = _missions[_selected_index]
	var difficulty: String = DIFFICULTIES[_selected_difficulty].to_lower().replace(" ", "-")
	SessionManager.enter_mission(mission.id, difficulty)
	SceneManager.goto_scene("res://scenes/2d/field.tscn")


func _refresh_display() -> void:
	for child in list_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if _selecting_difficulty and not _missions.is_empty():
		var mission = _missions[_selected_index]
		var header := Label.new()
		header.text = "── %s ──\n\nSelect Difficulty:" % mission.name
		header.modulate = Color(0, 0.733, 0.8)
		vbox.add_child(header)

		for i in range(DIFFICULTIES.size()):
			var label := Label.new()
			if i == _selected_difficulty:
				label.text = "> " + DIFFICULTIES[i]
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + DIFFICULTIES[i]
			vbox.add_child(label)
		hint_label.text = "[↑/↓] Select Difficulty  [ENTER] Accept  [ESC] Back"
	else:
		if _missions.is_empty():
			var empty := Label.new()
			empty.text = "  (No missions available)"
			empty.modulate = Color(0.333, 0.333, 0.333)
			vbox.add_child(empty)
		else:
			var last_area := ""
			for i in range(_missions.size()):
				var mission = _missions[i]
				# Area headers
				if mission.area != last_area:
					if not last_area.is_empty():
						var spacer := Label.new()
						spacer.text = ""
						vbox.add_child(spacer)
					var area_header := Label.new()
					area_header.text = "── %s ──" % mission.area
					area_header.modulate = Color(0, 0.733, 0.8)
					vbox.add_child(area_header)
					last_area = mission.area
				var label := Label.new()
				var unlocked: bool = _available[i] if i < _available.size() else true
				var completed: bool = GameState.is_mission_completed(mission.id)
				var status_tag: String = ""
				if completed:
					status_tag = " [CLEAR]"
				elif not unlocked:
					status_tag = " [LOCKED]"
				label.text = "%-24s%s" % [mission.name, status_tag]
				if i == _selected_index:
					label.text = "> " + label.text
					label.modulate = Color(1, 0.8, 0)
				else:
					label.text = "  " + label.text
					if not unlocked:
						label.modulate = Color(0.333, 0.333, 0.333)
					elif completed:
						label.modulate = Color(0.5, 0.8, 0.5)
				vbox.add_child(label)
		hint_label.text = "[↑/↓] Select  [ENTER] Choose  [ESC] Leave"

	scroll.add_child(vbox)
	list_panel.add_child(scroll)

	# Detail panel
	_refresh_detail()


func _refresh_detail() -> void:
	for child in detail_panel.get_children():
		child.queue_free()

	if _missions.is_empty() or _selected_index >= _missions.size():
		return

	var mission = _missions[_selected_index]
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "── %s ──" % mission.name
	name_label.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(name_label)

	var area_label := Label.new()
	area_label.text = "Area: %s" % mission.area
	vbox.add_child(area_label)

	var type_label := Label.new()
	type_label.text = "Type: %s" % ("Main Story" if mission.is_main else "Side Quest")
	vbox.add_child(type_label)

	if not mission.requires.is_empty():
		var req_label := Label.new()
		req_label.text = "Requires: %s" % ", ".join(PackedStringArray(mission.requires))
		req_label.modulate = Color(1, 0.267, 0.267)
		vbox.add_child(req_label)

	# Rewards
	if not mission.rewards.is_empty():
		var sep := Label.new()
		sep.text = ""
		vbox.add_child(sep)
		var rewards_header := Label.new()
		rewards_header.text = "Rewards:"
		rewards_header.modulate = Color(1, 0.8, 0)
		vbox.add_child(rewards_header)
		for diff_key in mission.rewards:
			var reward: Dictionary = mission.rewards[diff_key]
			var r := Label.new()
			r.text = "  %s: %s x%s, %s M" % [
				str(diff_key).capitalize(),
				str(reward.get("item", "???")),
				str(reward.get("quantity", 1)),
				str(reward.get("meseta", 0)),
			]
			vbox.add_child(r)

	detail_panel.add_child(vbox)

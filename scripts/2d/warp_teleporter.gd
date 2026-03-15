extends Control
## Warp Teleporter — select area and difficulty to enter the field.
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

## Story mission that must be completed to unlock each warp area.
const AREA_UNLOCK_MISSIONS := {
	"rioh": "waltz_of_rage",
	"ozette": "devilish_return",
	"paru": "a_small_friend",
	"makara": "fallen_flowers",
	"arca": "ana_s_request",
	"dark": "mother_s_memory",
	"tower": "mother_s_memory",
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
	"Eternal Tower": "tower",
}

const DIFFICULTIES := ["Normal", "Hard", "Super-Hard"]

enum Step { AREA_SELECT, DIFFICULTY_SELECT }

var _step: int = Step.AREA_SELECT
var _selected_area: int = 0
var _selected_difficulty: int = 0
var _quest_mode: bool = false
var _quest_area_id: String = ""
var _visible_areas: Array = []

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var content_panel: PanelContainer = $Panel/VBox/HBox/ContentPanel
@onready var info_panel: PanelContainer = $Panel/VBox/HBox/InfoPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	var data: Dictionary = SceneManager.get_transition_data()
	_quest_mode = data.get("quest_mode", false)
	_quest_area_id = str(data.get("area_id", ""))

	_build_visible_areas()
	title_label.text = "WARP TELEPORTER"

	# Auto-advance if only 1 area available
	if _visible_areas.size() == 1:
		_selected_area = 0
		_step = Step.DIFFICULTY_SELECT

	_refresh_display()


func _build_visible_areas() -> void:
	_visible_areas.clear()
	if _quest_mode and not _quest_area_id.is_empty():
		# Quest mode: only show the quest's target area
		for area in AREAS:
			if str(area["id"]) == _quest_area_id:
				_visible_areas.append(area)
				break
	else:
		# Free explore: show only unlocked areas
		for area in AREAS:
			if _is_area_unlocked(str(area["id"])):
				_visible_areas.append(area)


func _is_area_unlocked(area_id: String) -> bool:
	# Gurhacia is always unlocked
	if area_id == "gurhacia":
		return true
	# Check story mission unlock
	var mission_id: String = AREA_UNLOCK_MISSIONS.get(area_id, "")
	if not mission_id.is_empty() and GameState.is_mission_completed(mission_id):
		return true
	# Check quest-based unlock: completing any quest/mission for this area
	for completed_id in GameState.completed_missions:
		var mission = MissionRegistry.get_mission(str(completed_id))
		if mission and AREA_NAME_TO_ID.get(mission.area, "") == area_id:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if _visible_areas.is_empty():
		if event.is_action_pressed("ui_cancel"):
			SceneManager.pop_scene()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		if _step == Step.DIFFICULTY_SELECT:
			# If only 1 area, cancel goes back to city (not area select)
			if _visible_areas.size() == 1:
				SceneManager.pop_scene()
			else:
				_step = Step.AREA_SELECT
				_refresh_display()
		else:
			SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		if _step == Step.AREA_SELECT:
			_selected_area = wrapi(_selected_area - 1, 0, _visible_areas.size())
		else:
			_selected_difficulty = wrapi(_selected_difficulty - 1, 0, DIFFICULTIES.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if _step == Step.AREA_SELECT:
			_selected_area = wrapi(_selected_area + 1, 0, _visible_areas.size())
		else:
			_selected_difficulty = wrapi(_selected_difficulty + 1, 0, DIFFICULTIES.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _step == Step.AREA_SELECT:
			_step = Step.DIFFICULTY_SELECT
			_selected_difficulty = 0
		else:
			_warp_to_field()
		_refresh_display()
		get_viewport().set_input_as_handled()


func _warp_to_field() -> void:
	var area: Dictionary = _visible_areas[_selected_area]
	var area_id: String = str(area["id"])
	var difficulty: String = DIFFICULTIES[_selected_difficulty].to_lower().replace(" ", "-")

	if _quest_mode:
		# Start the accepted quest session, then enter field
		SessionManager.start_accepted_quest()
		_enter_3d_field()
	else:
		# Free explore
		SessionManager.enter_field(area_id, difficulty)
		var gen := GridGenerator.new()
		var field: Dictionary
		if area_id == "tower":
			field = gen.generate_tower_field(difficulty)
		else:
			field = gen.generate_field(difficulty, area_id)
		var sections: Array = field["sections"]
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


func _refresh_display() -> void:
	if _step == Step.AREA_SELECT:
		hint_label.text = "[↑/↓] Select Area  [ENTER] Choose  [ESC] Back"
		_show_area_select()
	else:
		hint_label.text = "[↑/↓] Select Difficulty  [ENTER] Warp  [ESC] Back"
		_show_difficulty_select()
	_refresh_info()


func _show_area_select() -> void:
	for child in content_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = "Select Destination"
	header.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(header)

	for i in range(_visible_areas.size()):
		var area: Dictionary = _visible_areas[i]
		var label := Label.new()
		label.text = str(area["name"])
		if i == _selected_area:
			label.text = "> " + label.text
			label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
		else:
			label.text = "  " + label.text
		vbox.add_child(label)

	content_panel.add_child(vbox)


func _show_difficulty_select() -> void:
	for child in content_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = "%s\n\nSelect Difficulty:" % str(_visible_areas[_selected_area]["name"])
	header.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(header)

	for i in range(DIFFICULTIES.size()):
		var label := Label.new()
		label.text = DIFFICULTIES[i]
		if i == _selected_difficulty:
			label.text = "> " + label.text
			label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
		else:
			label.text = "  " + label.text
		vbox.add_child(label)

	content_panel.add_child(vbox)


func _refresh_info() -> void:
	for child in info_panel.get_children():
		child.queue_free()

	if _visible_areas.is_empty():
		return

	var area: Dictionary = _visible_areas[_selected_area]
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = str(area["name"])
	name_label.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(name_label)

	var stages_label := Label.new()
	stages_label.text = "Stages: 3 (3 waves each)"
	vbox.add_child(stages_label)

	# Show enemy types
	var pool: Dictionary = EnemySpawner.get_enemy_pool(str(area["id"]))
	if not pool.is_empty():
		var sep := Label.new()
		sep.text = ""
		vbox.add_child(sep)
		var enemies_header := Label.new()
		enemies_header.text = "Enemies:"
		enemies_header.add_theme_color_override("font_color", ThemeColors.HEADER)
		vbox.add_child(enemies_header)
		for enemy_id in pool.get("common", []):
			var e := Label.new()
			e.text = "  " + enemy_id.replace("-", " ").capitalize()
			vbox.add_child(e)

	info_panel.add_child(vbox)

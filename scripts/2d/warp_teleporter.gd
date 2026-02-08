extends Control
## Warp Teleporter — select area and difficulty to enter the field.

const AREAS := [
	{"id": "gurhacia", "name": "Gurhacia Valley", "rec_level": [1, 35, 70]},
	{"id": "rioh", "name": "Rioh Snowfield", "rec_level": [10, 40, 75]},
	{"id": "ozette", "name": "Ozette Wetlands", "rec_level": [20, 45, 80]},
	{"id": "paru", "name": "Paru Waterfall", "rec_level": [30, 50, 85]},
	{"id": "makara", "name": "Makara Ruins", "rec_level": [40, 55, 90]},
	{"id": "arca", "name": "Arca Plant", "rec_level": [50, 60, 95]},
	{"id": "dark", "name": "Dark Shrine", "rec_level": [60, 70, 100]},
]

## Story mission that must be completed to unlock each warp area.
const AREA_UNLOCK_MISSIONS := {
	"gurhacia": "mayor_s_mission",
	"rioh": "waltz_of_rage",
	"ozette": "devilish_return",
	"paru": "a_small_friend",
	"makara": "fallen_flowers",
	"arca": "ana_s_request",
	"dark": "mother_s_memory",
}

const DIFFICULTIES := ["Normal", "Hard", "Super-Hard"]

enum Step { AREA_SELECT, DIFFICULTY_SELECT }

var _step: int = Step.AREA_SELECT
var _selected_area: int = 0
var _selected_difficulty: int = 0

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var content_panel: PanelContainer = $Panel/VBox/HBox/ContentPanel
@onready var info_panel: PanelContainer = $Panel/VBox/HBox/InfoPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	title_label.text = "WARP TELEPORTER"
	_refresh_display()


func _is_area_unlocked(area_id: String) -> bool:
	var mission_id: String = AREA_UNLOCK_MISSIONS.get(area_id, "")
	if mission_id.is_empty():
		return true
	return GameState.is_mission_completed(mission_id)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _step == Step.DIFFICULTY_SELECT:
			_step = Step.AREA_SELECT
			_refresh_display()
		else:
			SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		if _step == Step.AREA_SELECT:
			_selected_area = wrapi(_selected_area - 1, 0, AREAS.size())
		else:
			_selected_difficulty = wrapi(_selected_difficulty - 1, 0, DIFFICULTIES.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		if _step == Step.AREA_SELECT:
			_selected_area = wrapi(_selected_area + 1, 0, AREAS.size())
		else:
			_selected_difficulty = wrapi(_selected_difficulty + 1, 0, DIFFICULTIES.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _step == Step.AREA_SELECT:
			var area: Dictionary = AREAS[_selected_area]
			if not _is_area_unlocked(str(area["id"])):
				var mission_id: String = AREA_UNLOCK_MISSIONS.get(str(area["id"]), "")
				var mission = MissionRegistry.get_mission(mission_id)
				var mission_name: String = mission.name if mission else mission_id
				hint_label.text = "Area locked! Complete \"%s\" to unlock." % mission_name
				get_viewport().set_input_as_handled()
				return
			_step = Step.DIFFICULTY_SELECT
			_selected_difficulty = 0
		else:
			_warp_to_field()
		_refresh_display()
		get_viewport().set_input_as_handled()


func _warp_to_field() -> void:
	var area: Dictionary = AREAS[_selected_area]
	var difficulty: String = DIFFICULTIES[_selected_difficulty].to_lower().replace(" ", "-")
	SessionManager.enter_field(area["id"], difficulty)
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

	for i in range(AREAS.size()):
		var area: Dictionary = AREAS[i]
		var unlocked: bool = _is_area_unlocked(str(area["id"]))
		var label := Label.new()
		var status_tag: String = "" if unlocked else " [LOCKED]"
		var levels: Array = area["rec_level"]
		label.text = "%-24s Lv.%d+%s" % [str(area["name"]), int(levels[0]), status_tag]
		if i == _selected_area:
			label.text = "> " + label.text
			if unlocked:
				label.add_theme_color_override("font_color", ThemeColors.TEXT_HIGHLIGHT)
			else:
				label.add_theme_color_override("font_color", ThemeColors.DANGER)
		else:
			label.text = "  " + label.text
			if not unlocked:
				label.add_theme_color_override("font_color", ThemeColors.TEXT_DISABLED)
		vbox.add_child(label)

	content_panel.add_child(vbox)


func _show_difficulty_select() -> void:
	for child in content_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = "%s\n\nSelect Difficulty:" % str(AREAS[_selected_area]["name"])
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

	var area: Dictionary = AREAS[_selected_area]
	var unlocked: bool = _is_area_unlocked(str(area["id"]))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = str(area["name"])
	name_label.add_theme_color_override("font_color", ThemeColors.HEADER)
	vbox.add_child(name_label)

	if not unlocked:
		var lock_label := Label.new()
		var mission_id: String = AREA_UNLOCK_MISSIONS.get(str(area["id"]), "")
		var mission = MissionRegistry.get_mission(mission_id)
		var mission_name: String = mission.name if mission else mission_id
		lock_label.text = "Complete \"%s\" to unlock" % mission_name
		lock_label.add_theme_color_override("font_color", ThemeColors.DANGER)
		vbox.add_child(lock_label)
		info_panel.add_child(vbox)
		return

	var levels: Array = area["rec_level"]
	var level_label := Label.new()
	level_label.text = "Recommended Level:"
	vbox.add_child(level_label)
	for i in range(DIFFICULTIES.size()):
		var diff_label := Label.new()
		diff_label.text = "  %-12s Lv.%d+" % [DIFFICULTIES[i], int(levels[i])]
		vbox.add_child(diff_label)

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

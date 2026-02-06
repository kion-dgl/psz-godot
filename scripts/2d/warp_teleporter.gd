extends Control
## Warp Teleporter — select area and difficulty to enter the field.

const AREAS := [
	{"id": "gurhacia", "name": "Gurhacia Valley", "rec_level": 1},
	{"id": "rioh", "name": "Rioh Snowfield", "rec_level": 15},
	{"id": "ozette", "name": "Ozette Wetlands", "rec_level": 30},
	{"id": "paru", "name": "Paru Waterfall", "rec_level": 45},
	{"id": "makara", "name": "Makara Ruins", "rec_level": 60},
	{"id": "arca", "name": "Arca Plant", "rec_level": 75},
	{"id": "dark", "name": "Dark Shrine", "rec_level": 90},
]

const DIFFICULTIES := ["Normal", "Hard", "Super-Hard"]

enum Step { AREA_SELECT, DIFFICULTY_SELECT }

var _step: int = Step.AREA_SELECT
var _selected_area: int = 0
var _selected_difficulty: int = 0

@onready var title_label: Label = $VBox/TitleLabel
@onready var content_panel: PanelContainer = $VBox/HBox/ContentPanel
@onready var info_panel: PanelContainer = $VBox/HBox/InfoPanel
@onready var hint_label: Label = $VBox/HintLabel


func _ready() -> void:
	title_label.text = "══════ WARP TELEPORTER ══════"
	_refresh_display()


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
	header.text = "── Select Destination ──"
	header.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(header)

	for i in range(AREAS.size()):
		var area: Dictionary = AREAS[i]
		var label := Label.new()
		label.text = "%-24s Lv.%d+" % [str(area["name"]), int(area["rec_level"])]
		if i == _selected_area:
			label.text = "> " + label.text
			label.modulate = Color(1, 0.8, 0)
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
	header.text = "── %s ──\n\nSelect Difficulty:" % str(AREAS[_selected_area]["name"])
	header.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(header)

	for i in range(DIFFICULTIES.size()):
		var label := Label.new()
		label.text = DIFFICULTIES[i]
		if i == _selected_difficulty:
			label.text = "> " + label.text
			label.modulate = Color(1, 0.8, 0)
		else:
			label.text = "  " + label.text
		vbox.add_child(label)

	content_panel.add_child(vbox)


func _refresh_info() -> void:
	for child in info_panel.get_children():
		child.queue_free()

	var area: Dictionary = AREAS[_selected_area]
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "── %s ──" % str(area["name"])
	name_label.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(name_label)

	var level_label := Label.new()
	level_label.text = "Recommended Level: %d+" % int(area["rec_level"])
	vbox.add_child(level_label)

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
		enemies_header.modulate = Color(0, 0.733, 0.8)
		vbox.add_child(enemies_header)
		for enemy_id in pool.get("common", []):
			var e := Label.new()
			e.text = "  " + enemy_id.replace("-", " ").capitalize()
			vbox.add_child(e)

	info_panel.add_child(vbox)

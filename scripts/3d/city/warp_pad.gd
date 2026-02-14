extends GameElement
class_name WarpPad
## Interactive warp pad element for the warp area.
## Handles quest routing, session resume, and free-explore warp teleporter.

const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")

@export var area_id: String = ""
@export var display_name: String = ""

var _prompt_label: Label3D
var _player_ref: Node3D


func _init() -> void:
	interactable = true
	collision_size = Vector3(2, 2, 2)
	# Use the small warp model
	model_path = "special/o0s_warps.glb"


func _ready() -> void:
	super._ready()
	_setup_prompt()


func _setup_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.text = "[E] Enter %s" % display_name
	_prompt_label.font_size = 28
	_prompt_label.pixel_size = 0.01
	_prompt_label.position = Vector3(0, 2.0, 0)
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.modulate = Color(0.5, 1.0, 0.5)
	_prompt_label.outline_size = 8
	_prompt_label.outline_modulate = Color(0, 0, 0)
	_prompt_label.visible = false
	add_child(_prompt_label)


func _get_my_area() -> String:
	return SessionManager.WARP_TO_AREA.get(area_id, "")


func _process(delta: float) -> void:
	super._process(delta)
	if not (_player_ref and is_instance_valid(_player_ref)):
		_prompt_label.visible = false
		return

	var is_nearest: bool = _player_ref.get_nearest_interactable() == self
	var my_area: String = _get_my_area()

	# Determine prompt text and visibility based on quest state
	if SessionManager.has_completed_quest():
		# All pads disabled until quest is reported at guild
		_prompt_label.visible = false
		return

	if SessionManager.has_suspended_session():
		var suspended: Dictionary = SessionManager.get_session()
		# get_session returns empty when suspended — check the suspended data
		var susp_area: String = ""
		# Access internal suspended session area
		if SessionManager.has_suspended_session():
			# Resume shows on the correct pad
			var susp_session: Dictionary = SessionManager._suspended_session
			susp_area = str(susp_session.get("area_id", ""))
		if susp_area == my_area:
			_prompt_label.text = "[E] Resume Quest"
			_prompt_label.modulate = Color(0.3, 1.0, 0.3)
			_prompt_label.visible = is_nearest
		else:
			_prompt_label.visible = false
		return

	if SessionManager.has_accepted_quest():
		var quest_area: String = SessionManager.get_accepted_quest_area()
		if quest_area == my_area:
			var quest_name: String = str(SessionManager.get_accepted_quest().get("name", ""))
			_prompt_label.text = "[E] Enter %s" % quest_name
			_prompt_label.modulate = Color(0.3, 1.0, 0.3)
			_prompt_label.visible = is_nearest
		else:
			_prompt_label.visible = false
		return

	# No quest active — normal free-explore
	_prompt_label.text = "[E] Enter %s" % display_name
	_prompt_label.modulate = Color(0.5, 1.0, 0.5)
	_prompt_label.visible = is_nearest


func set_player(player: Node3D) -> void:
	_player_ref = player


func _on_interact(_player: Node3D) -> void:
	var my_area: String = _get_my_area()

	# Completed quest — pads disabled
	if SessionManager.has_completed_quest():
		return

	# Suspended session — resume if this is the right pad
	if SessionManager.has_suspended_session():
		var susp_session: Dictionary = SessionManager._suspended_session
		var susp_area: String = str(susp_session.get("area_id", ""))
		if susp_area == my_area:
			SessionManager.resume_session()
			_enter_3d_field()
		return

	# Accepted quest — start if this is the right pad
	if SessionManager.has_accepted_quest():
		var quest_area: String = SessionManager.get_accepted_quest_area()
		if quest_area == my_area:
			SessionManager.start_accepted_quest()
			_enter_3d_field()
		return

	# No quest — open warp teleporter for free-explore
	var area_controller := get_parent()
	if area_controller and area_controller.has_method("_save_player_state"):
		area_controller._save_player_state()
	SceneManager.push_scene("res://scenes/2d/warp_teleporter.tscn")


func _enter_3d_field() -> void:
	var session: Dictionary = SessionManager.get_session()
	var field_area_id: String = str(session.get("area_id", "gurhacia"))
	var sections: Array = SessionManager.get_field_sections()

	if sections.is_empty():
		# No sections (shouldn't happen for quests, fallback to 2D field)
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

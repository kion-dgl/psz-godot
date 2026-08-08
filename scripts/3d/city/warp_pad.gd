extends GameElement
class_name WarpPad
## Interactive warp pad element for the warp area.
## When area_id is empty, acts as a central pad that opens the teleporter menu.

const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")
const TeleporterDressingScript := preload("res://scripts/3d/elements/teleporter_dressing.gd")

## Layout piece whose measured uv/scroll config this pad's model wants. The
## storybook measured o0s_warpcn's two surfaces disagreeing — the glow sheet
## at offset (-2.68, 5.31) with a -0.5 u scroll over a plate at (0, 1) 2x2 —
## and that lives in data/city_teleporter.json, so read it from there rather
## than restating the numbers here.
const DRESSING_PIECE := "o0s_warpcn"

@export var area_id: String = ""
@export var display_name: String = ""

var _prompt_label: Label3D
var _player_ref: Node3D
var _is_dimmed: bool = false


func _init() -> void:
	interactable = true
	collision_size = Vector3(2, 2, 2)
	# City Warp A — the measured special_c3 pad, replacing the small
	# start-warp model this used to borrow.
	model_path = "special_c3/o0s_warpcn.glb"


func _ready() -> void:
	super._ready()
	if model:
		TeleporterDressingScript.dress_model_from_layout(model, DRESSING_PIECE)
	_setup_prompt()
	_update_dim_state()


func _setup_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.text = display_name
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


func _is_central_pad() -> bool:
	return area_id.is_empty()


func _get_my_area() -> String:
	return SessionManager.WARP_TO_AREA.get(area_id, "")


func _is_pad_active() -> bool:
	if _is_central_pad():
		return not SessionManager.has_completed_quest()
	var my_area: String = _get_my_area()
	if SessionManager.has_completed_quest():
		return false
	if SessionManager.has_suspended_session():
		var susp_area: String = str(SessionManager._suspended_session.get("area_id", ""))
		return susp_area == my_area
	if SessionManager.has_accepted_quest():
		return SessionManager.get_accepted_quest_area() == my_area
	return true  # No quest — all pads active


func _update_dim_state() -> void:
	if not model:
		return
	if _is_central_pad():
		return
	var quest_active: bool = SessionManager.has_accepted_quest() \
		or SessionManager.has_suspended_session() \
		or SessionManager.has_completed_quest()
	var should_dim: bool = quest_active and not _is_pad_active()
	if should_dim == _is_dimmed:
		return
	_is_dimmed = should_dim
	_apply_dim_materials(model, should_dim)


func _apply_dim_materials(node: Node, dim: bool) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var std_mat := mat as StandardMaterial3D
				if dim:
					var dup := std_mat.duplicate() as StandardMaterial3D
					dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					dup.albedo_color.a = 0.35
					mesh_inst.set_surface_override_material(i, dup)
				else:
					# Restore original — remove override
					mesh_inst.set_surface_override_material(i, null)
	for child in node.get_children():
		_apply_dim_materials(child, dim)


func _process(delta: float) -> void:
	super._process(delta)
	if not (_player_ref and is_instance_valid(_player_ref)):
		_prompt_label.visible = false
		return

	var is_nearest: bool = _player_ref.nearest_interactable == self

	if _is_central_pad():
		_process_central_prompt(is_nearest)
		return

	var my_area: String = _get_my_area()

	# Determine prompt text and visibility based on quest state
	if SessionManager.has_completed_quest():
		# All pads disabled until quest is reported at guild
		_prompt_label.visible = false
		return

	if SessionManager.has_suspended_session():
		# get_session returns empty when suspended — check the suspended data
		var susp_area: String = ""
		# Access internal suspended session area
		if SessionManager.has_suspended_session():
			# Resume shows on the correct pad
			var susp_session: Dictionary = SessionManager._suspended_session
			susp_area = str(susp_session.get("area_id", ""))
		if susp_area == my_area:
			_prompt_label.text = "Resume Quest"
			_prompt_label.modulate = Color(0.3, 1.0, 0.3)
			_prompt_label.visible = is_nearest
		else:
			_prompt_label.visible = false
		return

	if SessionManager.has_accepted_quest():
		var quest_area: String = SessionManager.get_accepted_quest_area()
		if quest_area == my_area:
			var quest_name: String = str(SessionManager.get_accepted_quest().get("name", ""))
			_prompt_label.text = "Enter %s" % quest_name
			_prompt_label.modulate = Color(0.3, 1.0, 0.3)
			_prompt_label.visible = is_nearest
		else:
			_prompt_label.visible = false
		return

	# No quest active — normal free-explore
	_prompt_label.text = "Enter %s" % display_name
	_prompt_label.modulate = Color(0.5, 1.0, 0.5)
	_prompt_label.visible = is_nearest


func _process_central_prompt(is_nearest: bool) -> void:
	if SessionManager.has_completed_quest():
		_prompt_label.visible = false
		return

	if SessionManager.has_suspended_session():
		_prompt_label.text = "Resume Quest"
		_prompt_label.modulate = Color(0.3, 1.0, 0.3)
		_prompt_label.visible = is_nearest
		return

	if SessionManager.has_accepted_quest():
		_prompt_label.text = "Warp Teleporter"
		_prompt_label.modulate = Color(0.3, 1.0, 0.3)
		_prompt_label.visible = is_nearest
		return

	# Free explore
	_prompt_label.text = "Warp Teleporter"
	_prompt_label.modulate = Color(0.5, 1.0, 0.5)
	_prompt_label.visible = is_nearest


func set_player(player: Node3D) -> void:
	_player_ref = player


func _on_interact(_player: Node3D) -> void:
	if _is_central_pad():
		_on_interact_central()
		return

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


func _on_interact_central() -> void:
	# Completed quest — pad disabled
	if SessionManager.has_completed_quest():
		return

	# Save player state before opening menu (covers all picker paths below)
	var area_controller := get_parent()
	if area_controller and area_controller.has_method("_save_player_state"):
		area_controller._save_player_state()

	# Suspended session — open the warp teleporter in section-selector mode
	# so the player can choose any sub-area they've visited (Valley A / E /
	# B etc) instead of being auto-routed to a single fixed cell. Spec from
	# the user: progressing through sections should ADD destinations to the
	# picker, and reset only on title return / quest accept / quest end.
	if SessionManager.has_suspended_session():
		SceneManager.push_scene("res://scenes/2d/warp_teleporter.tscn",
			{"section_select": true})
		return

	# Build transition data based on quest state
	var data := {}
	if SessionManager.has_accepted_quest():
		data = {
			"quest_mode": true,
			"area_id": SessionManager.get_accepted_quest_area(),
		}
	SceneManager.push_scene("res://scenes/2d/warp_teleporter.tscn", data)


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

		# Resume-from-suspension path: this method is reached after the warp
		# pad called SessionManager.resume_session(). Per spec, the player
		# always lands at the section's start cell — never warped directly
		# to the telepipe cell. They navigate from start back to wherever
		# their telepipe is (or wherever else they want to go) on foot.
		# State (cleared rooms, picked-up items, opened gates) must persist
		# across the round trip, so we hydrate from get_section_state.
		# An empty section_state means fresh expedition — dicts default to {}.
		var section_state: Dictionary = SessionManager.get_section_state(section_idx)
		SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
			"current_cell_pos": str(section.get("start_pos", "")),
			"spawn_edge": "",
			"keys_collected": section_state.get("keys_collected", {}),
			"gates_opened": section_state.get("gates_opened", {}),
			"visited_cells": section_state.get("visited_cells", {}),
			"cell_states": section_state.get("cell_states", {}),
		})
	else:
		SceneManager.goto_scene("res://scenes/2d/field.tscn")

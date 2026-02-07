extends GameElement
class_name WarpPad
## Interactive warp pad element for the warp area.
## Shows a prompt and opens the warp teleporter on interaction.

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


func _process(delta: float) -> void:
	super._process(delta)
	if _player_ref and is_instance_valid(_player_ref):
		_prompt_label.visible = _player_ref.get_nearest_interactable() == self
	else:
		_prompt_label.visible = false


func set_player(player: Node3D) -> void:
	_player_ref = player


func _on_interact(_player: Node3D) -> void:
	# Save position so we return to same spot after popping
	var area_controller := get_parent()
	if area_controller and area_controller.has_method("_save_player_state"):
		area_controller._save_player_state()
	SceneManager.push_scene("res://scenes/2d/warp_teleporter.tscn")

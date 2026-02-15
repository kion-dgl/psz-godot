extends Node3D
class_name StoryProp
## Static GLB prop placed in the field for story purposes (e.g., crashed dropship).
## Does not extend GameElement since it has no interaction — just loads and displays a GLB.

@export var prop_path: String = ""

var element_state: String = "default"


func _ready() -> void:
	if prop_path.is_empty():
		return

	var full_path := "res://" + prop_path
	var packed := load(full_path) as PackedScene
	if not packed:
		push_warning("StoryProp: Failed to load model: " + full_path)
		return

	var model := packed.instantiate()
	add_child(model)


func set_state(new_state: String) -> void:
	element_state = new_state

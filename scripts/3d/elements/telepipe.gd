extends GameElement
class_name Telepipe
## Interactive telepipe — player walks up and presses E to warp back to city.
## Renders as a cyan glowing cylinder placeholder.

signal activated

var _mesh: MeshInstance3D


func _init() -> void:
	interactable = true
	auto_collect = false
	collision_size = Vector3(2.0, 4.0, 2.0)
	element_state = "ready"


func _ready() -> void:
	_mesh = _build_warp_cylinder(Color(0.2, 0.8, 1.0), "TelepipeMesh")
	_setup_collision()
	_apply_state()


func _on_interact(_player: Node3D) -> void:
	print("[Telepipe] Player activated telepipe")
	activated.emit()

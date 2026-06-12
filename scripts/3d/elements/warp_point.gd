extends GameElement
class_name WarpPoint
## Debug warp point — player presses E to jump to a target section/cell.
## Renders as a purple cylinder placeholder.

signal activated

var warp_section: int = 0
var warp_cell: String = ""
var warp_position: Vector3 = Vector3.ZERO
var _mesh: MeshInstance3D


func _init() -> void:
	interactable = true
	auto_collect = false
	collision_size = Vector3(2.0, 4.0, 2.0)
	element_state = "ready"


func _ready() -> void:
	_mesh = _build_warp_cylinder(Color(0.67, 0.4, 1.0), "WarpPointMesh")
	_setup_collision()
	_apply_state()


func _on_interact(_player: Node3D) -> void:
	print("[WarpPoint] Player activated warp → section %d, cell %s, position %s" % [warp_section, warp_cell, warp_position])
	activated.emit()

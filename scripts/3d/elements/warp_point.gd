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
	_build_mesh()
	_setup_collision()
	_apply_state()


func _build_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.8
	cyl.bottom_radius = 0.8
	cyl.height = 3.0
	_mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.67, 0.4, 1.0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.67, 0.4, 1.0)
	mat.emission_energy_multiplier = 2.0
	_mesh.material_override = mat
	_mesh.name = "WarpPointMesh"
	_mesh.position.y = 1.5
	add_child(_mesh)


func _on_interact(_player: Node3D) -> void:
	print("[WarpPoint] Player activated warp → section %d, cell %s, position %s" % [warp_section, warp_cell, warp_position])
	activated.emit()

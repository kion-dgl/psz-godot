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
	mat.albedo_color = Color(0.2, 0.8, 1.0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.0
	_mesh.material_override = mat
	_mesh.name = "TelepipeMesh"
	_mesh.position.y = 1.5
	add_child(_mesh)


func _on_interact(_player: Node3D) -> void:
	print("[Telepipe] Player activated telepipe")
	activated.emit()

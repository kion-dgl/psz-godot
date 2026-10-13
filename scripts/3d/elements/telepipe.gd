extends GameElement
class_name Telepipe
## Interactive telepipe — player walks up and presses E to warp back to city.
## Low, open crown of cyan energy with a white-hot rim and rising streaks.

const ENERGY_SHADER := preload("res://scripts/3d/shaders/telepipe_energy.gdshader")
const HALO_SHADER := preload("res://scripts/3d/shaders/telepipe_halo.gdshader")

signal activated

var _mesh: MeshInstance3D


func _init() -> void:
	interactable = true
	auto_collect = false
	collision_size = Vector3(2.0, 4.0, 2.0)
	element_state = "ready"


func _ready() -> void:
	_build_effect()
	_setup_collision()
	_apply_state()


func _build_effect() -> void:
	# Uncapped sides leave the stage visible through the center of the pipe.
	var crown := CylinderMesh.new()
	crown.top_radius = 0.88
	crown.bottom_radius = 0.88
	crown.height = 1.15
	crown.radial_segments = 96
	crown.cap_top = false
	crown.cap_bottom = false
	_mesh = MeshInstance3D.new()
	_mesh.name = "TelepipeMesh"
	_mesh.mesh = crown
	_mesh.position.y = crown.height * 0.5 + 0.035
	var energy := ShaderMaterial.new()
	energy.shader = ENERGY_SHADER
	_mesh.material_override = energy
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	var halo := MeshInstance3D.new()
	halo.name = "TelepipeHalo"
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.65, 2.65)
	halo.mesh = plane
	halo.position.y = 0.025
	var glow := ShaderMaterial.new()
	glow.shader = HALO_SHADER
	halo.material_override = glow
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)


func _on_interact(_player: Node3D) -> void:
	print("[Telepipe] Player activated telepipe")
	# The autoload owns playback so the warp's scene change cannot cut it off.
	SfxManager.play("res://assets/sfx/common/common_005.wav")
	activated.emit()

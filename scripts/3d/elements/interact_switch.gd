extends GameElement
class_name InteractSwitch
## Player-activated switch that disables fences. Requires interaction to toggle.
## States: off, on

signal activated
signal deactivated

const MIRROR_SHADER = preload("res://scripts/3d/shaders/mirror_repeat.gdshader")

## Emissive color when switch is on
const ON_EMISSION_COLOR := Color(0, 1, 0)  # Green
const ON_EMISSION_ENERGY: float = 0.3

var _shader_materials: Array[ShaderMaterial] = []


func _init() -> void:
	model_path = "valley/o0c_switchs.glb"
	interactable = true
	collision_size = Vector3(1.5, 2, 1.5)
	element_state = "off"


func _ready() -> void:
	super._ready()
	_setup_mirror_materials()
	_apply_state()


func _setup_mirror_materials() -> void:
	_shader_materials.clear()
	if not model:
		return
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if std_mat.albedo_texture:
				var smat := ShaderMaterial.new()
				smat.shader = MIRROR_SHADER
				smat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
				smat.set_shader_parameter("uv_scale", Vector2(2, 1))
				smat.set_shader_parameter("mirror_x", true)
				smat.set_shader_parameter("mirror_y", false)
				mesh.set_surface_override_material(surface, smat)
				_shader_materials.append(smat)
	)


func _apply_state() -> void:
	for mat in _shader_materials:
		match element_state:
			"off":
				mat.set_shader_parameter("uv_offset", Vector2(0, 0.5))
				mat.set_shader_parameter("emission_enabled", false)
			"on":
				mat.set_shader_parameter("uv_offset", Vector2(0, 0))
				mat.set_shader_parameter("emission_enabled", true)
				mat.set_shader_parameter("emission_color", ON_EMISSION_COLOR)
				mat.set_shader_parameter("emission_energy", ON_EMISSION_ENERGY)


func _on_interact(_player: Node3D) -> void:
	toggle()


## Turn switch on
func turn_on() -> void:
	if element_state == "on":
		return
	set_state("on")
	activated.emit()
	print("[InteractSwitch] Activated")


## Turn switch off
func turn_off() -> void:
	if element_state == "off":
		return
	set_state("off")
	deactivated.emit()
	print("[InteractSwitch] Deactivated")


## Toggle switch state
func toggle() -> void:
	if element_state == "off":
		turn_on()
	else:
		turn_off()

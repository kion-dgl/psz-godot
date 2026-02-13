extends WarpBase
class_name AreaWarp
## Medium warp gate for area transitions.
## Uses o0s_warpm (medium warp) model.
## States: locked, open (shared with Gate/KeyGate)

const BEAM_TEXTURE_NAME := "fwarp2"
const RED_BEAM_TEXTURE := preload("res://assets/objects/special/red-beam.png")
const BEAM_SCROLL_SPEED := 1.35

## Mesh + surface index for the beam — always look up live material from mesh
## so it survives storybook's _fixup_materials duplicating the material.
var _beam_mesh: MeshInstance3D = null
var _beam_surface: int = -1
var _blue_texture: Texture2D = null


func _init() -> void:
	super._init()
	model_path = "special/o0s_warpm.glb"
	collision_size = Vector3(3, 4, 3)
	element_state = "locked"


func _ready() -> void:
	super._ready()
	_setup_beam_material()
	_apply_state()


func _setup_beam_material() -> void:
	if not model:
		return
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if std_mat.albedo_texture and BEAM_TEXTURE_NAME in std_mat.albedo_texture.resource_path:
				var dup := std_mat.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(surface, dup)
				_beam_mesh = mesh
				_beam_surface = surface
				_blue_texture = dup.albedo_texture
	)


## Get the live beam material from the mesh (survives external material swaps).
func _get_beam_material() -> StandardMaterial3D:
	if _beam_mesh and _beam_surface >= 0:
		return _beam_mesh.get_active_material(_beam_surface) as StandardMaterial3D
	return null


func _update_animation(delta: float) -> void:
	var mat := _get_beam_material()
	if mat:
		mat.uv1_offset.x -= BEAM_SCROLL_SPEED * delta


func _apply_state() -> void:
	# Skip WarpBase transparency — area warp stays fully opaque in both states
	var mat := _get_beam_material()
	if mat:
		match element_state:
			"locked":
				mat.albedo_texture = RED_BEAM_TEXTURE
			"open":
				mat.albedo_texture = _blue_texture

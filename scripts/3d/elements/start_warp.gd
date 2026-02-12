extends WarpBase
class_name StartWarp
## Small warp gate at stage start/end points.
## Uses o0s_warps (small warp) model.

## Animated warp surface texture identifier
const WARP_TEXTURE_NAME := "swarp3"
const WARP_SCROLL_SPEED := 1.35
const MIRROR_SHADER = preload("res://scripts/3d/shaders/mirror_repeat_alpha.gdshader")

var _warp_shader_mat: ShaderMaterial = null
var _scroll_offset: float = 0.0


func _init() -> void:
	super._init()
	model_path = "special/o0s_warps.glb"


func _ready() -> void:
	super._ready()
	_setup_warp_material()


func _setup_warp_material() -> void:
	if not model:
		return
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if std_mat.albedo_texture and WARP_TEXTURE_NAME in std_mat.albedo_texture.resource_path:
				var smat := ShaderMaterial.new()
				smat.shader = MIRROR_SHADER
				smat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
				smat.set_shader_parameter("mirror_x", true)
				smat.set_shader_parameter("mirror_y", true)
				mesh.set_surface_override_material(surface, smat)
				_warp_shader_mat = smat
	)


func _update_animation(delta: float) -> void:
	if _warp_shader_mat:
		_scroll_offset -= WARP_SCROLL_SPEED * delta
		_warp_shader_mat.set_shader_parameter("uv_offset", Vector2(0, _scroll_offset))

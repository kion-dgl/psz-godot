extends WarpBase
class_name AreaWarp
## Medium warp gate for area transitions.
## Uses o0s_warpm (medium warp) model.

## Animated warp surface texture identifier
const WARP_TEXTURE_NAME := "fwarp2"
const WARP_SCROLL_SPEED := 1.35
const MIRROR_SHADER = preload("res://scripts/3d/shaders/mirror_repeat_alpha.gdshader")

var _warp_shader_mat: ShaderMaterial = null
var _scroll_offset_x: float = 0.0
var _base_offset_y: float = 0.0


func _init() -> void:
	super._init()
	model_path = "special/o0s_warpm.glb"
	collision_size = Vector3(3, 4, 3)


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
	_apply_warp_offset()


func _apply_warp_offset() -> void:
	if element_state == "active":
		_base_offset_y = 1.34
	else:
		_base_offset_y = 0.0
	_update_shader_offset()


func _update_shader_offset() -> void:
	if _warp_shader_mat:
		_warp_shader_mat.set_shader_parameter("uv_offset", Vector2(_scroll_offset_x, _base_offset_y))


func _update_animation(delta: float) -> void:
	if _warp_shader_mat:
		_scroll_offset_x -= WARP_SCROLL_SPEED * delta
		_update_shader_offset()


func _apply_state() -> void:
	super._apply_state()
	_apply_warp_offset()

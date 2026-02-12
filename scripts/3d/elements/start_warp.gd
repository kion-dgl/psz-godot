extends WarpBase
class_name StartWarp
## Small warp gate at stage start/end points.
## Uses o0s_warps (small warp) model.

## Animated warp surface texture identifier
const WARP_TEXTURE_NAME := "swarp3"
const WARP_SCROLL_SPEED := 1.35

var _warp_material: StandardMaterial3D = null


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
				var dup := std_mat.duplicate() as StandardMaterial3D
				dup.texture_repeat = BaseMaterial3D.TEXTURE_REPEAT_MIRROR
				mesh.set_surface_override_material(surface, dup)
				_warp_material = dup
	)


func _update_animation(delta: float) -> void:
	if _warp_material:
		_warp_material.uv1_offset.y -= WARP_SCROLL_SPEED * delta

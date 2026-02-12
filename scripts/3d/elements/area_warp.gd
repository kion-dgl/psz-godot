extends WarpBase
class_name AreaWarp
## Medium warp gate for area transitions.
## Uses o0s_warpm (medium warp) model.

## Animated warp surface texture identifier
const WARP_TEXTURE_NAME := "fwarp2"
const WARP_SCROLL_SPEED := 1.35

var _warp_material: StandardMaterial3D = null


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
				var dup := std_mat.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(surface, dup)
				_warp_material = dup
	)
	_apply_warp_offset()


func _apply_warp_offset() -> void:
	if _warp_material:
		if element_state == "active":
			_warp_material.uv1_offset.y = 1.34
		else:
			_warp_material.uv1_offset.y = 0.0


func _update_animation(delta: float) -> void:
	if _warp_material:
		_warp_material.uv1_offset.x -= WARP_SCROLL_SPEED * delta


func _apply_state() -> void:
	super._apply_state()
	_apply_warp_offset()

extends WarpBase
class_name BossWarp
## Boss-arena warp — the entrance to a boss fight. Uses the large o0s_warpb (big)
## warp model instead of the medium o0s_warpm area-transition warp, so the step
## into the boss room reads as a boss warp, not just another area gate. Extends
## WarpBase directly (not AreaWarp) to avoid AreaWarp's class-scope pack-only
## red-beam preload; the goal-pad's separate GateTrigger drives the actual warp,
## so this element is purely the boss-warp visual.


func _init() -> void:
	super._init()
	model_path = "special/o0s_warpb.glb"
	collision_size = Vector3(4, 5, 4)
	auto_collect = false


## The storybook's Boss Warp texture config (web objectCatalog 'boss-warp'),
## applied the house way — duplicated StandardMaterial3D with uv1_offset and
## a per-frame scroll, exactly how warp_point/area_warp dress their surfaces.
## (A mirror-shader pass rendered the beams black: it dropped the imported
## transparency/unlit setup the beams rely on.)
##   o0s_1_bwarp2.png: offsetY 1.10, scrolling +0.40/s (the swirl)
##   o0s_0_bwarp1.png: identity
var _scroll_mats: Array[StandardMaterial3D] = []
var _scroll_base_y: float = 0.0


func _ready() -> void:
	super._ready()
	if not model:
		return
	apply_to_all_materials(func(mat, mesh: MeshInstance3D, surface: int):
		if not (mat is StandardMaterial3D):
			return
		var std := mat as StandardMaterial3D
		if not std.albedo_texture:
			return
		var tex_name := String(std.albedo_texture.resource_path).get_file()
		var offset := Vector2.ZERO
		if "o0s_1_bwarp2" in tex_name:
			offset = Vector2(0.0, 1.10)
		elif not ("o0s_0_bwarp1" in tex_name):
			return
		var dup := std.duplicate()
		dup.uv1_offset = Vector3(offset.x, offset.y, 0.0)
		mesh.set_surface_override_material(surface, dup)
		if "o0s_1_bwarp2" in tex_name:
			_scroll_mats.append(dup)
			_scroll_base_y = offset.y
	)


func _update_animation(_delta: float) -> void:
	# The swirl: bwarp2's window scrolls upward at 0.40 texture-heights per
	# second (the storybook's scrollY), wrapping through the texture.
	for mat in _scroll_mats:
		mat.uv1_offset = Vector3(0.0, _scroll_base_y + fmod(_time * 0.40, 1.0), 0.0)

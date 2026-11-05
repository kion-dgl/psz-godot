extends WarpBase
class_name BossWarp
## Boss entrance visual; the field's separate GateTrigger owns access control.
## Presentation contract: /states/field-gates/#boss-warp-presentation.

## Catalog-tuned transform (storybook "Boss Warp", mirror wrap on both axes
## for every surface). Raw units; the bake divides by the mirrored period 2.
const SCROLL_REPEAT := Vector2.ONE
const SCROLL_OFFSET := Vector2(0.0, -7.62)
const SCROLL_RAW_SPEED := -1.35
const BASE_REPEAT := Vector2(2.0, 2.0)
const BASE_OFFSET := Vector2(0.0, 1.0)
const MIRROR_PERIOD := Vector2(2.0, 2.0)

var _scroll_mat: StandardMaterial3D = null
var _scroll_time := 0.0

## Doubled mirror atlases per source texture path, shared by every instance.
static var _mirror_atlases: Dictionary = {}


func _init() -> void:
	super._init()
	model_path = "special/o0s_warpb.glb"
	collision_size = Vector3(4, 5, 4)
	auto_collect = false


func _ready() -> void:
	super._ready()
	# The standard model uses swarp3, not special_n's bwarp2. Both surfaces
	# render with plain StandardMaterial3D: the mirrored fold is baked into
	# per-vertex UVs plus a doubled mirror-atlas texture with ordinary repeat,
	# the same conversion the stage mirror bake applies (no mirror shader).
	_bake_native_materials(model)


func _apply_state() -> void:
	# WarpBase disables alpha for active/open/locked states. Preserve cutouts
	# in every state; the field controller manages the separate gate trigger.
	pass


func _update_animation(delta: float) -> void:
	if _scroll_mat == null:
		return
	_scroll_time += delta
	_scroll_mat.uv1_offset.y = (SCROLL_OFFSET.y + SCROLL_RAW_SPEED * _scroll_time) / MIRROR_PERIOD.y


## uv_baked = (uv * repeat + offset) / mirrored_period. Ordinary repeat over a
## texture doubled on both axes then reproduces the mirrored fold exactly.
func _bake_uv(uv: Vector2, repeat: Vector2, offset: Vector2) -> Vector2:
	return (uv * repeat + offset) / MIRROR_PERIOD


func _bake_native_materials(node: Node) -> void:
	for child in node.get_children():
		_bake_native_materials(child)
	if node is not MeshInstance3D:
		return
	var mesh_inst := node as MeshInstance3D
	var mesh := mesh_inst.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var baked_mesh := ArrayMesh.new()
	var edited := false
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var source := mesh_inst.get_active_material(s) as StandardMaterial3D
		if source != null and source.albedo_texture != null:
			var tex_name: String = source.albedo_texture.resource_path.get_file().get_basename()
			var repeat := Vector2.ONE
			var offset := Vector2.ZERO
			if tex_name == "o0s_1_swarp3":
				repeat = SCROLL_REPEAT
				offset = SCROLL_OFFSET
			elif tex_name == "o0s_0_bwarp1":
				repeat = BASE_REPEAT
				offset = BASE_OFFSET
			else:
				continue
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for i in uvs.size():
				uvs[i] = _bake_uv(uvs[i], repeat, offset)
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			var mat := source.duplicate() as StandardMaterial3D
			var atlas := _mirror_atlas(source.albedo_texture)
			if atlas != null:
				mat.albedo_texture = atlas
			mat.uv1_scale = Vector3.ONE
			mat.uv1_offset = Vector3.ZERO
			mat.texture_repeat = true
			mesh_inst.set_surface_override_material(s, mat)
			if tex_name == "o0s_1_swarp3":
				_scroll_mat = mat
			edited = true
		baked_mesh.add_surface_from_arrays(
			(mesh as ArrayMesh).surface_get_primitive_type(s) if mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES,
			arrays)
		if mesh is ArrayMesh:
			var built_in := (mesh as ArrayMesh).surface_get_material(s)
			if built_in != null:
				baked_mesh.surface_set_material(s, built_in)
	if edited:
		mesh_inst.mesh = baked_mesh


## Original on top-left, mirrored copies right and below: one atlas tile per
## two-texture mirror cycle, so a plain repeating sampler shows the fold.
static func _mirror_atlas(source: Texture2D) -> ImageTexture:
	var key := source.resource_path
	if _mirror_atlases.has(key):
		return _mirror_atlases[key]
	var src := source.get_image()
	if src == null or src.is_empty():
		return null
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w * 2, h * 2, false, Image.FORMAT_RGBA8)
	for y in h * 2:
		for x in w * 2:
			out.set_pixel(x, y, src.get_pixel(
				x if x < w else w * 2 - 1 - x,
				y if y < h else h * 2 - 1 - y))
	var atlas := ImageTexture.create_from_image(out)
	_mirror_atlases[key] = atlas
	return atlas

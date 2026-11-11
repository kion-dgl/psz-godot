extends RefCounted
## Imported Mag cutouts must write depth; alpha blending exposes rear faces (#795).
static var _binary_textures: Dictionary = {}

static func binary_alpha(image: Image) -> bool:
	if image == null or image.is_empty(): return false
	if image.is_compressed() and image.decompress() != OK: return false
	for y in image.get_height():
		for x in image.get_width():
			var alpha := image.get_pixel(x, y).a
			if alpha > 0.0 and alpha < 1.0: return false
	return true

static func cutout_copy(material: Material) -> Material:
	if not material is StandardMaterial3D: return material
	var source := material as StandardMaterial3D
	if source.transparency not in [BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]: return source
	if source.blend_mode != BaseMaterial3D.BLEND_MODE_MIX or source.albedo_color.a < 1.0 or source.albedo_texture == null: return source
	var texture := source.albedo_texture
	if not _binary_textures.has(texture): _binary_textures[texture] = binary_alpha(texture.get_image())
	if not _binary_textures[texture]: return source
	var fixed := source.duplicate() as StandardMaterial3D
	fixed.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fixed.alpha_scissor_threshold = 0.5
	fixed.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	return fixed

static func apply(node: Node) -> void:
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var source: Material = node.get_active_material(surface)
			var fixed := cutout_copy(source)
			if fixed != source: node.set_surface_override_material(surface, fixed)
	for child in node.get_children(): apply(child)

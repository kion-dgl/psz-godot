extends RefCounted
## Offline, topology-preserving UV/texture conversion. Runtime only loads the
## result; it never generates textures or folds UVs per frame.
const VERSION := 1
const META := "native_mirror_bake"
static var _texture_hashes: Dictionary = {}

static func eligible(fix: Dictionary, texture_path: String) -> bool:
	return (fix.get("wrapS", "repeat") == "mirror" or fix.get("wrapT", "repeat") == "mirror") \
		and not fix.get("hidden", false) and not fix.get("bakedBlend", false) \
		and not fix.has("scrollX") and not fix.has("scrollY") \
		and int(fix.get("framesY", 1)) == 1 and not "_fall" in texture_path \
		and fix.get("wrapS", "repeat") != "clamp" and fix.get("wrapT", "repeat") != "clamp"

static func period(fix: Dictionary) -> Vector2:
	return Vector2(2.0 if fix.get("wrapS", "repeat") == "mirror" else 1.0,
		2.0 if fix.get("wrapT", "repeat") == "mirror" else 1.0)

static func remap_uv(uv: Vector2, fix: Dictionary) -> Vector2:
	return (uv * Vector2(float(fix.get("repeatX", 1)), float(fix.get("repeatY", 1))) \
		+ Vector2(float(fix.get("offsetX", 0)), float(fix.get("offsetY", 0)))) / period(fix)

static func atlas_image(source: Image, fix: Dictionary) -> Image:
	var width := source.get_width()
	var height := source.get_height()
	var tile := period(fix)
	var image := Image.create(width * int(tile.x), height * int(tile.y), false, Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			image.set_pixel(x, y, source.get_pixel(x if x < width else width*2-1-x,
				y if y < height else height*2-1-y))
	return image

static func bake_arrays(arrays: Array, fix: Dictionary) -> Array:
	var baked := arrays.duplicate(true)
	var uvs: PackedVector2Array = baked[Mesh.ARRAY_TEX_UV]
	for i in range(uvs.size()):
		uvs[i] = remap_uv(uvs[i], fix)
	baked[Mesh.ARRAY_TEX_UV] = uvs
	# The former shader explicitly ignores vertex alpha. StandardMaterial3D
	# multiplies it with albedo alpha, so retain RGB but remove that inert alpha.
	if baked[Mesh.ARRAY_COLOR] is PackedColorArray:
		var colors: PackedColorArray = baked[Mesh.ARRAY_COLOR]
		for i in range(colors.size()):
			colors[i].a = 1.0
		baked[Mesh.ARRAY_COLOR] = colors
	return baked

static func packed_surface(source: ArrayMesh, surface: int, fix: Dictionary) -> Dictionary:
	# Preserve the packed vertex/normal/tangent/skin/index/LOD buffers verbatim.
	# Reconstructing an ArrayMesh from decoded normals quantizes them twice.
	var raw: Dictionary = source.get("_surfaces")[surface].duplicate(true)
	var format: int = raw.format
	assert(not (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES), "Bake requires uncompressed UV attributes")
	var count: int = raw.vertex_count
	var stride := RenderingServer.mesh_surface_get_format_attribute_stride(format, count)
	var uv_offset := RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_TEX_UV)
	var color_offset := RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_COLOR)
	var bytes: PackedByteArray = raw.attribute_data.duplicate()
	var baked := bake_arrays(source.surface_get_arrays(surface), fix)
	var uvs: PackedVector2Array = baked[Mesh.ARRAY_TEX_UV]
	for i in range(count):
		bytes.encode_float(i*stride+uv_offset, uvs[i].x)
		bytes.encode_float(i*stride+uv_offset+4, uvs[i].y)
		if format & Mesh.ARRAY_FORMAT_COLOR:
			bytes[i*stride+color_offset+3] = 255
	raw.attribute_data = bytes
	return raw

static func material(source: StandardMaterial3D, texture: Texture2D, fix: Dictionary) -> StandardMaterial3D:
	var baked := source.duplicate() as StandardMaterial3D
	baked.albedo_texture = texture
	baked.uv1_scale = Vector3.ONE
	baked.uv1_offset = Vector3.ZERO
	baked.texture_repeat = true
	baked.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	baked.vertex_color_use_as_albedo = true
	baked.vertex_color_is_srgb = false
	baked.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	baked.roughness = 1.0
	baked.metallic = 0.0
	baked.cull_mode = BaseMaterial3D.CULL_BACK
	baked.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if source.transparency in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR] else BaseMaterial3D.TRANSPARENCY_ALPHA
	baked.alpha_scissor_threshold = 0.1
	baked.render_priority = int(fix.get("renderPriority", 0))
	baked.albedo_color.a *= float(fix.get("opacity", 1.0))
	baked.grow = fix.has("surfaceOffset")
	baked.grow_amount = float(fix.get("surfaceOffset", 0))
	baked.set_meta(META, {"version": VERSION, "source_texture": source.albedo_texture.resource_path,
		"fix": fix.duplicate(true), "strategy": "reflected_period"})
	return baked

static func texture_identity(texture: Texture2D) -> String:
	if texture == null:
		return ""
	var key := texture.get_instance_id()
	if _texture_hashes.has(key):
		return _texture_hashes[key]
	var image := texture.get_image().duplicate() as Image
	var mipmaps := image.has_mipmaps()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	image.clear_mipmaps()
	var state := HashingContext.new()
	state.start(HashingContext.HASH_SHA256)
	state.update(image.get_data())
	var identity := "%dx%d:%s:mips%s" % [image.get_width(), image.get_height(), state.finish().hex_encode(), str(mipmaps)]
	_texture_hashes[key] = identity
	return identity

static func signature(mesh: ArrayMesh) -> String:
	var hash_state := HashingContext.new()
	hash_state.start(HashingContext.HASH_SHA256)
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		# Normals may have been filled by SmoothNormals before the material pass;
		# these source channels are unchanged by that operation.
		for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX, Mesh.ARRAY_COLOR, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			hash_state.update(var_to_bytes(arrays[channel]))
		var source := mesh.surface_get_material(surface)
		hash_state.update((source.resource_name if source else "").to_utf8_buffer())
		if source is StandardMaterial3D:
			hash_state.update(texture_identity(source.albedo_texture).to_utf8_buffer())
			hash_state.update(var_to_bytes([source.albedo_color, source.transparency]))
	return hash_state.finish().hex_encode()

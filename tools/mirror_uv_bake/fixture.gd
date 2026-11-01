extends RefCounted
## Adapter for already-baked Three.js triangles. No runtime fold shader on the
## candidate: geometry UVs and a reflected texture are normal Godot resources.

static func read_fixture(id: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/%s.json" % id))
	assert(int(data.get("version", 0)) == 1, "Unsupported fixture version")
	assert(data.get("staticSnapshot", false), "Only static snapshots supported")
	return data

static func source_image(data: Dictionary) -> Image:
	var image := Image.new()
	var error := image.load_png_from_buffer(Marshalls.base64_to_raw(data.texturePng))
	assert(error == OK, "Invalid fixture PNG")
	image.convert(Image.FORMAT_RGBA8)
	return image

static func reflected_atlas(image: Image, mirror: Array) -> Image:
	var width := image.get_width()
	var height := image.get_height()
	var atlas := Image.create(width * (2 if mirror[0] else 1), height * (2 if mirror[1] else 1), false, Image.FORMAT_RGBA8)
	for y in range(atlas.get_height()):
		for x in range(atlas.get_width()):
			var sx := x if x < width else 2 * width - 1 - x
			var sy := y if y < height else 2 * height - 1 - y
			atlas.set_pixel(x, y, image.get_pixel(sx, sy))
	return atlas

static func mesh_from_data(data: Dictionary, mirror: Array = [false, false]) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var count: int = data.position.size() / 3
	assert(count % 3 == 0 and data.normal.size() == count * 3 and data.uv.size() == count * 2)
	for tri in range(0, count, 3):
		# Three uses counterclockwise faces; Godot uses clockwise faces.
		for corner in [0, 2, 1]:
			var i: int = tri + corner
			positions.append(Vector3(data.position[i*3], data.position[i*3+1], data.position[i*3+2]))
			normals.append(Vector3(data.normal[i*3], data.normal[i*3+1], data.normal[i*3+2]))
			uvs.append(Vector2(data.uv[i*2] / (2.0 if mirror[0] else 1.0), data.uv[i*2+1] / (2.0 if mirror[1] else 1.0)))
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func texture(image: Image, mipmaps: bool) -> ImageTexture:
	var copy := image.duplicate() as Image
	if mipmaps:
		copy.generate_mipmaps()
	return ImageTexture.create_from_image(copy)

static func native_material(image: Image, lit: bool, mipmaps: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = "BakedUV_NativeStandardMaterial3D"
	material.albedo_texture = texture(image, mipmaps)
	material.texture_repeat = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if mipmaps else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if lit else BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 0.85
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

static func build_candidate(data: Dictionary, lit: bool = true, mipmaps: bool = false) -> ArrayMesh:
	var atlas := reflected_atlas(source_image(data), data.settings.mirror)
	var mesh := mesh_from_data(data.baked, data.settings.mirror)
	mesh.surface_set_material(0, native_material(atlas, lit, mipmaps))
	mesh.set_meta("mirror_bake", {"version": 1, "source": data.provenance, "settings": data.settings, "texture_strategy": "reflected_period_repeat", "static_snapshot": true})
	return mesh

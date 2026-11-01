extends SceneTree
const Bake := preload("res://scripts/utils/native_mirror_bake.gd")
const Normals := preload("res://scripts/3d/field/smooth_normals.gd")
const MeshHelpers := preload("res://scripts/utils/mesh_utils.gd")
const MANIFEST := "res://data/stage_configs/stage-mirror-bakes.json"
const TEXTURES := "res://assets/stages/native_mirror/lndmd"
var textures: Dictionary = {}
var texture_report: Dictionary = {}
var fixes: Dictionary
var errors: Array[String] = []
var surface_count := 0
var skipped: Array = []
var source_path := ""

func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	fixes = MeshHelpers.load_texture_fixes()
	var manifest := {"version": Bake.VERSION, "strategy": "reflected_period", "stages": {}, "unchanged": [], "textures": {}}
	var folders := DirAccess.get_directories_at("res://assets/stages")
	folders.sort()
	for name in folders:
		if name == "native_mirror":
			continue
		var folder: String = "res://assets/stages/" + name
		if not DirAccess.dir_exists_absolute(folder):
			errors.append("Missing source area " + folder)
			continue
		var stages := DirAccess.get_directories_at(folder)
		stages.sort()
		for id in stages:
			var path := "%s/%s/lndmd/%s_m.glb" % [folder, id, id]
			if not FileAccess.file_exists(path):
				continue
			var row := _stage(path)
			if row.is_empty():
				manifest.unchanged.append(path)
			else:
				manifest.stages[path] = row
	manifest.textures = texture_report
	manifest.skipped = skipped
	if not errors.is_empty():
		for message in errors:
			push_error(message)
		quit(1)
		return
	var file := FileAccess.open(MANIFEST, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t", true) + "\n")
	print("[stage-bake] %d stages converted, %d unchanged, %d surfaces, %d shared textures" % [manifest.stages.size(), manifest.unchanged.size(), surface_count, textures.size()])
	quit()

func _stage(path: String) -> Dictionary:
	source_path = path
	var packed := load(path) as PackedScene
	if packed == null:
		errors.append("Cannot load " + path)
		return {}
	var scene := packed.instantiate() as Node3D
	# Fill the same missing normals as the runtime, before serializing variants.
	Normals.ensure(scene, 2)
	var row := {"version": Bake.VERSION, "source_sha256": FileAccess.get_sha256(path), "fixes": {}, "meshes": []}
	for child in MeshHelpers.collect_mesh_instances(scene, []):
		var instance := child as MeshInstance3D
		var source := instance.mesh as ArrayMesh
		if source == null or source.get_blend_shape_count() > 0:
			continue
		var selected := _selected_surfaces(source)
		if selected.is_empty():
			continue
		var before := Bake.signature(source)
		var mesh := _mesh_variant(source, selected)
		if before != Bake.signature(source):
			push_error("Source mutated: " + path)
		var node_path := str(scene.get_path_to(instance))
		var directory := path.get_base_dir().path_join("mirror-bake")
		DirAccess.make_dir_recursive_absolute(directory)
		var output := directory.path_join(node_path.sha256_text().substr(0, 12) + ".res")
		if ResourceSaver.save(mesh, output, ResourceSaver.FLAG_COMPRESS) != OK:
			errors.append("Cannot save " + output)
		for surface in selected:
			var source_mat := source.surface_get_material(surface) as StandardMaterial3D
			row.fixes[source_mat.albedo_texture.resource_path.get_file()] = selected[surface]
		row.meshes.append({"node": node_path, "resource": output, "signature": Bake.signature(source), "converted_surfaces": selected.keys()})
	scene.free()
	if row.meshes.is_empty():
		return {}
	return row

func _selected_surfaces(mesh: ArrayMesh) -> Dictionary:
	var selected := {}
	for surface in range(mesh.get_surface_count()):
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		if material == null or material.albedo_texture == null:
			continue
		var fix: Dictionary = fixes.get(material.albedo_texture.resource_path.get_file(), {})
		if not Bake.eligible(fix, material.albedo_texture.resource_path) or "/city_" in source_path:
			if fix.get("wrapS") == "mirror" or fix.get("wrapT") == "mirror":
				skipped.append({"scene": source_path, "material": material.resource_name, "texture": material.albedo_texture.resource_path, "reason": "city pipeline" if "/city_" in source_path else "animated, hidden, blended effect or mixed clamp", "fix": fix})
			continue
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			errors.append("Non-triangle mirror surface " + material.resource_name)
			continue
		selected[surface] = fix
	return selected

func _mesh_variant(source: ArrayMesh, selected: Dictionary) -> ArrayMesh:
	var output := ArrayMesh.new()
	output.resource_name = source.resource_name
	output.custom_aabb = source.custom_aabb
	var packed: Array = source.get("_surfaces").duplicate(true)
	for surface in selected:
		var material := source.surface_get_material(surface) as StandardMaterial3D
		packed[surface] = Bake.packed_surface(source, surface, selected[surface])
		packed[surface].material = Bake.material(material, _texture_variant(material.albedo_texture, selected[surface]), selected[surface])
		surface_count += 1
	output.set("_surfaces", packed)
	# Later bake_mix lighting reuses these source colors; keep alpha opaque
	# on migrated surfaces, just as the old shader ignored vertex alpha.
	for key in source.get_meta_list():
		var value = source.get_meta(key)
		if str(key).begins_with("orig_color_") and value is PackedColorArray:
			var colors: PackedColorArray = value.duplicate()
			if selected.has(int(str(key).trim_prefix("orig_color_"))):
				for i in range(colors.size()):
					colors[i].a = 1.0
			output.set_meta(key, colors)
		else:
			output.set_meta(key, value)
	output.set_meta("native_mirror_source", Bake.signature(source))
	return output

func _texture_variant(source: Texture2D, fix: Dictionary) -> Texture2D:
	var image := source.get_image().duplicate() as Image
	var mipmaps := image.has_mipmaps()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	image.clear_mipmaps()
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(image.get_data())
	var pixels_sha := hashing.finish().hex_encode()
	var identity := "%dx%d:%s:%s:mips%s:v%d" % [image.get_width(), image.get_height(), pixels_sha, str(Bake.period(fix)), str(mipmaps), Bake.VERSION]
	var key := identity.sha256_text()
	if textures.has(key):
		return textures[key]
	var atlas := Bake.atlas_image(image, fix)
	if mipmaps:
		atlas.generate_mipmaps()
	var texture := ImageTexture.create_from_image(atlas)
	DirAccess.make_dir_recursive_absolute(TEXTURES)
	var output := TEXTURES.path_join(key + ".res")
	if ResourceSaver.save(texture, output, ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_CHANGE_PATH) != OK:
		errors.append("Cannot save " + output)
	textures[key] = texture
	texture_report[key] = {"resource": output, "source": source.resource_path, "pixels_sha256": pixels_sha,
		"source_size": [image.get_width(), image.get_height()], "output_size": [atlas.get_width(), atlas.get_height()],
		"source_bytes": image.get_data_size(), "output_bytes": atlas.get_data_size(), "mipmaps": mipmaps}
	return texture

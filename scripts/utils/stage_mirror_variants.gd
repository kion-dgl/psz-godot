extends RefCounted
## Load-only runtime bridge. Missing/stale packs retain the original shader path.
const Bake := preload("res://scripts/utils/native_mirror_bake.gd")
const MANIFEST := "res://data/stage_configs/stage-mirror-bakes.json"
static var _manifest: Dictionary = {}

static func manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(MANIFEST):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary:
			_manifest = parsed
	return _manifest

static func current_rows(entry: Dictionary, fixes: Dictionary) -> bool:
	for filename in entry.get("fixes", {}):
		if entry.fixes[filename] != fixes.get(filename, {}):
			return false
	return int(entry.get("version", 0)) == Bake.VERSION

static func apply_stage(root: Node, fixes: Dictionary) -> int:
	if OS.has_environment("PSZ_NATIVE_MIRROR_DISABLE"):
		return 0
	if root.has_meta("native_mirror_applied") or root.has_meta("native_mirror_reference"):
		return 0
	var entry: Dictionary = manifest().get("stages", {}).get(root.scene_file_path, {})
	return apply_entry(root, entry, fixes)

static func apply_entry(root: Node, entry: Dictionary, fixes: Dictionary) -> int:
	if entry.is_empty():
		return 0
	var prepared := _prepare_variants(root, entry, fixes)
	if prepared.is_empty():
		push_warning("[native-mirror] missing/stale stage variant; retaining source: " + root.scene_file_path)
		return 0
	for pair in prepared:
		var instance: MeshInstance3D = pair[0]
		instance.mesh = pair[1]
	root.set_meta("native_mirror_applied", true)
	print("[native-mirror] loaded %s: %d mesh variant(s)" % [root.scene_file_path.get_file(), prepared.size()])
	return prepared.size()

static func _prepare_variants(root: Node, entry: Dictionary, fixes: Dictionary) -> Array:
	if not current_rows(entry, fixes):
		return []
	var prepared: Array = []
	for row in entry.get("meshes", []):
		var instance := root.get_node_or_null(NodePath(row.node)) as MeshInstance3D
		if instance == null or not instance.mesh is ArrayMesh:
			return []
		if Bake.signature(instance.mesh) != row.signature or not ResourceLoader.exists(row.resource):
			if OS.has_environment("PSZ_MIRROR_DEBUG"):
				print("[mirror-debug] source signature ", Bake.signature(instance.mesh), " expected ", row.signature, " exists ", ResourceLoader.exists(row.resource))
			return []
		var replacement := load(row.resource) as ArrayMesh
		if replacement == null or replacement.get_surface_count() != instance.mesh.get_surface_count():
			return []
		if not baked_matches(replacement, row, entry):
			if OS.has_environment("PSZ_MIRROR_DEBUG"):
				print("[mirror-debug] metadata mismatch ", row.resource)
			return []
		prepared.append([instance, replacement])
	return prepared

static func baked_matches(mesh: ArrayMesh, row: Dictionary, entry: Dictionary) -> bool:
	if mesh.get_meta("native_mirror_source", "") != row.signature:
		return false
	for index in row.get("converted_surfaces", []):
		var material := mesh.surface_get_material(int(index)) as StandardMaterial3D
		if material == null:
			return false
		var identity: Dictionary = material.get_meta(Bake.META, {})
		var filename := str(identity.get("source_texture", "")).get_file()
		if int(identity.get("version", 0)) != Bake.VERSION or not entry.fixes.has(filename):
			return false
		if identity.get("fix", {}) != entry.fixes[filename]:
			return false
	return true

static func field_material(source: StandardMaterial3D, unlit: bool, keep_lit: Array) -> StandardMaterial3D:
	var material := source.duplicate() as StandardMaterial3D
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unlit \
		and not (keep_lit.has("*") or keep_lit.has(source.resource_name)) else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return material

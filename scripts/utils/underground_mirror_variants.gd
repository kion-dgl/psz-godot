extends RefCounted
const MANIFEST := "res://data/stage_configs/underground-mirror-bakes.json"
const ROOT := "res://assets/stages/city_e/s00e_sa4/"
const PATHS := [ROOT + "lndmd/s00e_sa4_m.glb", ROOT + "de_roll_le/fe_obj002_mizu.nj.glb",
	ROOT + "de_roll_le/fe_obj006_grid2.nj.glb", ROOT + "de_roll_le/fe_obj001_complex3.nj.glb"]
const Variants := preload("res://scripts/utils/stage_mirror_variants.gd")

static func fixes_for(root: Node) -> Dictionary:
	var fixes := MeshUtils.load_texture_fixes()
	# Authored GLB samplers: 33648 = mirrored repeat. The main room's
	# other materials use ordinary repeat; do not mirror the water/ground.
	const MAIN := {"1_auto": {"wrapS": "mirror", "wrapT": "repeat"},
		"1_ground2_1": {"wrapS": "mirror", "wrapT": "mirror"},
		"1_sh": {"wrapS": "mirror", "wrapT": "repeat"},
		"1_wall2": {"wrapS": "mirror", "wrapT": "repeat"}}
	for mesh in MeshUtils.collect_mesh_instances(root, []):
		for surface in mesh.mesh.get_surface_count():
			var material = mesh.mesh.surface_get_material(surface)
			if material is StandardMaterial3D and material.albedo_texture:
				var filename: String = material.albedo_texture.resource_path.get_file()
				if "/de_roll_le/" in root.scene_file_path:
					fixes[filename] = {"wrapS": "mirror", "wrapT": "mirror"}
				elif MAIN.has(material.resource_name):
					fixes[filename] = MAIN[material.resource_name]

	return fixes

static func apply(root: Node3D) -> bool:
	if OS.has_environment("PSZ_NATIVE_MIRROR_DISABLE") or not FileAccess.file_exists(MANIFEST):
		return false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var fixes := fixes_for(root)
	preload("res://scripts/3d/field/smooth_normals.gd").ensure(root, 2)
	return Variants.apply_entry(root, data.get("stages", {}).get(root.scene_file_path, {}), fixes) > 0

extends "res://tools/stage_mirror_bake/bake.gd"
const Underground := preload("res://scripts/utils/underground_mirror_variants.gd")

func _bake() -> void:
	var manifest := {"version": Bake.VERSION, "strategy": "reflected_period", "stages": {}, "textures": {}}
	for path in Underground.PATHS:
		var scene := (load(path) as PackedScene).instantiate()
		fixes = Underground.fixes_for(scene)
		scene.free()
		var row := _stage(path)
		if not row.is_empty():
			manifest.stages[path] = row
	manifest.textures = texture_report
	if not errors.is_empty():
		for message in errors: push_error(message)
		quit(1)
		return
	FileAccess.open(Underground.MANIFEST, FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t", true) + "\n")
	print("[underground-bake] %d models, %d surfaces, %d textures" % [manifest.stages.size(), surface_count, textures.size()])
	quit()

func _selected_surfaces(mesh: ArrayMesh) -> Dictionary:
	var selected := {}
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		if material and material.albedo_texture:
			var fix: Dictionary = fixes.get(material.albedo_texture.resource_path.get_file(), {})
			if Bake.eligible(fix, material.albedo_texture.resource_path):
				selected[surface] = fix
	return selected

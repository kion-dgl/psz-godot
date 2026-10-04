extends SceneTree
## Export the actual original/rebuilt ga1 pillar for the Three.js mesh lab.
## Godot --headless --path . --script scripts/tools/export_shrine_pillar_preview.gd
## Generated JSON stays beside the local asset-pack art (not committed).
const Lighting := preload("res://scripts/3d/field/shrine_lighting.gd")
const STAGE := "s07b_ga1"
const CENTER := Vector3(13, 0, 13)
const OUTPUT := "res://assets/stages/shrine_b/s07b_ga1/lndmd/s07b_ga1_pillar_preview.json"


func _initialize() -> void:
	call_deferred("_export")


func _export() -> void:
	var packed := load("res://assets/stages/shrine_b/s07b_ga1/lndmd/s07b_ga1_m.glb") as PackedScene
	var stage := packed.instantiate() as Node3D
	root.add_child(stage)
	SmoothNormals.ensure(stage, 2)
	MeshUtils.split_mesh_surfaces(stage)
	await process_frame
	var original := _capture(stage)
	var changed := Lighting.rebuild_pillars(stage, STAGE)
	var rebuilt := _capture(stage)
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write " + OUTPUT)
		quit(1)
		return
	file.store_string(JSON.stringify({"stage": STAGE, "center": [13, 0, 13],
		"original": original, "rebuilt": rebuilt}, ""))
	file.close()
	print("[PillarPreview] %d original surfaces, %d rebuilt surfaces; %d room inset triangles" %
		[original.size(), rebuilt.size(), changed])
	stage.free()
	quit()


func _capture(stage: Node3D) -> Array:
	var surfaces: Array = []
	for node in stage.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var transform_to_stage := stage.global_transform.affine_inverse() * mi.global_transform
		var mesh := mi.mesh as ArrayMesh
		if mesh == null or mi.is_queued_for_deletion():
			continue
		for s in range(mesh.get_surface_count()):
			var surface_material := mesh.surface_get_material(s)
			var material := surface_material as StandardMaterial3D
			if material == null and surface_material != null:
				material = surface_material.get_meta("shrine_source_material", null) as StandardMaterial3D
			if material == null:
				continue
			var arrays := mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				for i in range(vertices.size()):
					indices.append(i)
			var surface := {"material": material.resource_name, "positions": [],
				"normals": [], "uvs": [], "colors": [], "inset": material.resource_name == "ShrineTealInset"}
			for t in range(0, indices.size(), 3):
				var selected := true
				var highest := -INF
				for j in range(3):
					var p := transform_to_stage * vertices[indices[t+j]] - CENTER
					selected = selected and Vector2(p.x, p.z).length() < 2.2 and p.y >= -0.1
					highest = maxf(highest, p.y)
				if not selected or highest < .25:
					continue
				# Godot uses clockwise faces, Three.js uses counterclockwise.
				for j in [0, 2, 1]:
					var i := indices[t+j]
					var p := transform_to_stage * vertices[i] - CENTER
					var n := (transform_to_stage.basis.inverse().transposed() * normals[i]).normalized()
					var uv := uvs[i]
					var c := colors[i] if not colors.is_empty() else Color.WHITE
					surface.positions.append_array([p.x, p.y, p.z])
					surface.normals.append_array([n.x, n.y, n.z])
					surface.uvs.append_array([uv.x, uv.y])
					surface.colors.append_array([c.r, c.g, c.b])
			if surface.positions.is_empty():
				continue
			var fix := MeshUtils.fix_for_material(material)
			surface["texture"] = material.albedo_texture.resource_path.trim_prefix("res://") if material.albedo_texture else ""
			surface["repeat"] = [fix.get("repeatX", 1), fix.get("repeatY", 1)]
			surface["offset"] = [fix.get("offsetX", 0), fix.get("offsetY", 0)]
			surface["mirrorS"] = fix.get("wrapS", "repeat") == "mirror"
			surface["mirrorT"] = fix.get("wrapT", "repeat") == "mirror"
			surfaces.append(surface)
	return surfaces

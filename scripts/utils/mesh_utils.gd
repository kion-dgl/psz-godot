class_name MeshUtils
## Shared mesh helpers. Deduplicated from the identical `_apply_texture_recursive`
## in character_create.gd and character_select.gd — #294.


## Walk `node` and its descendants; for every MeshInstance3D surface, override the
## material's albedo with `texture` (nearest-filtered). Existing StandardMaterial3D
## surfaces are duplicated so the source material isn't mutated; surfaces with no
## material get a fresh StandardMaterial3D.
static func apply_texture_recursive(node: Node, texture: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh:
			for surface_idx in range(mesh.get_surface_count()):
				var mat := mesh_instance.get_active_material(surface_idx)
				if mat is StandardMaterial3D:
					var new_mat := mat.duplicate() as StandardMaterial3D
					new_mat.albedo_texture = texture
					new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mesh_instance.set_surface_override_material(surface_idx, new_mat)
				elif mat == null:
					var new_mat := StandardMaterial3D.new()
					new_mat.albedo_texture = texture
					new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mesh_instance.set_surface_override_material(surface_idx, new_mat)
	for child in node.get_children():
		apply_texture_recursive(child, texture)

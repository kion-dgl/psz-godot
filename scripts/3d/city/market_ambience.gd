extends RefCounted
## Animate the authored surfaces in place: no added geometry or colliders.
const CLOUDS := preload("res://scripts/3d/shaders/city_clouds.gdshader")
const CROWD := preload("res://scripts/3d/shaders/city_crowd.gdshader")

static func apply(root: Node) -> Dictionary:
	var counts := {"ground": 0, "crowd": 0}
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is MeshInstance3D or not node.mesh:
			continue
		for surface in node.mesh.get_surface_count():
			var original = node.get_active_material(surface)
			if not original is StandardMaterial3D:
				continue
			var id: String = original.resource_name
			if id.begins_with("1_ppl"):
				var crowd := ShaderMaterial.new()
				crowd.shader = CROWD
				crowd.set_shader_parameter("atlas", original.albedo_texture)
				node.set_surface_override_material(surface, crowd)
				counts.crowd += 1
			elif id.begins_with("floor03") or id.begins_with("floor4") or id.begins_with("gr01"):
				var ground := original.duplicate() as StandardMaterial3D
				var clouds := ShaderMaterial.new()
				clouds.shader = CLOUDS
				ground.next_pass = clouds
				node.set_surface_override_material(surface, ground)
				counts.ground += 1
	return counts

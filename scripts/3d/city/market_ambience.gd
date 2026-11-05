extends RefCounted
## Animate the authored surfaces in place: no added geometry or colliders.
const CLOUDS := preload("res://scripts/3d/shaders/city_clouds.gdshader")
const CROWD := preload("res://scripts/3d/shaders/city_crowd.gdshader")

static func apply(root: Node) -> Dictionary:
	var counts := {"clouds": 0, "crowd": 0}
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is MeshInstance3D or not node.mesh:
			continue
		for surface in node.mesh.get_surface_count():
			# Read the authored material: the generic scroll pass may already
			# have replaced wave02 with an additive water shader.
			var original = node.mesh.surface_get_material(surface)
			if not original is StandardMaterial3D:
				continue
			var id: String = original.resource_name
			if id.begins_with("1_ppl"):
				var crowd := ShaderMaterial.new()
				crowd.shader = CROWD
				crowd.set_shader_parameter("atlas", original.albedo_texture)
				node.set_surface_override_material(surface, crowd)
				counts.crowd += 1
			elif original.albedo_texture and original.albedo_texture.resource_path.get_file().ends_with("s00_2_wave02.png"):
				# The model already contains the sky cards AND the ground shadow.
				# Keep their UVs, alpha and vertex colors; additive blending makes
				# the almost-black ground card disappear instead of casting shade.
				var clouds := ShaderMaterial.new()
				clouds.shader = CLOUDS
				clouds.set_shader_parameter("cloud_texture", original.albedo_texture)
				clouds.set_shader_parameter("cloud_color", original.albedo_color)
				node.set_surface_override_material(surface, clouds)
				counts.clouds += 1
	return counts

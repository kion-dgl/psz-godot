extends RefCounted

static func run(t: Node) -> void:
	_test_market_clouds(t)
	seed(777)
	var detached := Node3D.new()
	t.assert_true(preload("res://scripts/3d/elements/shrapnel_burst.gd").spawn_bounds(detached, AABB(), Color.GRAY) == null, "detached destruction safely skips visuals")
	t.assert_true(preload("res://scripts/3d/elements/hazard_blast.gd").show_flash(detached, 4.0) == null, "detached trap safely skips visuals")
	detached.free()
	var parent := Node3D.new()
	t.add_child(parent)
	parent.position = Vector3(10, 3, -5)
	parent.scale = Vector3(2, 2, 2)
	var source := Node3D.new()
	parent.add_child(source)
	source.position = Vector3(2, 0, 1)
	var blast = preload("res://scripts/3d/elements/hazard_blast.gd").show_flash(source, 4.0)
	t.assert_eq(blast.global_position, source.global_position, "blast uses gameplay origin under transformed parent")
	t.assert_almost_eq(blast.global_basis.get_scale().x, 1.0, 0.001, "blast radius is in world units")
	t.assert_almost_eq(blast.get_child(0).mesh.radius, 4.0, 0.001, "blast matches gameplay radius")
	var visual := Node3D.new()
	source.add_child(visual)
	visual.position.y = 1.5
	var raised = preload("res://scripts/3d/elements/hazard_blast.gd").show_flash(source, 4.0, Color.ORANGE, visual)
	t.assert_eq(raised.global_position, visual.global_position, "floating blast follows trap model, not hit-query origin")
	t.assert_almost_eq(raised.get_child(1).global_position.y, source.global_position.y + 0.04, 0.001, "footprint stays at gameplay ground height")
	t.assert_true(raised.get_child(0).scale.x < 0.1, "blast starts small at the source before expanding")
	t.assert_eq(source.position, Vector3(2, 0, 1), "visual offset leaves gameplay source unchanged")
	var burst = preload("res://scripts/3d/elements/shrapnel_burst.gd").spawn_bounds(source, AABB(Vector3(-3, 0, -0.3), Vector3(6, 2, 0.6)), Color.GRAY)
	t.assert_eq(burst.global_transform, source.global_transform, "break effect preserves source transform")
	t.assert_eq(burst._shards.size(), 18, "wall burst has bounded shard count")
	var bounds := AABB(Vector3(-3, 0, -0.3), Vector3(6, 2, 0.6))
	var contained := true
	for shard in burst._shards:
		contained = contained and bounds.has_point(shard.node.position)
		contained = contained and shard.node.mesh.size.length() < 1.0
	t.assert_true(contained, "small debris starts throughout the model bounds")
	burst._process(0.7)
	t.assert_true(burst.is_queued_for_deletion(), "destruction effect has bounded lifetime")
	var feedback = preload("res://scripts/3d/enemies/enemy_status_effects.gd").new()
	parent.add_child(feedback)
	feedback.sync([{"type": "burn"}])
	t.assert_true(feedback.fire.visible and feedback.fire.emitting, "burn emits visible flames")
	feedback.sync([{"type": "stun"}])
	t.assert_true(not feedback.fire.visible and not feedback.fire.emitting, "burn clears immediately with another status active")
	parent.free()


static func _test_market_clouds(t: Node) -> void:
	var root := Node3D.new()
	var clouds := MeshInstance3D.new()
	clouds.mesh = QuadMesh.new()
	var original := StandardMaterial3D.new()
	var texture := ImageTexture.new()
	texture.resource_path = "res://assets/stages/city_e/market/dairon3_s00_2_wave02.png"
	original.albedo_texture = texture
	original.albedo_color = Color(1, 1, 1, 0.6129)
	clouds.mesh.material = original
	root.add_child(clouds)
	# Production applies generic scrolling first. Cloud detection must use
	# the source material even after that pass installs its water shader.
	var water := ShaderMaterial.new()
	water.shader = preload("res://scripts/3d/field/waterfall_shader.gdshader")
	clouds.set_surface_override_material(0, water)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = QuadMesh.new()
	var floor_material := StandardMaterial3D.new()
	floor_material.resource_name = "floor03_COLOR_0"
	floor_mesh.mesh.material = floor_material
	root.add_child(floor_mesh)
	var counts := preload("res://scripts/3d/city/market_ambience.gd").apply(root)
	var result := clouds.get_active_material(0) as ShaderMaterial
	t.assert_eq(counts.clouds, 1, "clouds recognized after generic scroll replacement")
	t.assert_eq(result.shader, preload("res://scripts/3d/shaders/city_clouds.gdshader"), "clouds replace additive water blending")
	t.assert_eq(result.get_shader_parameter("cloud_texture"), texture, "clouds retain authored wave02 texture")
	t.assert_eq(result.get_shader_parameter("cloud_color"), original.albedo_color, "clouds retain authored opacity")
	t.assert_eq(floor_mesh.get_active_material(0), floor_material, "ground retains its authored material")
	t.assert_true(floor_material.next_pass == null, "no procedural shadow overlays")
	t.assert_eq(root.get_child_count(), 2, "cloud fix adds no geometry or collision")
	root.free()

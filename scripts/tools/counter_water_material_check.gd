extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	var area = load("res://scripts/3d/city/city_area_base.gd").new()
	root.add_child(area)
	var stage = load("res://assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb").instantiate()
	area.add_child(stage)
	area._fix_city_materials()
	var pools = 0
	var falls = 0
	for mi in stage.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var mat = mi.get_active_material(i)
			var original = mi.mesh.surface_get_material(i)
			if original.resource_name == "mizu_COLOR_0":
				assert(mat.shader.resource_path == "res://scripts/3d/city/counter_water.gdshader")
				assert(abs(mat.get_shader_parameter("albedo_color").a - 0.48387) < 0.001)
				assert(mat.get_shader_parameter("uv_scroll") == Vector2(0,-0.12))
				pools += 1
			elif original.resource_name == "Material__75_COLOR_0":
				assert(mat.shader.resource_path == "res://scripts/3d/field/waterfall_shader.gdshader")
				falls += 1
	assert(pools == 1 and falls == 1)
	print("PASS: pool alpha-blends at original opacity and scroll; waterfalls retain additive glow")
	quit()

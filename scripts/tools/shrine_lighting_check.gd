extends Node3D
## Asset-backed checks: all B rooms load, inset cuts conserve surface area,
## rebuilding is idempotent, and tracked recipes replace stale local lights.
## Run: Godot --headless --path . scripts/tools/shrine_lighting_check.tscn
const Lighting := preload("res://scripts/3d/field/shrine_lighting.gd")
const Lab := preload("res://scripts/tools/field_lab.gd")
const Walk := preload("res://scripts/tools/shrine_walktest.gd")
var _map_root: Node3D
var failures := 0


func _ready() -> void:
	for stage in Walk.STAGES:
		var path := "res://assets/stages/shrine_b/%s/lndmd/%s_m.glb" % [stage, stage]
		var original := (load(path) as PackedScene).instantiate()
		var before := _area(original)
		original.free()
		var slot: Dictionary = FieldSlotTable.slot_for("dark", stage)
		_map_root = Lab.load_field_stage(self, slot, "shrine_b", stage)
		await get_tree().process_frame
		_check_double_sided(_map_root, stage)
		var after := _area(_map_root)
		_check(absf(before - after) < maxf(.01, before * .00001), stage + ": floor and pillar surface area preserved")
		_check(Lighting.rebuild_pillars(_map_root, stage) == 0, stage + ": idempotent rebuild")
		var recipe := Lighting.recipe(stage)
		_check(recipe.get("stage_id") == stage, stage + ": tracked recipe exists")
		var centers: Array = recipe.get("pillar_centers", [])
		var illuminated: Array = []
		for mi in _map_root.find_children("TealPillarInsets", "MeshInstance3D", true, false):
			var mesh: Mesh = mi.mesh
			var material := mesh.surface_get_material(0) as ShaderMaterial
			_check(material != null and material.shader == Lighting.POT_SHADER,
				stage + ": textured vessel uses approved teal band shader")
			var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for i in range(centers.size()):
				for v in vertices:
					if Vector2(v.x-float(centers[i][0]), v.z-float(centers[i][1])).length() < 2.1:
						if not illuminated.has(i):
							illuminated.append(i)
						break
		_check(illuminated.size() == centers.size(), stage + ": every pillar has rebuilt insets")
		WeatherController.new(self)._spawn_stage_effects(stage)
		var lights := _map_root.find_children("*", "OmniLight3D", true, false)
		_check(lights.size() == recipe.effects.size(), stage + ": recipe spawned once, local draft suppressed")
		_check(lights.size() <= 64, stage + ": scene light budget")
		for light in lights:
			if light.position.y < 1.0 and light.light_color.r > .9:
				_check(light.light_cull_mask == 1 << (MeshUtils.STAGE_LIGHT_LAYER - 1),
					stage + ": floor pool cannot illuminate actors")
		print("[ShrineCheck] %s: %d pillars, %d lights, area %.3f -> %.3f" %
			[stage, centers.size(), lights.size(), before, after])
		_map_root.free()
	for b_stage in Walk.STAGES:
		var stage: String = b_stage.replace("s07b_", "s07a_")
		var slot: Dictionary = FieldSlotTable.slot_for("dark", stage)
		var original := (load("res://assets/stages/shrine_a/%s/lndmd/%s_m.glb" % [stage, stage]) as PackedScene).instantiate()
		var before := _area(original)
		original.free()
		_map_root = Lab.load_field_stage(self, slot, "shrine_a", stage)
		await get_tree().process_frame
		_check_double_sided(_map_root, stage)
		var after := _area(_map_root)
		_check(absf(before - after) < maxf(.01, before * .00001), stage + ": no duplicated stage geometry")
		if stage.begins_with("s07a_"):
			WeatherController.new(self)._spawn_stage_effects(stage)
			var count: int = Lighting.recipe(stage).effects.filter(func(e): return e.type == "shrine_lantern").size()
			_check(count > 0 and _map_root.find_children("InteriorLight", "OmniLight3D", true, false).size() == count, stage + ": solid lanterns with internal lights")
			for mi in _map_root.find_children("*", "MeshInstance3D", true, false):
				if mi.mesh == null:
					continue
				for surface in mi.mesh.get_surface_count():
					var material: Material = mi.mesh.surface_get_material(surface)
					_check(material == null or material.resource_name != "1_light3", "A lantern sprite cards removed")
		_map_root.free()
	_check(Lighting.recipe("s07a_ga1").get("effects", []).filter(func(e): return e.type == "light").size() == 4, "A reference has four overhead pools")

	_check(Lighting.recipe("s07z_na1").is_empty(), "Z remains independent")
	print("[ShrineCheck] 36 rooms checked; %d failures" % failures)
	get_tree().quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _area(root: Node) -> float:
	var area := 0.0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.is_queued_for_deletion():
			continue
		var mesh: Mesh = mi.mesh
		for s in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(s)
			if mat == null or mat.resource_name in ["1_blight", "1_light3"]:
				continue
			var arrays := mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				for i in range(vertices.size()):
					indices.append(i)
			for t in range(0, indices.size(), 3):
				area += (vertices[indices[t+1]] - vertices[indices[t]]).cross(
					vertices[indices[t+2]] - vertices[indices[t]]).length() * .5
	return area


func _check_double_sided(root: Node3D, stage: String) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.is_queued_for_deletion() or mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			var material: Material = mi.get_active_material(surface)
			if material is BaseMaterial3D:
				_check(material.cull_mode == BaseMaterial3D.CULL_DISABLED, stage + ": double-sided standard material")
			elif material is ShaderMaterial:
				_check(material.shader.code.contains("cull_disabled"), stage + ": double-sided shader material")

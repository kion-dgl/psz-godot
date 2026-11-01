extends Node
const Bake := preload("res://scripts/utils/native_mirror_bake.gd")
const Variants := preload("res://scripts/utils/stage_mirror_variants.gd")
const FIX_SHADER := preload("res://scripts/3d/field/texture_fix_shader.gdshader")
const UNLIT_SHADER := preload("res://scripts/3d/field/texture_fix_shader_unlit.gdshader")
const WATERFALL := preload("res://scripts/3d/field/waterfall_shader.gdshader")
var passed := 0
var failed := 0
var surfaces := 0
var configs: Dictionary = {}

func assert_true(value: bool, message: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("[stage-audit] " + message)

func assert_eq(value, expected, message: String) -> void:
	assert_true(value == expected, message)

func _ready() -> void:
	configs = JSON.parse_string(FileAccess.get_file_as_string("res://data/stage_configs/unified-stage-configs.json"))
	preload("res://scripts/tools/native_mirror_tests.gd").run(self)
	var manifest := {"stages": _stage_rows()}
	assert_true(not manifest.stages.is_empty(), "manifest contains stage variants")
	for path in manifest.get("stages", {}):
		_audit_stage(path, manifest.stages[path])
	print("[stage-audit] %d checks passed; %d failures; %d native surfaces across %d stages" % [passed, failed, surfaces, manifest.stages.size()])
	get_tree().quit(1 if failed else 0)

func _audit_stage(path: String, entry: Dictionary) -> void:
	var packed := load(path) as PackedScene
	assert_true(packed != null, "source loads: " + path)
	if packed == null:
		return
	var source := packed.instantiate() as Node3D
	var native := packed.instantiate() as Node3D
	SmoothNormals.ensure(source, 2)
	SmoothNormals.ensure(native, 2)
	var fixes := MeshUtils.load_texture_fixes()
	var broken := entry.duplicate(true)
	broken.meshes[0].resource = "res://missing-valley-variant.res"
	assert_true(Variants._prepare_variants(native, broken, fixes).is_empty(), "missing pack asset rejected atomically")
	broken = entry.duplicate(true)
	broken.meshes[0].signature = "stale"
	assert_true(Variants._prepare_variants(native, broken, fixes).is_empty(), "changed source mesh rejected atomically")
	var cached := load(entry.meshes[0].resource) as ArrayMesh
	var changed_settings := entry.duplicate(true)
	var first_texture: String = changed_settings.fixes.keys()[0]
	changed_settings.fixes[first_texture]["repeatX"] = 999.0
	assert_true(not Variants.baked_matches(cached, entry.meshes[0], changed_settings), "old pack settings rejected even when mesh signature matches")
	var id := path.get_file().trim_suffix("_m.glb")
	var slot := FieldSlotTable.slot_for(preload("res://tools/stage_mirror_bake/areas.gd").area(path), id)
	MeshUtils.apply_field_materials(native, FIX_SHADER, WATERFALL, false, slot.has("lit_surfaces") and not slot.has("bake_mix"), UNLIT_SHADER, slot.get("lit_surfaces", []))
	assert_true(native.has_meta("native_mirror_applied"), "field pass installed variants: " + id)
	for row in entry.meshes:
		var original := source.get_node(NodePath(row.node)) as MeshInstance3D
		var converted := native.get_node(NodePath(row.node)) as MeshInstance3D
		assert_eq(converted.transform, original.transform, "node transform preserved")
		assert_eq(converted.skin, original.skin, "skin resource preserved")
		for surface in range(original.mesh.get_surface_count()):
			_audit_surface(original, converted, surface, row.converted_surfaces.any(func(value): return int(value) == surface), slot)
	var signature := Bake.signature((native.get_node(NodePath(entry.meshes[0].node)) as MeshInstance3D).mesh)
	MeshUtils.apply_field_materials(native, FIX_SHADER, WATERFALL, false, slot.has("lit_surfaces") and not slot.has("bake_mix"), UNLIT_SHADER, slot.get("lit_surfaces", []))
	assert_eq(Bake.signature((native.get_node(NodePath(entry.meshes[0].node)) as MeshInstance3D).mesh), signature, "repeat material pass does not rebake UVs")
	_audit_glow(source, native, entry, id)
	source.free()
	native.free()

func _audit_surface(original: MeshInstance3D, converted: MeshInstance3D, surface: int, selected: bool, slot: Dictionary) -> void:
	var old := original.mesh.surface_get_arrays(surface)
	var fresh := converted.mesh.surface_get_arrays(surface)
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_INDEX, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_TEX_UV2]:
		assert_eq(fresh[channel], old[channel], "surface channel preserved: %d" % channel)
	if not selected:
		assert_eq(fresh[Mesh.ARRAY_TEX_UV], old[Mesh.ARRAY_TEX_UV], "unselected UVs unchanged")
		assert_eq(fresh[Mesh.ARRAY_COLOR], old[Mesh.ARRAY_COLOR], "unselected colors unchanged")
		return
	surfaces += 1
	var material := converted.get_active_material(surface)
	assert_true(material is StandardMaterial3D, "migrated material is native")
	if not material is StandardMaterial3D:
		return
	assert_true(material.has_meta(Bake.META), "bake identity retained")
	var source_alpha := (original.get_active_material(surface) as StandardMaterial3D).transparency
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if source_alpha in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR] else BaseMaterial3D.TRANSPARENCY_ALPHA, "cutout/blend behavior preserved")
	var key := "orig_color_%d" % surface
	if original.mesh.has_meta(key):
		assert_true(converted.mesh.has_meta(key), "lighting color stash retained")
		if converted.mesh.has_meta(key):
			var colors: PackedColorArray = converted.mesh.get_meta(key)
			var before: PackedColorArray = original.mesh.get_meta(key)
			for i in range(before.size()):
				before[i].a = 1.0
			assert_eq(colors, before, "lighting stash keeps RGB and ignores vertex alpha")
	var source_material := original.get_active_material(surface) as StandardMaterial3D
	assert_eq(material.albedo_texture.get_image().has_mipmaps(), source_material.albedo_texture.get_image().has_mipmaps(), "source mipmap availability preserved")
	assert_eq(material.uv1_scale, Vector3.ONE, "scale not applied twice")
	assert_eq(material.uv1_offset, Vector3.ZERO, "offset not applied twice")
	var keep: Array = slot.get("lit_surfaces", [])
	var unlit := slot.has("lit_surfaces") and not slot.has("bake_mix") and not (keep.has("*") or keep.has(material.resource_name))
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED if unlit else BaseMaterial3D.SHADING_MODE_PER_PIXEL, "authored area lighting policy preserved")
	var data: Dictionary = material.get_meta(Bake.META)
	var expected := Bake.bake_arrays(old, data.fix)
	assert_eq(fresh[Mesh.ARRAY_TEX_UV], expected[Mesh.ARRAY_TEX_UV], "baked UVs match source transform")
	assert_eq(fresh[Mesh.ARRAY_COLOR], expected[Mesh.ARRAY_COLOR], "baked colors match ignored-alpha contract")

func _stage_rows() -> Dictionary:
	return Variants.manifest().get("stages", {})

func _audit_glow(source: Node3D, native: Node3D, entry: Dictionary, id: String) -> void:
	var passes := {}
	for row in configs.get(id, {}).get("glowMaterials", []):
		passes[str(row.material)] = row
	# Regression fixture: exercise the existing teal-mask path on a migrated
	# surface even when this room's authored config has no glow pass.
	if id == "s06a_ga1":
		var row: Dictionary = entry.meshes[0]
		var mesh := native.get_node(NodePath(row.node)) as MeshInstance3D
		var material_name: String = mesh.get_active_material(int(row.converted_surfaces[0])).resource_name
		passes[material_name] = {"mask": "teal"}
	MeshUtils.apply_glow_materials(native, passes)
	for row in entry.meshes:
		var original := source.get_node(NodePath(row.node)) as MeshInstance3D
		var converted := native.get_node(NodePath(row.node)) as MeshInstance3D
		for index in row.converted_surfaces:
			var material := converted.get_active_material(int(index)) as StandardMaterial3D
			if material == null or not passes.has(material.resource_name):
				continue
			assert_true(material.has_meta(Bake.META), "glow retains native bake metadata")
			assert_eq(material.uv1_scale, Vector3.ONE, "glow does not reapply UV transform")
			if passes[material.resource_name].get("mask", "") == "teal":
				var old := original.get_active_material(int(index)) as StandardMaterial3D
				var mask := MeshUtils._teal_mask_texture(old.albedo_texture)
				var identity: Dictionary = material.get_meta(Bake.META)
				var expected := Bake.atlas_image(mask.get_image(), identity.fix)
				assert_true(material.emission_texture != null, "native glow has emission mask")
				if material.emission_texture:
					assert_eq(material.emission_texture.get_image().get_data(), expected.get_data(), "raw-pixel glow mask follows mirrored texture period")

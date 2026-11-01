extends "res://tools/mirror_uv_bake/main.gd"
## Full-room review using the same shared material pass as valley_field.
const Variants := preload("res://scripts/utils/stage_mirror_variants.gd")
const Bake := preload("res://scripts/utils/native_mirror_bake.gd")
const FIX := preload("res://scripts/3d/field/texture_fix_shader.gdshader")
const UNLIT := preload("res://scripts/3d/field/texture_fix_shader_unlit.gdshader")
const WATERFALL := preload("res://scripts/3d/field/waterfall_shader.gdshader")
var paths: Array = []
var stage_roots: Array[Node3D] = []
var focused: CheckButton

func _ready() -> void:
	output_dir = "res://tools/stage_mirror_bake/output"
	paths = _source_paths()
	paths.sort()
	_build_ui()
	_select_source(0)
	if OS.get_cmdline_user_args().has("--verify"):
		call_deferred("_verify")

func _build_ui() -> void:
	super._build_ui()
	source_picker.clear()
	for path in paths:
		source_picker.add_item(str(path).get_file().trim_suffix("_m.glb"))
	lit_toggle.text = "Light all surfaces (diagnostic)"
	lit_toggle.set_pressed_no_signal(false)
	mip_toggle.text = "Source mipmaps"
	mip_toggle.set_pressed_no_signal(true)
	focused = CheckButton.new()
	focused.text = "Mirrored surfaces only"
	focused.toggled.connect(func(_pressed: bool): _rebuild())
	source_picker.get_parent().add_child(focused)
	for button in find_children("*", "Button", true, false):
		if button.text == "Save native-only scene":
			button.text = "Save Stage preview"

func _label(text: String, font_size: int = 16) -> Label:
	if text.begins_with("Mirror UV bake |"):
		text = "Stage | original materials vs native mirror bake"
	if text.begins_with("Independent project:"):
		text = "All field areas | static mirror materials | source GLBs preserved"
	return super._label(text, font_size)

func _select_source(index: int) -> void:
	source_id = str(paths[index]).get_file().trim_suffix("_m.glb")
	yaw = 0.45
	pitch = 0.85
	distance = 5.8
	_rebuild()

func _update_materials() -> void:
	if focused != null and not paths.is_empty():
		_rebuild()

func _rebuild() -> void:
	for stage in stage_roots:
		stage.free()
	stage_roots.clear()
	var path: String = paths[source_picker.selected]
	var slot := FieldSlotTable.slot_for(preload("res://tools/stage_mirror_bake/areas.gd").area(path), source_id)
	var keep: Array = ["*"] if lit_toggle.button_pressed else slot.get("lit_surfaces", [])
	for i in range(2):
		var stage := (load(path) as PackedScene).instantiate() as Node3D
		if i == 0:
			stage.set_meta("native_mirror_reference", true)
		worlds[i].add_child(stage)
		stage_roots.append(stage)
		SmoothNormals.ensure(stage, 2)
		var shaded := _filter_shader(FIX)
		var unshaded := _filter_shader(UNLIT)
		MeshUtils.apply_field_materials(stage, shaded, WATERFALL, false, slot.has("lit_surfaces") and not slot.has("bake_mix"), unshaded, keep)
		if slot.has("bake_mix"):
			SmoothNormals.neutralize_vertex_colors(stage, float(slot.bake_mix))
			SmoothNormals.make_lit(stage)
		# Split both views for focused inspection, preserving slot shading.
		MeshUtils.split_mesh_surfaces(stage)
		if slot.has("lit_surfaces"):
			MeshUtils.make_lit_surfaces(stage, keep)
			MeshUtils.make_unlit(stage, keep)
		_normalize_view(stage)
		lights[i].light_energy = float(slot.get("sun_energy", 0.9))
	_update_camera()
	_update_lights()
	var native_count := 0
	for instance in MeshUtils.collect_mesh_instances(stage_roots[1], []):
		if instance.is_queued_for_deletion():
			continue
		for surface in range(instance.mesh.get_surface_count()):
			var mat: Material = instance.get_active_material(surface)
			if mat is StandardMaterial3D and mat.has_meta(Bake.META):
				native_count += 1
	details.text = "%s | %d migrated surface(s) | original topology and vertex tint | authored area lighting policy" % [source_id, native_count]
	result.text = "Drag to orbit; compare full room or isolate mirrored surfaces. Default filtering preserves the source mipmap setting."

func _filter_shader(original: Shader) -> Shader:
	if mip_toggle.button_pressed:
		return original
	var filtered := Shader.new()
	filtered.code = original.code.replace("filter_linear_mipmap", "filter_linear")
	return filtered

func _normalize_view(stage: Node3D) -> void:
	var box := AABB()
	var first := true
	for instance in MeshUtils.collect_mesh_instances(stage, []):
		if instance.is_queued_for_deletion() or not instance.visible:
			continue
		var mirrored := false
		for surface in range(instance.mesh.get_surface_count()):
			var own := instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if own == null:
				continue
			if own.has_meta(Bake.META):
				mirrored = true
				own.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if mip_toggle.button_pressed else BaseMaterial3D.TEXTURE_FILTER_LINEAR
				var active := instance.get_active_material(surface) as StandardMaterial3D
				if active:
					active.texture_filter = own.texture_filter
			elif own.albedo_texture and Bake.eligible(MeshUtils.fix_for_material(own), own.albedo_texture.resource_path):
				mirrored = true
		if focused.button_pressed and not mirrored:
			instance.hide()
			continue
		var bounds: AABB = instance.global_transform * instance.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	var scale_factor := 4.0 / maxf(box.size.x, maxf(box.size.y, box.size.z))
	stage.scale = Vector3.ONE * scale_factor
	stage.position = -box.get_center() * scale_factor

func _preview_mipmaps(instance: MeshInstance3D) -> void:
	# The shipped Stage textures have no mips. Explicitly generate them on
	# BOTH sides only for this diagnostic, without modifying saved resources.
	var active := instance.get_active_material(0)
	var texture: Texture2D = active.albedo_texture if active is StandardMaterial3D else active.get_shader_parameter("albedo_texture")
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.generate_mipmaps()
	var preview := ImageTexture.create_from_image(image)
	if active is StandardMaterial3D:
		active.albedo_texture = preview
	else:
		active.set_shader_parameter("albedo_texture", preview)

func _settle() -> void:
	# Window occlusion can suppress automatic draw signals on macOS. The
	# review probe still needs completed offscreen viewport renders.
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	RenderingServer.force_draw(false)

func _save_native() -> void:
	var packed := PackedScene.new()
	packed.pack(stage_roots[1])
	var path := _ensure_output().path_join(source_id + "-native-preview.scn")
	ResourceSaver.save(packed, path)
	result.text = "Saved full Stage preview to " + path

func _verify() -> void:
	busy = true
	var report: Array = []
	var failed := false
	var representatives: Dictionary = {}
	for path in paths:
		var folder: String = str(path).split("/")[4]
		if not representatives.has(folder):
			representatives[folder] = str(path).get_file().trim_suffix("_m.glb")
	for id in representatives.values():
		var index := -1
		for i in range(paths.size()):
			if str(paths[i]).get_file() == id + "_m.glb":
				index = i
		if index < 0:
			failed = true
			continue
		source_picker.select(index)
		source_id = id
		for isolate in [false, true]:
			focused.set_pressed_no_signal(isolate)
			for mipmaps in [false, true]:
				mip_toggle.set_pressed_no_signal(mipmaps)
				_rebuild()
				await _settle()
				var original := viewports[0].get_texture().get_image()
				var native := viewports[1].get_texture().get_image()
				var stats := _diff(original, native)
				stats["stage"] = id
				stats["focused"] = isolate
				stats["mipmaps"] = mipmaps
				stats["native_applied"] = stage_roots[1].has_meta("native_mirror_applied")
				report.append(stats)
				var tag := "%s-%s-%s" % [id, "mirrors" if isolate else "room", "source-mips" if mipmaps else "base-level"]
				get_viewport().get_texture().get_image().save_png(_ensure_output().path_join(tag + ".png"))
				if not stats.native_applied or stats.foreground_pixels < 100 or (not mipmaps and stats.foreground_mean_rgb > 1.5):
					failed = true
				print("[stage-render] ", tag, " ", JSON.stringify(stats))
	var file := FileAccess.open(_ensure_output().path_join("render-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"failed": failed, "results": report}, "  "))
	print("[stage-render] ", "FAIL" if failed else "DONE ok")
	get_tree().quit(1 if failed else 0)

func _source_paths() -> Array:
	return Variants.manifest().get("stages", {}).keys()

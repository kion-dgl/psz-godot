extends Node3D
## Debug scene: loads a single GLB + config JSON, applies texture fixes,
## and prints diagnostics so you can visually verify the result.

const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")
const TEXTURE_FIX_SHADER := preload("res://scripts/3d/field/texture_fix_shader.gdshader")

@export var area_id: String = "arca"
@export var stage_id: String = "s06a_ib2"

var _texture_fixes: Array = []


func _ready() -> void:
	var area_cfg: Dictionary = GridGenerator.AREA_CONFIG.get(area_id, {})
	if area_cfg.is_empty():
		push_error("[TextureFixTest] Unknown area_id: %s" % area_id)
		return

	var folder: String = area_cfg["folder"]

	# Load texture fixes from config JSON
	_texture_fixes = _load_texture_fixes(folder, stage_id)
	print("[TextureFixTest] Loaded %d texture fixes" % _texture_fixes.size())
	for fix in _texture_fixes:
		print("  %s → meshes=%s  repeat=(%s,%s)  offset=(%s,%s)  wrapS=%s wrapT=%s" % [
			fix.get("textureFile", "?"),
			fix.get("meshNames", []),
			fix.get("repeatX", 1), fix.get("repeatY", 1),
			fix.get("offsetX", 0), fix.get("offsetY", 0),
			fix.get("wrapS", "repeat"), fix.get("wrapT", "repeat"),
		])

	# Load GLB from raw stages
	var variant: String = stage_id[3] if stage_id.length() >= 4 else "a"
	var subfolder := "%s_%s" % [folder, variant]
	var map_path := "res://assets/stages/%s/%s/lndmd/%s-scene.glb" % [subfolder, stage_id, stage_id]
	var packed_scene := load(map_path) as PackedScene
	if not packed_scene:
		push_error("[TextureFixTest] Failed to load: %s" % map_path)
		return

	var map_root := packed_scene.instantiate() as Node3D
	map_root.name = "Map"
	add_child(map_root)

	# Apply material fixes
	_fix_materials(map_root)

	# Place a simple camera
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 15, 20)
	cam.look_at(Vector3.ZERO)

	print("[TextureFixTest] Scene loaded. Use WASD to look around.")


func _load_texture_fixes(_folder: String, sid: String) -> Array:
	var config_path := "res://data/stage_configs/unified-stage-configs.json"
	if not FileAccess.file_exists(config_path):
		return []
	var file := FileAccess.open(config_path, FileAccess.READ)
	if not file:
		push_error("[TextureFixTest] Cannot open: %s" % config_path)
		return []
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[TextureFixTest] JSON parse error: %s" % config_path)
		return []
	var all_configs: Dictionary = json.data
	if not all_configs.has(sid):
		return []
	return all_configs[sid].get("textureFixes", [])


func _find_texture_fix_for_mesh(mesh_name: String) -> Dictionary:
	for fix in _texture_fixes:
		var mesh_names: Array = fix.get("meshNames", [])
		for mn in mesh_names:
			if str(mn) == mesh_name:
				return fix
	return {}


static func _wrap_mode_int(mode: String) -> int:
	match mode:
		"mirror": return 1
		"clamp": return 2
	return 0  # repeat


func _fix_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var fix := _find_texture_fix_for_mesh(mesh_inst.name)
		var needs_shader := not fix.is_empty() and (
			str(fix.get("wrapS", "repeat")) == "mirror" or
			str(fix.get("wrapT", "repeat")) == "mirror")
		if not fix.is_empty():
			print("[TextureFixTest] APPLYING fix to mesh '%s': repeat=(%s,%s) offset=(%s,%s) shader=%s" % [
				mesh_inst.name,
				fix.get("repeatX", 1), fix.get("repeatY", 1),
				fix.get("offsetX", 0), fix.get("offsetY", 0),
				needs_shader,
			])
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var std_mat := mat as StandardMaterial3D
				if needs_shader:
					var shader_mat := ShaderMaterial.new()
					shader_mat.shader = TEXTURE_FIX_SHADER
					if std_mat.albedo_texture:
						shader_mat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
					shader_mat.set_shader_parameter("albedo_color", std_mat.albedo_color)
					shader_mat.set_shader_parameter("uv_scale", Vector3(fix.get("repeatX", 1.0), fix.get("repeatY", 1.0), 1.0))
					shader_mat.set_shader_parameter("uv_offset", Vector3(fix.get("offsetX", 0.0), fix.get("offsetY", 0.0), 0.0))
					shader_mat.set_shader_parameter("wrap_s", _wrap_mode_int(str(fix.get("wrapS", "repeat"))))
					shader_mat.set_shader_parameter("wrap_t", _wrap_mode_int(str(fix.get("wrapT", "repeat"))))
					mesh_inst.set_surface_override_material(i, shader_mat)
				else:
					var new_mat := std_mat.duplicate() as StandardMaterial3D
					new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					new_mat.texture_repeat = true
					if not fix.is_empty():
						new_mat.uv1_scale = Vector3(fix.get("repeatX", 1.0), fix.get("repeatY", 1.0), 1.0)
						new_mat.uv1_offset = Vector3(fix.get("offsetX", 0.0), fix.get("offsetY", 0.0), 0.0)
						if str(fix.get("wrapS", "repeat")) == "clamp" or str(fix.get("wrapT", "repeat")) == "clamp":
							new_mat.texture_repeat = false
					mesh_inst.set_surface_override_material(i, new_mat)
	for child in node.get_children():
		_fix_materials(child)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()

extends Node3D
## Snowfield material-pipeline test scene (#646) — fast iteration on the
## in-game look without booting through menus.
##
## Runs the EXACT production material path the field controller runs —
## SmoothNormals → texture-fix shader pass (mirror-wrap surfaces become
## ShaderMaterial) → snowfield strip — against the real TimeManager night
## rig, with lanterns from the unified config. Startup prints dump every
## ground material's state; keys tune the rig live.
##
## Keys: ESC quit · [ / ] moon energy · - / = ambient energy · P re-dump.

const STAGE_ID := "s03a_ic1"
const STAGE_GLB := "res://assets/stages/snowfield_a/s03a_ic1/lndmd/s03a_ic1_m.glb"
const FLOOR_GLB := "res://assets/stages/snowfield_a/s03a_ic1/lndmd/s03a_ic1-floor.glb"
const UNIFIED_CONFIG := "res://data/stage_configs/unified-stage-configs.json"
const GLOBAL_FIXES := "res://data/stage_configs/global-texture-fixes.json"
const TEXTURE_FIX_SHADER := preload("res://scripts/3d/field/texture_fix_shader.gdshader")
const PLAYER_SCENE := preload("res://scenes/3d/player/player.tscn")
const ORBIT_CAMERA_SCENE := preload("res://scenes/3d/camera/orbit_camera.tscn")

const PLAYER_SPAWN := Vector3(0, 1.5, 6)

var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _dir_light: DirectionalLight3D
var _moonlight: DirectionalLight3D
var player: CharacterBody3D
var _glow_dot_tex: ImageTexture
var _bake_mix := -1.0  # -1 = untouched bake; 0..1 = neutralize blend
var _status: Label


func _ready() -> void:
	_build_environment()
	_load_stage()
	_load_floor_collision()
	_spawn_player(PLAYER_SPAWN)
	_spawn_snow()
	var count := _spawn_lanterns()
	_build_status_label()
	_update_status()
	print("[MatTest] ready — %d lanterns; keys: [/] moon, -/= ambient, T white toggle, P dump" % count)
	_dump_materials()


func _process(_delta: float) -> void:
	if Input.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_BRACKETLEFT:
				_moonlight.light_energy = maxf(0.0, _moonlight.light_energy - 0.1)
				print("[MatTest] moon energy %.2f" % _moonlight.light_energy)
				_update_status()
			KEY_BRACKETRIGHT:
				_moonlight.light_energy = _moonlight.light_energy + 0.1
				print("[MatTest] moon energy %.2f" % _moonlight.light_energy)
				_update_status()
			KEY_MINUS:
				_env.ambient_light_energy = maxf(0.0, _env.ambient_light_energy - 0.05)
				print("[MatTest] ambient energy %.2f" % _env.ambient_light_energy)
				_update_status()
			KEY_EQUAL:
				_env.ambient_light_energy = _env.ambient_light_energy + 0.05
				print("[MatTest] ambient energy %.2f" % _env.ambient_light_energy)
				_update_status()
			KEY_P:
				_dump_materials()
			KEY_T:
				_bake_mix = 1.0
				_apply_mix()
			KEY_COMMA:
				if _bake_mix < 0.0:
					_bake_mix = 1.0
				_bake_mix = maxf(0.0, _bake_mix - 0.1)
				_apply_mix()
			KEY_PERIOD:
				if _bake_mix < 0.0:
					_bake_mix = 1.0
				_bake_mix = minf(1.0, _bake_mix + 0.1)
				_apply_mix()
			KEY_R:
				get_tree().reload_current_scene()


## The field scene's environment recreated from valley_field.tscn, then the
## controller's snowfield treatment: Filmic white 6, COLOR ambient, and the
## real TimeManager night preset with the sun-at-night dropped.
func _build_environment() -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_top_color = Color(0.3, 0.55, 0.65)
	_sky_mat.sky_horizon_color = Color(0.6, 0.7, 0.6)
	_sky_mat.ground_bottom_color = Color(0.15, 0.12, 0.08)
	_sky_mat.ground_horizon_color = Color(0.45, 0.42, 0.35)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.85, 0.9, 0.85)
	_env.ambient_light_energy = 0.7
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 6.0
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	_dir_light = DirectionalLight3D.new()
	_dir_light.light_energy = 0.8
	_dir_light.shadow_enabled = true
	add_child(_dir_light)
	_moonlight = DirectionalLight3D.new()
	_moonlight.light_color = Color(0.5, 0.6, 0.9)
	_moonlight.light_energy = 0.0
	_moonlight.visible = false
	add_child(_moonlight)

	# The real production lighting call at the pinned night hour.
	TimeManager.current_hour = 22.0
	TimeManager.apply_to_scene(_env, _sky_mat, _dir_light, _moonlight)
	TimeManager.current_hour = 10.0
	_dir_light.light_energy = 0.0  # snowfield pin: single moonlight fill
	# White-mode baseline (#646): with vertex albedo stripped, bright
	# textures saturate under the bake-tuned energies. Approved white
	# balance starts lower; tune live with [ and -/=.
	_env.ambient_light_energy = 0.35
	_moonlight.light_energy = 0.4
	print("[MatTest] env: ambient src=%d color=%s energy=%.2f | sun=%.2f moon=%.2f vis=%s" % [
		_env.ambient_light_source, _env.ambient_light_color, _env.ambient_light_energy,
		_dir_light.light_energy, _moonlight.light_energy, _moonlight.visible])


func _load_stage() -> void:
	var packed := load(STAGE_GLB) as PackedScene
	var map_root := packed.instantiate() as Node3D
	map_root.name = "Map"
	add_child(map_root)
	var n := SmoothNormals.ensure(map_root, 2)
	_apply_texture_fixes(map_root)
	print("[MatTest] room: %d meshes normal-fixed (bake intact — W strips live, R reloads)" % n)


## The field controller's _fix_materials core: mirror-wrap textures get the
## custom shader (Godot can't mirror-repeat imported textures natively).
func _apply_texture_fixes(root: Node) -> void:
	var fixes := {}
	var file := FileAccess.open(GLOBAL_FIXES, FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			for key in json.data:
				# Keys may carry a "#N" material suffix — the texture name is
				# everything before it.
				var tex_name: String = str(key).split("#")[0]
				fixes[tex_name] = json.data[key]
	if fixes.is_empty():
		print("[MatTest] WARNING: no global texture fixes parsed")
	_apply_fix_pass(root, fixes)


func _apply_fix_pass(node: Node, fixes: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in range(SmoothNormals._surface_count(mi)):
			var mat := SmoothNormals._active_material(mi, i)
			if not (mat is StandardMaterial3D):
				continue
			var std := mat as StandardMaterial3D
			if not std.albedo_texture:
				continue
			var tex_name: String = std.albedo_texture.resource_path.get_file()
			var fix: Dictionary = fixes.get(tex_name, {})
			var wrap_s: String = str(fix.get("wrapS", "repeat"))
			var wrap_t: String = str(fix.get("wrapT", "repeat"))
			if wrap_s != "mirror" and wrap_t != "mirror":
				continue
			var shader_mat := ShaderMaterial.new()
			shader_mat.shader = TEXTURE_FIX_SHADER
			shader_mat.set_shader_parameter("albedo_texture", std.albedo_texture)
			shader_mat.set_shader_parameter("albedo_color", std.albedo_color)
			shader_mat.set_shader_parameter("uv_scale", Vector3(
				float(fix.get("repeatX", 1.0)), float(fix.get("repeatY", 1.0)), 1.0))
			shader_mat.set_shader_parameter("uv_offset", Vector3(
				float(fix.get("offsetX", 0.0)), float(fix.get("offsetY", 0.0)), 0.0))
			shader_mat.set_shader_parameter("wrap_s", 1 if wrap_s == "mirror" else 0)
			shader_mat.set_shader_parameter("wrap_t", 1 if wrap_t == "mirror" else 0)
			mi.set_surface_override_material(i, shader_mat)
	for child in node.get_children():
		_apply_fix_pass(child, fixes)


func _load_floor_collision() -> void:
	if not ResourceLoader.exists(FLOOR_GLB):
		return
	var floor_root := (load(FLOOR_GLB) as PackedScene).instantiate() as Node3D
	add_child(floor_root)
	if MapCollisionBuilder.has_static_body(floor_root):
		MapCollisionBuilder.setup_map_collision(floor_root)
	else:
		MapCollisionBuilder.create_collision_from_meshes(floor_root)


func _spawn_player(pos: Vector3) -> void:
	player = PLAYER_SCENE.instantiate() as CharacterBody3D
	player.add_to_group("player")
	add_child(player)
	player.global_position = pos
	player.spawn_position = pos
	SmoothNormals.ensure(player, 2)
	SmoothNormals.make_lit(player)
	var orbit_camera := ORBIT_CAMERA_SCENE.instantiate()
	add_child(orbit_camera)
	orbit_camera.set_target(player)
	orbit_camera.camera_rotation = PI


func _spawn_snow() -> void:
	var snow := GPUParticles3D.new()
	snow.name = "WeatherSnow"
	snow.amount = 450
	snow.lifetime = 5.0
	snow.visibility_aabb = AABB(Vector3(-70, -4, -70), Vector3(140, 40, 140))
	snow.fixed_fps = 30
	snow.interpolate = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 10.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 3.5
	mat.gravity = Vector3(0.3, -0.5, 0.1)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(26, 0.5, 26)
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	mat.damping_min = 0.2
	mat.damping_max = 0.5
	snow.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var quad_mat := StandardMaterial3D.new()
	quad_mat.albedo_color = Color(0.95, 0.97, 1.0, 0.8)
	quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = quad_mat
	snow.draw_pass_1 = quad
	snow.preprocess = 5.0
	snow.position.y = 16.0
	player.add_child(snow)


func _spawn_lanterns() -> int:
	var file := FileAccess.open(UNIFIED_CONFIG, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return 0
	var stage := (json.data as Dictionary).get(STAGE_ID, {}) as Dictionary
	var count := 0
	for effect in stage.get("effects", []):
		if str(effect.get("category", "")) == "placed":
			_spawn_placed_effect(effect)
			count += 1
	return count


func _spawn_placed_effect(effect: Dictionary) -> void:
	var pos_arr: Array = effect.get("position", [0, 0, 0])
	var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	var color_arr: Array = effect.get("color", [1, 1, 1])
	var color := Color(float(color_arr[0]), float(color_arr[1]), float(color_arr[2]))
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = float(effect.get("light_intensity", 1.0)) * 8.0
	light.omni_range = float(effect.get("light_radius", 5.0)) * 2.0
	light.omni_attenuation = 2.0
	root.add_child(light)
	var flame := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	flame.mesh = sphere
	var fm := StandardMaterial3D.new()
	fm.albedo_color = color
	fm.emission_enabled = true
	fm.emission = color
	fm.emission_energy_multiplier = 2.0
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override = fm
	flame.position = Vector3(0, 0.6, 0)
	root.add_child(flame)


## Dump every room surface's material state — the ground truth for
## debugging "white/unlit": class, shader, texture bound, vertex flags.
func _build_status_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_status.position = Vector2(12, 8)
	layer.add_child(_status)


func _update_status() -> void:
	if not _status:
		return
	var mode := "BAKE untouched" if _bake_mix < 0.0 else "bake mix %.1f" % _bake_mix
	_status.text = "%s | moon %.2f  ambient %.2f | T white · ,/. mix · R reload · P dump" % [
		mode,
		_moonlight.light_energy if _moonlight else 0.0,
		_env.ambient_light_energy if _env else 0.0,
	]


func _dump_materials() -> void:
	var map := get_node_or_null("Map")
	if not map:
		return
	var lines: Array[String] = []
	var counts := _dump_pass(map, lines)
	for line in lines:
		print("[MatTest]" + line)
	print("[MatTest] materials: %d ShaderMaterial, %d StandardMaterial3D" % [counts[0], counts[1]])


func _dump_pass(node: Node, lines: Array[String]) -> Array:
	var shader_count := 0
	var std_count := 0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		var has_normals := false
		if mesh is ArrayMesh and mesh.get_surface_count() > 0:
			has_normals = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] != null
		for i in range(SmoothNormals._surface_count(mi)):
			var mat := SmoothNormals._active_material(mi, i)
			if mat is ShaderMaterial:
				shader_count += 1
				var sm := mat as ShaderMaterial
				var tex = sm.get_shader_parameter("albedo_texture")
				lines.append("  SHADER surf %d tex=%s uvc=%s normals=%s" % [
					i, "bound" if tex != null else "NULL",
					str(sm.get_shader_parameter("use_vertex_color")), has_normals])
			elif mat is StandardMaterial3D:
				std_count += 1
				var std := mat as StandardMaterial3D
				lines.append("  STD    surf %d vcol=%s normals=%s" % [
					i, std.vertex_color_use_as_albedo, has_normals])
	var out := [shader_count, std_count]
	for child in node.get_children():
		var sub := _dump_pass(child, lines)
		out[0] += sub[0]
		out[1] += sub[1]
	return out

## The neutralize blend (the LightingLab slider): 0 = full bake, 1 = white.
## Live via , and . — T snaps to full white.
func _apply_mix() -> void:
	var map := get_node_or_null("Map")
	if map:
		var n := SmoothNormals.neutralize_vertex_colors(map, _bake_mix)
		SmoothNormals.make_lit(map)
		print("[MatTest] bake mix %.1f (%d meshes)" % [_bake_mix, n])
	_update_status()

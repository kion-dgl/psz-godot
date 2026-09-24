extends RefCounted
## Shared rig for the field-lighting tool scenes (#659) — the environment +
## walkable-player construction the labs duplicated (code-graph's dup gate):
## the field scene's environment recreated from valley_field.tscn, and the
## mattest player spawn (player + orbit camera, SmoothNormals pipeline).
## Static funcs; const-preload callers (the CI class-cache pattern).

const TEXTURE_FIX_SHADER := preload("res://scripts/3d/field/texture_fix_shader.gdshader")
const TEXTURE_FIX_SHADER_UNLIT := preload("res://scripts/3d/field/texture_fix_shader_unlit.gdshader")
const WATERFALL_SHADER := preload("res://scripts/3d/field/waterfall_shader.gdshader")


## The field scene's environment: Filmic white-6 tonemap, COLOR ambient, the
## valley sky material, sun + moon directionals (moon cool, hidden until a
## slot or knob raises it). Returns the pieces the labs' slot applies pin.
static func build_environment(root: Node) -> Dictionary:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.55, 0.65)
	sky_mat.sky_horizon_color = Color(0.6, 0.7, 0.6)
	sky_mat.ground_bottom_color = Color(0.15, 0.12, 0.08)
	sky_mat.ground_horizon_color = Color(0.45, 0.42, 0.35)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	var dir_light := DirectionalLight3D.new()
	root.add_child(dir_light)
	var moonlight := DirectionalLight3D.new()
	moonlight.light_color = Color(0.5, 0.6, 0.9)
	moonlight.light_energy = 0.0
	moonlight.visible = false
	root.add_child(moonlight)
	return {"env": env, "sky_mat": sky_mat, "dir_light": dir_light, "moonlight": moonlight}


## Apply a resolved FieldSlotTable row over the phase preset — the pin
## sequence the field's _apply_field_slot runs, shared by the labs (hour pin,
## TimeManager apply, then the row's rig overrides verbatim).
static func apply_slot(slot: Dictionary, env: Environment, sky_mat: ProceduralSkyMaterial,
		dir_light: DirectionalLight3D, moonlight: DirectionalLight3D, default_hour := 5.5) -> void:
	TimeManager.current_hour = float(slot.get("hour", default_hour))
	TimeManager.apply_to_scene(env, sky_mat, dir_light, moonlight)
	if slot.has("sun_energy"):
		dir_light.light_energy = float(slot["sun_energy"])
	if slot.has("ambient_energy"):
		env.ambient_light_energy = float(slot["ambient_energy"])
	if slot.has("moon_energy"):
		moonlight.light_energy = float(slot["moon_energy"])
		moonlight.visible = true
	if slot.has("moon_pitch"):
		moonlight.rotation_degrees.x = float(slot["moon_pitch"])
	if slot.get("moon_shadows", false):
		moonlight.shadow_enabled = true
		moonlight.shadow_blur = 1.0
	if slot.get("sun_shadows", false):
		dir_light.shadow_enabled = true
		dir_light.shadow_blur = 1.0
		# Acne guard (#648): grazing-angle ground under a steep sun bands
		# at the default normal bias — 4.0 holds shadows smooth.
		dir_light.shadow_normal_bias = 4.0
	# The baked-sun-spot hang (#649) — kept in lockstep with
	# ValleyFieldController._apply_field_slot (the dup-gate): the origin
	# aims, then a pinned pitch (if any) survives the aim.
	if slot.has("sun_origin"):
		var origin: Array = slot["sun_origin"]
		dir_light.global_position = Vector3(
			float(origin[0]), float(origin[1]), float(origin[2]))
		dir_light.look_at(Vector3.ZERO, Vector3.UP)
	if slot.has("sun_pitch"):
		dir_light.rotation_degrees.x = float(slot["sun_pitch"])
	# Overcast rows (#649): desaturated rig + sky bands over the preset —
	# kept in lockstep with ValleyFieldController._apply_field_slot (the
	# dup-gate: this must apply exactly what the field applies).
	if slot.has("sun_color"):
		dir_light.light_color = slot["sun_color"]
	if slot.has("ambient_color"):
		env.ambient_light_color = slot["ambient_color"]
	if slot.has("sky_top_color"):
		sky_mat.sky_top_color = slot["sky_top_color"]
	if slot.has("sky_horizon_color"):
		sky_mat.sky_horizon_color = slot["sky_horizon_color"]


## The full lab environment boot: the field environment, the area's REAL
## slot resolved + applied, then the PSZ_WALK_* rig overrides. Returns
## build_environment's dict plus "slot". (#649 dedup — the labs ran this
## sequence by hand.)
static func boot_environment(lab: Node, area_id: String, stage_id: String) -> Dictionary:
	var built := build_environment(lab)
	var slot: Dictionary = FieldSlotTable.slot_for(area_id, stage_id)
	apply_slot(slot, built["env"], built["sky_mat"], built["dir_light"],
		built["moonlight"])
	if not OS.get_environment("PSZ_WALK_SUN_PITCH").is_empty():
		built["dir_light"].rotation_degrees.x = \
			float(OS.get_environment("PSZ_WALK_SUN_PITCH"))
	if OS.get_environment("PSZ_WALK_SUN_SHADOWS") == "0":
		built["dir_light"].shadow_enabled = false
	if not OS.get_environment("PSZ_WALK_SHADOW_BIAS").is_empty():
		built["dir_light"].shadow_bias = \
			float(OS.get_environment("PSZ_WALK_SHADOW_BIAS"))
	if not OS.get_environment("PSZ_WALK_SHADOW_NORMAL_BIAS").is_empty():
		built["dir_light"].shadow_normal_bias = \
			float(OS.get_environment("PSZ_WALK_SHADOW_NORMAL_BIAS"))
	if not OS.get_environment("PSZ_WALK_SUN").is_empty():
		built["dir_light"].light_energy = float(OS.get_environment("PSZ_WALK_SUN"))
	if not OS.get_environment("PSZ_WALK_AMBIENT").is_empty():
		built["env"].ambient_light_energy = \
			float(OS.get_environment("PSZ_WALK_AMBIENT"))
	built["slot"] = slot
	return built


## The production stage load, shared — the field's room-build order
## verbatim: normals → strip embedded GLB lights → the surface pass (cheat
## context) → the bake white-strategy → the cheat rig → the optional
## skybox GLB. Returns the map root (null when the GLB is missing).
static func load_field_stage(scene_root: Node, slot: Dictionary,
		subfolder: String, stage_id: String, bake_mix := 0.0) -> Node3D:
	var packed := load("res://assets/stages/%s/%s/lndmd/%s_m.glb"
		% [subfolder, stage_id, stage_id]) as PackedScene
	if not packed:
		push_error("[FieldLab] no stage GLB for %s" % stage_id)
		return null
	var map_root := packed.instantiate() as Node3D
	map_root.name = "Map"
	scene_root.add_child(map_root)
	SmoothNormals.ensure(map_root, 2)
	WeatherController.new(null)._strip_embedded_lights(map_root)
	var cheat := slot.has("lit_surfaces") and not slot.has("bake_mix")
	MeshUtils.apply_field_materials(map_root, TEXTURE_FIX_SHADER,
		WATERFALL_SHADER, slot.get("geometry_casts_shadows", false), cheat,
		TEXTURE_FIX_SHADER_UNLIT, slot.get("lit_surfaces", []))
	if slot.has("bake_mix"):
		SmoothNormals.neutralize_vertex_colors(map_root, bake_mix)
		SmoothNormals.make_lit(map_root)
	if slot.has("lit_surfaces"):
		MeshUtils.split_mesh_surfaces(map_root)
		var lit_n: int = MeshUtils.make_lit_surfaces(map_root, slot["lit_surfaces"])
		var forced: int = MeshUtils.make_unlit(map_root, slot["lit_surfaces"])
		print("[FieldLab] cheat rig: %d lit, %d forced unlit" % [lit_n, forced])
	var skybox_path := "res://assets/stages/%s/%s/lndmd/skybox/o0s_zsky.glb" \
		% [subfolder, stage_id]
	if ResourceLoader.exists(skybox_path):
		var skybox := (load(skybox_path) as PackedScene).instantiate() as Node3D
		skybox.name = "Skybox"
		map_root.add_child(skybox)
		MeshUtils.apply_field_materials(skybox, TEXTURE_FIX_SHADER,
			WATERFALL_SHADER, false, cheat,
			TEXTURE_FIX_SHADER_UNLIT, slot.get("lit_surfaces", []))
	return map_root


## The stage's collision floor + the row's catcher — returns the walkable
## height (NAN when the floor GLB is absent).
static func load_floor_collision(scene_root: Node, floor_path: String,
		slot: Dictionary) -> float:
	if not ResourceLoader.exists(floor_path):
		return NAN
	var floor_root := (load(floor_path) as PackedScene).instantiate() as Node3D
	scene_root.add_child(floor_root)
	floor_root.visible = false
	if MapCollisionBuilder.has_static_body(floor_root):
		MapCollisionBuilder.setup_map_collision(floor_root)
	else:
		MapCollisionBuilder.create_collision_from_meshes(floor_root)
	if slot.get("shadow_catcher", false):
		var catcher := MeshUtils.make_shadow_catcher(floor_root)
		if catcher:
			scene_root.add_child(catcher)
			print("[FieldLab] shadow catcher on the collision shell")
	return MeshUtils.floor_top(floor_root)


## The row's weather, as the field spawns it (the shared WeatherController
## build — no lab copy to drift). PSZ_WALK_WEATHER=0 skips (clean diffs).
static func spawn_weather(player: Node, slot: Dictionary) -> void:
	if OS.get_environment("PSZ_WALK_WEATHER") == "0":
		return
	var node := WeatherController.build_weather_node(str(slot.get("weather", "")))
	if not node:
		return
	player.add_child(node)
	node.restart()
	print("[FieldLab] weather: %s" % str(slot.get("weather", "")))


## The labs' shared tuning keys — the common rig knobs (ambient, sun,
## pitch, shadow toggles/biases). Returns true when handled; the caller
## refreshes its status line.
static func handle_tune_key(keycode: int, env: Environment,
		dir_light: DirectionalLight3D) -> bool:
	match keycode:
		KEY_COMMA:
			env.ambient_light_energy = maxf(0.0, env.ambient_light_energy - 0.05)
		KEY_PERIOD:
			env.ambient_light_energy += 0.05
		KEY_9:
			dir_light.light_energy = maxf(0.0, dir_light.light_energy - 0.05)
		KEY_0:
			dir_light.light_energy += 0.05
		KEY_7:
			dir_light.rotation_degrees.x = \
				maxf(-89.0, dir_light.rotation_degrees.x - 5.0)
		KEY_8:
			dir_light.rotation_degrees.x = \
				minf(-5.0, dir_light.rotation_degrees.x + 5.0)
		KEY_M:
			dir_light.shadow_enabled = not dir_light.shadow_enabled
		KEY_F:
			dir_light.shadow_normal_bias = \
				maxf(0.0, dir_light.shadow_normal_bias - 1.0)
		KEY_G:
			dir_light.shadow_normal_bias = \
				minf(16.0, dir_light.shadow_normal_bias + 1.0)
		KEY_C:
			dir_light.shadow_bias = maxf(0.0, dir_light.shadow_bias - 0.05)
		KEY_V:
			dir_light.shadow_bias = minf(1.0, dir_light.shadow_bias + 0.05)
		_:
			return false
	return true


## The labs' status read-out line (top-left, amber).
static func make_status_label(root: Node) -> Label:
	var status := Label.new()
	status.position = Vector2(12, 12)
	status.add_theme_font_size_override("font_size", 18)
	status.modulate = Color(1, 1, 0.8, 0.9)
	root.add_child(status)
	return status


## A walkable player + orbit camera on the production material path
## (SmoothNormals ensure + make_lit) — the mattest spawn, shared.
static func spawn_player(root: Node, pos: Vector3) -> CharacterBody3D:
	const PLAYER_SCENE := preload("res://scenes/3d/player/player.tscn")
	const ORBIT_CAMERA_SCENE := preload("res://scenes/3d/camera/orbit_camera.tscn")
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.add_to_group("player")
	root.add_child(player)
	player.global_position = pos
	player.spawn_position = pos
	SmoothNormals.ensure(player, 2)
	SmoothNormals.make_lit(player)

	var orbit_camera := ORBIT_CAMERA_SCENE.instantiate()
	root.add_child(orbit_camera)
	orbit_camera.set_target(player)
	orbit_camera.camera_rotation = PI
	return player


## A lab's screenshot smoke-run state: the env-read shot path plus the frame
## counter. step() is the shared _process body — it advances the counter, ESC
## quits a live (shot-less) lab, and with a path set frame 45 saves the
## viewport PNG and quits (the run needs ~40 frames to settle: spawn, weather,
## first shadow frame; ESC cannot abort a capture mid-run). Labs whose
## _process does more (the valley A/B flow) keep their own counters instead.
class ShotRun:
	extends RefCounted
	var path := ""
	var frame := 0

	func step(lab: Node, tag: String) -> void:
		frame += 1
		if path.is_empty():
			if Input.is_action_pressed("ui_cancel"):
				lab.get_tree().quit()
			return
		if frame < 45:
			return
		var img := lab.get_viewport().get_texture().get_image()
		img.save_png(path)
		print("[%s] screenshot → %s" % [tag, path])
		lab.get_tree().quit()

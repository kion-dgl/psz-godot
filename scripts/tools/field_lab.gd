extends RefCounted
## Shared rig for the field-lighting tool scenes (#659) — the environment +
## walkable-player construction the labs duplicated (code-graph's dup gate):
## the field scene's environment recreated from valley_field.tscn, and the
## mattest player spawn (player + orbit camera, SmoothNormals pipeline).
## Static funcs; const-preload callers (the CI class-cache pattern).


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

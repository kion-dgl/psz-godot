extends Node3D
## Lantern test scene (#646) — one room, night rig, the authored lantern
## effects from the stage editor, falling snow, and a walkable player.
##
## Loads s03a_ga1 straight from its GLB plus its floor-collision GLB, reads
## the unified stage config (same file the field controller reads — lanterns
## live there alongside floor/portals per room), and spawns each placed
## effect with the identical parameter math as
## WeatherController._spawn_placed_effect. A minimal night environment
## stands in for TimeManager so the lantern pools are the star of the show.
## SPACE toggles COLOR_0 baked ⇄ white; ESC quits.

const STAGE_ID := "s03a_ga1"
const STAGE_GLB := "res://assets/stages/snowfield_a/s03a_ga1/lndmd/s03a_ga1_m.glb"
const FLOOR_GLB := "res://assets/stages/snowfield_a/s03a_ga1/lndmd/s03a_ga1-floor.glb"
const UNIFIED_CONFIG := "res://data/stage_configs/unified-stage-configs.json"
const PLAYER_SCENE := preload("res://scenes/3d/player/player.tscn")
const ORBIT_CAMERA_SCENE := preload("res://scenes/3d/camera/orbit_camera.tscn")

# TimeManager's NIGHT preset (scripts/autoloads/time_manager.gd) — moon
# doubled from 0.25 for this test: with near-black ambient, the eye has no
# mid-range reference and the lantern pools read as an instant clip.
const NIGHT_AMBIENT := Color(0.2, 0.25, 0.45)
const NIGHT_AMBIENT_ENERGY := 0.5
const NIGHT_SKY := Color(0.02, 0.02, 0.08)
const NIGHT_MOON_COLOR := Color(0.6, 0.7, 1.0)
const NIGHT_MOON_ENERGY := 0.55

const PLAYER_SPAWN := Vector3(0, 1.5, 6)

var player: CharacterBody3D
var _glow_dot_tex: ImageTexture
# Per-surface duplicated room materials — flipping vertex_color_use_as_albedo
# on these never touches the imported shared resources.
var _room_materials: Array[StandardMaterial3D] = []
var _vertex_colors_baked := true


func _ready() -> void:
	_build_environment()
	_load_stage()
	_load_floor_collision()
	_spawn_player(PLAYER_SPAWN)
	_build_snow()
	var count := _spawn_effects_from_config()
	print("[LanternTest] %s ready — %d lantern effects from %s" % [STAGE_ID, count, UNIFIED_CONFIG])
	print("[LanternTest] SPACE toggles COLOR_0: baked ⇄ white (currently baked)")
	print("[LanternTest] player materials forced lit; moonlight casts shadows")


func _process(_delta: float) -> void:
	if Input.is_action_pressed("ui_cancel"):
		get_tree().quit()


## SPACE toggles COLOR_0: the authored bake (vertex_color_use_as_albedo ON —
## how every field renders today) versus white (OFF — the rig owns shading,
## the LightingLab's "white" strategy and #646 objective 2).
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_vertex_colors_baked = not _vertex_colors_baked
		for mat in _room_materials:
			mat.vertex_color_use_as_albedo = _vertex_colors_baked
		print("[LanternTest] vertex colors: %s" % (
			"BAKED (authored COLOR_0)" if _vertex_colors_baked else "WHITE (rig owns shading)"))


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = NIGHT_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = NIGHT_AMBIENT
	env.ambient_light_energy = NIGHT_AMBIENT_ENERGY
	# Tone mapping research:
	# - Linear clips brights; ACES has a gamma bug (#87251: dark mids,
	#   oversaturated highlights, crunchy terminator).
	# - Plain AgX crushes low values — moon+ambient fell to apparent black,
	#   leaving the lantern as the only visible light ("one light at a
	#   time"). Blender pairs AgX with 8–10 look controls; Godot ships none
	#   (godot-proposals #7545).
	# - The docs' photoreal recipe: FILMIC with tonemap_white 6–8 — film-like
	#   rolloff without ACES's bug, highlights desaturate toward the light
	#   tint, mids survive. Exposure lifted for the night baseline.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.2
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.light_color = NIGHT_MOON_COLOR
	moon.light_energy = NIGHT_MOON_ENERGY
	moon.rotation_degrees = Vector3(-40, 30, 0)
	# The character and the room geometry cast real shadows (DS rooms ship
	# SHADOW_CASTING defaults — nothing strips them here).
	moon.shadow_enabled = true
	moon.shadow_blur = 1.0
	add_child(moon)


## The player model GLB is KHR_materials_unlit like the rooms — it imports
## unshaded, so lights can't touch it and the lanterns can't paint it
## orange. Flip its duplicated materials to per-pixel shading.
func _make_player_lit(root: Node) -> void:
	if root is MeshInstance3D:
		var mesh_inst := root as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				mesh_inst.set_surface_override_material(i, dup)
	for child in root.get_children():
		_make_player_lit(child)


## Floor collision from the stage's floor GLB, exactly as the field loads it
## (import-suffix StaticBodies when present, else built from the mesh).
func _load_floor_collision() -> void:
	if not ResourceLoader.exists(FLOOR_GLB):
		push_error("[LanternTest] missing floor GLB %s" % FLOOR_GLB)
		return
	var floor_root := (load(FLOOR_GLB) as PackedScene).instantiate() as Node3D
	floor_root.name = "FloorCollision"
	add_child(floor_root)
	if MapCollisionBuilder.has_static_body(floor_root):
		MapCollisionBuilder.setup_map_collision(floor_root)
	else:
		MapCollisionBuilder.create_collision_from_meshes(floor_root)


## The game's own player + follow camera, spawned the way the field does
## (orbit camera targets the player; blob shadow grounds them on the snow).
func _spawn_player(pos: Vector3) -> void:
	player = PLAYER_SCENE.instantiate() as CharacterBody3D
	player.add_to_group("player")
	add_child(player)
	player.global_position = pos
	player.spawn_position = pos
	var player_meshes := SmoothNormals.ensure(player, 2)
	print("[LanternTest] smooth normals generated on %d player meshes (2 smoothing passes)" % player_meshes)
	_make_player_lit(player)

	var orbit_camera := ORBIT_CAMERA_SCENE.instantiate()
	add_child(orbit_camera)
	orbit_camera.set_target(player)
	orbit_camera.camera_rotation = PI


func _load_stage() -> void:
	var packed := load(STAGE_GLB) as PackedScene
	if packed == null:
		push_error("[LanternTest] failed to load %s" % STAGE_GLB)
		return
	var map_root := packed.instantiate() as Node3D
	map_root.name = "Map"
	add_child(map_root)
	# The GLBs ship no NORMAL attribute and Godot's importer doesn't generate
	# one — without this every surface shades with a constant normal (flat,
	# flip-on-rotate lighting). Same for the player below.
	var normaled := SmoothNormals.ensure(map_root, 2)
	print("[LanternTest] smooth normals generated on %d room meshes (2 smoothing passes)" % normaled)
	_collect_room_materials(map_root)


## Duplicate each surface material into an override so the SPACE toggle can
## flip vertex_color_use_as_albedo without mutating the imported resource
## (which is shared across instantiations).
func _collect_room_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				mesh_inst.set_surface_override_material(i, dup)
				_room_materials.append(dup)
	for child in node.get_children():
		_collect_room_materials(child)


## Falling snow — the WeatherController snow rig (scripts/3d/field/
## weather_controller.gd) verbatim in parameter terms: same fall velocity
## (2.0–3.5), drift gravity, spin, damping and 0.08 soft-white quads — just
## pinned to the room center with a wider emission box since the orbiting
## camera frames the whole room instead of a player.
func _build_snow() -> void:
	var snow := GPUParticles3D.new()
	snow.name = "WeatherSnow"
	snow.amount = 450
	snow.lifetime = 5.0
	snow.visibility_aabb = AABB(Vector3(-70, -4, -70), Vector3(140, 40, 140))
	# Deterministic sim — the default (fixed_fps=0, interpolate=true) can
	# freeze the particle system until something invalidates the transform.
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
	mat.angle_min = 0.0
	mat.angle_max = 360.0
	mat.angular_velocity_min = -30.0
	mat.angular_velocity_max = 30.0
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
	# Player-attached, like the field's weather pass — the volume follows
	# the walker instead of sitting at the room center.
	player.add_child(snow)
	# Same kick the weather pass uses: restart after the first frames so the
	# preprocess runs against settled transforms and snow appears mid-fall.
	await get_tree().process_frame
	await get_tree().process_frame
	snow.restart()


func _spawn_effects_from_config() -> int:
	if not FileAccess.file_exists(UNIFIED_CONFIG):
		push_error("[LanternTest] missing %s" % UNIFIED_CONFIG)
		return 0
	var file := FileAccess.open(UNIFIED_CONFIG, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[LanternTest] failed to parse %s: %s" % [UNIFIED_CONFIG, json.get_error_message()])
		return 0
	var stage := (json.data as Dictionary).get(STAGE_ID, {}) as Dictionary
	var count := 0
	for effect in stage.get("effects", []):
		if str(effect.get("category", "")) == "placed":
			_spawn_placed_effect(effect)
			count += 1
	return count


## Mirrors WeatherController._spawn_placed_effect (scripts/3d/field/
## weather_controller.gd) — same parameter mapping, so what reads well here
## reads well in the field.
func _spawn_placed_effect(effect: Dictionary) -> void:
	var pos_arr: Array = effect.get("position", [0, 0, 0])
	var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	var color_arr: Array = effect.get("color", [1, 1, 1])
	var color := Color(float(color_arr[0]), float(color_arr[1]), float(color_arr[2]))
	var p_count: int = int(effect.get("count", 10))
	var radius: float = float(effect.get("radius", 1.0))
	var height: float = float(effect.get("height", 5.0))
	var speed: float = float(effect.get("speed", 1.0))
	var light_intensity: float = float(effect.get("light_intensity", 0.0))
	var light_radius: float = float(effect.get("light_radius", 5.0))
	var effect_type := str(effect.get("type", "spores"))

	var root := Node3D.new()
	root.name = "StageEffect_%s" % effect_type
	root.position = pos
	add_child(root)

	var particles := GPUParticles3D.new()
	particles.name = "%sParticles" % effect_type.capitalize()
	particles.amount = p_count
	particles.lifetime = height / maxf(speed, 0.1)
	particles.visibility_aabb = AABB(
		Vector3(-radius, 0, -radius), Vector3(radius * 2, height, radius * 2))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 15.0
	mat.initial_velocity_min = speed * 0.7
	mat.initial_velocity_max = speed * 1.3
	mat.gravity = Vector3(0, 0, 0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = radius
	mat.scale_min = 1.0
	mat.scale_max = 2.0
	mat.color = color
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color.r, color.g, color.b, 0.0))
	gradient.add_point(0.15, Color(color.r, color.g, color.b, 1.0))
	gradient.add_point(0.7, Color(color.r, color.g, color.b, 1.0))
	gradient.set_color(gradient.get_point_count() - 1, Color(color.r, color.g, color.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	mat.color_ramp = ramp
	particles.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.15)
	var quad_mat := StandardMaterial3D.new()
	quad_mat.albedo_color = color
	quad_mat.albedo_texture = _get_glow_dot_texture()
	quad_mat.emission_enabled = true
	quad_mat.emission = color
	quad_mat.emission_energy_multiplier = 3.0
	quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad_mat.no_depth_test = true
	quad.material = quad_mat
	particles.draw_pass_1 = quad
	root.add_child(particles)

	if light_intensity > 0:
		var light := OmniLight3D.new()
		light.name = "LanternLight"
		light.light_color = color
		light.light_energy = light_intensity * 8.0
		light.omni_range = light_radius * 2.0
		# Godot docs (class_omnilight3d): attenuation 2.0 IS inverse-square;
		# 1.0 is ≈1/d — with energy 12 everything in range stays above 1.0
		# (AgX crunches it all bright) while the range edge is a hard cutoff
		# to zero. Bright-or-black, no partial falloff. 2.0 gives the
		# three.js-style gradient: bright at arm's length, subtle by ~8u.
		light.omni_attenuation = 2.0
		root.add_child(light)


func _get_glow_dot_texture() -> ImageTexture:
	if _glow_dot_tex:
		return _glow_dot_tex
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var max_r := size / 2.0
	for y in range(size):
		for x in range(size):
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(center) / max_r
			var alpha: float = clampf(1.0 - _smoothstep(0.0, 1.0, dist), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_glow_dot_tex = ImageTexture.create_from_image(img)
	return _glow_dot_tex


static func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

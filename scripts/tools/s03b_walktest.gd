extends Node3D
## Snowfield B cave WALK lab (#659 lock pass) — walk the rig in a B cave
## without the snowfield-A run-up: the production material path (SmoothNormals
## → mirror-wrap fixes → bake neutralize + make_lit) under the REAL
## FieldSlotTable s03b row, with the stage's authored anchor lights + glow,
## a controllable player, and the field controller's tuner semantics — values
## read out in the [FieldSlot] shape and transfer 1:1 into the slot row.
##
## Env:  PSZ_WALK_STAGE=s03b_xb2   boot stage (one of the 12 anchored caves)
##       PSZ_WALK_SHOT=/tmp/o.png  screenshot + quit (smoke; else live keys)
## Keys: , / .  ambient ∓/± 0.05      [ / ]  moon ∓/± 0.05
##       - / =  bake mix ∓/± 0.05     P      read-out (field format)
##       M       moon shadows toggle  N      next cave · R reload · ESC quit

const STAGE_GLB_FMT := "res://assets/stages/snowfield_b/%s/lndmd/%s_m.glb"
const FLOOR_GLB_FMT := "res://assets/stages/snowfield_b/%s/lndmd/%s-floor.glb"
const SKYBOX_GLB_FMT := "res://assets/stages/snowfield_b/%s/lndmd/skybox/o0s_zsky.glb"
const UNIFIED_CONFIG := "res://data/stage_configs/unified-stage-configs.json"
const TEXTURE_FIX_SHADER := preload("res://scripts/3d/field/texture_fix_shader.gdshader")
const WATERFALL_SHADER := preload("res://scripts/3d/field/waterfall_shader.gdshader")
const FieldSlotTableScript := preload("res://scripts/3d/field/field_slot_table.gd")
const WeatherControllerScript := preload("res://scripts/3d/field/weather_controller.gd")
const PLAYER_SCENE := preload("res://scenes/3d/player/player.tscn")
const ORBIT_CAMERA_SCENE := preload("res://scenes/3d/camera/orbit_camera.tscn")

## The 12 anchored caves (unified-config authors effects/glow for exactly
## these) — N cycles in this order.
const STAGES := [
	"s03b_xb2", "s03b_ic1", "s03b_ic3", "s03b_ib1",
	"s03b_lb3", "s03b_lc1", "s03b_lc2", "s03b_na1",
	"s03b_nb2", "s03b_tc3", "s03b_td1", "s03b_td2",
]

## N's selection survives the scene reload that swaps the room.
static var _pending_stage := ""

var _stage_id := "s03b_xb2"
var _map_root: Node3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _dir_light: DirectionalLight3D
var _moonlight: DirectionalLight3D
var _bake_mix := 0.25
var _slot := {}
var _shot_path := ""
var _shot_frame := 0
var _status: Label


func _ready() -> void:
	if not _pending_stage.is_empty():
		_stage_id = _pending_stage
		_pending_stage = ""
	elif not OS.get_environment("PSZ_WALK_STAGE").is_empty():
		_stage_id = OS.get_environment("PSZ_WALK_STAGE")
	_shot_path = OS.get_environment("PSZ_WALK_SHOT")
	_build_environment()
	_load_stage()
	_load_floor_collision()
	_spawn_player(Vector3(0, 1.5, 10))
	_spawn_authored_effects()
	_build_status_label()
	_readout()
	print("[BWalk] ready — N next cave, R reload, ESC quit")


func _process(_delta: float) -> void:
	if Input.is_action_pressed("ui_cancel"):
		get_tree().quit()
	if _shot_path.is_empty():
		return
	_shot_frame += 1
	if _shot_frame < 45:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_path)
	print("[BWalk] screenshot → %s" % _shot_path)
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_COMMA:
			_env.ambient_light_energy = maxf(0.0, _env.ambient_light_energy - 0.05)
		KEY_PERIOD:
			_env.ambient_light_energy += 0.05
		KEY_BRACKETLEFT:
			_moonlight.light_energy = maxf(0.0, _moonlight.light_energy - 0.05)
		KEY_BRACKETRIGHT:
			_moonlight.light_energy += 0.05
		KEY_MINUS:
			_bake_mix = maxf(0.0, _bake_mix - 0.05)
			SmoothNormals.neutralize_vertex_colors(_map_root, _bake_mix)
		KEY_EQUAL:
			_bake_mix = minf(1.0, _bake_mix + 0.05)
			SmoothNormals.neutralize_vertex_colors(_map_root, _bake_mix)
		KEY_M:
			_moonlight.shadow_enabled = not _moonlight.shadow_enabled
		KEY_N:
			_pending_stage = STAGES[(STAGES.find(_stage_id) + 1) % STAGES.size()]
			get_tree().reload_current_scene()
		KEY_R:
			get_tree().reload_current_scene()
		KEY_P:
			_readout()
		_:
			return
	_update_status()


## The field scene's environment + the production slot apply — the real s03b
## row the field controller resolves (hour 5.5 pre-dawn, sun 0, moon sky-fill),
## with the row's energies and moon_shadows honored verbatim.
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
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 6.0
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)
	_dir_light = DirectionalLight3D.new()
	add_child(_dir_light)
	_moonlight = DirectionalLight3D.new()
	_moonlight.light_color = Color(0.5, 0.6, 0.9)
	_moonlight.light_energy = 0.0
	_moonlight.visible = false
	add_child(_moonlight)
	_slot = FieldSlotTableScript.slot_for("rioh", _stage_id)
	TimeManager.current_hour = float(_slot.get("hour", 5.5))
	TimeManager.apply_to_scene(_env, _sky_mat, _dir_light, _moonlight)
	if _slot.has("sun_energy"):
		_dir_light.light_energy = float(_slot["sun_energy"])
	if _slot.has("ambient_energy"):
		_env.ambient_light_energy = float(_slot["ambient_energy"])
	if _slot.has("moon_energy"):
		_moonlight.light_energy = float(_slot["moon_energy"])
		_moonlight.visible = true
	if _slot.get("moon_shadows", false):
		_moonlight.shadow_enabled = true
	_bake_mix = float(_slot.get("bake_mix", 0.0))


func _load_stage() -> void:
	var packed := load(STAGE_GLB_FMT % [_stage_id, _stage_id]) as PackedScene
	if not packed:
		push_error("[BWalk] no stage GLB for %s" % _stage_id)
		return
	_map_root = packed.instantiate() as Node3D
	_map_root.name = "Map"
	add_child(_map_root)
	# The field's room-build order verbatim (valley_field_controller._ready):
	# normals → strip embedded GLB lights → the full surface pass → bake
	# neutralize + make_lit. The surface pass is the shared MeshUtils one —
	# the earlier lab-only mirror pass left non-mirror surfaces (the pools)
	# as raw BLEND, which read see-through from the ground.
	SmoothNormals.ensure(_map_root, 2)
	WeatherControllerScript.new(null)._strip_embedded_lights(_map_root)
	MeshUtils.apply_field_materials(_map_root, TEXTURE_FIX_SHADER, WATERFALL_SHADER,
		_slot.get("geometry_casts_shadows", false))
	SmoothNormals.neutralize_vertex_colors(_map_root, _bake_mix)
	SmoothNormals.make_lit(_map_root)
	# Per-stage skybox GLB when the stage ships one (B caves so far do not).
	if ResourceLoader.exists(SKYBOX_GLB_FMT % [_stage_id, _stage_id]):
		var skybox := (load(SKYBOX_GLB_FMT % [_stage_id, _stage_id]) as PackedScene).instantiate() as Node3D
		skybox.name = "Skybox"
		_map_root.add_child(skybox)
		MeshUtils.apply_field_materials(skybox, TEXTURE_FIX_SHADER, WATERFALL_SHADER,
			_slot.get("geometry_casts_shadows", false))


## The stage's collision floor (mattest pattern): covers the real floor, kept
## invisible — the _m visuals come from the map root above.
func _load_floor_collision() -> void:
	var floor_path := FLOOR_GLB_FMT % [_stage_id, _stage_id]
	if not ResourceLoader.exists(floor_path):
		return
	var floor_root := (load(floor_path) as PackedScene).instantiate() as Node3D
	add_child(floor_root)
	floor_root.visible = false
	if MapCollisionBuilder.has_static_body(floor_root):
		MapCollisionBuilder.setup_map_collision(floor_root)
	else:
		MapCollisionBuilder.create_collision_from_meshes(floor_root)


func _spawn_player(pos: Vector3) -> void:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
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


## The authored placed effects for this stage — plain `light` entries become
## omnis exactly as the field builds them, plus the glow material pass.
func _spawn_authored_effects() -> void:
	var file := FileAccess.open(UNIFIED_CONFIG, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	var ok := json.parse(file.get_as_text()) == OK
	file.close()
	if not ok:
		return
	var cfg: Dictionary = (json.data as Dictionary).get(_stage_id, {})
	var count := 0
	for effect in cfg.get("effects", []):
		if str(effect.get("category", "")) != "placed" \
				or str(effect.get("type", "")) != "light":
			continue
		var pos_arr: Array = effect.get("position", [0, 0, 0])
		var color_arr: Array = effect.get("color", [1, 1, 1])
		var light := OmniLight3D.new()
		light.name = "AnchorLight_%d" % count
		light.light_color = Color(float(color_arr[0]), float(color_arr[1]), float(color_arr[2]))
		light.light_energy = float(effect.get("intensity", 1.0))
		light.omni_range = float(effect.get("radius", 6.0))
		light.omni_attenuation = 2.0
		light.shadow_enabled = false
		light.position = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		_map_root.add_child(light)
		count += 1
	var passes: Dictionary = {}
	for g in cfg.get("glowMaterials", []):
		passes[str(g.get("material", ""))] = g
	var touched := MeshUtils.apply_glow_materials(_map_root, passes)
	print("[BWalk] %s — %d anchors, glow on %d surfaces" % [_stage_id, count, touched])


## The read-out prints in the field's [FieldSlot] shape so a tuned set is
## copied into the FieldSlotTable row without translation.
func _readout() -> void:
	print("[FieldSlot %s] ambient %.2f  moon %.2f  bake mix %.2f  moon_shadows %s" % [
		_stage_id, _env.ambient_light_energy, _moonlight.light_energy,
		_bake_mix, str(_moonlight.shadow_enabled).to_lower()])


func _build_status_label() -> void:
	_status = Label.new()
	_status.position = Vector2(12, 12)
	_status.add_theme_font_size_override("font_size", 18)
	_status.modulate = Color(1, 1, 0.8, 0.9)
	add_child(_status)
	_update_status()


func _update_status() -> void:
	_status.text = "%s — ambient %.2f  moon %.2f  bake %.2f  shadows %s" % [
		_stage_id, _env.ambient_light_energy, _moonlight.light_energy,
		_bake_mix, "on" if _moonlight.shadow_enabled else "off"]

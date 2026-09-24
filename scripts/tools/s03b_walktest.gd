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
##       - / =  bake mix ∓/± 0.05     9 / 0  moon higher / lower (pitch ∓/± 5°)
##       P       read-out (field format)     M      moon shadows toggle
##       N       next cave · R reload · ESC quit

const STAGE_GLB_FMT := "res://assets/stages/snowfield_b/%s/lndmd/%s_m.glb"
const FLOOR_GLB_FMT := "res://assets/stages/snowfield_b/%s/lndmd/%s-floor.glb"
const SKYBOX_GLB_FMT := "res://assets/stages/snowfield_b/%s/lndmd/skybox/o0s_zsky.glb"
const UNIFIED_CONFIG := "res://data/stage_configs/unified-stage-configs.json"
const TEXTURE_FIX_SHADER := preload("res://scripts/3d/field/texture_fix_shader.gdshader")
const WATERFALL_SHADER := preload("res://scripts/3d/field/waterfall_shader.gdshader")
const FieldSlotTableScript := preload("res://scripts/3d/field/field_slot_table.gd")
const WeatherControllerScript := preload("res://scripts/3d/field/weather_controller.gd")
const ValleyFieldScript := preload("res://scripts/3d/field/valley_field_controller.gd")
const FieldLabScript := preload("res://scripts/tools/field_lab.gd")

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
var _player: CharacterBody3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _dir_light: DirectionalLight3D
var _moonlight: DirectionalLight3D
var _bake_mix := 0.25
var _slot := {}
var _shot := FieldLabScript.ShotRun.new()
var _status: Label


func _ready() -> void:
	if not _pending_stage.is_empty():
		_stage_id = _pending_stage
		_pending_stage = ""
	elif not OS.get_environment("PSZ_WALK_STAGE").is_empty():
		_stage_id = OS.get_environment("PSZ_WALK_STAGE")
	_shot.path = OS.get_environment("PSZ_WALK_SHOT")
	_build_environment()
	_load_stage()
	_load_floor_collision()
	_spawn_player(Vector3(0, 1.5, 10))
	_spawn_authored_effects()
	_spawn_snow()
	_build_status_label()
	_readout()
	print("[BWalk] ready — N next cave, R reload, ESC quit")


func _process(_delta: float) -> void:
	_shot.step(self, "BWalk")


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
		KEY_9:
			_moonlight.rotation_degrees.x = maxf(-89.0, _moonlight.rotation_degrees.x - 5.0)
		KEY_0:
			_moonlight.rotation_degrees.x = minf(-5.0, _moonlight.rotation_degrees.x + 5.0)
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
## with the row's energies, elevation, and moon_shadows honored verbatim.
func _build_environment() -> void:
	var built := FieldLabScript.build_environment(self)
	_env = built["env"]
	_sky_mat = built["sky_mat"]
	_dir_light = built["dir_light"]
	_moonlight = built["moonlight"]
	_slot = FieldSlotTableScript.slot_for("rioh", _stage_id)
	FieldLabScript.apply_slot(_slot, _env, _sky_mat, _dir_light, _moonlight)
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
	_player = FieldLabScript.spawn_player(self, pos)


## The authored placed effects for this stage — every category:"placed" entry
## goes through the REAL WeatherController._spawn_placed_effect (lights AND
## the kinoko spore drifts), so what walks here is what spawns in-field.
## The glow material pass follows, exactly as the field orders it.
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
	var weather := WeatherControllerScript.new(self)
	var lights := 0
	var spores := 0
	for effect in cfg.get("effects", []):
		if str(effect.get("category", "")) != "placed":
			continue
		weather._spawn_placed_effect(effect)
		if str(effect.get("type", "")) == "light":
			lights += 1
		else:
			spores += 1
	var passes: Dictionary = {}
	for g in cfg.get("glowMaterials", []):
		passes[str(g.get("material", ""))] = g
	var touched := MeshUtils.apply_glow_materials(_map_root, passes)
	print("[BWalk] %s — %d anchors, %d spores, glow on %d surfaces" % [
		_stage_id, lights, spores, touched])


## The row's weather, for the open-ceiling caves (the 5 enclosed stages stay
## skipped, same INDOOR_STAGES gate the field applies). Falls as the field's
## snow does: attached to the player, following them through the room.
func _spawn_snow() -> void:
	if str(_slot.get("weather", "")) != "snow" \
			or _stage_id in ValleyFieldScript.INDOOR_STAGES:
		return
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
	_player.add_child(snow)
	print("[BWalk] snow (open-ceiling cave)")


## The read-out prints in the field's [FieldSlot] shape so a tuned set is
## copied into the FieldSlotTable row without translation.
func _readout() -> void:
	print("[FieldSlot %s] ambient %.2f  moon %.2f  bake mix %.2f  moon_pitch %.0f  moon_shadows %s" % [
		_stage_id, _env.ambient_light_energy, _moonlight.light_energy,
		_bake_mix, _moonlight.rotation_degrees.x,
		str(_moonlight.shadow_enabled).to_lower()])


func _build_status_label() -> void:
	_status = FieldLabScript.make_status_label(self)
	_update_status()


func _update_status() -> void:
	_status.text = "%s — ambient %.2f  moon %.2f  bake %.2f  pitch %.0f°  shadows %s" % [
		_stage_id, _env.ambient_light_energy, _moonlight.light_energy,
		_bake_mix, _moonlight.rotation_degrees.x,
		"on" if _moonlight.shadow_enabled else "off"]

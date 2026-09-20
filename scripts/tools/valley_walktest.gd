extends Node3D
## Valley WALK lab (#648 lock pass) — walk the day rig in a valley room
## without the city run-up: the production material path (SmoothNormals →
## mirror-wrap fixes → bake neutralize + make_lit) under the REAL
## FieldSlotTable gurhacia row, with the stage's authored anchor lights + glow,
## the row's sand drift (the exact WeatherController build), a controllable
## player, and the field controller's tuner semantics — values read out in the
## [FieldSlot] shape and transfer 1:1 into the slot row.
##
## Env:  PSZ_WALK_STAGE=s01a_ga1   boot stage (default: first of STAGES)
##       PSZ_WALK_SHOT=/tmp/o.png  screenshot + quit (smoke; else live keys)
##       PSZ_WALK_SUN_PITCH=-60    sun elevation override (screenshot sweeps;
##                                 the live path is the 7/8 keys)
##       PSZ_WALK_SUN_SHADOWS=0    force sun shadows off (A/B diffs; the row
##                                 default is on)
##       PSZ_WALK_HIDE_PLAYER=1    hide the player model (A/B shadow diffs)
##       PSZ_WALK_WEATHER=0        skip the weather node (clean A/B diffs)
##       PSZ_WALK_SUN=0.9          sun energy override · PSZ_WALK_AMBIENT=0.4
##                                 ambient override (balance sweeps)
## Keys: , / .  ambient ∓/± 0.05      9 / 0  sun ∓/± 0.05
##       7 / 8  sun lower / steeper (pitch ∓/± 5°)
##       [ / ]  moon ∓/± 0.05         - / =  bake mix ∓/± 0.05
##       P       read-out (field format)     M      sun shadows toggle
##       N       next room · R reload · ESC quit

const STAGE_GLB_FMT := "res://assets/stages/%s/%s/lndmd/%s_m.glb"
const FLOOR_GLB_FMT := "res://assets/stages/%s/%s/lndmd/%s-floor.glb"
const UNIFIED_CONFIG := "res://data/stage_configs/unified-stage-configs.json"
const TEXTURE_FIX_SHADER := preload("res://scripts/3d/field/texture_fix_shader.gdshader")
const WATERFALL_SHADER := preload("res://scripts/3d/field/waterfall_shader.gdshader")
const FieldSlotTableScript := preload("res://scripts/3d/field/field_slot_table.gd")
const WeatherControllerScript := preload("res://scripts/3d/field/weather_controller.gd")
const FieldLabScript := preload("res://scripts/tools/field_lab.gd")

## Representative rooms (N cycles in this order): the oasis A-field look, the
## toro-lantern D room, a bridge+waterfall B room, the e transition, the boss
## arena — the extremes the day rig must hold.
const STAGES := [
	"s01a_ga1", "s01a_td1", "s01b_lb1", "s01e_ia1", "s01z_na1",
]

## N's selection survives the scene reload that swaps the room.
static var _pending_stage := ""

var _stage_id := "s01a_ga1"
var _map_root: Node3D
var _player: CharacterBody3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _dir_light: DirectionalLight3D
var _moonlight: DirectionalLight3D
var _bake_mix := 0.6
var _slot := {}
var _shot_path := ""
var _shot_frame := 0
var _status: Label
var _sun_open := false
var _shells_disarmed := 0
var _floor_top := NAN


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
	# #648 shell carve-out, production order: the row's geometry casting armed
	# everything in _load_stage's material pass; an enclosing shell now stops
	# CASTING (it would shadow its own interior and delete the player's
	# dynamic shadow) while still receiving shadows.
	_sun_open = _slot.get("sun_shadows", false) \
		and MeshUtils.sun_reaches_room(_map_root,
			_dir_light.global_transform.basis.z, _floor_top)
	if _slot.get("sun_shadows", false):
		_shells_disarmed = MeshUtils.disable_enclosing_casters(_map_root,
			_dir_light.global_transform.basis.z, _floor_top)
		# Panorama placement (#648): the compat shadow eye must sit in the
		# interior air — at the origin it's under the bridge deck in lb rooms.
		MeshUtils.place_light_inside_room(_dir_light, _map_root, _floor_top)
	_spawn_player(Vector3(0, 1.5, 10))
	if OS.get_environment("PSZ_WALK_HIDE_PLAYER") == "1":
		(_player.get_node("PlayerModel") as Node3D).visible = false
	_spawn_authored_effects()
	_spawn_weather()
	_build_status_label()
	_readout()
	print("[ValleyWalk] ready — N next room, R reload, ESC quit")


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
	print("[ValleyWalk] screenshot → %s" % _shot_path)
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_COMMA:
			_env.ambient_light_energy = maxf(0.0, _env.ambient_light_energy - 0.05)
		KEY_PERIOD:
			_env.ambient_light_energy += 0.05
		KEY_9:
			_dir_light.light_energy = maxf(0.0, _dir_light.light_energy - 0.05)
		KEY_0:
			_dir_light.light_energy += 0.05
		KEY_7:
			_dir_light.rotation_degrees.x = maxf(-89.0, _dir_light.rotation_degrees.x - 5.0)
		KEY_8:
			_dir_light.rotation_degrees.x = minf(-5.0, _dir_light.rotation_degrees.x + 5.0)
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
			_dir_light.shadow_enabled = not _dir_light.shadow_enabled
		KEY_N:
			_pending_stage = STAGES[(STAGES.find(_stage_id) + 1) % STAGES.size()] \
				if _stage_id in STAGES else STAGES[0]
			get_tree().reload_current_scene()
		KEY_R:
			get_tree().reload_current_scene()
		KEY_P:
			_readout()
		_:
			return
	_update_status()


## The field scene's environment + the production slot apply — the real
## gurhacia row the field controller resolves (hour 10 day, sun the shadow
## source), with the row's energies and sun_shadows honored verbatim.
func _build_environment() -> void:
	var built := FieldLabScript.build_environment(self)
	_env = built["env"]
	_sky_mat = built["sky_mat"]
	_dir_light = built["dir_light"]
	_moonlight = built["moonlight"]
	_slot = FieldSlotTableScript.slot_for("gurhacia", _stage_id)
	FieldLabScript.apply_slot(_slot, _env, _sky_mat, _dir_light, _moonlight)
	if not OS.get_environment("PSZ_WALK_SUN_PITCH").is_empty():
		_dir_light.rotation_degrees.x = float(OS.get_environment("PSZ_WALK_SUN_PITCH"))
	if OS.get_environment("PSZ_WALK_SUN_SHADOWS") == "0":
		_dir_light.shadow_enabled = false
	if not OS.get_environment("PSZ_WALK_SUN").is_empty():
		_dir_light.light_energy = float(OS.get_environment("PSZ_WALK_SUN"))
	if not OS.get_environment("PSZ_WALK_AMBIENT").is_empty():
		_env.ambient_light_energy = float(OS.get_environment("PSZ_WALK_AMBIENT"))
	_bake_mix = float(_slot.get("bake_mix", 0.0))


## Valley stages live in variant subfolders (valley_a/b/e/z — the variant
## char at index 3 of the stage id, same rule as the controller's
## _get_stage_subfolder).
func _subfolder() -> String:
	return "valley_" + _stage_id.substr(3, 1)


func _load_stage() -> void:
	var packed := load(STAGE_GLB_FMT % [_subfolder(), _stage_id, _stage_id]) as PackedScene
	if not packed:
		push_error("[ValleyWalk] no stage GLB for %s" % _stage_id)
		return
	_map_root = packed.instantiate() as Node3D
	_map_root.name = "Map"
	add_child(_map_root)
	# The field's room-build order verbatim (valley_field_controller._ready):
	# normals → strip embedded GLB lights → the full surface pass (geometry
	# casting per the row) → bake neutralize + make_lit.
	SmoothNormals.ensure(_map_root, 2)
	WeatherControllerScript.new(null)._strip_embedded_lights(_map_root)
	MeshUtils.apply_field_materials(_map_root, TEXTURE_FIX_SHADER, WATERFALL_SHADER,
		_slot.get("geometry_casts_shadows", false))
	SmoothNormals.neutralize_vertex_colors(_map_root, _bake_mix)
	SmoothNormals.make_lit(_map_root)


## The stage's collision floor (mattest pattern): covers the real floor, kept
## invisible — the _m visuals come from the map root above. Its AABB top is
## the walkable height the sun-enclosure test samples from.
func _load_floor_collision() -> void:
	var floor_path := FLOOR_GLB_FMT % [_subfolder(), _stage_id, _stage_id]
	if not ResourceLoader.exists(floor_path):
		return
	var floor_root := (load(floor_path) as PackedScene).instantiate() as Node3D
	add_child(floor_root)
	floor_root.visible = false
	var box := _node_aabb(floor_root)
	if box.size != Vector3.ZERO:
		_floor_top = box.end.y
	if MapCollisionBuilder.has_static_body(floor_root):
		MapCollisionBuilder.setup_map_collision(floor_root)
	else:
		MapCollisionBuilder.create_collision_from_meshes(floor_root)


func _node_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


func _spawn_player(pos: Vector3) -> void:
	_player = FieldLabScript.spawn_player(self, pos)


## The authored placed effects for this stage — every category:"placed" entry
## goes through the REAL WeatherController._spawn_placed_effect, so what walks
## here is what spawns in-field. The glow material pass follows, exactly as
## the field orders it.
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
	var other := 0
	for effect in cfg.get("effects", []):
		if str(effect.get("category", "")) != "placed":
			continue
		weather._spawn_placed_effect(effect)
		if str(effect.get("type", "")) == "light":
			lights += 1
		else:
			other += 1
	var passes: Dictionary = {}
	for g in cfg.get("glowMaterials", []):
		passes[str(g.get("material", ""))] = g
	var touched := MeshUtils.apply_glow_materials(_map_root, passes)
	print("[ValleyWalk] %s — %d anchors, %d other effects, glow on %d surfaces" % [
		_stage_id, lights, other, touched])


## The row's weather, as the field spawns it (the shared WeatherController
## build — no lab copy to drift). PSZ_WALK_WEATHER=0 skips it (clean diffs).
func _spawn_weather() -> void:
	if OS.get_environment("PSZ_WALK_WEATHER") == "0":
		return
	var node := WeatherControllerScript.build_weather_node(str(_slot.get("weather", "")))
	if not node:
		return
	_player.add_child(node)
	node.restart()
	print("[ValleyWalk] weather: %s" % str(_slot.get("weather", "")))


## The read-out prints in the field's [FieldSlot] shape so a tuned set is
## copied into the FieldSlotTable row without translation.
func _readout() -> void:
	print("[FieldSlot %s] ambient %.2f  sun %.2f  moon %.2f  bake mix %.2f  sun_pitch %.0f  sun_shadows %s" % [
		_stage_id, _env.ambient_light_energy, _dir_light.light_energy,
		_moonlight.light_energy, _bake_mix, _dir_light.rotation_degrees.x,
		str(_dir_light.shadow_enabled).to_lower()])
	print("[ValleyWalk] room sun: %s" %
		("open" if _sun_open else "enclosed — %d shell mesh(es) cast-off (#648)" % _shells_disarmed))


func _build_status_label() -> void:
	_status = Label.new()
	_status.position = Vector2(12, 12)
	_status.add_theme_font_size_override("font_size", 18)
	_status.modulate = Color(1, 1, 0.8, 0.9)
	add_child(_status)
	_update_status()


func _update_status() -> void:
	_status.text = "%s — ambient %.2f  sun %.2f  bake %.2f  pitch %.0f°  shadows %s  room %s" % [
		_stage_id, _env.ambient_light_energy, _dir_light.light_energy,
		_bake_mix, _dir_light.rotation_degrees.x,
		"on" if _dir_light.shadow_enabled else "off",
		"sun-open" if _sun_open else "shell-cast-off"]

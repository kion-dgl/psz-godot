extends Node3D
## Wetlands WALK lab (#649 lock pass) — walk the overcast rig in a wetlands
## room without the city run-up: the production material path (SmoothNormals →
## mirror-wrap fixes → the cheat rig with an EMPTY lit list — the whole stage
## keeps its bake) under the REAL FieldSlotTable ozette row, the catcher, the
## post-light pools, the row's rain (the exact WeatherController build), a
## controllable player, and a lit-prop preview crate. Tuning semantics match
## the valley lab — values read out in the [FieldSlot] shape and transfer 1:1
## into the slot row.
##
## Env:  PSZ_WALK_STAGE=s02a_ga1   boot stage (default: first of STAGES)
##       PSZ_WALK_SHOT=/tmp/o.png  screenshot + quit (smoke; else live keys)
##       PSZ_WALK_SUN_PITCH=-55    sun elevation override
##       PSZ_WALK_SUN_SHADOWS=0    force sun shadows off (A/B diffs)
##       PSZ_WALK_HIDE_PLAYER=1    hide the player model (A/B shadow diffs)
##       PSZ_WALK_WEATHER=0        skip the rain node (clean A/B diffs)
##       PSZ_WALK_SUN=0.35         sun energy override · PSZ_WALK_AMBIENT=0.9
##                                 ambient override (balance sweeps)
##       PSZ_WALK_POST_LIGHTS=0    skip the lamp-post pools (A/B diffs)
##       PSZ_WALK_SPAWN=x,z        override the boot spawn (default: the
##                                 stage config's gate/defaultSpawn)
##       PSZ_WALK_PROP=0           skip the lit-prop preview crate
##       PSZ_WALK_PILLAR=1         spawn a 3m control pillar beside the player
##                                 (a caster that provably shadows)
## Keys: , / .  ambient ∓/± 0.05      9 / 0  sun ∓/± 0.05
##       7 / 8  sun lower / steeper (pitch ∓/± 5°)
##       [ / ]  post pools ∓/± 0.25× (omni energy; 0.00 kills them — mind
##              the status line when the lanterns go dark)
##       D       dark room — sun 0 + sun shadows OFF + ambient 0.05 (the
##               lantern-dominance probe state); press again to restore
##       F / G  shadow normal bias ∓/± 1 (acne stripes on grazing ground)
##       C / V  shadow bias ∓/± 0.05
##       P       read-out (field format)     M      sun shadows toggle
##       N       next room · R reload · ESC quit
##
## Post-light base energy/range/color are MeshUtils constants (POST_LIGHT_*);
## [ / ] scale the pools live against those bases — read the multiplier out
## with P and fold it back into the constant (or say the word and it becomes
## row data).

const FLOOR_GLB_FMT := "res://assets/stages/%s/%s/lndmd/%s-floor.glb"
const UNIFIED_CONFIG := "res://data/stage_configs/unified-stage-configs.json"
const PROP_GLB := "res://assets/objects/wetlands/o02_cont.glb"
const WeatherControllerScript := preload("res://scripts/3d/field/weather_controller.gd")
const FieldLabScript := preload("res://scripts/tools/field_lab.gd")

## The arc in walk order (N cycles): the settled overcast look on A and E
## (peeking sun, drizzle), B's lb room, then the b_ga1 TURN — dark and
## rainy on the road into Z — and the octopus-boss downpour.
const STAGES := [
	"s02a_ga1", "s02e_ia1", "s02b_lb1", "s02b_ga1", "s02z_na1",
]

## N's selection survives the scene reload that swaps the room.
static var _pending_stage := ""

var _stage_id := "s02a_ga1"
var _map_root: Node3D
var _player: CharacterBody3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _dir_light: DirectionalLight3D
var _moonlight: DirectionalLight3D
var _slot := {}
var _shot_path := ""
var _shot_frame := 0
var _status: Label
var _sun_open := false
var _shells_disarmed := 0
var _floor_top := NAN
var _posts := 0
var _post_mult := 1.0
var _dark_room := false


func _ready() -> void:
	if not _pending_stage.is_empty():
		_stage_id = _pending_stage
		_pending_stage = ""
	elif not OS.get_environment("PSZ_WALK_STAGE").is_empty():
		_stage_id = OS.get_environment("PSZ_WALK_STAGE")
	_shot_path = OS.get_environment("PSZ_WALK_SHOT")
	_boot_room()
	_boot_actors()
	_spawn_authored_effects()
	_spawn_weather()
	# The storm rows' lightning (#649) — the shared builder, exactly what
	# the field spawns.
	if _slot.get("lightning", false):
		WeatherControllerScript.build_lightning(self)
		print("[WetlandsWalk] lightning strobes armed")
	_build_status_label()
	_readout()
	print("[WetlandsWalk] ready — N next room, R reload, ESC quit")


## The room half of the boot: environment, stage, floor, the sun shadow
## passes, and the row's lantern pools — all through the shared lab boot.
func _boot_room() -> void:
	var built := FieldLabScript.boot_environment(self, "ozette", _stage_id)
	_env = built["env"]
	_sky_mat = built["sky_mat"]
	_dir_light = built["dir_light"]
	_moonlight = built["moonlight"]
	_slot = built["slot"]
	_map_root = FieldLabScript.load_field_stage(self, _slot,
		_subfolder(), _stage_id)
	_floor_top = FieldLabScript.load_floor_collision(self,
		FLOOR_GLB_FMT % [_subfolder(), _stage_id, _stage_id], _slot)
	# #648 shell carve-out, production order (sun rows only): split, disarm
	# any enclosing shell, park the compat shadow eye in the room's air.
	_sun_open = _slot.get("sun_shadows", false) \
		and MeshUtils.sun_reaches_room(_map_root,
			_dir_light.global_transform.basis.z, _floor_top)
	if _slot.get("sun_shadows", false):
		MeshUtils.split_mesh_surfaces(_map_root)
		_shells_disarmed = MeshUtils.disable_enclosing_casters(_map_root,
			_dir_light.global_transform.basis.z, _floor_top)
		MeshUtils.place_light_inside_room(_dir_light, _map_root, _floor_top)
		MeshUtils.apply_sun_eye_pull(_dir_light, _map_root, _slot)
	# The row's post-light pools (#649) — after the floor load, same as the
	# field.
	if _slot.has("post_lights") and OS.get_environment("PSZ_WALK_POST_LIGHTS") != "0":
		_posts = MeshUtils.place_post_lights(_map_root, str(_slot["post_lights"]))
		for light in _map_root.find_children("PostLight*", "OmniLight3D", true, false):
			print("[WetlandsWalk] post light at %s" % (light as Node3D).global_position)


## The actor half: the player at the gate spawn, the lit-prop crate, the
## optional control pillar / hidden-model A/B knobs.
func _boot_actors() -> void:
	var spawn_pos := _boot_spawn()
	_spawn_player(spawn_pos)
	_spawn_prop_preview(spawn_pos)
	if OS.get_environment("PSZ_WALK_PILLAR") == "1":
		var pillar := MeshInstance3D.new()
		pillar.name = "A/BPillar"
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 3, 1)
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.6, 0.3, 0.2)
		pillar.mesh = bm
		pillar.material_override = bmat
		pillar.position = Vector3(spawn_pos.x + 2.5,
			_floor_top + 1.5 if is_finite(_floor_top) else 1.5, spawn_pos.z)
		add_child(pillar)
	if OS.get_environment("PSZ_WALK_HIDE_PLAYER") == "1":
		(_player.get_node("PlayerModel") as Node3D).visible = false


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
	print("[WetlandsWalk] screenshot → %s" % _shot_path)
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var keycode: int = (event as InputEventKey).keycode
	if FieldLabScript.handle_tune_key(keycode, _env, _dir_light):
		_update_status()
		return
	match keycode:
		KEY_BRACKETLEFT:
			_set_post_energy(_post_mult - 0.25)
		KEY_BRACKETRIGHT:
			_set_post_energy(_post_mult + 0.25)
		KEY_D:
			_toggle_dark_room()
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


## Wetlands stages live in variant subfolders (wetlands_a/b/e/z — the variant
## char at index 3 of the stage id, same rule as the controller's
## _get_stage_subfolder).
func _subfolder() -> String:
	return "wetlands_" + _stage_id.substr(3, 1)


func _spawn_player(pos: Vector3) -> void:
	_player = FieldLabScript.spawn_player(self, pos)


## The boot spawn: PSZ_WALK_SPAWN=x,z overrides; otherwise the stage
## config's own spawn-in (defaultSpawn, else the first spawn waypoint —
## the gate's authored position) so every stage in the cycle lands on
## walkable ground — the old fixed (0, 1.5, 8) fell through s02b_ga1's
## boardwalk into the marsh.
func _boot_spawn() -> Vector3:
	var raw := OS.get_environment("PSZ_WALK_SPAWN")
	if not raw.is_empty():
		var p := raw.split(",")
		if p.size() >= 2:
			return Vector3(float(p[0]), 1.5, float(p[1]))
	var pos = _config_spawn()
	if pos is Vector3:
		return Vector3(pos.x, 1.5, pos.z)
	return Vector3(0, 1.5, 8)


## The stage's authored spawn from the unified config (kion: "the gate").
func _config_spawn():
	var file := FileAccess.open(UNIFIED_CONFIG, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	var ok := json.parse(file.get_as_text()) == OK
	file.close()
	if not ok:
		return null
	var cfg: Dictionary = (json.data as Dictionary).get(_stage_id, {})
	var ds: Dictionary = cfg.get("defaultSpawn", {})
	if ds.has("position"):
		var arr: Array = ds["position"]
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	for w in cfg.get("waypoints", []):
		if str(w.get("kind", "")) == "spawn":
			var arr: Array = w["position"]
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return null


## The lit_props preview (#649): the field container on the element receive
## path — the same SmoothNormals + make_lit treatment GameElement._load_model
## applies under the flag, so the lab previews what a dropped crate reads.
## Spawned beside the player so it always lands on walkable ground.
func _spawn_prop_preview(spawn_pos: Vector3) -> void:
	if OS.get_environment("PSZ_WALK_PROP") == "0":
		return
	var packed := load(PROP_GLB) as PackedScene
	if not packed:
		return
	var prop := packed.instantiate() as Node3D
	add_child(prop)
	SmoothNormals.ensure(prop, 2)
	SmoothNormals.make_lit(prop)
	prop.global_position = Vector3(spawn_pos.x - 1.5,
		_floor_top if is_finite(_floor_top) else spawn_pos.y - 1.5, spawn_pos.z)


## The authored placed effects for this stage — every category:"placed" entry
## goes through the REAL WeatherController._spawn_placed_effect, so what walks
## here is what spawns in-field (the s02 stages author none yet; the pass
## stays for parity).
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
	var count := 0
	for effect in cfg.get("effects", []):
		if str(effect.get("category", "")) != "placed":
			continue
		weather._spawn_placed_effect(effect)
		count += 1
	if count > 0:
		print("[WetlandsWalk] %d authored placed effect(s)" % count)


## The row's weather, as the field spawns it (the shared boot — no lab
## copy to drift).
func _spawn_weather() -> void:
	FieldLabScript.spawn_weather(_player, _slot)


## Scale every post pool against its MeshUtils base.
func _set_post_energy(mult: float) -> void:
	_post_mult = clampf(mult, 0.0, 4.0)
	for light in _map_root.find_children("PostLight*", "OmniLight3D", true, false):
		(light as OmniLight3D).light_energy = MeshUtils.POST_LIGHT_ENERGY * _post_mult


## The lantern-dominance probe state: sun 0 with its shadows disarmed (a
## zero-energy sun still leaves its fixed-direction shadow map armed) and
## ambient at a floor — only the lanterns light the room, so the actors'
## shadows must swing with the nearest pool. Restores the row on the
## second press.
func _toggle_dark_room() -> void:
	_dark_room = not _dark_room
	if _dark_room:
		_dir_light.light_energy = 0.0
		_dir_light.shadow_enabled = false
		_env.ambient_light_energy = 0.05
	else:
		_dir_light.light_energy = float(_slot.get("sun_energy", 0.35))
		_dir_light.shadow_enabled = _slot.get("sun_shadows", false)
		_env.ambient_light_energy = float(_slot.get("ambient_energy", 0.65))


## The read-out prints in the field's [FieldSlot] shape so a tuned set is
## copied into the FieldSlotTable row without translation.
func _readout() -> void:
	print("[FieldSlot %s] ambient %.2f  sun %.2f  sun_pitch %.0f  sun_shadows %s" % [
		_stage_id, _env.ambient_light_energy, _dir_light.light_energy,
		_dir_light.rotation_degrees.x, str(_dir_light.shadow_enabled).to_lower()])
	print("[FieldSlot %s] shadow_bias %.2f  shadow_normal_bias %.1f" % [
		_stage_id, _dir_light.shadow_bias, _dir_light.shadow_normal_bias])
	print("[WetlandsWalk] room sun: %s  posts: %d pool(s) × %.2f (energy %.2f)" % [
		"open" if _sun_open else "enclosed — %d shell mesh(es) cast-off" % _shells_disarmed,
		_posts, _post_mult, MeshUtils.POST_LIGHT_ENERGY * _post_mult])


func _build_status_label() -> void:
	_status = FieldLabScript.make_status_label(self)
	_update_status()


func _update_status() -> void:
	_status.text = _status_line()


## The wetlands' own status shape — pools, the dark-room tag, the room read.
func _status_line() -> String:
	return "%s%s — ambient %.2f  sun %.2f  pitch %.0f°  shadows %s  nb %.1f  posts %d ×%.2f  room %s" % [
		"DARK " if _dark_room else "",
		_stage_id, _env.ambient_light_energy, _dir_light.light_energy,
		_dir_light.rotation_degrees.x,
		"on" if _dir_light.shadow_enabled else "off",
		_dir_light.shadow_normal_bias, _posts, _post_mult,
		"sun-open" if _sun_open else "shell-cast-off"]

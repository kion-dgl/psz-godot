extends Node3D
## Forgotten City WALK lab (#651 lock pass) — walk the ambient↔sun ladder in
## a paru room without the run-up: the production material path (SmoothNormals
## → mirror-wrap fixes → the cheat rig with the greenery keep-list) under the
## REAL FieldSlotTable rows — the paru area row for A/Z (ambient-led), the
## s05e transition row (sun-led), the s05b row (the balanced middle) — the
## catcher floor, the stage's authored spore pools (s05a_sa1 ships three),
## and a controllable player. Tuning semantics match the valley lab — values
## read out in the [FieldSlot] shape and transfer 1:1 into the slot row; the
## ambient/sun balance IS this area's identity, so the ,/. and 9/0 sweeps
## are the dial.
##
## Env:  PSZ_WALK_STAGE=s05a_ga1   boot stage (default: first of STAGES)
##       PSZ_WALK_SHOT=/tmp/o.png  screenshot + quit (smoke; else live keys)
##       PSZ_WALK_SUN_PITCH=-60    sun elevation override
##       PSZ_WALK_SUN_SHADOWS=0    force sun shadows off
##       PSZ_WALK_HIDE_PLAYER=1    hide the player model
##       PSZ_WALK_SUN=0.25         sun energy override · PSZ_WALK_AMBIENT=0.55
##                                 ambient override (balance sweeps)
##       PSZ_WALK_SPAWN=x,z        override the boot spawn (default: the stage
##                                 config's spawn — the B rooms ship water)
## Keys: , / .  ambient ∓/± 0.05      9 / 0  sun ∓/± 0.05
##       7 / 8  sun lower / steeper (pitch ∓/± 5°)
##       F / G  shadow normal bias ∓/± 1 · C / V  shadow bias ∓/± 0.05
##       P       read-out (field format)     M      sun shadows toggle
##       N       next room · R reload · ESC quit

const FLOOR_GLB_FMT := "res://assets/stages/%s/%s/lndmd/%s-floor.glb"
const EFFECTS_JSON_FMT := "res://assets/stages/%s/%s/lndmd/%s_effects.json"
const WeatherControllerScript := preload("res://scripts/3d/field/weather_controller.gd")
const FieldLabScript := preload("res://scripts/tools/field_lab.gd")

## The ladder in walk order (N cycles): A's field look and its td room (the
## only 1_reaf5 art), B's water rooms, the E transition, the boss arena.
const STAGES := [
	"s05a_ga1", "s05a_td1", "s05b_ib2", "s05b_ga1", "s05e_ia1", "s05z_na1",
]

## N's selection survives the scene reload that swaps the room.
static var _pending_stage := ""

var _stage_id := "s05a_ga1"
var _map_root: Node3D
var _player: CharacterBody3D
var _env: Environment
var _dir_light: DirectionalLight3D
var _slot := {}
var _shot := FieldLabScript.ShotRun.new()
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
	_shot.path = OS.get_environment("PSZ_WALK_SHOT")
	# The variant subfolder (paru_a/b/e/z — the variant char at index 3,
	# same rule as the controller's _get_stage_subfolder).
	var sub := "paru_" + _stage_id.substr(3, 1)
	var built := FieldLabScript.boot_environment(self, "paru", _stage_id)
	_env = built["env"]
	_dir_light = built["dir_light"]
	_slot = built["slot"]
	_map_root = FieldLabScript.load_field_stage(self, _slot, sub, _stage_id)
	_floor_top = FieldLabScript.load_floor_collision(self,
		FLOOR_GLB_FMT % [sub, _stage_id, _stage_id], _slot)
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
	_player = FieldLabScript.spawn_player(self, FieldLabScript.boot_spawn(_stage_id))
	if OS.get_environment("PSZ_WALK_HIDE_PLAYER") == "1":
		(_player.get_node("PlayerModel") as Node3D).visible = false
	_spawn_authored_effects()
	# The row ships no weather yet (the leaves/motes identity is #651's open
	# question) — the shared spawn no-ops on an empty weather key, and starts
	# spawning the day a row carries one.
	FieldLabScript.spawn_weather(_player, _slot)
	_status = FieldLabScript.make_status_label(self)
	_update_status()
	_readout()
	print("[ParuWalk] ready — N next room, R reload, ESC quit")


func _process(_delta: float) -> void:
	_shot.step(self, "ParuWalk")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var keycode: int = (event as InputEventKey).keycode
	if FieldLabScript.handle_tune_key(keycode, _env, _dir_light):
		_update_status()
		return
	match keycode:
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


## The stage's authored placed effects (s05a_sa1's three green spore pools
## carry lights) — parsed from the stage-folder effects JSON the field's
## _spawn_stage_effects reads, spawned through the REAL
## WeatherController._spawn_placed_effect so what walks here is what spawns
## in-field. (The controller's own path resolves the folder from the session
## area, which a lab boot has none of.)
func _spawn_authored_effects() -> void:
	var path := EFFECTS_JSON_FMT % ["paru_" + _stage_id.substr(3, 1), _stage_id, _stage_id]
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var ok := json.parse(file.get_as_text()) == OK
	file.close()
	if not ok:
		return
	var weather := WeatherControllerScript.new(self)
	var count := 0
	for effect in (json.data as Dictionary).get("effects", []):
		if str(effect.get("category", "")) != "placed":
			continue
		weather._spawn_placed_effect(effect)
		count += 1
	if count > 0:
		print("[ParuWalk] %d authored placed effect(s)" % count)


## The read-out prints in the field's [FieldSlot] shape so a tuned set is
## copied into the FieldSlotTable row without translation.
func _readout() -> void:
	print("[FieldSlot %s] ambient %.2f  sun %.2f  sun_pitch %.0f  sun_shadows %s  bias %.2f  nb %.1f" % [
		_stage_id, _env.ambient_light_energy, _dir_light.light_energy,
		_dir_light.rotation_degrees.x, str(_dir_light.shadow_enabled).to_lower(),
		_dir_light.shadow_bias, _dir_light.shadow_normal_bias])
	print("[ParuWalk] room sun: %s" %
		("open" if _sun_open else "enclosed — %d shell mesh(es) cast-off" % _shells_disarmed))


func _update_status() -> void:
	_status.text = "%s — ambient %.2f  sun %.2f  pitch %.0f°  shadows %s  room %s" % [
		_stage_id, _env.ambient_light_energy, _dir_light.light_energy,
		_dir_light.rotation_degrees.x,
		"on" if _dir_light.shadow_enabled else "off",
		"sun-open" if _sun_open else "shell-cast-off"]

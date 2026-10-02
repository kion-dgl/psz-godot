extends Node3D
## Dark Shrine WALK lab (#653) — walk the pin without the run-up: the
## production material path under the REAL FieldSlotTable rows — s07a (the
## white motes), s07b/s07z (the black), the dark area row the E transition
## rides — the catcher floor, the row's signature motes spawning live, and a
## controllable player. The stage keeps its bake by design (no bake_mix, no
## lit_surfaces: the row's silence is what keeps the sun off the stage), so
## the dials are the actors' fill and the minimum shadow source, plus the
## authored candle accents.
##
## This is also the AUTHORING lab for the shrine's candle/urn accents: K
## inventories the stage's materials (fixture discovery), and L prints an
## effects.json light entry at the player's feet — walk, press, paste into
## <stage>_effects.json, R to reload and see it live (the lab spawns that
## file through the real WeatherController, so what walks here is what
## spawns in-field).
##
## Env:  PSZ_WALK_STAGE=s07a_ga1   boot stage (default: first of STAGES)
##       PSZ_WALK_SHOT=/tmp/o.png  screenshot + quit (smoke; else live keys)
##       PSZ_WALK_SUN_PITCH=-60    sun elevation override
##       PSZ_WALK_SUN_SHADOWS=0    force sun shadows off
##       PSZ_WALK_HIDE_PLAYER=1    hide the player model
##       PSZ_WALK_SUN=0.1          sun energy override · PSZ_WALK_AMBIENT=0.2
##                                 ambient override (balance sweeps)
##       PSZ_WALK_SPAWN=x,z        override the boot spawn
##       PSZ_WALK_DUMP=materials   headless: K's inventory at boot, then quit
##                                 (authoring without a window)
##       PSZ_WALK_WEATHER=0        skip the signature motes (rig isolation)
## Keys: , / .  ambient ∓/± 0.05      9 / 0  sun ∓/± 0.05
##       7 / 8  sun lower / steeper (pitch ∓/± 5°)
##       F / G  shadow normal bias ∓/± 1 · C / V  shadow bias ∓/± 0.05
##       P       read-out (field format)     M      sun shadows toggle
##       K       material inventory · L      light-anchor snippet at the feet
##       N       next room · R reload · ESC quit

const FLOOR_GLB_FMT := "res://assets/stages/%s/%s/lndmd/%s-floor.glb"
const EFFECTS_JSON_FMT := "res://assets/stages/%s/%s/lndmd/%s_effects.json"
const WeatherControllerScript := preload("res://scripts/3d/field/weather_controller.gd")
const FieldLabScript := preload("res://scripts/tools/field_lab.gd")

## The variants in walk order (N cycles): A's gate, an lc room and the sa
## plaza-shaped room; B's gate and an lb room (the black-mote side); the E
## transition; both boss arenas.
const STAGES := [
	"s07a_ga1", "s07a_lc1", "s07a_sa1", "s07b_ga1", "s07b_lb1",
	"s07e_ia1", "s07z_na1", "s07z_na2",
]

## The anchor snippet's placeholder accent (#653 first draft): warm candle
## amber, small pools. The per-room palette is kion's live call — edit the
## pasted entry's color/intensity/radius freely.
const ANCHOR_COLOR := [1.0, 0.7, 0.35]
const ANCHOR_INTENSITY := 1.2
const ANCHOR_RADIUS := 5.0

## N's selection survives the scene reload that swaps the room.
static var _pending_stage := ""

var _stage_id := "s07a_ga1"
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
	# The variant subfolder (shrine_a/b/e/z — the variant char at index 3,
	# same rule as the controller's _get_stage_subfolder).
	var sub := "shrine_" + _stage_id.substr(3, 1)
	var built := FieldLabScript.boot_environment(self, "dark", _stage_id)
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
	# The rows ship no weather (the shrine is indoors) — the shared spawn
	# no-ops on the empty weather key; the SIGNATURE motes are the row's
	# identity and spawn like the field spawns them.
	FieldLabScript.spawn_weather(_player, _slot)
	FieldLabScript.spawn_signature(_player, _slot)
	_status = FieldLabScript.make_status_label(self)
	_update_status()
	_readout()
	if OS.get_environment("PSZ_WALK_DUMP") == "materials":
		_dump_materials()
		get_tree().quit()
		return
	print("[ShrineWalk] ready — N next room, R reload, K materials, L anchor, ESC quit")


func _process(_delta: float) -> void:
	_shot.step(self, "ShrineWalk")


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
		KEY_K:
			_dump_materials()
		KEY_L:
			_print_anchor_snippet()
		_:
			return
	_update_status()


## The stage's authored placed effects (the candle/urn accents) — parsed
## from the stage-folder effects JSON the field's _spawn_stage_effects
## reads, spawned through the REAL WeatherController._spawn_placed_effect so
## what walks here is what spawns in-field. (The controller's own path
## resolves the folder from the session area, which a lab boot has none of.)
func _spawn_authored_effects() -> void:
	var path := EFFECTS_JSON_FMT % ["shrine_" + _stage_id.substr(3, 1), _stage_id, _stage_id]
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
		print("[ShrineWalk] %d authored placed effect(s)" % count)


## Fixture discovery (#653): K inventories the stage's materials (per
## material: surfaces, vertices, world Y range) so fixture candidates
## (candle clusters, urn rims) can be spotted and their XZ eyeballed
## against the walk. Reads the mesh's OWN surface material — the fix pass
## swaps overrides to anonymous ShaderMaterials while the imported name
## survives on the mesh.
func _dump_materials() -> void:
	var stats: Dictionary = {}
	for node in MeshUtils.collect_mesh_instances(_map_root, []):
		var mi := node as MeshInstance3D
		var mesh := mi.mesh as ArrayMesh
		if mesh == null:
			continue
		var xform := mi.global_transform
		for i in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(i)
			var mname: String = mat.resource_name if mat != null else "(no material)"
			var arrays := mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] \
				if not arrays.is_empty() else PackedVector3Array()
			var st: Dictionary = stats.get(mname, {
				"surfaces": 0, "verts": 0, "ymin": INF, "ymax": -INF})
			st["surfaces"] = int(st["surfaces"]) + 1
			st["verts"] = int(st["verts"]) + verts.size()
			for v in verts:
				var y := (xform * v).y
				st["ymin"] = minf(float(st["ymin"]), y)
				st["ymax"] = maxf(float(st["ymax"]), y)
			stats[mname] = st
	var names := (stats.keys() as Array).duplicate()
	names.sort()
	print("[ShrineWalk] %s — %d material(s): name  surfaces  verts  y-range" %
		[_stage_id, names.size()])
	for mname in names:
		var st: Dictionary = stats[mname]
		print("  %-24s  %2d  %6d  y %.1f..%.1f" % [mname,
			int(st["surfaces"]), int(st["verts"]),
			float(st["ymin"]), float(st["ymax"])])


## The authoring loop's print half (#653): L emits an effects.json light
## entry at the player's feet — paste into the stage's file, R reloads, the
## pool walks. Position is map-space (the spawn adds to the map root at the
## origin, so world == authored).
func _print_anchor_snippet() -> void:
	var p := _player.global_position
	print("[ShrineWalk] light anchor at (%.1f, %.1f, %.1f) — paste into %s:" % [
		p.x, p.y, p.z,
		EFFECTS_JSON_FMT % ["shrine_" + _stage_id.substr(3, 1), _stage_id, _stage_id]])
	print('\t{ "type": "light", "category": "placed", "position": [%.1f, %.1f, %.1f],\n'
		+ '\t  "color": [%.2f, %.2f, %.2f], "intensity": %.1f, "radius": %.1f },' % [
		p.x, p.y, p.z, ANCHOR_COLOR[0], ANCHOR_COLOR[1], ANCHOR_COLOR[2],
		ANCHOR_INTENSITY, ANCHOR_RADIUS])


## The read-out prints in the field's [FieldSlot] shape so a tuned set is
## copied into the FieldSlotTable row without translation.
func _readout() -> void:
	print("[FieldSlot %s] ambient %.2f  sun %.2f  sun_pitch %.0f  sun_shadows %s  bias %.2f  nb %.1f" % [
		_stage_id, _env.ambient_light_energy, _dir_light.light_energy,
		_dir_light.rotation_degrees.x, str(_dir_light.shadow_enabled).to_lower(),
		_dir_light.shadow_bias, _dir_light.shadow_normal_bias])
	print("[ShrineWalk] room sun: %s" %
		("open" if _sun_open else "enclosed — %d shell mesh(es) cast-off" % _shells_disarmed))


func _update_status() -> void:
	_status.text = "%s — ambient %.2f  sun %.2f  pitch %.0f°  shadows %s  room %s" % [
		_stage_id, _env.ambient_light_energy, _dir_light.light_energy,
		_dir_light.rotation_degrees.x,
		"on" if _dir_light.shadow_enabled else "off",
		"sun-open" if _sun_open else "shell-cast-off"]

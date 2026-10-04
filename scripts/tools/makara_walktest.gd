extends Node3D
## Makara walk lab (#650): production FieldLab and WeatherController paths.
## WASD move; arrows/drag orbit; R reload; K materials; L anchor; U/I lights; P rig.
## PSZ_WALK_STAGE selects a room; PSZ_WALK_SHOT captures a rendered preview.

const FLOOR_GLB_FMT := "res://assets/stages/%s/%s/lndmd/%s-floor.glb"
const EFFECTS_JSON_FMT := "res://assets/stages/%s/%s/lndmd/%s_effects.json"
const WeatherControllerScript := preload("res://scripts/3d/field/weather_controller.gd")
const FieldLabScript := preload("res://scripts/tools/field_lab.gd")

const STAGES := [
	"s04b_ga1", "s04b_ib1", "s04b_ib2", "s04b_ic1", "s04b_ic3",
	"s04b_lb1", "s04b_lb3", "s04b_lc1", "s04b_lc2", "s04b_na1",
	"s04b_nb2", "s04b_nc2", "s04b_sa1", "s04b_tb3", "s04b_tc3",
	"s04b_td1", "s04b_td2", "s04b_xb2",
]

const ANCHOR_COLOR := [1.0, 0.7, 0.35]
const ANCHOR_INTENSITY := 1.2
const ANCHOR_RADIUS := 5.0

static var _pending_stage := ""

@export var boot_stage := "s04a_ic3"

var _stage_id := "s04a_ic3"
var _stage_cycle: Array = STAGES
var _map_root: Node3D
var _player: CharacterBody3D
var _env: Environment
var _dir_light: DirectionalLight3D
var _slot := {}
var _shot := FieldLabScript.ShotRun.new()
var _status: Label
var _pos_label: Label
var _sun_open := false
var _shells_disarmed := 0
var _floor_top := NAN
var _anchor_scale := 1.0


func _ready() -> void:
	_stage_id = boot_stage
	if not _pending_stage.is_empty():
		_stage_id = _pending_stage
		_pending_stage = ""
	elif not OS.get_environment("PSZ_WALK_STAGE").is_empty():
		_stage_id = OS.get_environment("PSZ_WALK_STAGE")
	if _stage_id.begins_with("s04a_"):
		_stage_cycle = STAGES.map(func(stage): return stage.replace("s04b_", "s04a_"))
	elif _stage_id.begins_with("s04e_") or _stage_id.begins_with("s04z_"):
		_stage_cycle = [_stage_id]
	_shot.path = OS.get_environment("PSZ_WALK_SHOT")
	var sub := "makara_" + _stage_id.substr(3, 1)
	var built := FieldLabScript.boot_environment(self, "makara", _stage_id)
	_env = built["env"]
	_dir_light = built["dir_light"]
	_slot = built["slot"]
	_map_root = FieldLabScript.load_field_stage(self, _slot, sub, _stage_id)
	_floor_top = FieldLabScript.load_floor_collision(self,
		FLOOR_GLB_FMT % [sub, _stage_id, _stage_id], _slot)
	_sun_open = _slot.get("sun_shadows", false) \
		and MeshUtils.sun_reaches_room(_map_root,
			_dir_light.global_transform.basis.z, _floor_top)
	if _slot.get("sun_shadows", false):
		MeshUtils.split_mesh_surfaces(_map_root)
		_shells_disarmed = MeshUtils.disable_enclosing_casters(_map_root,
			_dir_light.global_transform.basis.z, _floor_top)
		MeshUtils.place_light_inside_room(_dir_light, _map_root, _floor_top)
		MeshUtils.apply_sun_eye_pull(_dir_light, _map_root, _slot)
	var start := FieldLabScript.boot_spawn(_stage_id)
	_player = FieldLabScript.spawn_player(self, start)
	var orbit := get_node("OrbitCamera")
	if Vector2(start.x, start.z).length() > 4.0:
		orbit.camera_rotation = atan2(start.x, start.z)
	if not OS.get_environment("PSZ_WALK_YAW").is_empty():
		orbit.camera_rotation = deg_to_rad(float(OS.get_environment("PSZ_WALK_YAW")))
	if OS.get_environment("PSZ_WALK_HIDE_PLAYER") == "1":
		(_player.get_node("PlayerModel") as Node3D).visible = false
	_spawn_authored_effects()
	FieldLabScript.spawn_weather(_player, _slot)
	FieldLabScript.spawn_signature(_player, _slot)
	_status = FieldLabScript.make_status_label(self)
	_pos_label = FieldLabScript.make_status_label(self)
	_pos_label.position = Vector2(12,
		get_viewport().get_visible_rect().size.y - 44.0)
	_update_status()
	_readout()
	if OS.get_environment("PSZ_WALK_DUMP") == "materials":
		_dump_materials()
		get_tree().quit()
		return
	if OS.get_environment("PSZ_WALK_DUMP") == "instances":
		_dump_stage_layers()
		get_tree().quit()
		return
	print("[MakaraWalk] ready — N next room, R reload, K materials, L anchor, ESC quit")


func _process(_delta: float) -> void:
	_shot.step(self, "MakaraWalk")
	if _pos_label and is_instance_valid(_player):
		var p := _player.global_position
		_pos_label.text = "(%.1f, %.1f, %.1f) · %d FPS · WASD move · arrows/drag orbit · R reload · K materials" % [p.x, p.y, p.z, Engine.get_frames_per_second()]


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var keycode: int = (event as InputEventKey).keycode
	if FieldLabScript.handle_tune_key(keycode, _env, _dir_light):
		_update_status()
		return
	match keycode:
		KEY_N:
			_pending_stage = _stage_cycle[(_stage_cycle.find(_stage_id) + 1) % _stage_cycle.size()] \
				if _stage_id in _stage_cycle else _stage_cycle[0]
			get_tree().reload_current_scene()
		KEY_R:
			_pending_stage = _stage_id
			get_tree().reload_current_scene()
		KEY_P:
			_readout()
		KEY_K:
			_dump_materials()
		KEY_L:
			_print_anchor_snippet()
		KEY_U:
			_scale_anchors(0.9)
		KEY_I:
			_scale_anchors(1.1)
		_:
			return
	_update_status()


func _scale_anchors(mult: float) -> void:
	_anchor_scale *= mult
	var n := 0
	for child in _map_root.find_children("*", "OmniLight3D", true, false):
		if child.has_meta("authored_light"):
			(child as OmniLight3D).light_energy *= mult
			n += 1
	print("[MakaraWalk] anchor intensity x%.2f over %d light(s)" % [_anchor_scale, n])


func _spawn_authored_effects() -> void:
	preload("res://scripts/3d/field/makara_particles.gd").spawn_floor(_map_root, _stage_id)
	preload("res://scripts/3d/field/makara_lighting.gd").spawn_crystals(_map_root, _stage_id)
	var path := EFFECTS_JSON_FMT % ["makara_" + _stage_id.substr(3, 1), _stage_id, _stage_id]
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
		print("[MakaraWalk] %d authored placed effect(s)" % count)


func _dump_materials() -> void:
	var stats: Dictionary = {}
	for node in MeshUtils.collect_mesh_instances(_map_root, []):
		var mi := node as MeshInstance3D
		var mesh := mi.mesh as ArrayMesh
		if mi.is_queued_for_deletion() or mesh == null:
			continue
		var xform := mi.global_transform
		for i in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(i)
			var mname: String = mat.resource_name if mat != null else "(no material)"
			var tex: String = ""
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
				tex = (mat as StandardMaterial3D).albedo_texture.resource_path.get_file()
			var arrays := mesh.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] \
				if not arrays.is_empty() else PackedVector3Array()
			var st: Dictionary = stats.get(mname, {
				"surfaces": 0, "verts": 0, "ymin": INF, "ymax": -INF, "tex": tex})
			st["surfaces"] = int(st["surfaces"]) + 1
			st["verts"] = int(st["verts"]) + verts.size()
			for v in verts:
				var y := (xform * v).y
				st["ymin"] = minf(float(st["ymin"]), y)
				st["ymax"] = maxf(float(st["ymax"]), y)
			stats[mname] = st
	var names := (stats.keys() as Array).duplicate()
	names.sort()
	print("[MakaraWalk] %s — %d material(s): name  surfaces  verts  y-range  texture" %
		[_stage_id, names.size()])
	for mname in names:
		var st: Dictionary = stats[mname]
		print("  %-24s  %2d  %6d  y %.1f..%.1f  %s" % [mname,
			int(st["surfaces"]), int(st["verts"]),
			float(st["ymin"]), float(st["ymax"]), str(st["tex"])])


func _dump_stage_layers() -> void:
	var bit := 1 << (MeshUtils.STAGE_LIGHT_LAYER - 1)
	var total := 0
	var flagged := 0
	var missing: Array = []
	for node in MeshUtils.collect_mesh_instances(_map_root, []):
		var mi := node as MeshInstance3D
		total += 1
		if mi.layers & bit:
			flagged += 1
		else:
			missing.append("%s (mat %s)" % [mi.name,
				str(mi.mesh.surface_get_material(0).resource_name)
				if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_material(0) != null
				else "?"])
	print("[MakaraWalk] stage layer: %d/%d instance(s) flagged" % [flagged, total])
	for m in missing:
		print("  UNFLAGGED: %s" % m)


func _print_anchor_snippet() -> void:
	var p := _player.global_position
	print("[MakaraWalk] light anchor at (%.1f, %.1f, %.1f) — paste into %s:" % [
		p.x, p.y, p.z,
		EFFECTS_JSON_FMT % ["makara_" + _stage_id.substr(3, 1), _stage_id, _stage_id]])
	print('\t{ "type": "light", "category": "placed", "position": [%.1f, %.1f, %.1f],\n'
		+ '\t  "color": [%.2f, %.2f, %.2f], "intensity": %.1f, "radius": %.1f },' % [
		p.x, p.y, p.z, ANCHOR_COLOR[0], ANCHOR_COLOR[1], ANCHOR_COLOR[2],
		ANCHOR_INTENSITY, ANCHOR_RADIUS])


func _readout() -> void:
	print("[FieldSlot %s] ambient %.2f  sun %.2f  sun_pitch %.0f  sun_shadows %s  bias %.2f  nb %.1f  fog %.3f" % [
		_stage_id, _env.ambient_light_energy, _dir_light.light_energy,
		_dir_light.rotation_degrees.x, str(_dir_light.shadow_enabled).to_lower(),
		_dir_light.shadow_bias, _dir_light.shadow_normal_bias, _env.fog_density])
	print("[MakaraWalk] room sun: %s" %
		("open" if _sun_open else "shadows off" if not _slot.get("sun_shadows", false) else "enclosed — %d shell mesh(es) cast-off" % _shells_disarmed))


func _update_status() -> void:
	_status.text = "%s — ambient %.2f  sun %.2f  pitch %.0f°  sun shadows %s  fog %.3f  room %s" % [
		_stage_id, _env.ambient_light_energy, _dir_light.light_energy,
		_dir_light.rotation_degrees.x,
		"on" if _dir_light.shadow_enabled else "off",
		_env.fog_density,
		"sun-open" if _sun_open else ("actor shadows" if _slot.get("sun_shadows", false) else "baseline")]

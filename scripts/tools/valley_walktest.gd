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
##       PSZ_WALK_LIGHT_FOLLOW=1   brute-force: the light node rides 3 units
##                                 above the player's head (sanity check —
##                                 the compat shadow eye pinned to the player)
##       PSZ_WALK_PILLAR=1         spawn a 3m control pillar beside the player
##                                 (a caster that provably shadows — splits
##                                 room-level vs player-level shadow loss)
##       PSZ_WALK_PLAYER_PROXY=1   hide the model, stand a casting capsule in
##                                 the player's spot (shadow-proxy trial)
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
var _light_follow := false
var _shadow_ab := false


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
		# #648 per-surface split first: rooms ship as one mesh (backdrop +
		# floor + props in a dozen surfaces) but casting is per-instance —
		# split so the carve-out disarms the panorama shell without taking
		# the props' (carts, bridge) shadows with it.
		MeshUtils.split_mesh_surfaces(_map_root)
		_shells_disarmed = MeshUtils.disable_enclosing_casters(_map_root,
			_dir_light.global_transform.basis.z, _floor_top)
		# Panorama placement (#648): the compat shadow eye must sit in the
		# interior air — at the origin it's under the bridge deck in lb rooms.
		MeshUtils.place_light_inside_room(_dir_light, _map_root, _floor_top)
	_light_follow = OS.get_environment("PSZ_WALK_LIGHT_FOLLOW") == "1"
	_shadow_ab = OS.get_environment("PSZ_WALK_SHADOW_AB") == "1"
	_spawn_player(Vector3(0, 1.5, 10))
	if OS.get_environment("PSZ_WALK_PLAYER_PROXY") == "1":
		(_player.get_node("PlayerModel") as Node3D).visible = false
		var cap := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.3
		cm.height = 1.7
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.8, 0.7, 0.6)
		cap.mesh = cm
		cap.material_override = cmat
		add_child(cap)
		cap.position = Vector3(0, 0.85, 10)
	if OS.get_environment("PSZ_WALK_PILLAR") == "1":
		var pillar := MeshInstance3D.new()
		pillar.name = "A/BPillar"
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 3, 1)
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.6, 0.3, 0.2)
		pillar.mesh = bm
		pillar.material_override = bmat
		var px := 2.5
		var pz := 10.0
		if not OS.get_environment("PSZ_WALK_PILLAR_POS").is_empty():
			var p := OS.get_environment("PSZ_WALK_PILLAR_POS").split(",")
			px = float(p[0])
			pz = float(p[1])
		pillar.position = Vector3(px, _floor_top + 1.5 if is_finite(_floor_top) else 1.5, pz)
		add_child(pillar)
	if OS.get_environment("PSZ_WALK_HIDE_PLAYER") == "1":
		(_player.get_node("PlayerModel") as Node3D).visible = false
		var proxy := _player.get_node_or_null("ShadowProxy")
		if proxy:
			(proxy as Node3D).visible = false
	_spawn_authored_effects()
	_spawn_weather()
	_build_status_label()
	_readout()
	print("[ValleyWalk] ready — N next room, R reload, ESC quit")


func _process(_delta: float) -> void:
	if Input.is_action_pressed("ui_cancel"):
		get_tree().quit()
	if _light_follow and _player:
		_dir_light.global_position = _player.global_position + Vector3(0, 3, 0)
	if _shot_path.is_empty():
		return
	_shot_frame += 1
	if _shot_path.is_empty():
		return
	if _shadow_ab:
		# Single-boot A/B: shot A with the target caster, hide it, shot B
		# without. Identical everything — the diff IS the caster's shadow.
		# Target: the pillar if spawned (static — immune to the idle-sway
		# confound that fooled the player-proxy version), else the proxy.
		var target := (get_node_or_null("A/BPillar") as Node3D) \
			if get_node_or_null("A/BPillar") else _player.get_node("PlayerModel")
		match _shot_frame:
			44:
				_shot(("%s_A.png" % _shot_path.get_basename()))
				target.visible = false
			46:
				_shot(("%s_B.png" % _shot_path.get_basename()))
				var a := Image.load_from_file("%s_A.png" % _shot_path.get_basename())
				var b := Image.load_from_file("%s_B.png" % _shot_path.get_basename())
				if a and b:
					_strip_report(a, b, target)
				get_tree().quit()
		return
	if _shot_frame < 45:
		return
	_shot(_shot_path)
	_luma_probe(img_probe())
	get_tree().quit()


## Ground-truth shadow probe: sample the rendered pixels at the floor just
## past the player's feet (where a −60° sun throws the proxy shadow) against
## the floor to the side (same material, unshadowed). Printed numbers, not
## eyeballing — the shadow reads as a clear luma gap between the two.
func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[ValleyWalk] screenshot → %s" % path)


func img_probe() -> Image:
	return get_viewport().get_texture().get_image()


## Row of Δluma (A−B, caster on minus caster off) across a strip at the
## caster's screen base: a contiguous negative dip is its shadow. The strip
## sits BELOW the caster's silhouette bottom (floor pixels + shadow only),
## away from animated geometry. Numbers, not eyeballs.
func _strip_report(a: Image, b: Image, target: Node3D) -> void:
	var cam := get_viewport().get_camera_3d()
	var base: Vector3 = target.global_position
	var top: Vector3 = base + Vector3(0, 1.8, 0)
	var sp_base := cam.unproject_position(base)
	var sp_top := cam.unproject_position(top)
	var c := Vector2i(int(sp_base.x), int(sp_base.y) + int((sp_base.y - sp_top.y)) / 3)
	var y := c.y + 26
	var vals := _strip_values(a, b, c.x, y)
	var parts := _strip(a, b, c.x, y)
	var ctrl := _strip(a, b, c.x + 420, y)
	var dip_x := -1
	var dip := 0.0
	for i in range(vals.size()):
		if vals[i] < dip:
			dip = vals[i]
			dip_x = c.x - 126 + i * 18
	print("[ValleyWalk] Δstrip   @y=%d: %s" % [y, " ".join(parts)])
	print("[ValleyWalk] Δctrl   @y=%d: %s" % [y, " ".join(ctrl)])
	print("[ValleyWalk] deepest dip %.2f at x=%d (caster x=%d) — %s" % [
		dip, dip_x, c.x,
		"SHADOW RENDERS" if dip < -0.04 and absi(dip_x - c.x) < 120 else "no shadow"])


func _strip_values(a: Image, b: Image, cx: int, y: int) -> Array[float]:
	var vals: Array[float] = []
	for i in range(14):
		var x := cx - 126 + i * 18
		var d := 0.0
		var n := 0
		for yy in range(y - 4, y + 5):
			if x >= 0 and yy >= 0 and x < a.get_size().x and yy < a.get_size().y:
				d += a.get_pixel(x, yy).v - b.get_pixel(x, yy).v
				n += 1
		vals.append(d / maxf(1.0, float(n)))
	return vals


func _strip(a: Image, b: Image, cx: int, y: int) -> Array[String]:
	var parts: Array[String] = []
	for i in range(14):
		var x := cx - 126 + i * 18
		var d := 0.0
		var n := 0
		for yy in range(y - 4, y + 5):
			if x >= 0 and yy >= 0 and x < a.get_size().x and yy < a.get_size().y:
				d += a.get_pixel(x, yy).v - b.get_pixel(x, yy).v
				n += 1
		parts.append("%+.2f" % (d / maxf(1.0, float(n))))
	return parts


func _luma_probe(img: Image) -> void:
	var c := _player_screen_center()
	var shadow := Vector2i(c.x - int(img.get_size().x * 0.02), c.y - 26)
	var aside := Vector2i(c.x - int(img.get_size().x * 0.20), c.y - 10)
	var l_shadow := _region_luma(img, shadow, 46)
	var l_aside := _region_luma(img, aside, 46)
	print("[ValleyWalk] luma probe: shadow-side %.3f  aside %.3f  gap %.3f%s" % [
		l_shadow, l_aside, l_aside - l_shadow,
		"  ← SHADOW" if l_aside - l_shadow > 0.05 else "  ← no shadow"])


func _player_screen_center() -> Vector2i:
	var cam := get_viewport().get_camera_3d()
	var sp := cam.unproject_position(_player.global_position + Vector3(0, 0.9, 0))
	return Vector2i(int(sp.x), int(sp.y))


func _region_luma(img: Image, at: Vector2i, box: int) -> float:
	var sum := 0.0
	var n := 0
	for y in range(at.y - box / 2, at.y + box / 2):
		for x in range(at.x - box / 2, at.x + box / 2):
			if x >= 0 and y >= 0 and x < img.get_size().x and y < img.get_size().y:
				sum += img.get_pixel(x, y).v
				n += 1
	return sum / maxf(1.0, float(n))


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

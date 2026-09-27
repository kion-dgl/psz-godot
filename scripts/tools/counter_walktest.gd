extends CityAreaBase
## Guild counter WALK lab (#656 lock pass) — walk the authored rig in the
## s00e_sa2 hall without the city run-up: the production material path
## (_fix_city_materials → vertex colors off, the controller's "baked too
## dark" override) under the REAL sidecar rig (_add_authored_lights: ambient
## override + placeholder-sun retirement included), on the trimesh floor,
## with a controllable player. The scene mirrors city_counter.tscn's own
## environment (sky ambient 1.5 warm + 0.3 sun) so the sidecar's overrides
## land exactly as they do in-game — including the sun going dark.
##
## The DS bake look (B, the default) is the WETLANDS A pattern indoors
## (kion's conditions, 2026-09-26): no sun; the authored omnis in the scene;
## the city mesh pure bake (UNSHADED — lights cannot touch it); the actors
## lit by the omnis; and the actors' dynamic shadows cast BY the omnis (the
## wetlands lantern precedent — placed omnis CAN cast, dual-paraboloid on
## compat, only actors cast so the passes stay cheap) onto the MUL catcher:
## the collision shell rendered white/multiply — lit ground multiplies by
## ~1 (invisible, the bake reads verbatim), pools and shadows multiply DOWN
## onto it. The catcher is never "shown": multiply cannot paint, only
## darken — the black-floor era was the shadow_to_opacity shader catcher.
##
## Env:  PSZ_WALK_STAGE=s00e_sa2    boot stage (must have a city-lights sidecar)
##       PSZ_WALK_BAKE=0            boot OUT of the DS bake (the lit A/B look)
##       PSZ_WALK_SHADOWS=0          boot with the omni shadows off (diff control)
##       PSZ_WALK_FLOOR_LIT=a,b      override the floor-lit surface list (the
##                               DEFAULT covers ground01/groud01/doorset — an
##                               unlisted floor neither pools nor shadows);
##                               "0" disables the rig (catcher probes return)
##       PSZ_WALK_FLAT_FLOOR=r,g,b   with FLOOR_LIT=0: the collision shell as
##                               an opaque flat-color lit floor ("1" = warm
##                               gray) — total coverage, pools + omni shadows
##                               everywhere, bake kept on walls/props
##       PSZ_WALK_BAKE_FLOOR=1      with FLOOR_LIT=0: the same opaque shell
##                               receiver wearing a one-shot top-down capture
##                               of the stage's own bake as its albedo — the
##                               "transparent hull that shows the shadow"
##       PSZ_WALK_SHOT=/tmp/o.png   screenshot + quit (smoke; else live keys)
##       PSZ_WALK_STATIONS="x,y,z;…"  station walk — teleport to each station,
##                               settle, screenshot + the per-light verdict
##                               table, quit after the last. THE read for
##                               "where in the hall does a shadow show?"
##       PSZ_WALK_STATION_DIR=/tmp/x  where station shots land (default /tmp/cwalk)
##       PSZ_WALK_CAM_ROT=-1.5708  follow-camera azimuth (default π); turn it
##                               so wall-side stations frame over open floor
##       PSZ_WALK_SHOT_EVERY=30     live: save a screenshot every N frames to
##       PSZ_WALK_SHOT_DIR=/tmp/y   that dir — ground truth for what the live
##                               window showed, no capture process needed.
##                               NOTE: the readback stalls the frame it lands
##                               on — leave it OFF when judging framerate.
##       PSZ_WALK_FPS=1             print avg fps + slow-frame count every
##                               120 frames (the perf read)
## Keys: , / .  ambient ∓/± 0.05     [ / ]  omni pools ∓/± 0.25× (0.00 kills)
##       B       DS architecture A/B (the wetlands-pattern rig above)
##       M       omni shadows toggle (all authored lights at once)
##       P       read-out — the sidecar JSON, paste-ready for
##               data/stage_configs/city-lights/<stage>.json
##       N       next stage · R reload · ESC quit
##
## Tuning here IS authoring: [ / ] rescale the base energies, P prints the
## scaled rig, and the JSON drops straight into the sidecar the game loads.

const FieldLabScript := preload("res://scripts/tools/field_lab.gd")

## City stages with a city-lights sidecar (the counter today; the office,
## underground, and market join when their rigs land).
const STAGES := ["s00e_sa2"]

const STAGE_GLB_FMT := "res://assets/stages/city_e/%s/lndmd/%s_m.glb"
const FLOOR_GLB_FMT := "res://assets/stages/city_e/%s/lndmd/%s-floor.glb"

## city_counter_controller's own spawn: a touch above the real floor (−10.67).
const DEFAULT_SPAWN := Vector3(-0.05, -9.0, 121.78)

## The floor surfaces that receive the rig (the ozette wildcard, floored):
## the two ground materials plus the door strips — the office doorway is
## doorset, and an unlisted floor can neither pool nor shadow (kion's
## "no shadow next to the principal's office", 2026-09-26).
const FLOOR_LIT_DEFAULT := "ground01_COLOR_0,groud01_COLOR_0.001,doorset_COLOR_0,doorset_COLOR_0.001"

## N's selection survives the scene reload that swaps the room.
static var _pending_stage := ""

var _stage_id := "s00e_sa2"
var _env: Environment
var _pool_scale := 1.0
var _base_energies: Dictionary = {}  # OmniLight3D path → authored energy
var _base_shadows: Dictionary = {}   # OmniLight3D path → authored shadow_enabled
var _bake_mode := false
var _catcher: MeshInstance3D
var _shot := FieldLabScript.ShotRun.new()
var _status: Label

## The station walk (PSZ_WALK_STATIONS): station index, frames since its
## teleport. Each station teleports, settles ~40 frames (fall, one clean
## draw), then screenshots + prints the per-light verdict table.
var _stations: Array[Vector3] = []
var _station_idx := -1
var _station_frame := 0
var _station_dir := "/tmp/cwalk"

## Live periodic capture (PSZ_WALK_SHOT_EVERY): frames between screenshots,
## 0 = off. Same viewport the window shows, saved straight to disk.
var _live_every := 0
var _live_dir := "/tmp/cwalk_live"
var _live_frame := 0

const STATION_SETTLE := 40


func _ready() -> void:
	if not _pending_stage.is_empty():
		_stage_id = _pending_stage
		_pending_stage = ""
	elif not OS.get_environment("PSZ_WALK_STAGE").is_empty():
		_stage_id = OS.get_environment("PSZ_WALK_STAGE")
	_shot.path = OS.get_environment("PSZ_WALK_SHOT")
	for spec in OS.get_environment("PSZ_WALK_STATIONS").split(";", false):
		var xyz := spec.split(",")
		if xyz.size() == 3:
			_stations.append(Vector3(xyz[0].to_float(), xyz[1].to_float(), xyz[2].to_float()))
	if not OS.get_environment("PSZ_WALK_STATION_DIR").is_empty():
		_station_dir = OS.get_environment("PSZ_WALK_STATION_DIR")
	_live_every = OS.get_environment("PSZ_WALK_SHOT_EVERY").to_int()
	if not OS.get_environment("PSZ_WALK_SHOT_DIR").is_empty():
		_live_dir = OS.get_environment("PSZ_WALK_SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(_station_dir)
	DirAccess.make_dir_recursive_absolute(_live_dir)
	_fps_wanted = OS.get_environment("PSZ_WALK_FPS") == "1"
	_build_environment()
	_load_stage()
	# The controller's _ready order verbatim: texture fixes, the SA2 vertex
	# bake override, then the sidecar (ambient override + sun retirement
	# inside _add_authored_lights) with the legacy row as fallback.
	_fix_city_materials()
	_override_vertex_colors(false)
	if not _add_authored_lights(_stage_id):
		_add_interior_lights([
			Vector3(0, 4, 18), Vector3(0, 4, 12), Vector3(0, 4, 6), Vector3(0, 4, 0),
			Vector3(0, 4, -6), Vector3(0, 4, -12), Vector3(0, 4, -18),
		])
	_capture_base_energies()
	_add_trimesh_floor(FLOOR_GLB_FMT % [_stage_id, _stage_id], Vector3.ZERO)
	var lab_player := FieldLabScript.spawn_player(self, DEFAULT_SPAWN)
	_player = lab_player
	# PSZ_WALK_CAM_ROT (radians): the follow camera defaults to PI (behind in
	# −z); wall-side stations want it turned so the camera sits over open
	# floor — e.g. −PI/2 frames the east sconces from the hall center.
	var cam_rot := OS.get_environment("PSZ_WALK_CAM_ROT")
	if not cam_rot.is_empty():
		var orbit := get_node_or_null("OrbitCamera")
		if orbit:
			orbit.camera_rotation = cam_rot.to_float()
	# PSZ_WALK_TELEPORT="x,y,z": drop the player elsewhere before the shot —
	# the between-two-lights smoke.
	var tp := OS.get_environment("PSZ_WALK_TELEPORT")
	if not tp.is_empty():
		var parts := tp.split(",")
		if parts.size() == 3:
			_player.global_position = Vector3(
				parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
	# Same floor the game guards: the mesh is authored low (−10.67) and the
	# default −10 fall-respawn would read the floor as a fall.
	lab_player.fall_respawn_y = -25.0
	# PSZ_WALK_SUN_PROBE=1: a dim shadow-casting directional (the valley
	# contract) over the same catcher — the asymmetry probe for "does the
	# MUL catcher receive directional but not omni shadow maps on compat?"
	if OS.get_environment("PSZ_WALK_SUN_PROBE") == "1":
		var probe := DirectionalLight3D.new()
		probe.name = "SunProbe"
		probe.light_energy = 0.6
		probe.shadow_enabled = true
		probe.rotation_degrees = Vector3(-60, 25, 0)
		add_child(probe)
	# PSZ_WALK_DUMP_SURFACES=1: print every stage surface's material names —
	# the discovery read for PSZ_WALK_FLOOR_LIT (which names are the floor).
	if OS.get_environment("PSZ_WALK_DUMP_SURFACES") == "1":
		var map := get_node_or_null("Map")
		for node in MeshUtils.collect_mesh_instances(map, []):
			var mi := node as MeshInstance3D
			for i in range(mi.get_surface_override_material_count()):
				var mat: Material = mi.get_active_material(i)
				if mat:
					print("[CWalk] surface %s[%d] material '%s'" % [mi.name, i, mat.resource_name])
	_build_status_label()
	_readout()
	# The DS architecture is the DEFAULT look (the #656 objective). B still
	# A/Bs live; PSZ_WALK_BAKE=0 boots the pre-bake lit look instead.
	if OS.get_environment("PSZ_WALK_BAKE") != "0":
		_set_bake_mode(true)
	print("[CWalk] ready — , . ambient · [ ] pools · B bake+catcher · M shadows · P readout · N next · R reload · ESC quit")

var _player: Node3D


func _process(_delta: float) -> void:
	_update_live_status()
	_fps_tick(_delta)
	if not _stations.is_empty():
		_step_stations()
		return
	_shot.step(self, "CWalk")
	_live_step()


var _fps_wanted := false
var _fps_frames := 0
var _fps_acc := 0.0
var _fps_slow := 0


## PSZ_WALK_FPS=1: avg frame rate + slow-frame count (>50 ms) per 120 frames
## — the read for "is the rig itself heavy, or was it the capture reel?"
func _fps_tick(delta: float) -> void:
	if not _fps_wanted:
		return
	_fps_frames += 1
	_fps_acc += delta
	if delta > 0.05:
		_fps_slow += 1
	if _fps_frames >= 120:
		print("[CWalk] fps %.1f avg, %d slow frames (>50ms) over %d" % [
			_fps_frames / maxf(_fps_acc, 0.0001), _fps_slow, _fps_frames])
		_fps_frames = 0
		_fps_acc = 0.0
		_fps_slow = 0


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_COMMA:
			_env.ambient_light_energy = maxf(0.0, _env.ambient_light_energy - 0.05)
		KEY_PERIOD:
			_env.ambient_light_energy += 0.05
		KEY_BRACKETLEFT:
			_pool_scale = maxf(0.0, _pool_scale - 0.25)
			_apply_pool_scale()
		KEY_BRACKETRIGHT:
			_pool_scale += 0.25
			_apply_pool_scale()
		KEY_B:
			_set_bake_mode(not _bake_mode)
		KEY_M:
			var shadows := not _authored_lights()[0].shadow_enabled if not _authored_lights().is_empty() else false
			for light in _authored_lights():
				light.shadow_enabled = shadows
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


## city_counter.tscn's own environment and placeholder sun, mirrored — the
## sidecar then overrides the ambient and zeroes the sun exactly as the
## production boot does, so the A/B here is the A/B in-game.
func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.4, 0.5, 0.7)
	sky_mat.sky_horizon_color = Color(0.6, 0.7, 0.8)
	sky_mat.ground_bottom_color = Color(0.2, 0.2, 0.2)
	sky_mat.ground_horizon_color = Color(0.4, 0.45, 0.5)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_color = Color(0.9, 0.88, 0.82)
	_env.ambient_light_energy = 1.5
	var env_node := WorldEnvironment.new()
	env_node.environment = _env
	# Name it like the tscn does: runtime-added nodes auto-name to
	# @WorldEnvironment@N, and the production ambient override must find it.
	env_node.name = "WorldEnvironment"
	add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.position = Vector3(10, 20, 10)
	sun.light_energy = 0.3
	sun.shadow_enabled = false
	add_child(sun)


func _load_stage() -> void:
	var packed := load(STAGE_GLB_FMT % [_stage_id, _stage_id]) as PackedScene
	if not packed:
		push_error("[CWalk] no stage GLB for %s" % _stage_id)
		return
	var map_root := packed.instantiate() as Node3D
	map_root.name = "Map"
	add_child(map_root)


## The wetlands-A architecture, indoors (B): the stage keeps its pure baked
## look (MeshUtils.make_unlit: UNSHADED, COLOR_0 as albedo — no light can
## touch the city mesh); the authored omnis light the actors exactly as
## authored; and the omnis CAST (the wetlands lantern exception) so each
## throws the actors' real dynamic shadow from its own position — stand
## between two lights and two shadows fall away from each. The catcher is
## the collision shell with the VALLEY material (white, multiply-blended,
## up-facing only — the city floor GLB wraps the whole room and its walls
## sat coplanar with the stage): lit ground multiplies by ~1 (the bake reads
## verbatim), pools and the omnis' shadow maps multiply down onto it. The
## catcher cannot "show" — multiply only darkens what is behind it (the
## black-floor era was the shadow_to_opacity catcher, retired).
func _set_bake_mode(on: bool) -> void:
	_bake_mode = on
	# The floor-lit rig is the default; PSZ_WALK_FLOOR_LIT overrides the
	# surface list, "0" disables it (the catcher probes come back then).
	var floor_lit := OS.get_environment("PSZ_WALK_FLOOR_LIT")
	if floor_lit.is_empty():
		floor_lit = FLOOR_LIT_DEFAULT
	var map := get_node_or_null("Map")
	if map:
		if on:
			MeshUtils.make_unlit(map, [])
			# The ozette contract on the floor surfaces — per-pixel with the
			# vertex bake as albedo, so the authored omnis pool on them AND
			# their shadow maps land (opaque receivers take omni shadows on
			# compat; the MUL catcher measurably doesn't). Walls and props
			# stay pure bake; no catcher mesh at all — the visual floor IS
			# the receiver.
			if floor_lit != "0":
				var wanted: Dictionary = {}
				for n in floor_lit.split(",", false):
					wanted[n.strip_edges()] = true
				for node in MeshUtils.collect_mesh_instances(map, []):
					var mi := node as MeshInstance3D
					for i in range(mi.get_surface_override_material_count()):
						var mat: Material = mi.get_active_material(i)
						if mat is StandardMaterial3D \
								and wanted.has((mat as StandardMaterial3D).resource_name):
							var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
							dup.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
							dup.vertex_color_use_as_albedo = true
							mi.set_surface_override_material(i, dup)
		else:
			# Back to the production lit look: per-pixel, vertex colors off.
			for node in MeshUtils.collect_mesh_instances(map, []):
				var mi := node as MeshInstance3D
				for i in range(mi.get_surface_override_material_count()):
					var mat: Material = mi.get_active_material(i)
					if mat is StandardMaterial3D:
						var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
						dup.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
						dup.vertex_color_use_as_albedo = false
						mi.set_surface_override_material(i, dup)
		# The stage never casts — indoors the whole room is the valley's
		# enclosing shell. Actors (the player, NPCs) are the only casters, so
		# the omnis' shadow maps are the actors' shadows and nothing else's,
		# and the extra shadow passes stay cheap.
		for node in MeshUtils.collect_mesh_instances(map, []):
			(node as MeshInstance3D).cast_shadow = \
					GeometryInstance3D.SHADOW_CASTING_SETTING_ON if not on \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The catcher probes only run with the floor-lit rig disabled.
	if on and _catcher == null and floor_lit == "0" \
			and OS.get_environment("PSZ_WALK_NO_CATCHER") != "1":
		var floor_root := get_node_or_null("FloorCollision")
		if floor_root:
			var flat := OS.get_environment("PSZ_WALK_FLAT_FLOOR")
			# PSZ_WALK_BAKE_FLOOR=1: the FLAT_FLOOR receiver wearing the
			# stage's own bake — a one-shot top-down ortho capture of the
			# UNSHADED floor slice, mapped by world XZ (kion's "transparent
			# hull that shows the shadow": the printed floor IS the bake, so
			# the opaque receiver reads as transparent while taking the
			# omnis' shadow maps).
			if OS.get_environment("PSZ_WALK_BAKE_FLOOR") == "1":
				var bake := await _capture_floor_bake()
				if bake != null:
					_catcher = bake
			if _catcher == null:
				# PSZ_WALK_FLAT_FLOOR="r,g,b" (or "1" for the default warm gray):
				# kion's proposal — the c18324ba catcher architecture (the whole
				# collision shell, up-facing, +0.04) but an OPAQUE flat-color
				# per-pixel floor instead of the black shadow_to_opacity veil.
				# No surface list to hunt (the shell IS the walk surface — the
				# mid-floor strips that ground01/doorset miss are covered), and
				# an opaque lit receiver is exactly what takes the omnis' shadow
				# maps on compat. The stage keeps its bake; the walls keep theirs.
				if not flat.is_empty():
					_catcher = MeshUtils.make_flat_floor(floor_root, _flat_floor_color(flat))
				else:
					_catcher = MeshUtils.make_shadow_catcher(floor_root, true, false)
			if _catcher:
				# PSZ_WALK_MUL_SHADER=1: the multiply through the SHADER path
				# (blend_mul) instead of the StandardMaterial3D MUL — the
				# asymmetry probe showed omni shadow maps don't reach the
				# standard transparent-MUL receiver on compat (directionals
				# do), while c18324ba's shader catcher took them fine.
				if flat.is_empty() and _catcher.name == "ShadowCatcher" \
						and OS.get_environment("PSZ_WALK_MUL_SHADER") == "1":
					var mat := ShaderMaterial.new()
					var sh := Shader.new()
					sh.code = "
shader_type spatial;
render_mode blend_mul, depth_draw_never;
void fragment() {
	ALBEDO = vec3(1.0);
}
"
					mat.shader = sh
					_catcher.mesh.surface_set_material(0, mat)
				add_child(_catcher)
	elif not on and _catcher != null:
		_catcher.queue_free()
		_catcher = null
	# The omnis ARE the rig — every authored light casts in bake mode (the
	# wetlands lantern precedent: shadow_enabled + blur 1.0). Leaving bake
	# restores each sidecar's own state; M still flips everything live.
	# PSZ_WALK_SHADOWS=0 is the screenshot A/B control (bake + catcher, no
	# casters).
	var shadows_on := OS.get_environment("PSZ_WALK_SHADOWS") != "0"
	for light in _authored_lights():
		light.shadow_enabled = shadows_on if on \
				else bool(_base_shadows.get(light.get_path(), light.shadow_enabled))
		if on:
			light.shadow_blur = 1.0
	_update_status()


## PSZ_WALK_FLAT_FLOOR color spec: "1" picks the default warm gray; "r,g,b"
## (0..1 each) authoring a custom flat tone.
func _flat_floor_color(spec: String) -> Color:
	const DEFAULT_FLAT := Color(0.42, 0.39, 0.35)
	if spec != "1":
		var rgb := spec.split(",")
		if rgb.size() == 3:
			return Color(
				clampf(rgb[0].to_float(), 0.0, 1.0),
				clampf(rgb[1].to_float(), 0.0, 1.0),
				clampf(rgb[2].to_float(), 0.0, 1.0))
	return DEFAULT_FLAT


## The one-shot bake capture (PSZ_WALK_BAKE_FLOOR): a top-down ortho
## SubViewport over the UNSHADED stage, hung just above the walk height
## with a short far plane so walls only print their base strip, and the
## player hidden — what lands in the texture is the pure floor bake,
## world-XZ aligned (rotation −90°: camera right = +X, so texture u/v map
## directly onto world x/z from the capture bounds' minimum corner).
func _capture_floor_bake() -> MeshInstance3D:
	var floor_root := get_node_or_null("FloorCollision")
	if floor_root == null:
		return null
	var aabb := AABB()
	var has_aabb := false
	for node in MeshUtils.collect_mesh_instances(floor_root, []):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var world_aabb: AABB = mi.global_transform * mi.get_aabb()
		if has_aabb:
			aabb = aabb.merge(world_aabb)
		else:
			aabb = world_aabb
			has_aabb = true
	if not has_aabb:
		return null
	var origin := Vector2(aabb.position.x - 1.0, aabb.position.z - 1.0)
	var size := Vector2(aabb.size.x + 2.0, aabb.size.z + 2.0)
	var px := mini(2048, int(24.0 * size.x))
	var py := mini(2048, int(24.0 * size.y))
	var vp := SubViewport.new()
	vp.size = Vector2(px, py)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.position = Vector3(
		origin.x + size.x * 0.5,
		MeshUtils.floor_top(floor_root) + 1.2,
		origin.y + size.y * 0.5)
	cam.set_orthogonal(size.y, 0.05, 2.5)
	vp.add_child(cam)
	add_child(vp)
	# The player must not print into the bake.
	if _player != null:
		_player.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if _player != null:
		_player.visible = true
	print("[CWalk] floor bake captured %dx%d over x[%.1f..%.1f] z[%.1f..%.1f]" % [
		img.get_width(), img.get_height(),
		origin.x, origin.x + size.x, origin.y, origin.y + size.y])
	return MeshUtils.make_baked_floor(floor_root, ImageTexture.create_from_image(img),
		origin, size)


func _authored_lights() -> Array[OmniLight3D]:
	var out: Array[OmniLight3D] = []
	for child in get_children():
		if child is OmniLight3D:
			out.append(child)
	return out


func _capture_base_energies() -> void:
	for light in _authored_lights():
		_base_energies[light.get_path()] = light.light_energy
		_base_shadows[light.get_path()] = light.shadow_enabled


func _apply_pool_scale() -> void:
	for light in _authored_lights():
		light.light_energy = float(_base_energies.get(light.get_path(), light.light_energy)) * _pool_scale


## The read-out prints the live rig as the sidecar JSON it would become —
## ambient, then every omni with its scaled energy — paste-ready for
## data/stage_configs/city-lights/<stage>.json (the game and the web labs
## load that file verbatim).
func _readout() -> void:
	var lights: Array = []
	for light in _authored_lights():
		lights.append({
			"name": String(light.name),
			"pos": [snappedf(light.position.x, 0.001), snappedf(light.position.y, 0.001), snappedf(light.position.z, 0.001)],
			"color": [light.light_color.r, light.light_color.g, light.light_color.b],
			"energy": snappedf(light.light_energy, 0.01),
			"range": snappedf(light.omni_range, 0.1),
			"attenuation": light.omni_attenuation,
			"shadows": light.shadow_enabled,
		})
	var doc := {
		"stage": _stage_id,
		"ambient": {
			"color": [_env.ambient_light_color.r, _env.ambient_light_color.g, _env.ambient_light_color.b],
			"energy": snappedf(_env.ambient_light_energy, 0.01),
		},
		"lights": lights,
	}
	print("[CWalk] sidecar read-out — paste into data/stage_configs/city-lights/%s.json:\n%s" % [
		_stage_id, JSON.stringify(doc, "  ")])


## The station walk: teleport, settle, shoot, report. The verdict table
## printed beside each shot is the reconciliation read — which lights are
## in range here and casting, next to the screenshot that says what reads.
func _step_stations() -> void:
	if _station_idx < 0:
		_station_idx = 0
		_player.global_position = _stations[0]
		_station_frame = 0
		print("[CWalk] station 1/%d → %s" % [_stations.size(), _stations[0]])
		return
	_station_frame += 1
	if _station_frame < STATION_SETTLE:
		return
	var path := "%s/station_%d_x%.1f_z%.1f.png" % [
		_station_dir, _station_idx + 1,
		_stations[_station_idx].x, _stations[_station_idx].z]
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	_print_light_state("station %d/%d @ (%.1f, %.1f) → %s" % [
		_station_idx + 1, _stations.size(),
		_stations[_station_idx].x, _stations[_station_idx].z, path])
	_station_idx += 1
	if _station_idx >= _stations.size():
		get_tree().quit()
		return
	_player.global_position = _stations[_station_idx]
	_station_frame = 0
	print("[CWalk] station %d/%d → %s" % [
		_station_idx + 1, _stations.size(), _stations[_station_idx]])


## The per-light verdict at the player: distance, range gate, and whether
## the light is casting. Two lights share the name "Light 1", so each row
## leads with its index.
func _print_light_state(tag: String) -> void:
	var p := _player.global_position + Vector3(0, 0.8, 0)
	var rows: Array[String] = []
	var lights := _authored_lights()
	for i in lights.size():
		var light := lights[i]
		var d := light.global_position.distance_to(p)
		var verdict := "casts" if light.shadow_enabled else "no-cast"
		if d >= light.omni_range:
			verdict += "+out-of-range"
		rows.append("P%d %s(e%.0f d=%.1f %s)" % [i, light.name, light.light_energy, d, verdict])
	print("[CWalk] %s — %s" % [tag, "  ".join(rows)])


## The HUD carries the live position and the strongest in-range light
## (energy/d²) — where a shadow should be reading right now.
func _update_live_status() -> void:
	if _status == null or _player == null:
		return
	var top := "-"
	var top_w := 0.0
	var p := _player.global_position + Vector3(0, 0.8, 0)
	for light in _authored_lights():
		var d := light.global_position.distance_to(p)
		if d >= light.omni_range or d < 0.01:
			continue
		var w := light.light_energy / (d * d)
		if w > top_w:
			top_w = w
			top = "%s d=%.1f" % [light.name, d]
	var live := " | (%.1f, %.1f) top: %s" % [
		_player.global_position.x, _player.global_position.z, top]
	_status.text = _base_status() + live


## PSZ_WALK_SHOT_EVERY: the live ground-truth reel — the same framebuffer the
## window shows, dropped to PSZ_WALK_SHOT_DIR every N frames while walking.
func _live_step() -> void:
	if _live_every <= 0:
		return
	_live_frame += 1
	if _live_frame % _live_every != 0:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/frame_%04d.png" % [_live_dir, _live_frame])
	if _live_frame == _live_every:
		print("[CWalk] live capture → %s every %d frames" % [_live_dir, _live_every])


func _build_status_label() -> void:
	_status = FieldLabScript.make_status_label(self)
	_update_status()


func _update_status() -> void:
	_status.text = _base_status()


func _base_status() -> String:
	var n := _authored_lights().size()
	return "%s%s — ambient %.2f (, .)  pools %.2f× ([ ])  shadows %s (M)  bake (B)" % [
		_stage_id, " · DS bake" if _bake_mode else "",
		_env.ambient_light_energy, _pool_scale,
		"on" if n > 0 and _authored_lights()[0].shadow_enabled else "off"]

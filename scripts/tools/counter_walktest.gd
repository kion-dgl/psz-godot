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


## The per-light projector rig: one SubViewport per placed light renders the
## actor's SILHOUETTE from that light's position (camera at the light, aimed
## at the actor, actors-only cull layer); the catcher is an UNSHADED quad
## field whose shader projects each silhouette onto the floor through the
## same camera's matrices and composites them with per-light weights
## (energy / distance²). Transparent floor by construction (the catcher is
## unlit — no engine light can touch it, no min formula, no veil), N real
## per-light shadows, renderer-proof. Every engine-shadow path was measured
## or derived dead first — see mesh_utils.make_shadow_catcher's doc.
const PROJECTOR_SHADER := "
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never;

uniform sampler2D u_tex0; uniform mat4 u_view0; uniform mat4 u_proj0; uniform float u_w0;
uniform sampler2D u_tex1; uniform mat4 u_view1; uniform mat4 u_proj1; uniform float u_w1;
uniform sampler2D u_tex2; uniform mat4 u_view2; uniform mat4 u_proj2; uniform float u_w2;
uniform sampler2D u_tex3; uniform mat4 u_view3; uniform mat4 u_proj3; uniform float u_w3;
uniform sampler2D u_tex4; uniform mat4 u_view4; uniform mat4 u_proj4; uniform float u_w4;
uniform sampler2D u_tex5; uniform mat4 u_view5; uniform mat4 u_proj5; uniform float u_w5;
uniform sampler2D u_tex6; uniform mat4 u_view6; uniform mat4 u_proj6; uniform float u_w6;
uniform sampler2D u_tex7; uniform mat4 u_view7; uniform mat4 u_proj7; uniform float u_w7;

uniform float u_debug;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = vec3(0.0);
	float a = 0.0;
	vec4 c;
	vec2 uv;
	c = u_proj0 * (u_view0 * vec4(world_pos, 1.0));
	if (u_w0 > 0.001 && c.w > 0.0) {
		uv = c.xy / c.w * 0.5 + 0.5; uv.y = 1.0 - uv.y;
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			a = max(a, texture(u_tex0, uv).a * u_w0);
		}
	}
	c = u_proj1 * (u_view1 * vec4(world_pos, 1.0));
	if (u_w1 > 0.001 && c.w > 0.0) {
		uv = c.xy / c.w * 0.5 + 0.5; uv.y = 1.0 - uv.y;
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			a = max(a, texture(u_tex1, uv).a * u_w1);
		}
	}
	c = u_proj2 * (u_view2 * vec4(world_pos, 1.0));
	if (u_w2 > 0.001 && c.w > 0.0) {
		uv = c.xy / c.w * 0.5 + 0.5; uv.y = 1.0 - uv.y;
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			a = max(a, texture(u_tex2, uv).a * u_w2);
		}
	}
	c = u_proj3 * (u_view3 * vec4(world_pos, 1.0));
	if (u_w3 > 0.001 && c.w > 0.0) {
		uv = c.xy / c.w * 0.5 + 0.5; uv.y = 1.0 - uv.y;
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			a = max(a, texture(u_tex3, uv).a * u_w3);
		}
	}
	c = u_proj4 * (u_view4 * vec4(world_pos, 1.0));
	if (u_w4 > 0.001 && c.w > 0.0) {
		uv = c.xy / c.w * 0.5 + 0.5; uv.y = 1.0 - uv.y;
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			a = max(a, texture(u_tex4, uv).a * u_w4);
		}
	}
	c = u_proj5 * (u_view5 * vec4(world_pos, 1.0));
	if (u_w5 > 0.001 && c.w > 0.0) {
		uv = c.xy / c.w * 0.5 + 0.5; uv.y = 1.0 - uv.y;
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			a = max(a, texture(u_tex5, uv).a * u_w5);
		}
	}
	c = u_proj6 * (u_view6 * vec4(world_pos, 1.0));
	if (u_w6 > 0.001 && c.w > 0.0) {
		uv = c.xy / c.w * 0.5 + 0.5; uv.y = 1.0 - uv.y;
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			a = max(a, texture(u_tex6, uv).a * u_w6);
		}
	}
	c = u_proj7 * (u_view7 * vec4(world_pos, 1.0));
	if (u_w7 > 0.001 && c.w > 0.0) {
		uv = c.xy / c.w * 0.5 + 0.5; uv.y = 1.0 - uv.y;
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			a = max(a, texture(u_tex7, uv).a * u_w7);
		}
	}
	ALPHA = a;
	if (u_debug > 0.5) {
		ALBEDO = vec3(0.85, 0.1, 0.1);
		ALPHA = clamp(0.18 + a, 0.0, 0.9);
	}
}
"

## The render layer the projector cameras see: actor meshes only.
const ACTOR_LAYER := 8
## Shadow strength at the strongest — the max composite alpha.
const SHADOW_MAX_ALPHA := 0.55

## N's selection survives the scene reload that swaps the room.
static var _pending_stage := ""

var _stage_id := "s00e_sa2"
var _env: Environment
var _pool_scale := 1.0
## The catcher's emission base lift (PSZ_WALK_CATCHER_EMISSION, live via
## - / =): ambient + emission ≈ 1 hides the multiply mesh; pools top it.
var _catcher_emission := 0.85
var _base_energies: Dictionary = {}  # OmniLight3D path → authored energy
var _base_shadows: Dictionary = {}   # OmniLight3D path → authored shadow_enabled
var _bake_mode := false
var _catcher: MeshInstance3D
var _catcher_mat: ShaderMaterial
var _projectors: Array[Dictionary] = []  # {vp, cam, light}
var _shadows_on := true
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


## The lab's env knobs (extracted from _ready): stations, live reel,
## ambient/pools/emission boot overrides, fps read.
func _parse_walk_envs() -> void:
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
	# Station runs must keep compositing: macOS throttles occluded windows
	# to a standstill and every capture after that returns the same stale
	# frame (measured 2026-09-26 — stations 4/5 wrote one shared hash).
	if not _stations.is_empty():
		get_window().always_on_top = true
	_fps_wanted = OS.get_environment("PSZ_WALK_FPS") == "1"


func _ready() -> void:
	if not _pending_stage.is_empty():
		_stage_id = _pending_stage
		_pending_stage = ""
	elif not OS.get_environment("PSZ_WALK_STAGE").is_empty():
		_stage_id = OS.get_environment("PSZ_WALK_STAGE")
	_parse_walk_envs()
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
	# PSZ_WALK_AMBIENT / PSZ_WALK_POOLS: boot-time equivalents of the live
	# , . and [ ] keys — the calibrated-catcher experiments need them from
	# the first frame (kion's live tuning: 0.1 / 0.25).
	var ambient_env := OS.get_environment("PSZ_WALK_AMBIENT")
	if not ambient_env.is_empty():
		_env.ambient_light_energy = clampf(ambient_env.to_float(), 0.0, 4.0)
	var pools_env := OS.get_environment("PSZ_WALK_POOLS")
	if not pools_env.is_empty():
		_pool_scale = clampf(pools_env.to_float(), 0.0, 4.0)
		_apply_pool_scale()
	var emis_env := OS.get_environment("PSZ_WALK_CATCHER_EMISSION")
	if not emis_env.is_empty():
		_catcher_emission = clampf(emis_env.to_float(), 0.0, 1.5)
	_add_trimesh_floor(FLOOR_GLB_FMT % [_stage_id, _stage_id], Vector3.ZERO)
	_spawn_lab_player()
	_build_status_label()
	_readout()
	# The DS architecture is the DEFAULT look (the #656 objective). B still
	# A/Bs live; PSZ_WALK_BAKE=0 boots the pre-bake lit look instead.
	if OS.get_environment("PSZ_WALK_BAKE") != "0":
		_set_bake_mode(true)
	print("[CWalk] ready — , . ambient · [ ] pools · B bake+catcher · M shadows · P readout · N next · R reload · ESC quit")

var _player: Node3D


## The lab player + camera + boot probes (extracted from _ready).
func _spawn_lab_player() -> void:
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
	# The projector cameras see ACTOR_LAYER only — the player's meshes
	# join it so the silhouettes render.
	for node in MeshUtils.collect_mesh_instances(_player, []):
		(node as GeometryInstance3D).layers |= 8
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



func _process(_delta: float) -> void:
	_update_projectors()
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
		KEY_MINUS:
			_catcher_emission = maxf(0.0, _catcher_emission - 0.05)
			_apply_catcher_emission()
		KEY_EQUAL:
			_catcher_emission = minf(1.5, _catcher_emission + 0.05)
			_apply_catcher_emission()
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


## The blend_mul shader probe (extracted): the asymmetry experiment
## that measured omni shadow maps missing the multiply receiver.
func _apply_mul_probe() -> void:
	# PSZ_WALK_MUL_SHADER=1: the multiply through the SHADER path
	# (blend_mul) instead of the StandardMaterial3D MUL — the
	# asymmetry probe showed omni shadow maps don't reach the
	# standard transparent-MUL receiver on compat (directionals
	# do), while c18324ba's shader catcher took them fine.
	if OS.get_environment("PSZ_WALK_MUL_SHADER") == "1" \
			and _catcher != null and _catcher.name == "ShadowCatcher":
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


## The floor-lit receiver family (extracted from _set_bake_mode): the
## name-list / "geom" surface flip — per-pixel, bake as albedo, so the
## omnis pool on the floor and their shadow maps land on it directly.
func _apply_floor_lit_rig(map: Node, floor_lit: String) -> void:
	if floor_lit != "0":
		# "geom": flip by GEOMETRY, not name — every stage surface
		# whose triangles are mostly floor-tilted and near walk
		# height receives the rig. The name lists could never cover
		# the stage's material splits (kion's mid-floor dead strips,
		# 2026-09-26); geometry can. The shell is retired entirely:
		# the collision mesh never renders — the REAL stage floor is
		# the receiver, showing its own bake, pools, and the omnis'
		# shadow maps and nothing else.
		var geom := floor_lit == "geom"
		var wanted: Dictionary = {}
		if not geom:
			for n in floor_lit.split(",", false):
				wanted[n.strip_edges()] = true
		var floor_root := get_node_or_null("FloorCollision")
		var walk_y := MeshUtils.floor_top(floor_root) if floor_root else -10.67
		for node in MeshUtils.collect_mesh_instances(map, []):
			var mi := node as MeshInstance3D
			var arr_mesh: ArrayMesh = (mi.mesh as ArrayMesh) if geom else null
			for i in range(mi.get_surface_override_material_count()):
				var mat: Material = mi.get_active_material(i)
				if not (mat is StandardMaterial3D):
					continue
				if geom:
					if not _surface_is_floor(mi, arr_mesh, i, walk_y):
						continue
				elif not wanted.has((mat as StandardMaterial3D).resource_name):
					continue
				var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				dup.vertex_color_use_as_albedo = true
				mi.set_surface_override_material(i, dup)


## The catcher receiver family (extracted from _set_bake_mode): the sto
## baseline, the bake capture, the flat floor, the projector, the MUL
## probe — every PSZ_WALK_FLOOR_LIT=0 mode builds its receiver here.
func _build_catcher_rig(floor_lit: String) -> void:
	if _catcher == null and floor_lit == "0" \
			and OS.get_environment("PSZ_WALK_NO_CATCHER") != "1":
		var floor_root := get_node_or_null("FloorCollision")
		if floor_root:
			var flat := OS.get_environment("PSZ_WALK_FLAT_FLOOR")
			# PSZ_WALK_STO=1: the c18324ba rig VERBATIM — the
			# shadow_to_opacity catcher (up-facing, +0.04) with the
			# authored omnis casting. The known-good baseline kion's eyes
			# certified; every other mode bisects from here.
			if OS.get_environment("PSZ_WALK_STO") == "1":
				_catcher = MeshUtils.make_shadow_catcher(floor_root, true, true)
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
				elif OS.get_environment("PSZ_WALK_BAKE_FLOOR") == "1":
					# a failed bake capture degrades to the flat floor — never
					# ship a black bake
					_catcher = MeshUtils.make_flat_floor(floor_root, _flat_floor_color("1"))
				elif OS.get_environment("PSZ_WALK_PROJECTOR") == "1":
					# PSZ_WALK_PROJECTOR=1: the UNSHADED catcher + projected
					# per-light silhouettes (the 8def749b rig, returned to).
					# No light ever touches the catcher — no ambient veil, no
					# pools, no multiply: the collision mesh shows ONLY the
					# player's shadows, painted from each light's own position.
					# The multiply catcher cannot do this (a lit sheet always
					# reads: gray below x1, glow above); the projector is the
					# only rig where "nothing visible but the shadow" is exact.
					var mesh := MeshUtils.collision_face_mesh(floor_root, 0.6)
					if mesh != null:
						_catcher_mat = ShaderMaterial.new()
						var sh := Shader.new()
						sh.code = PROJECTOR_SHADER
						_catcher_mat.shader = sh
						if OS.get_environment("PSZ_WALK_CATCHER_DEBUG") == "1":
							_catcher_mat.set_shader_parameter("u_debug", 1.0)
						mesh.surface_set_material(0, _catcher_mat)
						_catcher = MeshInstance3D.new()
						_catcher.name = "ShadowProjector"
						_catcher.mesh = mesh
						_catcher.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						_catcher.position.y = 0.04
						_build_projectors()
			else:
				_catcher = MeshUtils.make_shadow_catcher(floor_root, true, false)
				# PSZ_WALK_CATCHER_EMISSION (default 0.85): the base lift
				# that breaks the ambient zero-sum — emission is an UNLIT
				# additive term on the multiply catcher, so it raises the
				# floor multiplier toward x1 (invisible mesh, no veil, no
				# seams) without shallowing shadows the way ambient does;
				# pools then push past x1 and read as light, shadows
				# remove only the pool term. The valley's uniform sun did
				# this for free; indoors, emission is the dial.
				if _catcher:
					var cmat := _catcher.mesh.surface_get_material(0) as StandardMaterial3D
					if cmat:
						cmat.emission_enabled = true
						cmat.emission = Color(1, 1, 1) * _catcher_emission
			_apply_mul_probe()



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
			_apply_floor_lit_rig(map, floor_lit)
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
	if on:
		_build_catcher_rig(floor_lit)
	elif _catcher != null:
		_catcher.queue_free()
		_catcher = null

	# The omnis ARE the rig — every authored light casts in bake mode (the
	# wetlands lantern precedent: shadow_enabled + blur 1.0). Leaving bake
	# restores each sidecar's own state; M still flips everything live.
	# PSZ_WALK_SHADOWS=0 is the screenshot A/B control (bake + catcher, no
	# casters).
	var shadows_on := OS.get_environment("PSZ_WALK_SHADOWS") != "0"
	# PSZ_WALK_SHADOW_BIAS: the omni shadow bias. The engine default lets
	# the floor pixels between the player's feet leak lit (no contact
	# shadow — the c18324ba catcher hid this, sitting +0.04 closer to the
	# caster); lower values pull the contact shadow onto the scene floor
	# directly.
	var shadow_bias := OS.get_environment("PSZ_WALK_SHADOW_BIAS").to_float()
	for light in _authored_lights():
		light.shadow_enabled = shadows_on if on \
				else bool(_base_shadows.get(light.get_path(), light.shadow_enabled))
		if on:
			light.shadow_blur = 1.0
			if shadow_bias > 0.0:
				light.shadow_bias = shadow_bias
	_update_status()


## One SubViewport per placed light, its camera sitting AT the light aimed
## at the actor, seeing only the actor layer (ACTOR_LAYER — the player's
## meshes join it after spawn). The catcher shader samples these each frame.
func _build_projectors() -> void:
	_shadows_on = OS.get_environment("PSZ_WALK_SHADOWS") != "0"
	var lights := _authored_lights()
	for i in lights.size():
		var vp := SubViewport.new()
		vp.name = "ShadowVP_%d" % i
		vp.size = Vector2(256, 256)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cam := Camera3D.new()
		cam.cull_mask = ACTOR_LAYER
		cam.set_orthogonal(2.6, 0.05, 60.0)
		vp.add_child(cam)
		add_child(vp)
		_catcher_mat.set_shader_parameter("u_tex%d" % i, vp.get_texture())
		_projectors.append({"vp": vp, "cam": cam, "light": lights[i]})

## Per frame: aim every projector camera at the actor and feed the catcher
## shader each light's view/projection and weight (energy / distance², in
## range, above the actor). Lights out of range or below the actor's plane
## throw nothing — walk the hall and the shadows trade off light to light.
func _update_projectors() -> void:
	if _catcher_mat == null or _player == null:
		return
	var p := _player.global_position + Vector3(0, 0.8, 0)
	for i in _projectors.size():
		var pr := _projectors[i]
		var light := pr["light"] as OmniLight3D
		var cam := pr["cam"] as Camera3D
		var l := light.global_position
		var d := l.distance_to(p)
		cam.position = l
		# Dead-under a light the aim is ±Y: look_at's default up is
		# colinear and the transform FREEZES — aim along a perpendicular up.
		var dir := (p - l).normalized()
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.999 else Vector3(1, 0, 0)
		cam.look_at(p, up)
		cam.far = d + 3.0
		var w := 0.0
		if _shadows_on and d < light.omni_range and l.y > p.y:
			# 20× energy/d²: an e2 sconce reads a full shadow to ~6 units and
			# a fading one to its range edge; the e40s carry across the hall.
			w = clampf(20.0 * light.light_energy / maxf(d * d, 0.25), 0.0, 1.0) * SHADOW_MAX_ALPHA
		_catcher_mat.set_shader_parameter("u_view%d" % i, cam.global_transform)
		_catcher_mat.set_shader_parameter("u_proj%d" % i, cam.get_camera_projection())
		_catcher_mat.set_shader_parameter("u_w%d" % i, w)



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


## The one-shot bake capture (PSZ_WALK_BAKE_FLOOR): a temporary top-down
## ORTHO camera swapped into the MAIN WINDOW, one frame, read via the
## window texture — the one read path that forces a draw even when macOS
## throttles an occluded window (SubViewport captures measured boot-flaky
## black exactly when the window wasn't compositing; every SHOT read from
## the same shells worked). Hung just above the walk height with a short
## far plane so walls only print their base strip; player and HUD hidden —
## what lands in the texture is the pure floor bake, world-XZ aligned
## (rotation −90°: camera right = +X, so texture u/v map directly onto
## world x/z from the captured rect's minimum corner). The window's aspect
## widens the captured rect beyond the shell's X extent — harmless, the
## declared rect is what the shell shader maps.
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
	var vp := get_viewport()
	var aspect: float = float(vp.size.x) / maxf(float(vp.size.y), 1.0)
	var z_size := aabb.size.z + 2.0
	var x_size: float = z_size * aspect
	var origin := Vector2(
		aabb.position.x + aabb.size.x * 0.5 - x_size * 0.5,
		aabb.position.z - 1.0)
	var cam := Camera3D.new()
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.position = Vector3(
		origin.x + x_size * 0.5,
		MeshUtils.floor_top(floor_root) + 1.2,
		origin.y + z_size * 0.5)
	cam.set_orthogonal(z_size, 0.05, 2.5)
	add_child(cam)
	cam.current = true
	if _player != null:
		_player.visible = false
	var hud_hidden := false
	if _status:
		hud_hidden = _status.visible
		_status.visible = false
	var img: Image = null
	for attempt in 4:
		await get_tree().process_frame
		img = vp.get_texture().get_image()
		if _bake_has_content(img):
			break
		print("[CWalk] bake attempt %d came back black — retrying" % attempt)
		img = null
	cam.current = false
	cam.queue_free()
	if _player != null:
		_player.visible = true
	if _status and hud_hidden:
		_status.visible = true
	if img == null:
		push_error("[CWalk] floor bake never drew content — degrading to the flat floor")
		return null
	var dump_path := OS.get_environment("PSZ_WALK_BAKE_DUMP")
	if not dump_path.is_empty():
		img.save_png(dump_path)
	print("[CWalk] floor bake captured %dx%d over x[%.1f..%.1f] z[%.1f..%.1f]" % [
		img.get_width(), img.get_height(),
		origin.x, origin.x + x_size, origin.y, origin.y + z_size])
	return MeshUtils.make_baked_floor(floor_root, ImageTexture.create_from_image(img),
		origin, Vector2(x_size, z_size))


## Sampled-luminance gate for the bake capture: true when the image holds
## something other than black (a 12×12 grid of pixels, any channel > 0.03).
func _bake_has_content(img: Image) -> bool:
	for y in range(0, img.get_height(), maxi(1, img.get_height() / 12)):
		for x in range(0, img.get_width(), maxi(1, img.get_width() / 12)):
			var c := img.get_pixel(x, y)
			if c.r > 0.03 or c.g > 0.03 or c.b > 0.03:
				return true
	return false


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


## The emission base lift, applied live (- / =).
func _apply_catcher_emission() -> void:
	if _catcher == null:
		return
	var cmat := _catcher.mesh.surface_get_material(0) as StandardMaterial3D
	if cmat:
		cmat.emission_enabled = true
		cmat.emission = Color(1, 1, 1) * _catcher_emission


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
		"catcherEmission": _catcher_emission,
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
	if _ab_pending and _station_frame == 0:
		_ab_step()
		return
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
	# PSZ_WALK_AB=1: the in-boot shadow A/B — same station, shadows flipped
	# off, one settle, a second shot. Two-boot diffs drown in animation
	# noise; this isolates the shadow maps' contribution exactly.
	if OS.get_environment("PSZ_WALK_AB") == "1":
		for light in _authored_lights():
			light.shadow_enabled = false
		_station_frame = -25
		_ab_pending = true
		_ab_path = path.replace(".png", "_noshadow.png")
		return
	_station_idx += 1
	if _station_idx >= _stations.size():
		get_tree().quit()
		return
	_player.global_position = _stations[_station_idx]
	_station_frame = 0
	print("[CWalk] station %d/%d → %s" % [
		_station_idx + 1, _stations.size(), _stations[_station_idx]])


var _ab_pending := false
var _ab_path := ""


## The settle hook for the in-boot shadow A/B (PSZ_WALK_AB): once the
## off-state settles, take the second shot, arm shadows back, and advance
## to the next station (the settle counter restarts).
func _ab_step() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_ab_path)
	print("[CWalk] A/B shadow-off shot → %s" % _ab_path)
	for light in _authored_lights():
		light.shadow_enabled = true
	_ab_pending = false
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
	var base := "%s%s — ambient %.2f (, .)  pools %.2f× ([ ])  shadows %s (M)  bake (B)" % [
		_stage_id, " · DS bake" if _bake_mode else "",
		_env.ambient_light_energy, _pool_scale,
		"on" if n > 0 and _authored_lights()[0].shadow_enabled else "off"]
	if _catcher != null and _catcher.name == "ShadowCatcher":
		base += "  emis %.2f (- =)" % _catcher_emission
	return base

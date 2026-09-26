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
## Env:  PSZ_WALK_STAGE=s00e_sa2    boot stage (must have a city-lights sidecar)
##       PSZ_WALK_BAKE=0            boot OUT of the DS bake (the lit A/B look)
##       PSZ_WALK_SHADOWS=0          boot with the projector shadows off (diff control)
##       PSZ_WALK_SHOT=/tmp/o.png   screenshot + quit (smoke; else live keys)
## Keys: , / .  ambient ∓/± 0.05     [ / ]  omni pools ∓/± 0.25× (0.00 kills)
##       B       DS architecture A/B — stage bake unlit (MeshBasic: COLOR_0
##               modulates albedo, light-immune), the authored omnis
##               lighting the actors, and per-light PROJECTED shadows: a
##               shadow viewport per placed light renders the actor's
##               silhouette from the light's own position and the catcher
##               composites them onto the transparent floor — stand
##               between two lights and two shadows fall away from each
##       M       projector shadows toggle
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

## N's selection survives the scene reload that swaps the room.
static var _pending_stage := ""

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
}
"

## The render layer the projector cameras see: actor meshes only.
const ACTOR_LAYER := 8
## Shadow strength at the strongest — the max composite alpha.
const SHADOW_MAX_ALPHA := 0.55

var _stage_id := "s00e_sa2"
var _env: Environment
var _pool_scale := 1.0
var _base_energies: Dictionary = {}  # OmniLight3D path → authored energy
var _base_shadows: Dictionary = {}   # OmniLight3D path → authored shadow_enabled
var _bake_mode := false
var _player: Node3D
var _catcher: MeshInstance3D
var _catcher_mat: ShaderMaterial
var _projectors: Array[Dictionary] = []  # {vp, cam, light}
var _shadows_on := true
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
	# The player's meshes join the projector layer: every shadow viewport
	# camera sees exactly the actors, nothing of the stage.
	for node in MeshUtils.collect_mesh_instances(_player, []):
		(node as GeometryInstance3D).layers |= ACTOR_LAYER
	# Same floor the game guards: the mesh is authored low (−10.67) and the
	# default −10 fall-respawn would read the floor as a fall.
	lab_player.fall_respawn_y = -25.0
	_build_status_label()
	_readout()
	# The DS architecture is the DEFAULT look (the #656 objective: bake on the
	# stage, lights for the actors, catcher floor for the shadows). B still
	# A/Bs live; PSZ_WALK_BAKE=0 boots the pre-bake lit look instead.
	if OS.get_environment("PSZ_WALK_BAKE") != "0":
		_set_bake_mode(true)
	print("[CWalk] ready — , . ambient · [ ] pools · B bake+catcher · M shadows · P readout · N next · R reload · ESC quit")


func _process(_delta: float) -> void:
	_update_projectors()
	_shot.step(self, "CWalk")


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
			_shadows_on = not _shadows_on
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


## The DS architecture A/B (B) — "normal freaking shadows": N real
## per-light shadows over a transparent floor. The stage keeps its pure
## baked look (MeshUtils.make_unlit: UNSHADED, COLOR_0 as albedo). The
## authored omnis light the actors exactly as authored. The shadows are
## PROJECTIVE: every placed light gets a shadow viewport whose camera
## sits AT the light aimed at the actor (actors-only layer), rendering
## the actor's silhouette; the catcher is an UNSHADED quad field whose
## shader projects each silhouette onto the floor through the same
## camera matrices, weighted by energy/distance². No engine shadow path
## is involved — every one was measured or derived dead (the min-formula
## veil, the zero-sum fills; the full log lives in
## mesh_utils.make_shadow_catcher's doc) — so the floor is transparent
## BY CONSTRUCTION and each light throws its own shadow its own way:
## stand between two lights and two shadows fall away from each.
func _set_bake_mode(on: bool) -> void:
	_bake_mode = on
	var map := get_node_or_null("Map")
	if map:
		if on:
			MeshUtils.make_unlit(map, [])
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
		# enclosing shell; only the actors appear in the shadow viewports.
		# shadow maps.
		for node in MeshUtils.collect_mesh_instances(map, []):
			(node as MeshInstance3D).cast_shadow = \
					GeometryInstance3D.SHADOW_CASTING_SETTING_ON if not on \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if on and _catcher == null:
		var floor_root := get_node_or_null("FloorCollision")
		if floor_root:
			# up-facing only: the city floor GLB wraps the whole room, and its
			# walls sat exactly coplanar with the stage — the crazy z-fight.
			# The projector shader catcher: unlit, composited manually.
			var mesh := MeshUtils.collision_face_mesh(floor_root, 0.6)
			if mesh != null:
				_catcher_mat = ShaderMaterial.new()
				var sh := Shader.new()
				sh.code = PROJECTOR_SHADER
				_catcher_mat.shader = sh
				mesh.surface_set_material(0, _catcher_mat)
				_catcher = MeshInstance3D.new()
				_catcher.name = "ShadowProjector"
				_catcher.mesh = mesh
				_catcher.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_catcher.position.y = 0.04
				add_child(_catcher)
		_build_projectors()
	elif not on and _catcher != null:
		_catcher.queue_free()
		_catcher = null
		for pr in _projectors:
			(pr["vp"] as SubViewport).queue_free()
		_projectors.clear()
	# The authored omnis are the ACTOR rig — full mask, their sidecar shadow
	# states untouched; the catcher is unlit and cannot see them at all.
	for light in _authored_lights():
		light.shadow_enabled = bool(_base_shadows.get(light.get_path(), light.shadow_enabled))
		light.light_cull_mask = 0xFFFFFFFF
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
		cam.look_at(p)
		cam.far = d + 3.0
		var w := 0.0
		if _shadows_on and d < light.omni_range and l.y > p.y:
			w = clampf(8.0 * light.light_energy / maxf(d * d, 0.25), 0.0, 1.0) * SHADOW_MAX_ALPHA
		_catcher_mat.set_shader_parameter("u_view%d" % i, cam.global_transform)
		_catcher_mat.set_shader_parameter("u_proj%d" % i, cam.get_camera_projection())
		_catcher_mat.set_shader_parameter("u_w%d" % i, w)


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


func _build_status_label() -> void:
	_status = FieldLabScript.make_status_label(self)
	_update_status()


func _update_status() -> void:
	var n := _authored_lights().size()
	_status.text = "%s%s — ambient %.2f  pools %.2f× (%d)  shadows %s" % [
		_stage_id, " · DS bake" if _bake_mode else "",
		_env.ambient_light_energy, _pool_scale, n,
		"on" if _shadows_on else "off"]

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
##       PSZ_WALK_SHADOWS=0          boot with the shadow twin off (diff control)
##       PSZ_WALK_SHOT=/tmp/o.png   screenshot + quit (smoke; else live keys)
## Keys: , / .  ambient ∓/± 0.05     [ / ]  omni pools ∓/± 0.25× (0.00 kills)
##       B       DS architecture A/B — stage bake unlit (MeshBasic: COLOR_0
##               modulates albedo, light-immune), omnis lighting actors
##               alone, and the valley #648 catcher contract driven by a
##               SHADOW TWIN: one directional aimed from the dominant placed
##               light through the player over a shadowless glow — lit floor
##               clamps at x1 (transparent), the actor's silhouette drops to
##               the base, direction from the light you stand near
##       M       shadow twin toggle
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

## Render layer the catcher lives on: the omnis are masked off it (they
## light actors only — a pool on the floor is the stage being lit) and the
## glow + shadow twin are masked ONTO it (they exist for the catcher alone).
const CATCHER_LAYER := 2
## The catcher's lit clamp target: ambient + glow + twin ≥ this everywhere,
## so the MUL reads ×1 (transparent floor) at every lit pixel. The shadowed
## pixel loses the twin's TWIN_ENERGY — that drop IS the shadow depth.
const BASE_TARGET := 1.08
const TWIN_ENERGY := 0.55

var _stage_id := "s00e_sa2"
var _env: Environment
var _pool_scale := 1.0
var _base_energies: Dictionary = {}  # OmniLight3D path → authored energy
var _base_shadows: Dictionary = {}   # OmniLight3D path → authored shadow_enabled
var _bake_mode := false
var _player: Node3D
var _catcher: MeshInstance3D
var _glow: DirectionalLight3D
var _twin: DirectionalLight3D
var _twin_owner: OmniLight3D          # the placed light the twin currently serves
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
	_update_twin()
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
			if _twin:
				_twin.shadow_enabled = not _twin.shadow_enabled
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


## The DS architecture A/B (B) — the valley #648 contract, indoors, with a
## placed light standing in for the sun. The stage keeps its pure baked
## look (MeshUtils.make_unlit: UNSHADED, COLOR_0 as albedo — light cannot
## touch it). The catcher is the valley's own white MUL on the catcher-only
## render layer; exactly two lights may touch it: a shadowless GLOW (the
## uniform base — straight down, every pixel, no falloff: the piece an omni
## field can never provide) and the SHADOW TWIN (one directional whose
## direction comes from the dominant placed light). Lit pixels read
## ambient + glow + twin ≥ 1 → clamp ×1 → the floor is TRANSPARENT, the
## bake verbatim; the actor's silhouette blocks the twin and drops the
## pixel to the base — a real shadow-map shadow, ~TWIN_ENERGY deep, thrown
## away from the light you stand near. The omnis light the actors alone.
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
		# enclosing shell; only the actors' silhouettes reach the twin's
		# shadow map.
		for node in MeshUtils.collect_mesh_instances(map, []):
			(node as MeshInstance3D).cast_shadow = \
					GeometryInstance3D.SHADOW_CASTING_SETTING_ON if not on \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if on and _catcher == null:
		var floor_root := get_node_or_null("FloorCollision")
		if floor_root:
			# up-facing only: the city floor GLB wraps the whole room, and its
			# walls sat exactly coplanar with the stage — the crazy z-fight.
			_catcher = MeshUtils.make_shadow_catcher(floor_root, true)
			if _catcher:
				_catcher.layers = CATCHER_LAYER
				add_child(_catcher)
		# The uniform base: shadowless, straight down, catcher-only. Its
		# energy is recomputed every frame against the ambient keys so the
		# lit clamp target survives live tuning.
		_glow = DirectionalLight3D.new()
		_glow.name = "CatcherGlow"
		_glow.rotation_degrees = Vector3(-90, 0, 0)
		_glow.shadow_enabled = false
		_glow.light_cull_mask = CATCHER_LAYER
		add_child(_glow)
		# The shadow twin: casts the actors' silhouettes, rides the player
		# (the compatibility renderer anchors the directional shadow frustum
		# at the light node — the valley's place_light_inside_room lesson).
		# PSZ_WALK_SHADOWS=0 is the screenshot A/B control (bake, no caster).
		_twin = DirectionalLight3D.new()
		_twin.name = "ShadowTwin"
		_twin.shadow_enabled = OS.get_environment("PSZ_WALK_SHADOWS") != "0"
		_twin.directional_shadow_max_distance = 40.0
		_twin.light_energy = TWIN_ENERGY
		_twin.light_cull_mask = CATCHER_LAYER
		add_child(_twin)
	elif not on and _catcher != null:
		_catcher.queue_free()
		_catcher = null
		_glow.queue_free()
		_glow = null
		_twin.queue_free()
		_twin = null
		_twin_owner = null
	# The omnis: actors only. Culled off the catcher in bake (their direct
	# term on the catcher would pool — and one more time, the min/sum math
	# means any light that could hold the floor up also fills the shadows
	# in); shadows off, nothing they may light receives them. Leaving bake
	# restores each sidecar's own state and full mask.
	for light in _authored_lights():
		light.shadow_enabled = false if on \
				else bool(_base_shadows.get(light.get_path(), light.shadow_enabled))
		light.light_cull_mask = 0xFFFFFFFF & ~CATCHER_LAYER if on else 0xFFFFFFFF
	_update_status()


## Per frame: pick the placed light the twin serves (hard switch with
## hysteresis — the incumbent keeps its post until a challenger clearly
## out-scores it, so the shadow never oscillates while walking a seam),
## aim mostly DOWN tilted away from that light (a ceiling light's shadow:
## straight down under it, swinging out as you step away), anchor above
## the player, and keep the glow's energy compensating the ambient keys so
## the lit floor stays clamped at ×1.
func _update_twin() -> void:
	if _twin == null or _player == null:
		return
	var p := _player.global_position
	var owner_score := -1.0
	var challenger: OmniLight3D = null
	var challenger_score := 0.0
	for light in _authored_lights():
		var l := light.global_position
		if l.y - p.y < 2.0:
			continue  # at-eye or below-floor lights throw no sane shadow
		var d2 := p.distance_squared_to(l)
		if d2 > light.omni_range * light.omni_range:
			continue
		var score := light.light_energy / maxf(d2, 0.25)
		if light == _twin_owner:
			owner_score = score
		elif score > challenger_score:
			challenger_score = score
			challenger = light
	if _twin_owner == null or not is_instance_valid(_twin_owner) or owner_score < 0.0:
		_twin_owner = challenger
	elif challenger != null and challenger_score > owner_score * 1.6:
		_twin_owner = challenger
	var aim := Vector3.DOWN
	if _twin_owner != null:
		var horiz := Vector3(p.x - _twin_owner.global_position.x, 0.0,
				p.z - _twin_owner.global_position.z)
		if horiz.length() > 0.05:
			aim = (Vector3.DOWN + horiz.normalized() * clampf(horiz.length() / 12.0, 0.0, 0.6)).normalized()
	_twin.global_position = p + Vector3(0, 8.0, 0)
	_twin.look_at(_twin.global_position + aim)
	_glow.light_energy = maxf(0.1, BASE_TARGET - _env.ambient_light_energy - TWIN_ENERGY)


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
		"on" if _twin != null and _twin.shadow_enabled else "off"]

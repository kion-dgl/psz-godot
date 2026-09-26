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
##       PSZ_WALK_SHOT=/tmp/o.png   screenshot + quit (smoke; else live keys)
## Keys: , / .  ambient ∓/± 0.05     [ / ]  omni pools ∓/± 0.25× (0.00 kills)
##       B       DS architecture A/B — stage bake unlit (MeshBasic: COLOR_0
##               modulates albedo, light-immune) + the collision shell's
##               walk surfaces as a shadow-catcher floor (the valley #648
##               rig; walls filtered out — the city floor GLB wraps the room)
##               + every omni shadow-casting, so actors cast dynamic shadows
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


## The DS architecture A/B (B): the stage keeps its pure baked look —
## MeshUtils.make_unlit forces every surface UNSHADED with COLOR_0 as albedo
## (the MeshBasic contract; light cannot touch it) — while the collision
## shell becomes the shadow catcher (the valley #648 rig): a white
## multiply-blended receiver at walk height. The omnis then matter only to
## the actors and the catcher: pools and shadows composite onto the bake.
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
	if on and _catcher == null:
		var floor_root := get_node_or_null("FloorCollision")
		if floor_root:
			# up-facing only: the city floor GLB wraps the whole room, and its
			# walls sat exactly coplanar with the stage — the crazy z-fight.
			_catcher = MeshUtils.make_shadow_catcher(floor_root, true)
			if _catcher:
				add_child(_catcher)
	elif not on and _catcher != null:
		_catcher.queue_free()
		_catcher = null
	# The architecture's dynamic half: an actor shadow needs a caster — every
	# authored omni switches its shadows on with the bake (the lantern is the
	# only light that ships with them). Leaving bake restores each sidecar's
	# own state; M still flips everything live.
	for light in _authored_lights():
		light.shadow_enabled = true if on \
				else bool(_base_shadows.get(light.get_path(), light.shadow_enabled))
	_update_status()


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
		"on" if n > 0 and _authored_lights()[0].shadow_enabled else "off"]

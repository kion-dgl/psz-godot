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
##       PSZ_WALK_SHADOWS=0          boot with the twin shadows off (diff control)
##       PSZ_WALK_SHOT=/tmp/o.png   screenshot + quit (smoke; else live keys)
## Keys: , / .  ambient ∓/± 0.05     [ / ]  omni pools ∓/± 0.25× (0.00 kills)
##       B       DS architecture A/B — stage bake unlit (MeshBasic: COLOR_0
##               modulates albedo, light-immune), the authored omnis
##               lighting actors alone, and the catcher driven by TWIN
##               OMNIS: private copies of every placed light (same
##               position/range/color, boosted to clamp the floor
##               transparent) casting real per-light shadows — stand
##               between two lights and two shadows fall away from each
##       M       twin shadows toggle
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

## Render layer the catcher lives on: the authored omnis are masked OFF it
## (they light actors only) and every light's TWIN is masked ONTO it (the
## twins exist for the catcher alone).
const CATCHER_LAYER := 2
## Twin energies: the gles3 shadow_to_opacity MIN reads a pixel's alpha as
## min over lights of (1 - attenuated light) — the veil. A twin clamps its
## zone transparent when its attenuated light ≥ 1 everywhere it reaches;
## with a(d) = (1 - (d/r)^4)^2 / d that takes ~36 energy at 12 of 15 range.
## max(authored × TWIN_BOOST, TWIN_COVER_MIN) keeps the strong lights
## dominant in proportion while every twin clears its own floor.
const TWIN_BOOST := 4.0
const TWIN_COVER_MIN := 36.0

var _stage_id := "s00e_sa2"
var _env: Environment
var _pool_scale := 1.0
var _base_energies: Dictionary = {}  # OmniLight3D path → authored energy
var _base_shadows: Dictionary = {}   # OmniLight3D path → authored shadow_enabled
var _bake_mode := false
var _player: Node3D
var _catcher: MeshInstance3D
var _twins: Array[OmniLight3D] = []  # catcher-private copies of the rig
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
			var twin_shadows := not _twins[0].shadow_enabled if not _twins.is_empty() else false
			for twin in _twins:
				twin.shadow_enabled = twin_shadows
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


## The DS architecture A/B (B) — the black-floor rig that read RIGHT
## (kion, walking it: "two shadows coming from each direction"), with its
## one defect fixed by construction. The stage keeps its pure baked look
## (MeshUtils.make_unlit: UNSHADED, COLOR_0 as albedo — light cannot touch
## it). The catcher keeps the shadow_to_opacity shader — N per-light
## shadow maps, every placed light throwing its own real shadow — but it
## is driven by TWIN OMNIS on its private render layer: same position/
## range/color as each placed light, energy boosted so the attenuated
## light ≥ 1 across each twin's reach. The gles3 MIN (alpha = min over
## lights of 1 − attenuated light, capped by the ambient share) then reads
## every lit pixel TRANSPARENT — the veil was exactly the strongest
## light's shortfall, and the twins no longer fall short — while a
## blocked twin drops its pixel to min(1 − second light, ambient): a real
## per-light shadow, as deep as the ambient share allows. The authored
## omnis themselves are culled off the catcher and keep lighting the
## actors exactly as authored.
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
		# enclosing shell; only the actors' silhouettes reach the twins'
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
			# shadow_only: the shadow_to_opacity shader — per-light shadow
			# maps, driven by the twins below.
			_catcher = MeshUtils.make_shadow_catcher(floor_root, true, true)
			if _catcher:
				_catcher.layers = CATCHER_LAYER
				add_child(_catcher)
		_build_twins()
	elif not on and _catcher != null:
		_catcher.queue_free()
		_catcher = null
		for twin in _twins:
			twin.queue_free()
		_twins.clear()
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


## One catcher-private twin per placed light: same position, color, range
## and attenuation — so every shadow falls exactly where its light throws
## it — with energy max(authored × TWIN_BOOST, TWIN_COVER_MIN) so the
## attenuated light clears 1 across the twin's reach (the gles3 MIN then
## reads every lit catcher pixel transparent) and the strong lights stay
## dominant in proportion. Shadow-casting; PSZ_WALK_SHADOWS=0 boots them
## shadowless for screenshot diffs. Static — no per-frame work.
func _build_twins() -> void:
	var shadows_on := OS.get_environment("PSZ_WALK_SHADOWS") != "0"
	for light in _authored_lights():
		var twin := OmniLight3D.new()
		twin.name = "CatcherTwin_" + String(light.name).replace(" ", "")
		twin.position = light.position
		twin.light_color = light.light_color
		twin.light_energy = maxf(light.light_energy * TWIN_BOOST, TWIN_COVER_MIN)
		twin.omni_range = light.omni_range
		twin.omni_attenuation = light.omni_attenuation
		twin.shadow_enabled = shadows_on
		twin.light_cull_mask = CATCHER_LAYER
		add_child(twin)
		_twins.append(twin)


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
		"on" if not _twins.is_empty() and _twins[0].shadow_enabled else "off"]

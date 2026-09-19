extends Node3D
## Snowfield B cave preview (#657) — screenshot lab for the s03b slot rig.
##
## Boots a B-cave stage through the production material pipeline (SmoothNormals
## → texture-fix pass → white-strategy mix) under the real FieldSlotTable row
## (area derived from the stage prefix — any area's stages preview here),
## spawns the authored placed effects from the unified config, and writes
## a screenshot after the scene settles. Env knobs so a headless-friendly loop
## can iterate the rig without typing into the window:
##
##   PSZ_PREVIEW_STAGE=s03b_xb2   stage id (snowfield_b/<id>)
##   PSZ_PREVIEW_DIR=snowfield_b  area folder holding the stage (default)
##   PSZ_PREVIEW_HOUR=5.5         override the slot hour
##   PSZ_PREVIEW_AMBIENT=0.6      override ambient energy
##   PSZ_PREVIEW_MOON=0.12        override moon energy
##   PSZ_PREVIEW_SUN=1.2          override sun energy (day rigs, #648)
##   PSZ_PREVIEW_BAKE=0.25        override bake mix
##   PSZ_PREVIEW_MOON_SHADOWS=1   moonlight casts real shadows (experiment:
##                                white COLOR_0 + moon shadows = dynamic bake)
##   PSZ_PREVIEW_SUN_SHADOWS=1    sunlight casts real shadows (day rigs)
##   PSZ_PREVIEW_SHOT=/tmp/o.png  write screenshot + quit (else live keys:
##                                [/] moon, ,/. ambient, R reload)

const STAGE_GLB_FMT := "res://assets/stages/%s/%s/lndmd/%s_m.glb"
const UNIFIED_CONFIG := "res://data/stage_configs/unified-stage-configs.json"
const TEXTURE_FIX_SHADER := preload("res://scripts/3d/field/texture_fix_shader.gdshader")
const FieldSlotTableScript := preload("res://scripts/3d/field/field_slot_table.gd")
const FieldLabScript := preload("res://scripts/tools/field_lab.gd")

var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _dir_light: DirectionalLight3D
var _moonlight: DirectionalLight3D
var _map_root: Node3D
var _slot: Dictionary
var _stage_id: String
var _shot_path: String
var _shot_frame := 0


func _ready() -> void:
	_stage_id = OS.get_environment("PSZ_PREVIEW_STAGE")
	if _stage_id.is_empty():
		_stage_id = "s03b_xb2"
	_shot_path = OS.get_environment("PSZ_PREVIEW_SHOT")
	_build_environment()
	_load_stage()
	_spawn_authored_effects()
	_place_camera()
	print("[BPreview] %s — hour %.2f ambient %.2f sun %.2f moon %.2f mix %.2f" % [
		_stage_id, TimeManager.current_hour, _env.ambient_light_energy,
		_dir_light.light_energy, _moonlight.light_energy,
		float(_slot.get("bake_mix", 0.0))])


func _build_environment() -> void:
	# The valley_field scene's setup (#646), shared with the other labs:
	# Filmic + white 6, COLOR ambient, sun + moon directionals.
	var built := FieldLabScript.build_environment(self)
	_env = built["env"]
	_sky_mat = built["sky_mat"]
	_dir_light = built["dir_light"]
	_dir_light.shadow_enabled = false
	_moonlight = built["moonlight"]

	# The production slot apply — the real row the field controller resolves
	# for the stage's area (prefix-derived), with env overrides for the
	# tuning loop.
	var area_id := str(SessionManager.STAGE_PREFIX_TO_AREA.get(
		_stage_id.substr(0, 3), ""))
	_slot = FieldSlotTableScript.slot_for(area_id, _stage_id)
	if not OS.get_environment("PSZ_PREVIEW_HOUR").is_empty():
		_slot["hour"] = float(OS.get_environment("PSZ_PREVIEW_HOUR"))
	if not OS.get_environment("PSZ_PREVIEW_MOON").is_empty():
		_slot["moon_energy"] = float(OS.get_environment("PSZ_PREVIEW_MOON"))
	if not OS.get_environment("PSZ_PREVIEW_SUN").is_empty():
		_slot["sun_energy"] = float(OS.get_environment("PSZ_PREVIEW_SUN"))
	if not OS.get_environment("PSZ_PREVIEW_BAKE").is_empty():
		_slot["bake_mix"] = float(OS.get_environment("PSZ_PREVIEW_BAKE"))
	FieldLabScript.apply_slot(_slot, _env, _sky_mat, _dir_light, _moonlight)
	if not OS.get_environment("PSZ_PREVIEW_AMBIENT").is_empty():
		_env.ambient_light_energy = float(OS.get_environment("PSZ_PREVIEW_AMBIENT"))
	if OS.get_environment("PSZ_PREVIEW_MOON_SHADOWS") == "1":
		_moonlight.shadow_enabled = true
	if OS.get_environment("PSZ_PREVIEW_SUN_SHADOWS") == "1":
		_dir_light.shadow_enabled = true
		_dir_light.shadow_blur = 1.0


func _load_stage() -> void:
	var dir: String = OS.get_environment("PSZ_PREVIEW_DIR")
	if dir.is_empty():
		dir = "snowfield_b"
	var packed := load(STAGE_GLB_FMT % [dir, _stage_id, _stage_id]) as PackedScene
	if not packed:
		push_error("[BPreview] no stage GLB for %s" % _stage_id)
		return
	_map_root = packed.instantiate() as Node3D
	_map_root.name = "Map"
	add_child(_map_root)
	SmoothNormals.ensure(_map_root, 2)
	MeshUtils.apply_mirror_wrap_fixes(_map_root, MeshUtils.load_texture_fixes(), TEXTURE_FIX_SHADER)
	if _slot.has("bake_mix"):
		SmoothNormals.neutralize_vertex_colors(_map_root, float(_slot["bake_mix"]))
		SmoothNormals.make_lit(_map_root)


## The authored placed effects for this stage — plain `light` entries become
## omnis exactly as WeatherController builds them (inverse-square 2.0), plus
## the glow material pass.
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
	var count := 0
	for effect in cfg.get("effects", []):
		if str(effect.get("category", "")) != "placed" \
				or str(effect.get("type", "")) != "light":
			continue
		var pos_arr: Array = effect.get("position", [0, 0, 0])
		var color_arr: Array = effect.get("color", [1, 1, 1])
		var light := OmniLight3D.new()
		light.name = "AnchorLight_%d" % count
		light.light_color = Color(float(color_arr[0]), float(color_arr[1]), float(color_arr[2]))
		light.light_energy = float(effect.get("intensity", 1.0))
		light.omni_range = float(effect.get("radius", 6.0))
		light.omni_attenuation = 2.0
		light.shadow_enabled = false
		light.position = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		_map_root.add_child(light)
		count += 1
	if count:
		print("[BPreview] %d authored anchor lights" % count)
	var passes: Dictionary = {}
	for g in cfg.get("glowMaterials", []):
		passes[str(g.get("material", ""))] = g
	var touched := MeshUtils.apply_glow_materials(_map_root, passes)
	if touched:
		print("[BPreview] glow pass on %d surfaces" % touched)


## Static 3/4 room view — these are ~70-unit rooms with the entrance to the
## south, so a camera over the south edge looking slightly past center reads
## the whole cave floor and one wall.
func _place_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "PreviewCamera"
	add_child(cam)
	cam.global_position = Vector3(0, 16, 34)
	cam.look_at(Vector3(0, 0.5, -4), Vector3.UP)


func _process(_delta: float) -> void:
	if _shot_path.is_empty():
		return
	_shot_frame += 1
	if _shot_frame < 30:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_path)
	print("[BPreview] screenshot → %s" % _shot_path)
	get_tree().quit()

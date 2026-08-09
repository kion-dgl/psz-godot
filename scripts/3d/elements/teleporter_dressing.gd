extends Node3D
class_name TeleporterDressing
## City warp-pad dressing — the special_c3 object set (compass plates + the
## warp ring) arranged around the counter area's warp pad.
##
## The layout is authored in the web mock (#/teleporter-mock) and committed as
## data/city_teleporter.json; this node makes the runtime match it. Piece
## positions are offsets from the layout's `anchor`, applied after re-pivoting
## each GLB to its bounding-box bottom-center — the GLBs keep stage-baked node
## offsets, so without the re-pivot the meshes land away from where the mock
## shows them.
##
## Purely decorative: no interaction, no collision (WarpPad handles the warp).
## Every surface gets uv_dressing.gdshader — the source materials are unlit
## with mirrored texture wrap, which BaseMaterial3D can't express, and the
## glow pieces UV-scroll (TIME-driven, no per-frame script).

const LAYOUT_PATH := "res://data/city_teleporter.json"
const OBJECTS_DIR := "res://assets/objects/"
const UV_SHADER := preload("res://scripts/3d/shaders/uv_dressing.gdshader")
# Keep in sync with uv_dressing.gdshader's wrap_u/wrap_v encoding.
const WRAP := {"mirror": 0, "repeat": 1, "clamp": 2}


func _ready() -> void:
	build(_load_layout())


## Build the dressing from a parsed layout dict. Split from _ready so the
## test_runner can drive it (and the pivot/material helpers) directly.
func build(layout: Dictionary) -> void:
	if layout.is_empty():
		return
	var anchor: Array = layout.get("anchor", [0.0, 0.0, 0.0])
	position = Vector3(anchor[0], anchor[1], anchor[2])
	var set_id: String = layout.get("set", "")
	var pieces: Dictionary = layout.get("pieces", {})
	for piece_name in pieces:
		# visible:false = authored-but-parked piece; skip the load entirely.
		if not pieces[piece_name].get("visible", true):
			continue
		var packed := load(OBJECTS_DIR + set_id + "/" + piece_name + ".glb") as PackedScene
		if not packed:
			push_warning("TeleporterDressing: missing model %s/%s.glb" % [set_id, piece_name])
			continue
		add_child(_build_piece(piece_name, packed.instantiate() as Node3D, pieces[piece_name]))


func _load_layout() -> Dictionary:
	var fa := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if not fa:
		push_warning("TeleporterDressing: missing " + LAYOUT_PATH)
		return {}
	var json := JSON.new()
	if json.parse(fa.get_as_text()) != OK or not (json.data is Dictionary):
		push_warning("TeleporterDressing: bad JSON in " + LAYOUT_PATH)
		return {}
	return json.data


## Wrap a model in a pivot at the model's bbox bottom-center and apply the
## piece config (pos/ry/s offsets from the anchor, uv + scroll on materials).
func _build_piece(piece_name: String, model: Node3D, cfg: Dictionary) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = piece_name
	var aabb := _combined_aabb(model)
	model.position -= Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	pivot.add_child(model)
	var pos: Array = cfg.get("pos", [0.0, 0.0, 0.0])
	pivot.position = Vector3(pos[0], pos[1], pos[2])
	pivot.rotation.y = float(cfg.get("ry", 0.0))
	pivot.scale = Vector3.ONE * float(cfg.get("s", 1.0))
	_apply_dress_materials(model, cfg)
	return pivot


## Merged AABB of every MeshInstance3D under root, in root's parent space
## (i.e. including root's own transform) — the space the pivot offset applies in.
func _combined_aabb(root: Node3D) -> AABB:
	return MeshBounds.combined(root, true)


## Dress a model that is NOT spawned by this node, using one piece's config
## from data/city_teleporter.json.
##
## The city Warp Teleporter renders o0s_warpcn itself (WarpPad), so it never
## passes through build() — but it still needs the measured uv/scroll the
## storybook read off that model, or the glow sheet draws unscrolled at the
## wrong offset. Sharing this keeps one copy of the numbers.
static func dress_model_from_layout(model: Node3D, piece_name: String) -> bool:
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if not f:
		push_warning("TeleporterDressing: missing " + LAYOUT_PATH)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("TeleporterDressing: bad JSON in " + LAYOUT_PATH)
		return false
	var pieces: Dictionary = (parsed as Dictionary).get("pieces", {})
	if not pieces.has(piece_name):
		push_warning("TeleporterDressing: no piece '%s' in layout" % piece_name)
		return false
	_apply_dress_materials(model, pieces[piece_name])
	return true


## Swap every textured surface to uv_dressing.gdshader, carrying over the
## imported material's texture/color/scissor and applying the piece's uv +
## scroll config.
static func _apply_dress_materials(model: Node3D, cfg: Dictionary) -> void:
	_dress_recursive(model, cfg)


## Debug palette, indexed by surface. Only used when PSZ_DRESSING_DEBUG_TINT=1.
const DEBUG_TINTS: Array[Color] = [
	Color(1.0, 0.3, 0.3),  # surface 0 — red
	Color(0.3, 1.0, 0.3),  # surface 1 — green
	Color(0.4, 0.6, 1.0),  # surface 2 — blue
	Color(1.0, 1.0, 0.3),  # surface 3 — yellow
]


static func _dress_recursive(node: Node, cfg: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		var debug_mode := OS.get_environment("PSZ_DRESSING_DEBUG_TINT")
		var debug_tint := debug_mode != ""
		var debug_y := debug_mode == "y"
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture:
				var dressed := _make_dress_material(mat as StandardMaterial3D, cfg)
				if debug_y:
					dressed.set_shader_parameter("debug_y_tint", true)
					print("[dressing-debug] %s surface %d: Y-banded (yellow<-0.375, cyan<0.15, magenta>=0.15) tex=%s" % [
						mesh_inst.name, i, _albedo_name(mat as StandardMaterial3D)])
				elif debug_tint:
					dressed.set_shader_parameter("debug_tint", DEBUG_TINTS[i % DEBUG_TINTS.size()])
					print("[dressing-debug] %s surface %d tinted %s (tex=%s)" % [
						mesh_inst.name, i, DEBUG_TINTS[i % DEBUG_TINTS.size()],
						_albedo_name(mat as StandardMaterial3D)])
				mesh_inst.set_surface_override_material(i, dressed)
	for child in node.get_children():
		_dress_recursive(child, cfg)


## Resolve the uv/scroll config for one texture.
##
## A piece may carry a `textures` map keyed by texture filename whose entries
## override the piece-level `uv` / `scroll`. That indirection exists because
## the pieces genuinely need it: o0s_warpcn draws its glow sheet at offset
## (-2.68, 5.31) repeat 1x1 with a -0.5 u scroll over a base plate at offset
## (0, 1) repeat 2x2 and no scroll. A single per-piece config cannot express
## two surfaces that disagree, which is what the storybook's texture inspector
## measured them doing.
##
## Merge is per-key, not whole-dict: a texture entry that sets only `scroll`
## still inherits the piece's `uv`, so shared placement stays written once.
static func _texture_cfg(cfg: Dictionary, texture_name: String) -> Dictionary:
	var overrides: Dictionary = cfg.get("textures", {})
	if texture_name.is_empty() or not overrides.has(texture_name):
		return cfg
	var per_tex: Dictionary = overrides[texture_name]
	var merged := cfg.duplicate()
	for key in ["uv", "scroll"]:
		if per_tex.has(key):
			merged[key] = per_tex[key]
	return merged


## Filename (no directory, no import suffix) of a material's albedo texture,
## for matching against a piece's `textures` map. Empty when the texture has
## no resource path — synthetic textures in tests, for instance.
static func _albedo_name(src: StandardMaterial3D) -> String:
	if not src.albedo_texture:
		return ""
	return String(src.albedo_texture.resource_path).get_file()


## Build the ShaderMaterial for one surface from the imported material + the
## piece's layout config. Pure (no tree access) so the test_runner can cover
## the cfg → uniform mapping directly.
static func _make_dress_material(src: StandardMaterial3D, piece_cfg: Dictionary) -> ShaderMaterial:
	var cfg := _texture_cfg(piece_cfg, _albedo_name(src))
	var smat := ShaderMaterial.new()
	smat.shader = UV_SHADER
	smat.set_shader_parameter("albedo_tex", src.albedo_texture)
	smat.set_shader_parameter("albedo_color", src.albedo_color)
	if src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		smat.set_shader_parameter("alpha_scissor", src.alpha_scissor_threshold)
	# Carry the source's sidedness. These meshes mix the two on one model, and
	# the shader is compile-time double-sided, so a CULL_BACK surface has to
	# discard its back faces or it draws through the piece.
	smat.set_shader_parameter("cull_back", src.cull_mode == BaseMaterial3D.CULL_BACK)
	# Optional floor for the piece's geometry — see min_y in the shader.
	if cfg.has("min_y"):
		smat.set_shader_parameter("min_y", float(cfg["min_y"]))
	var uv: Dictionary = cfg.get("uv", {})
	var wrap_modes: Array = uv.get("wrap", ["mirror", "mirror"])
	smat.set_shader_parameter("wrap_u", WRAP.get(wrap_modes[0], 0))
	smat.set_shader_parameter("wrap_v", WRAP.get(wrap_modes[1], 0))
	var repeat: Array = uv.get("repeat", [1.0, 1.0])
	smat.set_shader_parameter("uv_scale", Vector2(repeat[0], repeat[1]))
	var offset: Array = uv.get("offset", [0.0, 0.0])
	smat.set_shader_parameter("uv_offset", Vector2(offset[0], offset[1]))
	smat.set_shader_parameter("uv_rot", float(uv.get("rot", 0.0)))
	var scroll: Dictionary = cfg.get("scroll", {})
	smat.set_shader_parameter(
		"scroll_speed",
		Vector2(float(scroll.get("u", 0.0)), float(scroll.get("v", 0.0)))
	)
	return smat

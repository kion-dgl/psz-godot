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
## (i.e. including root's own transform), computed without entering the tree.
func _combined_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [[root as Node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node = entry[0]
		var xform: Transform3D = entry[1]
		if node is Node3D:
			xform = xform * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			var ab: AABB = xform * (node as MeshInstance3D).mesh.get_aabb()
			result = ab if first else result.merge(ab)
			first = false
		for child in node.get_children():
			stack.push_back([child, xform])
	return result


## Swap every textured surface to uv_dressing.gdshader, carrying over the
## imported material's texture/color/scissor and applying the piece's uv +
## scroll config. The whole piece shares one config — same as the web mock.
func _apply_dress_materials(model: Node3D, cfg: Dictionary) -> void:
	_dress_recursive(model, cfg)


func _dress_recursive(node: Node, cfg: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture:
				mesh_inst.set_surface_override_material(i, _make_dress_material(mat as StandardMaterial3D, cfg))
	for child in node.get_children():
		_dress_recursive(child, cfg)


## Build the ShaderMaterial for one surface from the imported material + the
## piece's layout config. Pure (no tree access) so the test_runner can cover
## the cfg → uniform mapping directly.
func _make_dress_material(src: StandardMaterial3D, cfg: Dictionary) -> ShaderMaterial:
	var smat := ShaderMaterial.new()
	smat.shader = UV_SHADER
	smat.set_shader_parameter("albedo_tex", src.albedo_texture)
	smat.set_shader_parameter("albedo_color", src.albedo_color)
	if src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		smat.set_shader_parameter("alpha_scissor", src.alpha_scissor_threshold)
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

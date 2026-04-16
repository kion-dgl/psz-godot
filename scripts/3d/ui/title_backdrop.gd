extends Node3D
## Title-screen 3D backdrop.
## Builds the composition from assets/title/title-config.json and the baked
## PNGs produced by the web prototype (Export bundle button at /title-screen).
## Mirrors the three.js scene: moon + halo, horizon plane, rocky ground with
## beam-spot shader, nebulae, stars, and the GLB scene instantiated three
## times with per-group offsets/scales so subsets can transform independently.

const CONFIG_PATH := "res://assets/title/title-config.json"
const ASSET_BASE := "res://assets/title/"
const GLB_PATH := "res://assets/title/scene.glb"
const GROUND_SHADER := preload("res://scripts/3d/shaders/title_ground.gdshader")

# Nodes and materials that need per-frame updates.
var _scroll_targets: Array[Dictionary] = []  # {mat: StandardMaterial3D, speed: Vector2}


func _ready() -> void:
	var config := _load_config()
	if config.is_empty():
		push_error("title_backdrop: failed to load %s" % CONFIG_PATH)
		return
	_build_environment(config)
	_build_camera(config)
	_build_moon(config)
	_build_halo(config)
	_build_horizon(config)
	_build_ground(config)
	_build_nebulae(config)
	_build_stars(config)
	_build_glb(config)


func _process(delta: float) -> void:
	for t in _scroll_targets:
		var mat: StandardMaterial3D = t["mat"]
		var s: Vector2 = t["speed"]
		var off := mat.uv1_offset
		off.x = fposmod(off.x + s.x * delta, 1.0)
		off.y = fposmod(off.y + s.y * delta, 1.0)
		mat.uv1_offset = off


# --- helpers -----------------------------------------------------------------

func _load_config() -> Dictionary:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _vec3(arr: Variant) -> Vector3:
	return Vector3(arr[0], arr[1], arr[2])


func _color(hex: String) -> Color:
	return Color(hex)


func _load_tex(name: String) -> Texture2D:
	return load(ASSET_BASE + name) as Texture2D


# --- builders ----------------------------------------------------------------

func _build_environment(config: Dictionary) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = _color(config["ambient"]["color"])
	e.ambient_light_energy = config["ambient"]["intensity"]
	env.environment = e
	add_child(env)


func _build_camera(config: Dictionary) -> void:
	var cfg: Dictionary = config["camera"]
	var cam := Camera3D.new()
	cam.position = Vector3(cfg["x"], cfg["y"], cfg["z"])
	cam.fov = cfg["fov"]
	cam.near = 0.1
	cam.far = 2000.0
	cam.current = true
	add_child(cam)
	# look_at requires the node to be in the tree.
	cam.look_at(_vec3(cfg["lookAt"]), Vector3.UP)


func _build_moon(config: Dictionary) -> void:
	var cfg: Dictionary = config["moon"]
	var sphere := SphereMesh.new()
	sphere.radius = cfg["radius"]
	sphere.height = float(cfg["radius"]) * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _load_tex(cfg["material"]["map"])
	mat.emission_enabled = true
	mat.emission = _color(cfg["material"]["emissive"])
	mat.emission_energy_multiplier = 1.0
	mat.roughness = 1.0
	mat.metallic = 0.0

	var mi := MeshInstance3D.new()
	mi.name = "Moon"
	mi.mesh = sphere
	mi.material_override = mat
	mi.position = _vec3(cfg["position"])
	add_child(mi)

	for L in cfg["lights"]:
		var light := DirectionalLight3D.new()
		light.light_color = _color(L["color"])
		light.light_energy = L["intensity"]
		light.position = _vec3(L["fromPos"])
		add_child(light)
		light.look_at(_vec3(L["targetPos"]), Vector3.UP)


func _build_halo(config: Dictionary) -> void:
	var cfg: Dictionary = config["halo"]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _load_tex(cfg["texture"])
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_receive_shadows = true

	var quad := QuadMesh.new()
	var size: float = cfg["scale"]
	quad.size = Vector2(size, size)

	var mi := MeshInstance3D.new()
	mi.name = "MoonHalo"
	mi.mesh = quad
	mi.material_override = mat
	mi.position = _vec3(cfg["position"])
	# Render before (behind) the moon.
	mat.render_priority = -16
	add_child(mi)


func _build_horizon(config: Dictionary) -> void:
	var cfg: Dictionary = config["horizon"]
	var size: Array = cfg["planeSize"]
	var quad := QuadMesh.new()
	quad.size = Vector2(size[0], size[1])

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _load_tex(cfg["texture"])
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = cfg["renderOrder"]

	var mi := MeshInstance3D.new()
	mi.name = "Horizon"
	mi.mesh = quad
	mi.material_override = mat
	mi.position = _vec3(cfg["position"])
	add_child(mi)


func _build_ground(config: Dictionary) -> void:
	var cfg: Dictionary = config["ground"]
	var size: Array = cfg["planeSize"]
	var plane := PlaneMesh.new()
	plane.size = Vector2(size[0], size[1])

	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("rock_tex", _load_tex(cfg["texture"]))
	mat.set_shader_parameter("tiles", float(cfg["tiles"]))
	mat.set_shader_parameter("ambient_amount", float(cfg["ambient"]))
	var key: Dictionary = cfg["keyLight"]
	mat.set_shader_parameter("key_color", _color(key["color"]))
	mat.set_shader_parameter("key_intensity", float(key["intensity"]))
	mat.set_shader_parameter("key_dir", _vec3(key["dir"]))
	var beam: Dictionary = cfg["beamLight"]
	mat.set_shader_parameter("beam_pos", _vec3(beam["pos"]))
	mat.set_shader_parameter("beam_color", _color(beam["color"]))
	mat.set_shader_parameter("beam_intensity", float(beam["intensity"]))
	mat.set_shader_parameter("beam_radius", float(beam["radius"]))
	var fog: Dictionary = cfg["fog"]
	mat.set_shader_parameter("fog_near", float(fog["near"]))
	mat.set_shader_parameter("fog_far", float(fog["far"]))
	mat.set_shader_parameter("fog_color", _color(fog["color"]))
	mat.render_priority = -5

	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = _vec3(cfg["position"])
	# PlaneMesh is already XZ (flat), no rotation needed.
	add_child(mi)


func _build_nebulae(config: Dictionary) -> void:
	var tex := _load_tex("nebula.png")
	var parent := Node3D.new()
	parent.name = "Nebulae"
	add_child(parent)
	for n in config["nebulae"]:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.albedo_color = _color(n["color"]) * float(n["opacity"]) * 2.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.disable_receive_shadows = true
		mat.render_priority = -25

		var quad := QuadMesh.new()
		var s: float = n["size"]
		quad.size = Vector2(s, s)

		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.position = _vec3(n["pos"])
		parent.add_child(mi)


func _build_stars(config: Dictionary) -> void:
	# Simple starfield: MultiMeshInstance3D of tiny white quads, billboarded.
	# Sparkle/color variation is punted for a later pass.
	var cfg: Dictionary = config["stars"]
	var env: Dictionary = cfg["envelope"]
	var total: int = int(cfg["staticCount"]) + int(cfg["sparkleCount"])
	var palette_strings: Array = cfg["palette"]
	var palette: Array[Color] = []
	for p in palette_strings:
		palette.append(_color(p))

	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	star_mat.vertex_color_use_as_albedo = true
	star_mat.disable_receive_shadows = true
	star_mat.render_priority = -20

	var star_mesh := QuadMesh.new()
	star_mesh.size = Vector2(0.6, 0.6)
	star_mesh.material = star_mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = star_mesh
	mm.instance_count = total

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var x_range: float = env["x"]
	var y_lo: float = env["yLo"]
	var y_hi: float = env["yHi"]
	var z_lo: float = env["zMin"]
	var z_hi: float = env["zMax"]

	for i in range(total):
		var pos := Vector3(
			rng.randf_range(-x_range * 0.5, x_range * 0.5),
			rng.randf_range(y_lo, y_hi),
			rng.randf_range(z_lo, z_hi),
		)
		var scale := rng.randf_range(0.6, 2.0)
		var xf := Transform3D(Basis().scaled(Vector3.ONE * scale), pos)
		mm.set_instance_transform(i, xf)
		var c: Color = palette[rng.randi() % palette.size()]
		mm.set_instance_color(i, c)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Stars"
	mmi.multimesh = mm
	add_child(mmi)


func _build_glb(config: Dictionary) -> void:
	var glb_cfg: Dictionary = config["glb"]
	var groups: Array = glb_cfg["groups"]
	var scrolls: Dictionary = glb_cfg["defaultScrollPerNode"]

	# Collect every name claimed by a group so the default instance can hide them.
	var claimed := {}
	for g in groups:
		for n in g["names"]:
			claimed[n] = true

	# Default instance: everything except claimed meshes.
	var root_default := _instantiate_glb()
	if root_default == null:
		return
	add_child(root_default)
	_apply_visibility(root_default, claimed, false)  # hide claimed
	_apply_scrolls(root_default, scrolls, claimed, false)

	# One instance per group.
	for g in groups:
		var root := _instantiate_glb()
		if root == null:
			continue
		add_child(root)
		var keep := {}
		for n in g["names"]:
			keep[n] = true
		_apply_visibility(root, keep, true)  # hide non-kept
		if g.has("offset"):
			var off: Array = g["offset"]
			root.position = Vector3(off[0], off[1], off[2])
		if g.has("scale"):
			var s: float = g["scale"]
			root.scale = Vector3(s, s, s)
		if g.has("renderOrder"):
			_apply_render_priority(root, keep, int(g["renderOrder"]))
		_apply_scrolls(root, scrolls, keep, true)


func _instantiate_glb() -> Node3D:
	var packed := load(GLB_PATH) as PackedScene
	if packed == null:
		push_error("title_backdrop: could not load %s (is it imported?)" % GLB_PATH)
		return null
	return packed.instantiate() as Node3D


# Visibility filter. `hide_non_match = true` hides everything NOT in `names`;
# `hide_non_match = false` hides everything IN `names`.
func _apply_visibility(root: Node, names: Dictionary, hide_non_match: bool) -> void:
	for mi in _walk_mesh_instances(root):
		var is_match: bool = names.has(mi.name)
		mi.visible = is_match if hide_non_match else not is_match


func _apply_render_priority(root: Node, names: Dictionary, priority: int) -> void:
	for mi in _walk_mesh_instances(root):
		if not names.has(mi.name):
			continue
		var mat: Material = mi.get_surface_override_material(0)
		if mat == null:
			mat = mi.mesh.surface_get_material(0)
		if mat == null:
			continue
		var dup := mat.duplicate() as Material
		dup.render_priority = priority
		mi.set_surface_override_material(0, dup)


func _apply_scrolls(root: Node, scrolls: Dictionary, names: Dictionary, only_matching: bool) -> void:
	for mi in _walk_mesh_instances(root):
		if only_matching and not names.has(mi.name):
			continue
		if not only_matching and names.has(mi.name):
			continue
		if not scrolls.has(mi.name):
			continue
		var s: Dictionary = scrolls[mi.name]
		var sx: float = s["scrollX"]
		var sy: float = s["scrollY"]
		if is_zero_approx(sx) and is_zero_approx(sy):
			continue
		var mat: Material = mi.get_surface_override_material(0)
		if mat == null:
			mat = mi.mesh.surface_get_material(0)
		if mat == null or not (mat is StandardMaterial3D):
			continue
		# Duplicate so per-instance scroll doesn't mutate a shared material.
		var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		dup.uv1_triplanar = false
		mi.set_surface_override_material(0, dup)
		_scroll_targets.append({"mat": dup, "speed": Vector2(sx, sy)})


func _walk_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_walk_recursive(root, out)
	return out


func _walk_recursive(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_walk_recursive(child, out)

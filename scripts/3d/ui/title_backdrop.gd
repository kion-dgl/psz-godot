extends Node3D
## Title-screen 3D backdrop.
##
## Static composition lives in title_backdrop.tscn so it can be edited in
## the Godot inspector (camera, moon, halo, horizon, ground, and the two
## GLB group parents). This script only handles:
##   - Loading scene.glb into each GLB* parent and splitting the merged
##     MeshInstance3D into per-surface nodes named dstitle_2..dstitle_6.
##   - Hiding surfaces that don't belong to that group.
##   - Stamping the configured render_priority on the light group.
##   - Building the starfield (MultiMeshInstance3D) and nebulae (child
##     MeshInstance3Ds) which are too numerous to sensibly author.
##   - Setting up ambient lighting via WorldEnvironment and the two
##     moon-rim DirectionalLight3Ds, aimed at the Moon node.
##   - Animating UV scroll on dstitle_2/3/4/6 every frame.
##
## Tweak positions in the editor; restart the scene to see changes.

const CONFIG_PATH := "res://assets/title/title-config.json"
const ASSET_BASE := "res://assets/title/"
const GLB_PATH := "res://assets/title/scene.glb"

# Surface index -> mesh name, based on the imported mesh's surface materials:
#   0,1 -> DSimage_dk19_cl (clouds)
#   2,4 -> DSimage_dk19_l02 (waves)
#   3   -> DSimage_dk19_l01 (beam)
const SURFACE_TO_NAME := {
	0: "dstitle_2",
	1: "dstitle_3",
	2: "dstitle_4",
	3: "dstitle_5",
	4: "dstitle_6",
}

const CLOUD_GROUP := ["dstitle_2", "dstitle_3"]
const LIGHT_GROUP := ["dstitle_4", "dstitle_5", "dstitle_6"]
const LIGHT_GROUP_RENDER_PRIORITY := 10

@onready var _moon: MeshInstance3D = $Moon
@onready var _glb_clouds: Node3D = $GLBClouds
@onready var _glb_light: Node3D = $GLBLight
@onready var _nebulae: Node3D = $Nebulae
@onready var _stars: MultiMeshInstance3D = $Stars

var _scroll_targets: Array[Dictionary] = []  # {mat: BaseMaterial3D, speed: Vector2}


func _ready() -> void:
	var config := _load_config()
	if config.is_empty():
		push_error("title_backdrop: failed to load %s" % CONFIG_PATH)
		return
	_build_environment(config)
	_build_moon_lights(config)
	_populate_group(_glb_clouds, CLOUD_GROUP, -1, config)
	_populate_group(_glb_light, LIGHT_GROUP, LIGHT_GROUP_RENDER_PRIORITY, config)
	_build_nebulae(config)
	_build_stars(config)


func _process(delta: float) -> void:
	for t in _scroll_targets:
		var mat: BaseMaterial3D = t["mat"]
		var s: Vector2 = t["speed"]
		var off := mat.uv1_offset
		off.x = fposmod(off.x + s.x * delta, 1.0)
		off.y = fposmod(off.y + s.y * delta, 1.0)
		mat.uv1_offset = off


# --- config/helpers ----------------------------------------------------------

func _load_config() -> Dictionary:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _vec3(arr: Variant) -> Vector3:
	return Vector3(arr[0], arr[1], arr[2])


func _color(hex: String) -> Color:
	return Color(hex)


func _load_tex(name: String) -> Texture2D:
	return load(ASSET_BASE + name) as Texture2D


# --- lighting ----------------------------------------------------------------

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


func _build_moon_lights(config: Dictionary) -> void:
	for L in config["moon"]["lights"]:
		var light := DirectionalLight3D.new()
		light.light_color = _color(L["color"])
		light.light_energy = L["intensity"]
		light.position = _vec3(L["fromPos"])
		add_child(light)
		light.look_at(_moon.position, Vector3.UP)


# --- GLB instancing ----------------------------------------------------------

func _populate_group(parent: Node3D, keep_names: Array, priority: int, config: Dictionary) -> void:
	var packed := load(GLB_PATH) as PackedScene
	if packed == null:
		push_error("title_backdrop: could not load %s" % GLB_PATH)
		return
	var instance := packed.instantiate() as Node3D
	parent.add_child(instance)
	_split_merged_surfaces(instance)

	var scrolls: Dictionary = config["glb"]["defaultScrollPerNode"]
	for mi in _walk_mesh_instances(instance):
		var keep: bool = keep_names.has(mi.name)
		mi.visible = keep
		if not keep:
			continue
		if priority != -1:
			_set_render_priority(mi, priority)
		_register_scroll(mi, scrolls)


# Godot's GLTF importer merged six SkinnedMeshes into one MeshInstance3D
# with five surfaces. Split each surface back into its own MeshInstance3D
# sharing the source skeleton + skin, named dstitle_2..dstitle_6 per the
# observed texture->name mapping (see SURFACE_TO_NAME).
func _split_merged_surfaces(root: Node) -> void:
	var source: MeshInstance3D = null
	for mi in _walk_mesh_instances(root):
		if mi.mesh != null and mi.mesh.get_surface_count() > 1:
			source = mi
			break
	if source == null:
		return
	var source_mesh: Mesh = source.mesh
	var skel_path: NodePath = source.skeleton
	var skin: Skin = source.skin
	var host: Node = source.get_parent()
	for i in source_mesh.get_surface_count():
		var mat: Material = source_mesh.surface_get_material(i)
		var new_mesh := ArrayMesh.new()
		new_mesh.add_surface_from_arrays(
			source_mesh.surface_get_primitive_type(i),
			source_mesh.surface_get_arrays(i),
		)
		if mat != null:
			new_mesh.surface_set_material(0, mat)
		var split := MeshInstance3D.new()
		split.mesh = new_mesh
		split.skeleton = skel_path
		split.skin = skin
		split.name = SURFACE_TO_NAME.get(i, "surface_%d" % i)
		host.add_child(split)
	source.queue_free()


func _set_render_priority(mi: MeshInstance3D, priority: int) -> void:
	var mat: Material = _ensure_override_material(mi)
	if mat != null:
		mat.render_priority = priority


func _register_scroll(mi: MeshInstance3D, scrolls: Dictionary) -> void:
	if not scrolls.has(mi.name):
		return
	var s: Dictionary = scrolls[mi.name]
	var sx: float = s["scrollX"]
	var sy: float = s["scrollY"]
	if is_zero_approx(sx) and is_zero_approx(sy):
		return
	var mat: Material = _ensure_override_material(mi)
	if mat == null or not (mat is BaseMaterial3D):
		return
	_scroll_targets.append({"mat": mat, "speed": Vector2(sx, sy)})


func _ensure_override_material(mi: MeshInstance3D) -> Material:
	var mat: Material = mi.get_surface_override_material(0)
	if mat != null:
		return mat
	if mi.mesh == null:
		return null
	mat = mi.mesh.surface_get_material(0)
	if mat == null:
		return null
	var dup := mat.duplicate() as Material
	mi.set_surface_override_material(0, dup)
	return dup


# --- nebulae + stars ---------------------------------------------------------

func _build_nebulae(config: Dictionary) -> void:
	var tex := _load_tex("nebula.png")
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
		_nebulae.add_child(mi)


func _build_stars(config: Dictionary) -> void:
	var cfg: Dictionary = config["stars"]
	var env: Dictionary = cfg["envelope"]
	var total: int = int(cfg["staticCount"]) + int(cfg["sparkleCount"])
	var palette: Array[Color] = []
	for p in cfg["palette"]:
		palette.append(_color(p))

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	mat.render_priority = -20

	var star_mesh := QuadMesh.new()
	star_mesh.size = Vector2(0.6, 0.6)
	star_mesh.material = mat

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
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * scale), pos))
		mm.set_instance_color(i, palette[rng.randi() % palette.size()])

	_stars.multimesh = mm


# --- tree walk ---------------------------------------------------------------

func _walk_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_walk_recursive(root, out)
	return out


func _walk_recursive(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_walk_recursive(child, out)

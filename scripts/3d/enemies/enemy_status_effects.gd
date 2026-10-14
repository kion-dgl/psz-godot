extends Node3D
## Readable combat feedback. Enemy tuning is intentionally separate from player statuses.
const DEFINITIONS := {
	"burn": {"duration": 6.0, "dot_percent": 0.05, "defense_mod": -0.1},
	"freeze": {"duration": 5.0, "skip_chance": 1.0, "damage_taken_mult": 1.5},
	"stun": {"duration": 5.0, "immobilize_duration": 5.0, "skip_chance": 1.0},
}
var fire: CPUParticles3D
var ice: MeshInstance3D
var stars: Node3D

static func definition(kind: String) -> Dictionary:
	return DEFINITIONS.get(kind, CombatManager.STATUS_EFFECTS.get(kind, {}))

func _ready() -> void:
	fire = CPUParticles3D.new()
	fire.emitting = false
	fire.amount = 36
	fire.lifetime = 0.65
	fire.preprocess = 0.3
	fire.direction = Vector3.UP
	fire.spread = 20.0
	fire.gravity = Vector3(0, 1.5, 0)
	fire.initial_velocity_min = 1.0
	fire.initial_velocity_max = 2.0
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 0.55
	fire.position.y = 0.7
	fire.scale_amount_min = 0.4
	fire.scale_amount_max = 0.8
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 0.95, 0.3, 0.95), Color(1, 0.35, 0.03, 0.8), Color(0.8, 0.05, 0, 0)])
	gradient.offsets = PackedFloat32Array([0, 0.4, 1])
	fire.color_ramp = gradient
	var texture := GradientTexture2D.new()
	var mask := Gradient.new()
	mask.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	texture.gradient = mask
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0)
	var flame := QuadMesh.new()
	flame.size = Vector2(0.65, 1.1)
	var flame_material := _material(Color.WHITE)
	flame_material.albedo_texture = texture
	flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flame_material.vertex_color_use_as_albedo = true
	flame.material = flame_material
	fire.mesh = flame
	add_child(fire)
	ice = MeshInstance3D.new()
	var crystal := CylinderMesh.new()
	crystal.top_radius = 0.35
	crystal.bottom_radius = 0.9
	crystal.height = 2.3
	crystal.radial_segments = 6
	crystal.material = _material(Color(0.3, 0.75, 1, 0.45))
	ice.mesh = crystal
	ice.position.y = 1.0
	ice.visible = false
	add_child(ice)
	stars = Node3D.new()
	stars.position.y = 2.1
	stars.visible = false
	add_child(stars)
	for i in 3:
		var star := Label3D.new()
		star.text = "★"
		star.font_size = 64
		star.pixel_size = 0.007
		star.modulate = Color(1, 0.9, 0.1)
		star.outline_modulate = Color(0.45, 0.2, 0.02)
		star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		var angle := TAU * float(i) / 3.0
		star.position = Vector3(cos(angle) * 0.7, 0, sin(angle) * 0.7)
		stars.add_child(star)
	_fit_to_model()

func _fit_to_model() -> void:
	var enemy := get_parent() as EnemyBase
	if not enemy or not enemy.model: return
	var bounds := AABB()
	var found := false
	var pending: Array[Node] = [enemy.model]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and node.mesh:
			var box: AABB = (global_transform.affine_inverse() * node.global_transform) * node.get_aabb()
			bounds = bounds.merge(box) if found else box
			found = true
		pending.append_array(node.get_children())
	if not found: return
	var height := maxf(bounds.size.y, 1.5)
	var radius := maxf(maxf(bounds.size.x, bounds.size.z) * 0.55, 0.6)
	var center := bounds.get_center()
	ice.position = center
	ice.scale = Vector3(radius / 0.9, height / 2.3, radius / 0.9)
	(ice.mesh as CylinderMesh).top_radius = 0.8
	stars.position = Vector3(center.x, bounds.end.y + 0.4, center.z)
	for star in stars.get_children():
		star.position *= maxf(radius / 0.7, 1.0)
	fire.position = center - Vector3.UP * height * 0.15
	fire.emission_sphere_radius = radius * 0.7
	fire.scale_amount_min = height * 0.18
	fire.scale_amount_max = height * 0.35

func sync(effects: Array) -> void:
	var kinds: Array = effects.map(func(fx: Dictionary): return fx.type)
	fire.emitting = "burn" in kinds
	ice.visible = "freeze" in kinds
	stars.visible = "stun" in kinds or "sleep" in kinds

func _process(delta: float) -> void:
	if stars.visible: stars.rotation.y += delta * 2.5

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

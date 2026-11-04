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
	fire = preload("res://scripts/3d/effects/burn_flames.gd").create()
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
	fire.visible = "burn" in kinds
	fire.emitting = fire.visible
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

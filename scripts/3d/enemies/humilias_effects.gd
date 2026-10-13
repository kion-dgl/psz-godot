extends Node3D
## Authored hover exhaust and malfunction sparks; no retail effect parity claim.
var jets: Array[CPUParticles3D] = []
var sparks: CPUParticles3D
var rings: Array[MeshInstance3D] = []

func _ready() -> void:
	for side in [-1.0,1.0]:
		var jet := _particles(Color(0.25,0.8,1.0,0.7),48,0.45)
		jet.position = Vector3(side*1.1,1.0,0)
		jet.direction = Vector3.DOWN
		jet.spread = 35
		jet.initial_velocity_min = 2.0
		jet.initial_velocity_max = 4.0
		jet.gravity = Vector3(0,1,0)
		jets.append(jet)
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.8
		mesh.outer_radius = 1.2
		mesh.rings = 16
		mesh.ring_segments = 8
		mesh.material = _material(Color(0.2,0.8,1.0,0.5))
		ring.mesh = mesh
		ring.position = Vector3(side*1.1,0.25,0)
		ring.scale.y = 0.15
		add_child(ring)
		rings.append(ring)
	sparks = _particles(Color(1,0.65,0.15,0.9),24,0.35)
	sparks.position.y = 2.0
	sparks.direction = Vector3.UP
	sparks.spread = 180
	sparks.initial_velocity_min = 3.0
	sparks.initial_velocity_max = 6.0
	sparks.gravity = Vector3(0,-6,0)

func update_state(mode: String, request: String, tick: int) -> void:
	var hovering := mode == "combined" and request == "move"
	for jet in jets: jet.emitting = hovering
	for ring in rings:
		ring.visible = hovering
		var pulse := 1.0+0.15*sin(tick*0.7)
		ring.scale.x = pulse
		ring.scale.z = pulse
	sparks.emitting = mode in ["splitting","split"] or request == "down"

func _particles(tint: Color, count: int, duration: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.amount = count
	particles.lifetime = duration
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.4
	particles.scale_amount_min = 0.15
	particles.scale_amount_max = 0.35
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = _material(tint)
	particles.mesh = mesh
	add_child(particles)
	return particles

func _material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	return material

extends Node3D
## Presentation only: no collision or gameplay callbacks. A projectile owns its
## travelling visual; the current scene owns short-lived release/contact bursts.

const FIRE := Color(1.0, 0.32, 0.045)
const ICE := Color(0.25, 0.8, 1.0)
const HEAL := Color(0.35, 1.0, 0.65)
var kind := "foie"
var duration := 0.0
var elapsed := 0.0
var travel_alpha := 1.0
var _fire_materials: Array[ShaderMaterial] = []
var _ice_material: ShaderMaterial
var pattern_seed := 1
var _cloud_material: ShaderMaterial
var _growth_offsets: Array[float] = []
var _pieces: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []


static func burst(parent: Node, at: Vector3, spell: String, lifetime := 0.35, size := 1.0) -> Node3D:
	var effect = load("res://scripts/3d/effects/technique_visual.gd").new()
	effect.kind = spell
	effect.duration = lifetime
	effect.pattern_seed = hash(at) ^ effect.get_instance_id()
	parent.add_child(effect)
	effect.global_position = at
	effect.scale = Vector3.ONE * size
	return effect


func _ready() -> void:
	add_to_group("technique_visuals")
	var tint := ICE if kind.begins_with("ice") else HEAL if kind.begins_with("heal") else FIRE
	if kind == "cure": tint = Color(0.65, 0.85, 1.0)
	if kind == "heal_empty": tint = Color(0.7, 0.8, 0.75)
	if kind == "rafoie_blast":
		for i in range(2):
			var sphere := SphereMesh.new()
			sphere.radius = 1.0 - i * 0.12
			sphere.height = sphere.radius * 2.0
			sphere.radial_segments = 48
			sphere.rings = 24
			var shell := _piece(sphere, FIRE, Vector3(0, 0.4, 0))
			var material := ShaderMaterial.new()
			material.shader = preload("res://scripts/3d/shaders/technique_fire.gdshader")
			material.set_shader_parameter("phase", float(i) * 9.7)
			material.set_shader_parameter("heat", 0.85 + i * 0.2)
			shell.material_override = material
			_fire_materials.append(material)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.96
		ring.outer_radius = 1.0
		ring.rings = 64
		ring.ring_segments = 8
		var wave := _piece(ring, Color(1.0, 0.035, 0.01), Vector3(0, 0.012, 0))
		wave.scale.y = 0.2
		return
	if kind == "ice_line":
		_make_cloud(Vector2(1.9, 0.7), Vector3(0, -0.08, 0))
		return
	if kind == "ice_growth":
		var rng := RandomNumberGenerator.new()
		rng.seed = pattern_seed # Never consume combat's shared random stream.
		_ice_material = ShaderMaterial.new()
		_ice_material.shader = preload("res://scripts/3d/shaders/technique_ice.gdshader")
		for i in range(rng.randi_range(3, 5)):
			var shard := _piece(_ice_rock(rng), ICE, Vector3(rng.randf_range(-0.32, 0.32), 0, rng.randf_range(-0.24, 0.24)))
			shard.material_override = _ice_material
			shard.rotation = Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(-PI, PI), rng.randf_range(-0.7, 0.7))
			_growth_offsets.append(rng.randf_range(0.0, 0.055))
		_make_cloud(Vector2(rng.randf_range(1.0, 1.5), 0.45), Vector3(0, 0.18, 0))
		return
	if duration > 0.0:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.8
		ring.outer_radius = 0.86
		ring.rings = 24
		ring.ring_segments = 6
		_piece(ring, tint, Vector3.ZERO)
		for i in range(8):
			var angle := TAU * i / 8.0
			var mote := SphereMesh.new()
			mote.radius = 0.045
			mote.height = 0.09
			mote.radial_segments = 6
			mote.rings = 3
			_piece(mote, tint.lerp(Color.WHITE, 0.4), Vector3(cos(angle), 0.0, sin(angle)) * 0.5)
	elif kind == "ice":
		for i in range(5):
			var crystal := CylinderMesh.new()
			crystal.top_radius = 0.0
			crystal.bottom_radius = 0.12 if i == 0 else 0.075
			crystal.height = 0.52 if i == 0 else 0.3
			crystal.radial_segments = 4
			var shard := _piece(crystal, tint.lerp(Color.WHITE, 0.12 * i), Vector3((i % 3 - 1) * 0.12, 0, i * 0.11))
			shard.rotation.z = (i - 2) * 0.2
	else:
		# A rounded hot core plus turbulent translucent flame envelopes.
		for i in range(6):
			var flame := SphereMesh.new()
			flame.radius = 0.28 * (1.0 - i * 0.12)
			flame.height = flame.radius * 2.0
			flame.radial_segments = 24
			flame.rings = 12
			var ember := _piece(flame, FIRE, Vector3(0, 0, i * 0.17))
			ember.scale = Vector3.ONE if i == 0 else Vector3(1, 1, 1.8)
			var fire := ShaderMaterial.new()
			fire.shader = preload("res://scripts/3d/shaders/technique_fire.gdshader")
			fire.set_shader_parameter("phase", float(i) * 7.3)
			fire.set_shader_parameter("heat", 1.3 if i == 0 else 0.9)
			ember.material_override = fire
			_fire_materials.append(fire)


func _piece(mesh: Mesh, tint: Color, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 0.6
	node.material_override = material
	add_child(node)
	_pieces.append(node)
	_materials.append(material)
	return node


func _process(delta: float) -> void:
	elapsed += delta
	if kind == "rafoie_blast":
		var growth := lerpf(0.08, 1.0, ease(clampf(elapsed / 0.16, 0.0, 1.0), 0.35))
		for i in range(2):
			_pieces[i].scale = Vector3.ONE * growth
			_pieces[i].position.y = 0.4 * growth
			_fire_materials[i].set_shader_parameter("fade", 1.0 - smoothstep(0.18 + i * 0.06, duration, elapsed))
		var radius := lerpf(0.05, 1.0, smoothstep(0.0, 0.4, elapsed))
		_pieces[2].scale = Vector3(radius, 0.2, radius)
		_materials[2].albedo_color.a = 1.0 - smoothstep(0.4, duration, elapsed)
		if elapsed >= duration: queue_free()
		return
	if kind == "ice_line":
		_cloud_material.set_shader_parameter("opacity", travel_alpha * 0.85)
		return
	if kind == "ice_growth":
		for i in range(_pieces.size()):
			var growth := smoothstep(_growth_offsets[i], _growth_offsets[i] + 0.12, elapsed)
			_pieces[i].scale = Vector3(0.8 + growth*0.2, maxf(growth, 0.001), 0.8 + growth*0.2)
		_ice_material.set_shader_parameter("dissolve", smoothstep(0.24, duration, elapsed))
		_ice_material.set_shader_parameter("opacity", smoothstep(0.0, 0.08, elapsed))
		_cloud_material.set_shader_parameter("opacity", sin(clampf(elapsed/duration, 0.0, 1.0)*PI)*0.55)
		if elapsed >= duration: queue_free()
		return
	if duration <= 0.0:
		for material in _fire_materials:
			material.set_shader_parameter("fade", travel_alpha)
		for material in _materials:
			material.albedo_color.a = travel_alpha
		for i in range(_pieces.size()):
			_pieces[i].position.y = sin(elapsed * 24.0 + i) * 0.025
		return
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	var healing := kind.begins_with("heal") or kind == "cure"
	_pieces[0].scale = Vector3.ONE * (0.35 + progress * 0.65)
	for i in range(1, _pieces.size()):
		var angle := TAU * (i - 1) / 8.0 + progress * 0.4
		var radius := 0.5 + progress * (0.15 if healing else 0.55)
		_pieces[i].position = Vector3(cos(angle) * radius, progress * (1.5 if healing else 0.35), sin(angle) * radius)
	for material in _materials:
		material.albedo_color.a = 1.0 - progress
	if elapsed >= duration:
		queue_free()


func _make_cloud(size: Vector2, at: Vector3) -> void:
	var cloud := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	cloud.mesh = quad
	cloud.position = at
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cloud_material = ShaderMaterial.new()
	_cloud_material.shader = preload("res://scripts/3d/shaders/technique_frost.gdshader")
	_cloud_material.set_shader_parameter("phase", float(pattern_seed % 101))
	cloud.material_override = _cloud_material
	add_child(cloud)


## Uneven, leaning, bevelled ice masses with broad caps, rather than cones.
func _ice_rock(rng: RandomNumberGenerator) -> ArrayMesh:
	var width := rng.randf_range(0.13, 0.26)
	var height := rng.randf_range(0.28, 0.72)
	var lean := Vector2(rng.randf_range(-0.16, 0.16), rng.randf_range(-0.13, 0.13))
	var vertices: Array[Vector3] = []
	var ring_radii := [0.8, 1.0, 0.75, 0.42]
	var ring_heights := [0.0, 0.2, 0.8, 1.0]
	var widths: Array[float] = []
	for side in range(6): widths.append(rng.randf_range(0.75, 1.25))
	for ring in range(4):
		for side in range(6):
			var angle := TAU * side / 6.0
			var y: float = ring_heights[ring]
			vertices.append(Vector3(cos(angle)*width*ring_radii[ring]*widths[side]+lean.x*y, y*height, sin(angle)*width*ring_radii[ring]*widths[side]+lean.y*y))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(3):
		for side in range(6):
			var a := ring*6+side
			var b := ring*6+(side+1)%6
			for index in [a, b, a+6, b, b+6, a+6]: surface.add_vertex(vertices[index])
	for side in range(1, 5):
		for index in [18, 18+side, 19+side]: surface.add_vertex(vertices[index])
	surface.generate_normals()
	return surface.commit()

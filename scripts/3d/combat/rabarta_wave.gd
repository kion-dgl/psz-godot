extends Node3D
## Ground ice propagates once from the cast position; each enemy is hit once.
const RADIUS := 5.0
const SPEED := 16.0
var caster: Node3D
var damage := 0
var knockback := 0.0
var element := "ice"
var element_level := 1
var elapsed := 0.0
var hit: Array = []
var material: ShaderMaterial
var next_growth := 0.45
var mist: Array[MeshInstance3D] = []
var mist_materials: Array[ShaderMaterial] = []

func _ready() -> void:
	add_to_group("technique_visuals")
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Shared polar vertices form a continuous rumpled sheet, not radial missiles.
	var points: Array[Vector3] = []
	const SIDES := 96
	const RINGS := 24
	for ring in range(RINGS + 1):
		for side in range(SIDES):
			var angle := TAU * side / SIDES
			var radius := RADIUS * ring / RINGS
			var edge := 1.0 + 0.025 * sin(angle * 7.0) + 0.02 * sin(angle * 13.0)
			var x := cos(angle) * radius * edge
			var z := sin(angle) * radius * edge
			var height := 0.06 + (0.12 + 0.1 * sin(x * 3.1 + z * 1.7)) * (0.5 + 0.5 * sin(z * 3.8 - x))
			points.append(Vector3(x, height, z))
	for ring in range(RINGS):
		for side in range(SIDES):
			var a := ring * SIDES + side
			var b := ring * SIDES + (side + 1) % SIDES
			for index in [a, a + SIDES, b, b, a + SIDES, b + SIDES]: surface.add_vertex(points[index])
	surface.generate_normals()
	var sheet := MeshInstance3D.new()
	sheet.mesh = surface.commit()
	material = ShaderMaterial.new()
	material.shader = preload("res://scripts/3d/shaders/rabarta_sheet.gdshader")
	sheet.material_override = material
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sheet)
	material.set_shader_parameter("speed", SPEED)
	for i in range(24):
		var cloud := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(2.4, 1.3)
		cloud.mesh = quad
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var frost := ShaderMaterial.new()
		frost.shader = preload("res://scripts/3d/shaders/technique_frost.gdshader")
		frost.set_shader_parameter("phase", float(i) * 3.17)
		frost.set_shader_parameter("opacity", 0.0)
		cloud.material_override = frost
		add_child(cloud)
		mist.append(cloud)
		mist_materials.append(frost)

func _physics_process(delta: float) -> void:
	elapsed += delta
	var radius := minf(elapsed * SPEED, RADIUS)
	material.set_shader_parameter("age", elapsed)
	for i in range(mist.size()):
		var angle := TAU * float(i) / mist.size()
		var cloud_radius := radius * (0.68 if i % 2 == 0 else 0.84)
		mist[i].position = Vector3(cos(angle) * cloud_radius, 0.25 + elapsed * 0.35, sin(angle) * cloud_radius)
		mist_materials[i].set_shader_parameter("opacity", smoothstep(0.0, 0.045, elapsed) * (1.0 - smoothstep(RADIUS / SPEED + 0.12, RADIUS / SPEED + 0.6, elapsed)) * 0.85)
	while next_growth <= radius:
		# Staggered, overlapping Barta ice clusters and their low frost clouds.
		var count := maxi(8, int(TAU * next_growth / 1.0))
		for i in range(count):
			var angle := TAU * (float(i) / count + next_growth * 0.071)
			var at := global_position + Vector3(cos(angle), 0, sin(angle)) * next_growth
			preload("res://scripts/3d/effects/technique_visual.gd").burst(get_tree().current_scene, at, "ice_growth", 0.65, 1.15)
		next_growth += 0.8
	if is_instance_valid(caster):
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy in hit or not enemy.get("is_alive"): continue
			var offset: Vector3 = enemy.global_position - global_position
			if absf(offset.y) > 2.0 or Vector2(offset.x, offset.z).length() > radius: continue
			var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3, enemy.global_position + Vector3.UP * 0.3, 1)
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
			hit.append(enemy)
			if enemy.hurtbox: enemy.hurtbox.take_hit(damage, offset.normalized() * knockback, 100, element, element_level, true, "technique", caster)
	if elapsed > RADIUS / SPEED + 0.7: queue_free()

extends RefCounted
## Local party support. Recipient APIs own their own HP/status state.
const RADIUS := 6.0
const Visual = preload("res://scripts/3d/effects/technique_visual.gd")
const SOUNDS := {
	"razonde": "res://assets/sfx/common/common_130.wav",
	"rabarta": "res://assets/sfx/common/common_126.wav",
	"rafoie": "res://assets/sfx/common/common_122.wav",
	"shifta": "res://assets/sfx/common/common_140.wav",
	"foie": "res://assets/sfx/common/common_120.wav",
	"barta": "res://assets/sfx/common/common_124.wav",
	"zonde": "res://assets/sfx/common/common_128.wav",
	"resta": "res://assets/sfx/common/common_134.wav",
	"anti": "res://assets/sfx/common/common_135.wav",
}

static func play_sound(caster: Node3D, technique: String) -> void:
	if SOUNDS.has(technique): SfxManager.play_at(SOUNDS[technique], caster.global_position, -5.0)

static func cast(caster: Node3D, technique: String, amount: int) -> Array:
	var affected: Array = []
	var candidates: Array = [caster]
	for member in caster.get_tree().get_nodes_in_group("party_members"):
		if not candidates.has(member): candidates.append(member)
	for member in candidates:
		if not is_instance_valid(member) or member.is_queued_for_deletion() or not member is Node3D: continue
		if not member.has_method("can_receive_support") or not member.can_receive_support(): continue
		if caster.global_position.distance_squared_to(member.global_position) > RADIUS * RADIUS: continue
		var changed: int = member.receive_support(technique, amount)
		if changed <= 0: continue
		affected.append(member)
		if technique == "shifta":
			SfxManager.play_at("res://assets/sfx/common/common_142.wav", member.global_position, -8.0)
			continue # Recipient power-up cue; persistent wrists are owned by the buff.
		# Attached to the actual recipient, so running does not leave healing behind.
		Visual.burst(member, member.global_position + Vector3.UP * 0.08, "heal" if technique == "resta" else "cure", 0.9)
		_particles(member, technique)
	_area(caster, technique)
	return affected

static func _particles(recipient: Node3D, technique: String) -> void:
	var particles := CPUParticles3D.new()
	particles.name = "SupportParticles"
	particles.add_to_group("support_particles")
	particles.amount = 32
	particles.lifetime = 0.7
	particles.one_shot = true
	particles.explosiveness = 0.45
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.45
	particles.direction = Vector3.UP
	particles.spread = 25.0
	particles.initial_velocity_min = 0.8
	particles.initial_velocity_max = 1.6
	particles.gravity = Vector3(0, 0.3, 0)
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	particles.mesh = mesh
	var tint := Color(0.4, 1, 0.6) if technique == "resta" else Color(0.65, 0.85, 1)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([tint, Color(tint, 0.0)])
	particles.color_ramp = gradient
	recipient.add_child(particles)
	particles.position.y = 0.7
	particles.emitting = true
	var tween := particles.create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(particles.queue_free)

static func _area(caster: Node3D, technique: String) -> void:
	var ring := MeshInstance3D.new()
	ring.add_to_group("support_areas")
	var mesh := TorusMesh.new()
	mesh.inner_radius = RADIUS - 0.04
	mesh.outer_radius = RADIUS
	mesh.rings = 48
	mesh.ring_segments = 6
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.3, 1, 0.6, 0.45) if technique == "resta" else Color(0.6, 0.8, 1, 0.45)
	if technique == "shifta": material.albedo_color = Color(1.0, 0.08, 0.03, 0.65)
	ring.material_override = material
	caster.get_tree().current_scene.add_child(ring)
	ring.global_position = caster.global_position + Vector3.UP * 0.06
	var tween := ring.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.55)
	tween.tween_callback(ring.queue_free)

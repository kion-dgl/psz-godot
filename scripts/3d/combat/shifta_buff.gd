extends Node3D
## Runtime buff and its wrist indicators share one lifetime.
const DURATION := 60.0
var technique := "shifta"
var remaining := DURATION
var amount := 0.1
var _skeleton: Skeleton3D
var _clouds: Array[MeshInstance3D] = []
var _bones: Array[int] = []
var _drips: Array[CPUParticles3D] = []

static func apply_to(recipient: Node3D, level: int, spell := "shifta") -> void:
	var active := recipient.get_node_or_null(spell.capitalize() + "Buff")
	if active != null and active.is_queued_for_deletion():
		active.name = "ExpiredShifta"
		active = null
	if active == null:
		active = load("res://scripts/3d/combat/shifta_buff.gd").new()
		active.name = spell.capitalize() + "Buff"
		active.technique = spell
		recipient.add_child(active)
	active.amount = maxf(active.amount, 0.1 * maxi(1, level))
	active.remaining = DURATION

static func amount_for(recipient: Node, spell := "shifta") -> float:
	if not is_instance_valid(recipient): return 0.0
	var active := recipient.get_node_or_null(spell.capitalize() + "Buff")
	return float(active.amount) if active != null and active.remaining > 0 and not active.is_queued_for_deletion() else 0.0

func _ready() -> void:
	add_to_group("shifta_buffs")
	for i in range(2):
		var cloud := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.42, 0.42)
		cloud.mesh = quad
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = preload("res://scripts/3d/shaders/shifta_cloud.gdshader")
		material.set_shader_parameter("phase", i * 9.3)
		material.set_shader_parameter("defense", technique in ["deband", "zalure"])
		cloud.material_override = material
		cloud.hide()
		add_child(cloud)
		_clouds.append(cloud)
		if technique in ["jellen", "zalure"]: _make_drips()

func _process(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	var recipient := get_parent()
	var alive: bool = recipient.can_receive_support() if recipient.has_method("can_receive_support") else bool(recipient.get("is_alive"))
	if remaining <= 0 or not alive:
		queue_free()
		return
	if not is_instance_valid(_skeleton) or not _skeleton.is_inside_tree():
		_skeleton = NodeUtils.first_of_type(recipient, "Skeleton3D") as Skeleton3D
		_bones.clear()
		if _skeleton:
			for bone_name in ["070_RArm02", "040_LArm02"]: _bones.append(_skeleton.find_bone(bone_name))
			if _bones.has(-1):
				_bones.clear()
				for side in ["r", "l"]:
					var found := -1
					for bone in range(_skeleton.get_bone_count()):
						var label := _skeleton.get_bone_name(bone).to_lower()
						if (side + "arm" in label or side + "hand" in label or side + "wrist" in label or "_" + side in label) and ("arm" in label or "hand" in label or "wrist" in label): found = bone
					_bones.append(found)
	for i in range(_clouds.size()):
		_clouds[i].visible = _drips.is_empty()
		if is_instance_valid(_skeleton) and _bones.size() == 2 and _bones[i] >= 0:
			_clouds[i].global_position = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_bones[i])).origin
		else:
			# Some creature rigs (Ghowl) expose no arm/wrist bones. Keep the
			# paired indicators on the creature's sides rather than hiding them.
			_clouds[i].position = Vector3(-0.45 if i == 0 else 0.45, 0.65, 0.15)
		_clouds[i].material_override.set_shader_parameter("opacity", minf(remaining, 1.0) * 0.85)
		if i < _drips.size():
			_drips[i].global_position = _clouds[i].global_position
			_drips[i].emitting = remaining > 0.55

func _make_drips() -> void:
	var particles := CPUParticles3D.new()
	particles.amount = 6
	particles.lifetime = 0.55
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.12
	particles.direction = Vector3.DOWN
	particles.spread = 12.0
	particles.initial_velocity_min = 0.4
	particles.initial_velocity_max = 0.9
	particles.gravity = Vector3(0, -2.5, 0)
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.2
	var drop := SphereMesh.new()
	drop.radius = 0.025
	drop.height = 0.12
	drop.radial_segments = 6
	drop.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	drop.material = material
	particles.mesh = drop
	var tint := Color(1.0, 0.15, 0.06) if technique == "jellen" else Color(0.12, 0.55, 1.0)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([tint.lightened(0.35), tint, Color(tint, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	particles.color_ramp = gradient
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	particles.emitting = true
	_drips.append(particles)

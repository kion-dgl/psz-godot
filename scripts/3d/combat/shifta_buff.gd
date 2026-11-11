extends Node3D
## Runtime buff and its wrist indicators share one lifetime.
const DURATION := 60.0
var remaining := DURATION
var amount := 0.1
var _skeleton: Skeleton3D
var _clouds: Array[MeshInstance3D] = []
var _bones: Array[int] = []

static func apply_to(recipient: Node3D, level: int) -> void:
	var active := recipient.get_node_or_null("ShiftaBuff")
	if active != null and active.is_queued_for_deletion():
		active.name = "ExpiredShifta"
		active = null
	if active == null:
		active = load("res://scripts/3d/combat/shifta_buff.gd").new()
		active.name = "ShiftaBuff"
		recipient.add_child(active)
	active.amount = maxf(active.amount, 0.1 * maxi(1, level))
	active.remaining = DURATION

static func amount_for(recipient: Node) -> float:
	if not is_instance_valid(recipient): return 0.0
	var active := recipient.get_node_or_null("ShiftaBuff")
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
		cloud.material_override = material
		cloud.hide()
		add_child(cloud)
		_clouds.append(cloud)

func _process(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	var recipient := get_parent()
	if remaining <= 0 or not recipient.can_receive_support():
		queue_free()
		return
	if not is_instance_valid(_skeleton) or not _skeleton.is_inside_tree():
		_skeleton = NodeUtils.first_of_type(recipient, "Skeleton3D") as Skeleton3D
		_bones.clear()
		if _skeleton:
			for bone_name in ["070_RArm02", "040_LArm02"]: _bones.append(_skeleton.find_bone(bone_name))
	for i in range(_clouds.size()):
		_clouds[i].visible = is_instance_valid(_skeleton) and _bones.size() == 2 and _bones[i] >= 0
		if _clouds[i].visible:
			_clouds[i].global_position = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_bones[i])).origin
			_clouds[i].material_override.set_shader_parameter("opacity", minf(remaining, 1.0) * 0.85)

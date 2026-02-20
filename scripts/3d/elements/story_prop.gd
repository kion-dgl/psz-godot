extends Node3D
class_name StoryProp
## Static GLB prop placed in the field for story purposes (e.g., crashed dropship).
## Does not extend GameElement since it has no interaction — just loads and displays a GLB.

@export var prop_path: String = ""
@export var prop_scale: float = 1.0

var element_state: String = "default"


func _ready() -> void:
	if prop_path.is_empty():
		return

	var full_path := "res://" + prop_path
	var packed := load(full_path) as PackedScene
	if not packed:
		push_warning("StoryProp: Failed to load model: " + full_path)
		return

	var model := packed.instantiate()
	if prop_scale != 1.0:
		model.scale = Vector3.ONE * prop_scale
	add_child(model)

	# Offset model so its bottom sits at y=0
	var aabb := _get_combined_aabb(model)
	if aabb.size.y > 0:
		model.position.y -= aabb.position.y * prop_scale

	# Add static collision based on AABB
	if aabb.size.length() > 0:
		_add_collision(aabb)


func _add_collision(aabb: AABB) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1  # Environment layer
	body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size * prop_scale
	shape.shape = box

	# Center the collision box on the scaled AABB
	var center := aabb.get_center() * prop_scale
	shape.position = Vector3(center.x, center.y - aabb.position.y * prop_scale, center.z)

	body.add_child(shape)
	add_child(body)


func _get_combined_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_aabb: AABB = (child as MeshInstance3D).get_aabb()
			if first:
				result = mesh_aabb
				first = false
			else:
				result = result.merge(mesh_aabb)
		var child_aabb := _get_combined_aabb(child)
		if child_aabb.size.length() > 0:
			if first:
				result = child_aabb
				first = false
			else:
				result = result.merge(child_aabb)
	return result


func set_state(new_state: String) -> void:
	element_state = new_state

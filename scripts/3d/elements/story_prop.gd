extends Node3D
class_name StoryProp
## Static GLB prop placed in the field for story purposes (e.g., crashed dropship).
## Does not extend GameElement since it has no interaction — just loads and displays a GLB.

@export var prop_path: String = ""
@export var prop_scale: float = 1.0
## When true, skip auto-generated collision. Used for quest props that the player
## needs to walk through (e.g. Apothecary's Supply plants).
@export var no_collision: bool = false


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

	# Offset model so its bottom sits at y=0, accounting for internal node transforms
	var visual_min_y := _get_visual_min_y(model)
	if visual_min_y != 0.0:
		model.position.y -= visual_min_y

	# Add static collision based on AABB (skip for dropship — mesh is pre-scaled in GLB).
	# Quest props can opt out via no_collision (e.g. Apothecary's Supply plants).
	var aabb := _get_combined_aabb(model)
	if aabb.size.length() > 0 and not prop_path.contains("dropship") and not no_collision:
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


func _get_visual_min_y(node: Node) -> float:
	## Walk all MeshInstance3D children and find the lowest y after applying
	## each node's local transform chain. Handles GLBs with internal scaling.
	var result := [INF]  # Array so recursion can mutate it
	_collect_visual_min_y(node, Transform3D.IDENTITY, result)
	return result[0] if result[0] != INF else 0.0


func _collect_visual_min_y(node: Node, parent_xform: Transform3D, result: Array) -> void:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh_aabb := mi.get_aabb()
		var transformed: AABB = xform * mesh_aabb
		var bottom: float = transformed.position.y
		if bottom < result[0]:
			result[0] = bottom
	for child in node.get_children():
		_collect_visual_min_y(child, xform, result)


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

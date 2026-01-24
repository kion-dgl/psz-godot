extends Node3D
## Base class for map scenes - handles navigation mesh baking

@export var auto_bake_navmesh: bool = false  # Disabled - using raycast floor detection instead

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	if auto_bake_navmesh and nav_region:
		# Wait for scene to be fully loaded
		await get_tree().process_frame
		_bake_navigation_mesh()


func _print_node_tree(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var type_info := node.get_class()
	if node is MeshInstance3D:
		type_info += " (mesh)"
	elif node is StaticBody3D:
		type_info += " (collision)"
	elif node is Area3D:
		type_info += " (area)"
	print("%s%s [%s]" % [indent, node.name, type_info])
	for child in node.get_children():
		_print_node_tree(child, depth + 1)


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found := _find_node_by_name(child, target_name)
		if found:
			return found
	return null


func _bake_navigation_mesh() -> void:
	if not nav_region or not nav_region.navigation_mesh:
		push_warning("No NavigationRegion3D or NavigationMesh found")
		return

	# Bake the navigation mesh from child geometry
	nav_region.bake_navigation_mesh()

	# Debug: Check if navmesh has geometry
	var navmesh := nav_region.navigation_mesh
	var vertex_count := navmesh.vertices.size()
	var polygon_count := navmesh.get_polygon_count()
	print("Navigation mesh baked for: ", name)
	print("  Vertices: ", vertex_count, ", Polygons: ", polygon_count)

	if polygon_count == 0:
		push_warning("NavigationMesh is empty! Check that floor geometry exists and is parsed correctly.")

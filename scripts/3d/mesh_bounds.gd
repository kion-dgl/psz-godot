extends RefCounted
class_name MeshBounds
## Merged bounding box of every MeshInstance3D under a node.
##
## Two callers needed this and had grown near-identical copies (EPIC #295 spotted
## the pair): TeleporterDressing re-pivots each city dressing piece to its bbox
## bottom-center, and Box sizes its collider from whichever per-field container
## the active area loaded. They differ only in whether the root's own transform
## counts, so that is the parameter.

## Merged AABB of every MeshInstance3D under `root`.
##
## `include_root_transform` false measures in root's LOCAL space — what you want
## when sizing a collider for the node itself, since the collider is a sibling
## in that same space. True measures in root's PARENT space, i.e. including
## root's own transform — what you want when repositioning root relative to its
## parent, since the offset you compute has to be in the space root moves in.
##
## Returns a zero-size AABB when there is no mesh to measure; callers use that
## as the signal to keep their authored default.
static func combined(root: Node3D, include_root_transform: bool = false) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [[root as Node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node = entry[0]
		var xform: Transform3D = entry[1]
		if node is Node3D and (include_root_transform or node != root):
			xform = xform * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			var ab: AABB = xform * (node as MeshInstance3D).mesh.get_aabb()
			result = ab if first else result.merge(ab)
			first = false
		for child in node.get_children():
			stack.push_back([child, xform])
	return result

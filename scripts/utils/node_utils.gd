extends RefCounted
class_name NodeUtils
## Small Node-tree helpers shared across the field/enemy/player scripts.

## First descendant of `root` whose class (or script class_name) is `type_name`,
## or null if none. Wraps Node.find_children with owned=false so it reaches
## nodes under instanced scenes (e.g. a loaded GLB) whose owner isn't set —
## the reason the hand-rolled recursive finders this replaces existed.
static func first_of_type(root: Node, type_name: String) -> Node:
	var hit := root.find_children("*", type_name, true, false)
	return hit[0] if not hit.is_empty() else null

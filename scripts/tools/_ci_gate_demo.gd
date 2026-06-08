extends RefCounted
# Intentional dead code to witness the code-health CI gate fail on a real PR.
# Removed in the follow-up commit. EPIC #295.
func _demo_unreferenced_dead_function() -> int:
	var acc := 0
	for i in range(5):
		acc += i
	return acc

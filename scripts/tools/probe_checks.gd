extends RefCounted
## Shared assertion logging and accumulated result for live Godot probes.

static func check(condition: bool, message: String, previous_ok: bool, label: String) -> bool:
	print("[%s] %s: %s" % [label, "PASS" if condition else "FAIL", message])
	return condition and previous_ok

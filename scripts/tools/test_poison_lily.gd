extends SceneTree
## Test: just try loading the PoisonLily script
## Run: godot --headless --path . --script scripts/tools/test_poison_lily.gd

func _init() -> void:
	print("[Test] Attempting to load poison_lily.gd...")
	var script = load("res://scripts/3d/enemies/poison_lily.gd")
	if script:
		print("[Test] SUCCESS: Script loaded")
		print("[Test] Script: %s" % script)
	else:
		print("[Test] FAILED: Script returned null")
	quit(0 if script else 1)

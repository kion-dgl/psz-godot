extends SceneTree
## Export the reusable authored model for inspection in the Three.js lab.
func _initialize() -> void:
	call_deferred("_export")

func _export() -> void:
	var lantern := preload("res://scenes/props/shrine_lantern.tscn").instantiate()
	root.add_child(lantern)
	await process_frame
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_scene(lantern, state)
	if error == OK:
		error = document.write_to_filesystem(state, "res://assets/stages/shrine_b/s07b_ga1/lndmd/shrine_lantern_preview.glb")
	print("[LanternExport] result: %d" % error)
	lantern.free()
	quit(0 if error == OK else 1)

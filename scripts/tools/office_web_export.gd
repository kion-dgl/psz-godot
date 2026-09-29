extends SceneTree
## Export the current procedural room for the browser inspection page.
## godot --headless --path . --script res://scripts/tools/office_web_export.gd

func _initialize() -> void:
	_export.call_deferred()


func _export() -> void:
	var room := Node3D.new()
	room.name = "PrincipalOffice"
	root.add_child(room)
	load("res://scripts/3d/city/office_library_room.gd").build(room)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_scene(room, state)
	if result == OK:
		var folder := ProjectSettings.globalize_path("res://web/public/office-preview")
		DirAccess.make_dir_recursive_absolute(folder)
		result = document.write_to_filesystem(state, folder.path_join("room.glb"))
	if result != OK:
		push_error("Office export failed: %s" % error_string(result))
	else:
		print("[office-preview] Exported current room to web/public/office-preview/room.glb")
	room.queue_free()
	quit(0 if result == OK else 1)

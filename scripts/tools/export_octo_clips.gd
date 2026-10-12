extends SceneTree
## Reproduce with -- <asset-viewer/public/enemies/boss_octopus>.
## Meshes stay in the existing pack; corrected small clip libraries ship in app.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected asset-viewer boss_octopus directory")
		quit(1)
		return
	for part in ["z_002_tt","z_002_st"]:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var path := args[0].path_join("parts/%s/%s.glb" % [part,part])
		if document.append_from_file(path,state) != OK:
			quit(1)
			return
		var scene := document.generate_scene(state)
		var player := NodeUtils.first_of_type(scene,"AnimationPlayer") as AnimationPlayer
		var library := AnimationLibrary.new()
		for clip in player.get_animation_list():
			if clip == "RESET": continue
			var animation := player.get_animation(clip).duplicate(true) as Animation
			library.add_animation(clip,animation)
		var result := ResourceSaver.save(library,"res://data/boss_animations/%s.tres" % part)
		print("[octo-clips] %s clips=%d save=%d" % [part,library.get_animation_list().size(),result])
		scene.free()
	quit()

extends SceneTree
## Reproduce with -- <asset-viewer/public/enemies/boss_robot>.
## Meshes stay in the existing pack; corrected small clip libraries ship in app.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected asset-viewer boss_robot directory")
		quit(1)
		return
	for part in ["z_003u","z_003n"]:
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
			if part == "z_003u":
				# Shipped combined-archive split rig lacks the unused put02 joint.
				for track in range(animation.get_track_count()-1,-1,-1):
					var path_string := str(animation.track_get_path(track))
					if path_string.ends_with(":put02"): animation.remove_track(track)
					else: animation.track_set_path(track,NodePath(path_string.replace("z_003u/","z_103u/")))
			library.add_animation(clip,animation)
		var result := ResourceSaver.save(library,"res://data/boss_animations/paru_%s.tres" % part)
		print("[robot-clips] %s clips=%d save=%d" % [part,library.get_animation_list().size(),result])
		scene.free()
	quit()

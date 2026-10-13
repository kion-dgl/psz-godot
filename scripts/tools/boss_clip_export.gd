extends RefCounted
## Preserve every source track when exporting a standalone boss animation library.
static func save_library(path: String, output: String) -> Error:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path,state)
	if error != OK: return error
	var scene := document.generate_scene(state)
	var player := NodeUtils.first_of_type(scene,"AnimationPlayer") as AnimationPlayer
	if not player:
		scene.free()
		return ERR_INVALID_DATA
	var library := AnimationLibrary.new()
	for clip in player.get_animation_list():
		if clip == "RESET": continue
		library.add_animation(clip,player.get_animation(clip).duplicate(true))
	var result := ResourceSaver.save(library,output)
	print("[boss-clips] %s clips=%d save=%d" % [output,library.get_animation_list().size(),result])
	scene.free()
	return result

static func run(args: PackedStringArray, parts: Array, folder: String, prefix: String) -> int:
	if args.size() != 1:
		push_error("Expected directory containing boss GLB parts")
		return 1
	for part in parts:
		var path := args[0].path_join(folder).path_join("%s/%s.glb" % [part,part])
		if save_library(path,"res://data/boss_animations/%s%s.tres" % [prefix,part]) != OK:
			return 1
	return 0

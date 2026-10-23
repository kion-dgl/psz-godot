extends Node3D
## Meshy biped preview lab — render GLBs (absolute filesystem paths, so
## pre-import candidates can be inspected) side by side and screenshot them
## for visual checks. Companion to the counter NPC mesh swap: the same tool
## verifies the retargeted Mixamo clips once baked (lib playback + seek).
##
## Env:  PSZ_PREVIEW_PATHS=/a.glb,/b.glb  models to load (comma separated)
##       PSZ_PREVIEW_SHOT=/tmp/o.png      screenshot + quit (smoke; else idle)
##       PSZ_PREVIEW_LIB=/tmp/lib.glb     anim-lib GLB (CityNPC source shape)
##       PSZ_PREVIEW_ANIM=clip_name       clip to remap onto every model
##       PSZ_PREVIEW_SEEK=1.5             seconds to seek before the shot
##       PSZ_PREVIEW_CAM_Y=0.65           camera target height (default 0.85)
##       PSZ_PREVIEW_DIST=2.6             camera distance (default 2.6)

const CAMERA_TARGET := Vector3(0, 0.85, 0)
const SPACING := 1.2


func _ready() -> void:
	var paths := OS.get_environment("PSZ_PREVIEW_PATHS").split(",", false)
	var shot := OS.get_environment("PSZ_PREVIEW_SHOT")
	var lib_path := OS.get_environment("PSZ_PREVIEW_LIB")
	var anim_name := OS.get_environment("PSZ_PREVIEW_ANIM")
	var seek_t := float(OS.get_environment("PSZ_PREVIEW_SEEK")) if OS.get_environment("PSZ_PREVIEW_SEEK") != "" else 0.0

	_setup_env()

	var models: Array[Node] = []
	for i in range(paths.size()):
		var model := _load_glb(paths[i].strip_edges())
		if not model:
			continue
		add_child(model)
		model.position.x = (i - float(paths.size() - 1) / 2.0) * SPACING
		models.append(model)

	var camera := Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	var cam_target := Vector3(0, 0.85, 0)
	if OS.get_environment("PSZ_PREVIEW_CAM_Y") != "":
		cam_target.y = float(OS.get_environment("PSZ_PREVIEW_CAM_Y"))
	var cam_dist := 2.6
	if OS.get_environment("PSZ_PREVIEW_DIST") != "":
		cam_dist = float(OS.get_environment("PSZ_PREVIEW_DIST"))
	camera.position = cam_target + Vector3(0, 0.1, cam_dist)
	camera.look_at(cam_target)

	if not lib_path.is_empty() and not anim_name.is_empty():
		for model in models:
			_play_from_lib(model, lib_path, anim_name, seek_t)

	if shot.is_empty():
		return
	# Let the seeked pose (and textures) land before capturing.
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot)
	print("[meshy_preview] wrote %s (%dx%d)" % [shot, img.get_width(), img.get_height()])
	get_tree().quit()


func _setup_env() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.44, 0.48)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.ambient_light_energy = 1.0
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.1
	add_child(sun)
	sun.rotation_degrees = Vector3(-35, -30, 0)


func _load_glb(path: String) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("[meshy_preview] GLTF load failed %d: %s" % [err, path])
		return null
	print("[meshy_preview] loaded %s (anims: %s)" % [path, state.animations.map(func(a): return a.resource_name)])
	return doc.generate_scene(state)


## Mirrors CityNPC._setup_idle_anim: duplicate the clip, retarget its track
## paths from the lib's skeleton onto this model's skeleton, play + seek.
func _play_from_lib(model: Node, lib_path: String, anim_name: String, seek_t: float) -> void:
	var lib_scene := _load_glb(lib_path)
	if not lib_scene:
		return
	var src_player: AnimationPlayer = _find_typed(lib_scene, "AnimationPlayer") as AnimationPlayer
	var skel: Skeleton3D = _find_typed(model, "Skeleton3D") as Skeleton3D
	if not src_player or not skel or not src_player.has_animation(anim_name):
		push_warning("[meshy_preview] anim '%s' not found in %s" % [anim_name, lib_path])
		lib_scene.queue_free()
		return
	var anim := src_player.get_animation(anim_name).duplicate()
	anim.loop_mode = Animation.LOOP_LINEAR
	for i in range(anim.get_track_count()):
		var track_path := String(anim.track_get_path(i))
		if "Skeleton3D" in track_path:
			var skel_idx := track_path.find("Skeleton3D")
			anim.track_set_path(i, NodePath(skel.name + track_path.substr(skel_idx + 10)))
	lib_scene.queue_free()

	var player := AnimationPlayer.new()
	player.name = "PreviewAnimPlayer"
	skel.get_parent().add_child(player)
	var lib := AnimationLibrary.new()
	lib.add_animation(anim_name, anim)
	player.add_animation_library("", lib)
	player.play(anim_name)
	player.seek(seek_t, true)
	print("[meshy_preview] playing %s (seek %.2fs) on skeleton %s" % [anim_name, seek_t, skel.name])


func _find_typed(root: Node, type_name: String) -> Node:
	if root.get_class() == type_name:
		return root
	for child in root.get_children():
		var found := _find_typed(child, type_name)
		if found:
			return found
	return null

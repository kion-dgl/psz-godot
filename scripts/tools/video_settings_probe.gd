extends SceneTree
## Run in a disposable user-data namespace; creates a preview character.
## Optional PSZ_VIDEO_CAPTURE_DIR captures each aspect at native render scale.
var failures := 0
func _initialize():
	call_deferred("run")
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func run():
	var video := root.get_node("VideoSettings")
	var mobile := root.get_node("MobileControls")
	mobile._activate()
	var chars := root.get_node("CharacterManager")
	chars.create_character(0, "humar", "VideoPreview")
	chars.set_active_slot(0)
	var city: Node3D = load("res://scenes/3d/city/city_market.tscn").instantiate()
	root.add_child(city)
	current_scene = city
	await create_timer(0.5).timeout
	var menu := root.get_node("PsoStartMenu")
	menu.open()
	menu._mode = menu.Mode.OPTIONS
	menu._options_idx = 9
	for aspect in 4:
		video.aspect_index = aspect
		for scale in 5:
			video.scale_index = scale
			video.apply()
			menu._canvas.queue_redraw()
			await process_frame
			await process_frame
			var size := root.get_visible_rect().size
			check(menu._canvas.size.is_equal_approx(size), "Start menu canvas fills active viewport")
			var expected: float = float(root.size.x) / root.size.y if aspect == 0 else float(video.ASPECT_SIZES[aspect].x) / video.ASPECT_SIZES[aspect].y
			check(abs(size.x / size.y - expected) < 0.002, "aspect matches selection")
			check(is_equal_approx(root.scaling_3d_scale, video.SCALES[scale]), "render scale applied")
			check(mobile._dpad.position.is_equal_approx(Vector2(180, size.y - 180)), "dpad follows aspect change")
			for item in mobile._layout_items:
				check(Rect2(Vector2.ZERO, size).has_point(item.node.position), "touch target inside viewport")
			if scale == 2:
				await create_timer(0.25).timeout
				await RenderingServer.frame_post_draw
				var captures := OS.get_environment("PSZ_VIDEO_CAPTURE_DIR")
				if not captures.is_empty():
					DirAccess.make_dir_recursive_absolute(captures)
					root.get_texture().get_image().save_png(captures.path_join("aspect-%d.png" % aspect))
		print("VIDEO combination PASS aspect=", aspect)
	video.aspect_index = 0
	video.scale_index = 2
	video.apply()
	video.save_settings()
	print("VIDEO CHECK failures=", failures)
	quit(1 if failures else 0)

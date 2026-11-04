extends RefCounted

static func run(t: Node) -> void:
	var video := t.get_node("/root/VideoSettings")
	var old_aspect: int = video.aspect_index
	var old_scale: int = video.scale_index
	var existed := FileAccess.file_exists(video.SETTINGS_PATH)
	var saved := FileAccess.get_file_as_bytes(video.SETTINGS_PATH) if existed else PackedByteArray()
	var cfg := ConfigFile.new()
	cfg.set_value("video", "crt_mode", "scanlines")
	cfg.set_value("video", "aspect", "unknown")
	cfg.set_value("video", "render_scale", "invalid")
	cfg.save(video.SETTINGS_PATH)
	video.load_settings()
	t.assert_eq(video.aspect_index, 0, "unknown aspect falls back to device")
	t.assert_eq(video.scale_index, 2, "invalid scale falls back to native")
	video.cycle_aspect(-1)
	t.assert_eq(video.aspect_label(), "21:9", "aspect cycles backward with wrap")
	video.cycle_scale(1)
	t.assert_almost_eq(t.get_tree().root.scaling_3d_scale, 1.5, 0.001, "render scale applies to 3D")
	cfg.load(video.SETTINGS_PATH)
	t.assert_eq(cfg.get_value("video", "crt_mode"), "scanlines", "video saves preserve CRT setting")
	video.aspect_index = 0
	video.scale_index = 0
	video.load_settings()
	t.assert_eq(video.aspect_index, 3, "aspect persists")
	t.assert_eq(video.scale_index, 3, "render scale persists")
	var menu := t.get_node("/root/PsoStartMenu")
	menu._toggle_option(8)
	t.assert_eq(video.aspect_index, 0, "Options Accept wraps aspect to device")
	menu._toggle_option(9)
	t.assert_eq(video.scale_index, 4, "Options Accept advances render scale")
	var router: StartMenuInput = menu.get("_input")
	var old_row: int = menu._options_idx
	menu._options_idx = 9
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	router._input_options(right)
	t.assert_eq(video.scale_index, 0, "Options Right wraps maximum render scale")
	var left := InputEventAction.new()
	left.action = "ui_left"
	left.pressed = true
	router._input_options(left)
	t.assert_eq(video.scale_index, 4, "Options Left wraps back to maximum")
	menu._options_idx = 8
	router._input_options(left)
	t.assert_eq(video.aspect_index, 3, "Options Left cycles aspect backward")
	menu._options_idx = old_row
	var preview := SubViewport.new()
	t.add_child(preview)
	t.assert_almost_eq(preview.scaling_3d_scale, 2.0, 0.001, "new 3D previews inherit render scale")
	preview.free()
	video.aspect_index = old_aspect
	video.scale_index = old_scale
	video.apply()
	if existed:
		var file := FileAccess.open(video.SETTINGS_PATH, FileAccess.WRITE)
		file.store_buffer(saved)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(video.SETTINGS_PATH))

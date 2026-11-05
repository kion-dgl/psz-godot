extends Node
## Device-wide display preferences; UI remains at native resolution.
const SETTINGS_PATH := "user://video_settings.cfg"
const ASPECT_IDS := ["device", "4:3", "16:9", "21:9"]
const ASPECT_LABELS := ["Fit to device", "4:3", "16:9", "21:9"]
const ASPECT_SIZES := [Vector2i(1280, 720), Vector2i(1280, 960), Vector2i(1280, 720), Vector2i(1680, 720)]
const SCALES := [0.5, 0.75, 1.0, 1.5, 2.0]
var aspect_index := 0
var scale_index := 2

func _ready() -> void:
	load_settings()
	apply()
	get_tree().node_added.connect(_on_node_added)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	aspect_index = maxi(0, ASPECT_IDS.find(str(cfg.get_value("video", "aspect", "device"))))
	var saved_scale = cfg.get_value("video", "render_scale", 1.0)
	scale_index = SCALES.find(saved_scale) if saved_scale is float or saved_scale is int else -1
	if scale_index < 0: scale_index = 2

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("video", "aspect", ASPECT_IDS[aspect_index])
	cfg.set_value("video", "render_scale", SCALES[scale_index])
	cfg.save(SETTINGS_PATH)

func cycle_aspect(step: int = 1) -> void:
	aspect_index = wrapi(aspect_index + step, 0, ASPECT_IDS.size())
	apply()
	save_settings()

func cycle_scale(step: int = 1) -> void:
	scale_index = wrapi(scale_index + step, 0, SCALES.size())
	apply()
	save_settings()

func apply() -> void:
	var window := get_tree().root
	window.content_scale_size = ASPECT_SIZES[aspect_index]
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if aspect_index == 0 else Window.CONTENT_SCALE_ASPECT_KEEP
	_apply_scale(window)

func _apply_scale(node: Node) -> void:
	if node is Viewport:
		node.scaling_3d_scale = SCALES[scale_index]
	for child in node.get_children():
		_apply_scale(child)

func _on_node_added(node: Node) -> void:
	if node is Viewport:
		node.scaling_3d_scale = SCALES[scale_index]

func aspect_label() -> String:
	return ASPECT_LABELS[aspect_index]

func scale_label() -> String:
	return "%sx%s" % [str(SCALES[scale_index]), " (Native)" if scale_index == 2 else ""]

func render_size() -> Vector2i:
	var window := get_tree().root
	var logical := window.get_visible_rect().size
	var pixels := Vector2(window.size)
	var fit := minf(pixels.x / logical.x, pixels.y / logical.y)
	return Vector2i((logical * fit * float(SCALES[scale_index])).floor())

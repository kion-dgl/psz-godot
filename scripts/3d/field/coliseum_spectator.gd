extends RefCounted
## Quiet gallery spectators. Contract: /mechanics/coliseum-spectators.
const HEIGHT := 3.3
const ALPHA_THRESHOLD := 0.5
const IDLE_DURATIONS := [2.4, 0.6, 0.12, 0.6]
static var _frames_cache: Dictionary = {}

static func add_to_stage(stage: Node3D, stage_id: String) -> void:
	if stage_id != "s00a_nr2": return
	_add(stage, "KionSpectator", "res://assets/easter_eggs/kion_spectator.png",
		Vector3(-12.3, 4.0, -24.6), 1.0, 0)
	_add(stage, "RosalineSpectator", "res://assets/easter_eggs/rosaline_spectator.png",
		Vector3(14.35, 4.0, 22.55), 0.8, 1)

static func _add(stage: Node3D, spectator_name: String, texture_path: String, position: Vector3, size_multiplier: float, phase: int) -> void:
	var sheet_path := texture_path.replace("_spectator.png", "_idle.png")
	var columns := 4 if ResourceLoader.exists(sheet_path) else 1
	var path := sheet_path if columns == 4 else texture_path
	if not ResourceLoader.exists(path): return
	var frames := make_frames(load(path) as Texture2D, columns)
	var spectator := AnimatedSprite3D.new()
	var height := HEIGHT * size_multiplier
	spectator.name = spectator_name
	spectator.sprite_frames = frames
	spectator.pixel_size = height / maxf(frames.get_frame_texture("idle", 0).get_height(), 1.0)
	spectator.position = position + Vector3.UP * height * 0.5
	spectator.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	spectator.rotation.y = atan2(-position.x, -position.z)
	spectator.modulate = Color(0.72, 0.70, 0.68, 1.0)
	spectator.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spectator.alpha_scissor_threshold = ALPHA_THRESHOLD
	spectator.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	spectator.no_depth_test = false
	spectator.shaded = false
	stage.add_child(spectator)
	spectator.play("idle")
	spectator.set_frame_and_progress(phase % columns, 0.0)

## Crop each cell to the alpha-cutout bounds, then pad to a shared canvas.
## The atlas margins anchor every pair of feet at the same bottom baseline.
static func make_frames(texture: Texture2D, columns: int) -> SpriteFrames:
	var key := "%d:%d" % [texture.get_instance_id(), columns]
	if _frames_cache.has(key): return _frames_cache[key]
	var image := texture.get_image()
	var cell_width := image.get_width() / columns
	var regions: Array[Rect2i] = []
	var canvas := Vector2i.ZERO
	for index in columns:
		var cell := Rect2i(index * cell_width, 0, cell_width, image.get_height())
		var bounds := _visible_bounds(image, cell)
		regions.append(bounds)
		canvas = canvas.max(bounds.size)
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 1.0)
	for index in columns:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = regions[index]
		var padding := Vector2(canvas - regions[index].size)
		atlas.margin = Rect2(Vector2(floorf(padding.x * 0.5), padding.y), padding)
		frames.add_frame("idle", atlas, IDLE_DURATIONS[index % IDLE_DURATIONS.size()])
	_frames_cache[key] = frames
	return frames

static func _visible_bounds(image: Image, cell: Rect2i) -> Rect2i:
	var low := cell.end
	var high := Vector2i(-1, -1)
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	return Rect2i(low, high - low + Vector2i.ONE) if high.x >= 0 else cell

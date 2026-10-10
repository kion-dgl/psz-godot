extends RefCounted
## Quiet, widely separated spectators behind the balcony rails. Face the arena, not the camera.
const HEIGHT := 3.3
const ALPHA_THRESHOLD := 0.5
static var _bounds_cache: Dictionary = {}

static func add_to_stage(stage: Node3D, stage_id: String) -> void:
	if stage_id != "s00a_nr2": return
	_add(stage, "KionSpectator", "res://assets/easter_eggs/kion_spectator.png",
		Vector3(-12.3, 4.0, -24.6), true)
	_add(stage, "RosalineSpectator", "res://assets/easter_eggs/rosaline_spectator.png",
		Vector3(14.35, 4.0, 22.55), true, 0.8)

static func _add(stage: Node3D, spectator_name: String, texture_path: String, position: Vector3, pixel_art: bool, size_multiplier: float = 1.0) -> void:
	if not ResourceLoader.exists(texture_path): return
	var texture := load(texture_path) as Texture2D
	var height := HEIGHT * size_multiplier
	var spectator := Sprite3D.new()
	spectator.name = spectator_name
	spectator.texture = texture
	var bounds := _visible_bounds(texture)
	spectator.region_enabled = true
	spectator.region_rect = bounds
	spectator.pixel_size = height / maxf(bounds.size.y, 1.0)
	spectator.position = position + Vector3.UP * height * 0.5
	spectator.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	spectator.rotation.y = atan2(-position.x, -position.z)
	spectator.modulate = Color(0.72, 0.70, 0.68, 1.0)
	spectator.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spectator.alpha_scissor_threshold = ALPHA_THRESHOLD
	spectator.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS if pixel_art else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	spectator.no_depth_test = false
	spectator.shaded = false
	stage.add_child(spectator)

## Generated PNGs can contain faint alpha specks far outside the visible character.
## Match the renderer's cutout threshold rather than Image.get_used_rect's nonzero alpha.
static func _visible_bounds(texture: Texture2D) -> Rect2i:
	var key := texture.get_instance_id()
	if _bounds_cache.has(key): return _bounds_cache[key]
	var image := texture.get_image()
	var low := image.get_size()
	var high := Vector2i(-1, -1)
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				low = low.min(Vector2i(x, y))
				high = high.max(Vector2i(x, y))
	var bounds := Rect2i(low, high - low + Vector2i.ONE) if high.x >= 0 else Rect2i(Vector2i.ZERO, image.get_size())
	_bounds_cache[key] = bounds
	return bounds

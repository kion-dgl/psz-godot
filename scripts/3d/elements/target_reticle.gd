extends RefCounted
class_name TargetReticle
## Shared builder for the red downward-triangle reticle shown above a target
## when the player is locked onto it. The Sprite3D + triangle texture were
## duplicated verbatim in enemy_base / enemy_spawn / box (#517); only the
## vertical offset differed, so callers pass that in.

## Build the reticle sprite. `y_offset` is the local height above the target's
## origin (typically collision height + 0.5). Caller add_child()s the result.
static func build(y_offset: float) -> Sprite3D:
	var reticle := Sprite3D.new()
	reticle.name = "TargetReticle"
	reticle.pixel_size = 0.008
	reticle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	reticle.no_depth_test = true
	reticle.modulate = Color(1.0, 0.15, 0.15, 0.9)
	reticle.visible = false

	# Filled downward-pointing triangle: top row full width, narrowing to a point.
	var size := 48
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half: int = size / 2
	for y in range(size):
		var progress: float = float(y) / float(size - 1)
		var half_width: int = int(float(half) * (1.0 - progress))
		for x in range(half - half_width, half + half_width + 1):
			if x >= 0 and x < size:
				img.set_pixel(x, y, Color.WHITE)
	reticle.texture = ImageTexture.create_from_image(img)
	reticle.position = Vector3(0, y_offset, 0)
	return reticle

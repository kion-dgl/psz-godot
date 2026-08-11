extends RefCounted
class_name TargetReticle
## Shared builder for the lock-on reticle shown above a target. The Sprite3D +
## triangle texture were duplicated verbatim in enemy_base / enemy_spawn / box
## (#517); only the vertical offset differed, so callers pass that in.
##
## The triangle used to be drawn procedurally into an ImageTexture. It is now
## the game's own model (#577): `ef_com_rockon` plus `ef_com_rockon_s`.
##
## Those two are an OUTLINE PAIR, not variants — the geometry says so rather
## than the naming. `_s` is smaller (x +/-0.073 against +/-0.104), concentric
## with the larger one, and sits IN FRONT of it (z 0.024 against 0.008). The
## larger model carries all-black vertex colours; the smaller carries no
## COLOR_0 at all and so renders white. Black border behind, white fill in
## front — which is also why loading either one alone looks wrong.

const OUTLINE_MODEL := "ef_com_rockon"
const FILL_MODEL := "ef_com_rockon_s"

## Fallback triangle size, used only when the models cannot be loaded.
const FALLBACK_PX := 48


## Build the reticle. `y_offset` is the local height above the target's origin
## (typically collision height + 0.5). Caller add_child()s the result and drives
## `visible`. Returns a Node3D — it used to be a Sprite3D, and callers that
## still type it that way will not compile.
static func build(y_offset: float) -> Node3D:
	var root := Node3D.new()
	root.name = "TargetReticle"
	root.visible = false
	root.position = Vector3(0, y_offset, 0)

	# ORIENTATION IS UNRESOLVED. The models are authored pointing UP, while the
	# sprite they replace pointed DOWN at the target it hangs above.
	#
	# Both ways of flipping it fail: BILLBOARD_ENABLED replaces the node basis
	# with the camera's, so rotating the node moves the offset without turning
	# the quad, and a negative Y scale reverses the winding so the quad vanishes.
	# Flipping it properly means flipping the geometry or hand-billboarding.
	#
	# Left as authored rather than guessed at — it may well be that the original
	# pins this BELOW the target, in which case pointing up is already right and
	# only the attach point is wrong. Worth one look at the real game.
	# Draw order matters: both quads disable depth testing so they read through
	# the target, which means the painter's order is all that separates them.
	var outline := EffectBillboard.load_model(OUTLINE_MODEL, 0)
	var fill := EffectBillboard.load_model(FILL_MODEL, 1)
	if outline and fill:
		root.add_child(outline)
		root.add_child(fill)
		return root

	# The models live in the asset pack; if it is missing we still want a
	# visible reticle rather than an invisible node the player cannot aim with.
	if outline:
		outline.queue_free()
	if fill:
		fill.queue_free()
	root.add_child(_fallback_sprite())
	return root


## The pre-#577 procedural triangle, kept as a pack-free fallback.
static func _fallback_sprite() -> Sprite3D:
	var reticle := Sprite3D.new()
	reticle.name = "FallbackTriangle"
	reticle.pixel_size = 0.008
	reticle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	reticle.no_depth_test = true
	reticle.modulate = Color(1.0, 0.15, 0.15, 0.9)

	# Filled downward-pointing triangle: top row full width, narrowing to a point.
	var size := FALLBACK_PX
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
	return reticle

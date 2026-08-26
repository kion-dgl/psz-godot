extends RefCounted
class_name TargetReticle
## Shared builder for the lock-on reticle. The Sprite3D + single triangle
## texture were duplicated verbatim in enemy_base / enemy_spawn / box (#517);
## only the vertical offset differed, so callers pass that in.
##
## The reticle is THREE TRIANGLES AROUND A CENTER POINT — the original's
## lock-on shape, read off the real game in play: three small triangles spaced
## 120° apart, each pointing inward at the target's centre. #577 briefly used
## the pack's ef_com_rockon outline/fill pair, but that pair is a SINGLE
## triangle and the models are absent from the asset manifests anyway, so the
## shape is drawn procedurally here. When the effect models land in the pack,
## compare against ef_com_rockon before replacing this.

## Texture pixel size for the fallback sprite.
const FALLBACK_PX := 96

## Distance from texture centre to a triangle's apex (pointing inward) and to
## its base, in fractions of the half-size.
const APEX_RADIUS := 0.16
const BASE_RADIUS := 0.42
## Half-width of each triangle's base, as a fraction of the half-size.
const BASE_HALF_WIDTH := 0.14


## Build the reticle. `y_offset` is the local height above the target's origin
## where the reticle centre sits — over the body centre for a wall, above the
## head for an enemy. Caller add_child()s the result and drives `visible`.
## Returns a Node3D — it used to be a Sprite3D, and callers that still type it
## that way will not compile.
static func build(y_offset: float) -> Node3D:
	var root := Node3D.new()
	root.name = "TargetReticle"
	root.visible = false
	root.position = Vector3(0, y_offset, 0)

	var reticle := Sprite3D.new()
	reticle.name = "ThreeTriangleReticle"
	reticle.pixel_size = 0.008
	reticle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	reticle.no_depth_test = true
	reticle.modulate = Color(1.0, 0.15, 0.15, 0.9)
	reticle.texture = _three_triangle_texture()
	root.add_child(reticle)
	return root


## Three inward-pointing triangles, 120° apart, around a transparent centre.
static func _three_triangle_texture() -> ImageTexture:
	var size := FALLBACK_PX
	var half := size / 2.0
	var center := Vector2(half, half)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for k in range(3):
		var angle := TAU * float(k) / 3.0 - PI / 2.0
		var dir := Vector2(cos(angle), sin(angle))
		var perp := Vector2(-dir.y, dir.x)
		# Apex points at the centre; the base sits further out.
		var apex := center + dir * (half * APEX_RADIUS)
		var b1 := center + dir * (half * BASE_RADIUS) + perp * (half * BASE_HALF_WIDTH)
		var b2 := center + dir * (half * BASE_RADIUS) - perp * (half * BASE_HALF_WIDTH)
		_fill_triangle(img, apex, b1, b2)

	return ImageTexture.create_from_image(img)


## Rasterize one white triangle (the Sprite3D's modulate carries the colour).
static func _fill_triangle(img: Image, a: Vector2, b: Vector2, c: Vector2) -> void:
	var min_x := int(floor(minf(a.x, minf(b.x, c.x))))
	var max_x := int(ceil(maxf(a.x, maxf(b.x, c.x))))
	var min_y := int(floor(minf(a.y, minf(b.y, c.y))))
	var max_y := int(ceil(maxf(a.y, maxf(b.y, c.y))))
	var area := _edge(a, b, c)
	if absf(area) < 0.0001:
		return
	for y in range(maxi(min_y, 0), mini(max_y, img.get_height() - 1) + 1):
		for x in range(maxi(min_x, 0), mini(max_x, img.get_width() - 1) + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			# Same-side test against all three edges, robust to winding.
			if _edge(a, b, p) * area >= 0.0 and _edge(b, c, p) * area >= 0.0 \
					and _edge(c, a, p) * area >= 0.0:
				img.set_pixel(x, y, Color.WHITE)


static func _edge(a: Vector2, b: Vector2, p: Vector2) -> float:
	return (p.x - a.x) * (b.y - a.y) - (p.y - a.y) * (b.x - a.x)

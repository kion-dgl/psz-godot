class_name PszPanel
## The PSZ HUD plate language (spec /mechanics/targeting): a chamfered plate
## with horizontal pinstripes and a navy border — light-blue variant for the
## target-info panel, navy variant for the quick weapon menu. Static draw
## helpers for use inside a Control's _draw().

const BORDER := Color(0.10, 0.16, 0.29)        # navy edge
const LIGHT_A := Color(0.72, 0.83, 0.92)       # light plate stripes
const LIGHT_B := Color(0.66, 0.78, 0.88)
const DARK_A := Color(0.16, 0.24, 0.39, 0.94)  # dark plate stripes
const DARK_B := Color(0.13, 0.20, 0.34, 0.94)
const TEXT_DARK := Color(0.09, 0.15, 0.29)     # text on the light plate
const TEXT_LIGHT := Color(0.72, 0.82, 0.94)    # text on the dark plate

const CHAMFER := 10.0     # corner cut
const TAB := 24.0         # the larger bottom-right cut of the PSZ plate


## Chamfered outline polygon for a plate of the given size.
static func outline(size: Vector2) -> PackedVector2Array:
	var w := size.x
	var h := size.y
	return PackedVector2Array([
		Vector2(CHAMFER, 0), Vector2(w - CHAMFER, 0), Vector2(w, CHAMFER),
		Vector2(w, h - TAB * 0.66), Vector2(w - TAB, h),
		Vector2(CHAMFER, h), Vector2(0, h - CHAMFER), Vector2(0, CHAMFER),
	])


## Horizontal extents (left, right) of the plate interior at height y —
## piecewise-linear along the chamfered corners, used to clip the stripes.
static func _extent(size: Vector2, y: float) -> Vector2:
	var w := size.x
	var h := size.y
	var left := 0.0
	if y < CHAMFER:
		left = CHAMFER - y
	elif y > h - CHAMFER:
		left = y - (h - CHAMFER)
	var right := w
	if y < CHAMFER:
		right = w - (CHAMFER - y)
	elif y > h - TAB * 0.66:
		var t := (y - (h - TAB * 0.66)) / maxf(TAB * 0.66, 0.001)
		right = w - TAB * t
	return Vector2(left, right)


## Draw the full plate: navy border polygon with the striped fill inset 2 px.
static func draw_plate(ci: CanvasItem, size: Vector2, dark: bool) -> void:
	ci.draw_colored_polygon(outline(size), BORDER)
	var stripe_a := DARK_A if dark else LIGHT_A
	var stripe_b := DARK_B if dark else LIGHT_B
	var y := 2.0
	var idx := 0
	while y < size.y - 2.0:
		var band := minf(3.0, size.y - 2.0 - y)
		var top := _extent(size, y)
		var bottom := _extent(size, y + band)
		var left := maxf(top.x, bottom.x) + 2.0
		var right := minf(top.y, bottom.y) - 2.0
		if right > left:
			ci.draw_rect(Rect2(left, y, right - left, band), stripe_a if idx % 2 == 0 else stripe_b)
		y += band
		idx += 1

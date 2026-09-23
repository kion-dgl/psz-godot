class_name StartMenuMainSkin
extends Control
## PSO-BB "Flauros" redesign of the start menu's MAIN page.
## Visual contract: skeleton/game_menu_redesign/ (React/Vite mock on a fixed
## 1920x1080 stage). Every layout value below is the mock's stage-space
## value; SCALE converts it to the project's 1280x720 viewport (exactly 2/3).
##
## Node-based on purpose: the legacy StartMenuRenderer paints sub-modes in
## immediate mode on the canvas, but the mock's staggered entry, cursor pulse
## and swap animations want Tweens, and its rows want mouse hover/click —
## both are cheap as child Controls. PsoStartMenu attaches this on open()
## while Mode.MAIN is active and hides it when a sub-mode takes over; the
## renderer skips its own painting while the skin is visible.

const SCALE := 2.0 / 3.0

## Project base viewport (project.godot stretch is canvas_items, so UI
## coordinates are always 1280x720 regardless of window size). The skin sets
## explicit sizes instead of relying on anchors: the legacy _canvas Control
## under the CanvasLayer is never actually laid out (immediate-mode drawing
## with absolute coordinates never needed it).
const VIEW_W := 1280.0
const VIEW_H := 720.0

# Repo-committed (bootstrap/) so the preload is safe pre-pack — the same
# class-scope-preload rule the renderer's MENU_FONT comment documents.
const FONT: Font = preload("res://bootstrap/fonts/VT323-Regular.ttf")

# ── Mock palette (exact values from the React components) ──────────────────────
const C_STAGE := Color("#ffffff")
## Deviations from the mock (playtest feedback, 2026-09-22): the mock's
## opaque white stage is gone entirely — the start menu is a non-pausing
## overlay, so only the blue octagon L (left strip + bottom band) and the
## chamfered panels paint over the game. Round 4 also dropped the mock's
## name panel (the persistent HudStats plate owns that corner, on top) and
## the footer key guide, and moved the stats window to the far right.
const STAGE_ALPHA := 0.82
const C_FRAME_TOP := Color("#c8dbf5")
const C_FRAME_MID := Color("#b6d0ee")
const C_FRAME_BOT := Color("#9dbde6")
const C_CONTOUR := Color("#274676")
const C_INNER_NAVY := Color("#2e4d7d")
const C_SCAN_WHITE := Color(1.0, 1.0, 1.0, 0.42)
const C_SCAN_NAVY := Color(0x20 / 255.0, 0x40 / 255.0, 0x70 / 255.0, 0.08)
const C_PAPER := Color("#f8fafd")
const C_PAPER_RULE := Color("#dbe5f2")
const C_SKY := Color("#cfe0f6")
const C_SKY_RULE := Color("#b9d1ee")
const C_TEXT := Color("#121212")
const C_TEXT_STATS := Color("#111111")
const C_TEXT_DISABLED := Color("#a4a4a4")
const C_STRIP_BG := Color("#c5d9f0")
const C_OCT := Color(1.0, 1.0, 1.0, 0.48)
const C_SEL_TOP_INSET := Color("#ffeaa8")
const C_SEL_BOT_INSET := Color("#b35900")
const C_SEL_GLOW := Color(0.969, 0.647, 0.165, 0.45)  # rgba(247,165,42,.45)
const C_HP_TRACK := Color("#133525")
const C_RING_WHITE := Color("#ffffff")
const C_RING_NAVY := Color("#243c68")
const C_STAR_FILL := Color("#ffd738")
const C_STAR_STROKE := Color("#423004")
const C_SHOULDER_BG := Color("#0d0d0d")
const C_SHOULDER_RING := Color("#1a2a44")
const C_ARROW_FILL := Color("#3bd57d")
const C_ARROW_HOVER := Color("#7af3a9")
const C_ARROW_STROKE := Color("#0d3521")

# ── Mock typography, scaled ────────────────────────────────────────────────────
const FS_MAIN := 32       # mock 48px body text
const FS_COUNTER := 29    # mock 44px page counter
const FS_SHOULDER := 28   # mock 42px L/R key labels

# ── Mock layout (stage-space values, scaled on use) ────────────────────────────
const NAME_POS := Vector2(32, 48)
const NAME_SIZE := Vector2(335, 114)
static var NAME_OUTER := PackedVector2Array([Vector2(22, 0), Vector2(215, 0), Vector2(228, 14), Vector2(228, 24), Vector2(332, 24), Vector2(296, 112), Vector2(24, 112), Vector2(0, 88), Vector2(0, 22)])
static var NAME_INNER := PackedVector2Array([Vector2(10, 34), Vector2(322, 34), Vector2(290, 102), Vector2(10, 102)])
const STAR_POS := Vector2(58, 4)
const STAR_SIZE := 22.0
const ORB_POS := Vector2(14, 38)
const ORB_SIZE := 42.0
const MENU_POS := Vector2(32, 172)
const MENU_SIZE := Vector2(215, 546)
static var MENU_OUTER := PackedVector2Array([Vector2(6, 0), Vector2(209, 0), Vector2(215, 6), Vector2(215, 516), Vector2(187, 546), Vector2(28, 546), Vector2(0, 518), Vector2(0, 6)])
static var MENU_INNER := PackedVector2Array([Vector2(12, 10), Vector2(203, 10), Vector2(203, 508), Vector2(12, 508)])
const ROW_X := 14.0
const ROW_Y := 12.0
const ROW_W := 187.0
const ROW_H := 50.0
const DESC_POS := Vector2(32, 738)
const DESC_SIZE := Vector2(455, 250)
static var DESC_OUTER := PackedVector2Array([Vector2(24, 0), Vector2(431, 0), Vector2(455, 24), Vector2(455, 226), Vector2(431, 250), Vector2(24, 250), Vector2(0, 226), Vector2(0, 24)])
static var DESC_INNER := PackedVector2Array([Vector2(28, 12), Vector2(427, 12), Vector2(443, 28), Vector2(443, 222), Vector2(427, 238), Vector2(28, 238), Vector2(12, 222), Vector2(12, 28)])
const STATS_POS := Vector2(630, 695)
const STATS_SIZE := Vector2(650, 380)
static var STATS_OUTER := PackedVector2Array([Vector2(25, 0), Vector2(625, 0), Vector2(650, 25), Vector2(650, 355), Vector2(625, 380), Vector2(345, 380), Vector2(315, 347), Vector2(28, 347), Vector2(0, 319), Vector2(0, 25)])
static var STATS_INNER := PackedVector2Array([Vector2(16, 66), Vector2(634, 66), Vector2(634, 324), Vector2(16, 324)])
const STATS_ROWS_X := 40.0
const STATS_ROWS_Y := 72.0
const STATS_ROWS_W := 575.0
const STATS_ROW_H := 49.0
const STRIP_W := 265.0
const BAND_Y := 640.0

## Main-menu item descriptions (mock data.ts wording; Quest adapted — it is
## a live quest log here, not the mock's permanently-disabled entry).
const ITEM_DESC := {
	"Items": "Use and manage your items.",
	"Equip": "Change equipment.",
	"Techs": "Review learned techniques.",
	"Palette": "Set the action palette.",
	"Mags": "Check on your MAG.",
	"Quest": "View the quest log.",
	"System": "Change system settings.",
}

# ── State ───────────────────────────────────────────────────────────────────────
var _c: CanvasLayer  # PsoStartMenu back-reference (extracted-controller pattern)
var _rows: Array = []
var _desc_label: Label
var _desc_base_x := 0.0
var _desc_tween: Tween
var _counter_label: Label
var _stats_rows: Control
var _stats_base_x := 0.0
var _stats_tween: Tween
var _last_in_main := false
var _last_menu := -1
var _last_page := -1
var _last_labels := ""
var _numeric_font: Font


# ═══ Shared runtime-generated textures (PszStyle.scanline_texture precedent) ═══

static var _scan_tex: ImageTexture
static var _paper_tex: ImageTexture
static var _sky_tex: ImageTexture
static var _frame_grad: GradientTexture1D
static var _orange_grad: GradientTexture1D
static var _hp_grad: GradientTexture1D
static var _pp_grad: GradientTexture1D
static var _orb_radial: GradientTexture2D
static var _glint_radial: GradientTexture2D
static var _band_tex: ImageTexture
static var _top_light_tex: ImageTexture
static var _strip_edge_tex: ImageTexture


static func tex_scan() -> ImageTexture:
	if _scan_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for x in 4:
			img.set_pixel(x, 0, C_SCAN_WHITE)
			img.set_pixel(x, 2, C_SCAN_NAVY)
		_scan_tex = ImageTexture.create_from_image(img)
	return _scan_tex


static func tex_paper() -> ImageTexture:
	if _paper_tex == null:
		_paper_tex = _pattern_tex(C_PAPER, C_PAPER_RULE)
	return _paper_tex


static func tex_sky() -> ImageTexture:
	if _sky_tex == null:
		_sky_tex = _pattern_tex(C_SKY, C_SKY_RULE)
	return _sky_tex


static func _pattern_tex(base: Color, rule: Color) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for x in 4:
		img.set_pixel(x, 2, rule)
	return ImageTexture.create_from_image(img)


static func tex_frame_grad() -> GradientTexture1D:
	if _frame_grad == null:
		var grad := Gradient.new()
		grad.set_color(0, C_FRAME_TOP)
		grad.set_color(1, C_FRAME_BOT)
		grad.add_point(0.5, C_FRAME_MID)
		_frame_grad = GradientTexture1D.new()
		_frame_grad.gradient = grad
		_frame_grad.width = 8
	return _frame_grad


static func tex_orange() -> GradientTexture1D:
	if _orange_grad == null:
		var grad := Gradient.new()
		grad.set_color(0, Color("#ffc94a"))
		grad.set_color(1, Color("#ee8a12"))
		grad.add_point(0.16, Color("#f7a224"))
		_orange_grad = GradientTexture1D.new()
		_orange_grad.gradient = grad
		_orange_grad.width = 8
	return _orange_grad


static func tex_hp() -> GradientTexture1D:
	if _hp_grad == null:
		var grad := Gradient.new()
		grad.set_color(0, Color("#a4f5c5"))
		grad.set_color(1, Color("#28aa63"))
		# End colors FIRST, then midpoints: set_color() indexes shift when
		# add_point() inserts, so setting the end last hits the new midpoint
		# and leaves the real end at Gradient's default opaque white.
		grad.add_point(0.35, Color("#7cf0aa"))
		grad.add_point(0.36, Color("#3bc87e"))
		_hp_grad = GradientTexture1D.new()
		_hp_grad.gradient = grad
		_hp_grad.width = 8
	return _hp_grad


## PP fill — the HP bar's glossy style in the legacy PP blue.
static func tex_pp() -> GradientTexture1D:
	if _pp_grad == null:
		var grad := Gradient.new()
		grad.set_color(0, Color("#a4c8f5"))
		grad.set_color(1, Color("#2863aa"))
		grad.add_point(0.35, Color("#7cabee"))
		grad.add_point(0.36, Color("#3b78d9"))
		_pp_grad = GradientTexture1D.new()
		_pp_grad.gradient = grad
		_pp_grad.width = 8
	return _pp_grad


## Vertical gradients are baked 1x64 ImageTextures, NOT transposed
## GradientTexture1Ds: on the GL compatibility renderer, draw_texture_rect
## with transpose=true silently draws nothing when the gradient contains a
## fully-transparent stop (verified with a scratch probe — opaque-stop
## gradients like the HP fill transpose fine, alpha-fade ones don't).
static func _vertical_tex(stops: Array) -> ImageTexture:
	var img := Image.create(1, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		img.set_pixel(0, y, _sample_stops(stops, float(y) / 63.0))
	return ImageTexture.create_from_image(img)


static func _sample_stops(stops: Array, t: float) -> Color:
	if t <= float(stops[0][0]):
		return stops[0][1]
	for i in range(stops.size() - 1):
		var o1 := float(stops[i + 1][0])
		if t <= o1:
			var o0 := float(stops[i][0])
			var f := (t - o0) / maxf(o1 - o0, 0.0001)
			var c0: Color = stops[i][1]
			return c0.lerp(stops[i + 1][1], f)
	return stops[stops.size() - 1][1]


## Bottom-band fill, baked 64x64 with BOTH fades multiplied into the alpha:
## the vertical fade-in over the mock's first 50px (33px scaled) and the
## far-right dissolve to full transparency (playtest round 3).
static func tex_band() -> ImageTexture:
	if _band_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			var v_alpha := STAGE_ALPHA * clampf(float(y) / 63.0 / 0.115, 0.0, 1.0)
			for x in 64:
				var right_f := band_right_fade(float(x) / 63.0, 1.0)
				img.set_pixel(x, y, Color(C_STRIP_BG.r, C_STRIP_BG.g, C_STRIP_BG.b, v_alpha * right_f))
		_band_tex = ImageTexture.create_from_image(img)
	return _band_tex


## Far-right fade shared by the band fill (UV space) and its octagon lines
## (pixel space): solid to 82% of the width, fully transparent by 99.5%.
static func band_right_fade(x: float, w: float) -> float:
	return clampf((0.995 * w - x) / (0.175 * w), 0.0, 1.0)


static func tex_top_light() -> ImageTexture:
	if _top_light_tex == null:
		_top_light_tex = _vertical_tex([
			[0.0, Color(1, 1, 1, 0.65)],
			[0.2, Color(1, 1, 1, 0.2)],
			[0.55, Color(1, 1, 1, 0.0)],
			[1.0, Color(1, 1, 1, 0.0)],
		])
	return _top_light_tex


static func tex_strip_edge() -> ImageTexture:
	if _strip_edge_tex == null:
		_strip_edge_tex = _vertical_tex([
			[0.0, Color(1, 1, 1, 0.95)],
			[0.6, Color(1, 1, 1, 0.8)],
			[1.0, Color(1, 1, 1, 0.4)],
		])
	return _strip_edge_tex


static func tex_orb() -> GradientTexture2D:
	if _orb_radial == null:
		var grad := Gradient.new()
		grad.set_color(0, Color("#ff9898"))
		grad.set_color(1, Color("#590404"))
		grad.add_point(0.35, Color("#ee2c2c"))
		grad.add_point(0.85, Color("#9b0b0b"))
		_orb_radial = GradientTexture2D.new()
		_orb_radial.gradient = grad
		_orb_radial.fill = GradientTexture2D.FILL_RADIAL
		_orb_radial.fill_from = Vector2(0.35, 0.3)  # mock's light anchor
		_orb_radial.fill_to = Vector2(1.05, 1.05)
	return _orb_radial


static func tex_glint() -> GradientTexture2D:
	if _glint_radial == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0.85))
		grad.set_color(1, Color(1, 1, 1, 0.0))
		grad.add_point(0.8, Color(1, 1, 1, 0.0))
		_glint_radial = GradientTexture2D.new()
		_glint_radial.gradient = grad
		_glint_radial.fill = GradientTexture2D.FILL_RADIAL
		_glint_radial.fill_from = Vector2(0.5, 0.5)
		_glint_radial.fill_to = Vector2(1.0, 0.5)
	return _glint_radial


static func spread_digits(value: String) -> String:
	if not value.strip_edges().is_valid_int():
		return value
	var out := ""
	for i in value.length():
		if i > 0:
			out += " "
		out += value[i]
	return out


static func _closed_polyline(c: Control, pts: PackedVector2Array, color: Color, width: float) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	c.draw_polyline(loop, color, width)


static func _s(v: float) -> float:
	return v * SCALE


static func _v(v: Vector2) -> Vector2:
	return v * SCALE


static func _p(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = pts[i] * SCALE
	return out


# ═══ Inner drawing Controls ═══


## Full-stage backdrop: no stage base at all (the game shows through
## everywhere the pattern isn't) — just the blue octagon L: a translucent
## left strip and a full-width bottom band that fades in over its top edge.
class Backdrop extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var band_y := StartMenuMainSkin._s(StartMenuMainSkin.BAND_Y)
		# Snap the strip out to a whole number of octagon tiles (176.67 → 192)
		# so every diamond fits INSIDE the fill — the playtest complaint was
		# exactly the pattern poking past the blue (round 3), and 4.5 has no
		# per-draw clip rect to trim it any other way.
		var strip_w := ceilf(StartMenuMainSkin._s(StartMenuMainSkin.STRIP_W) / OCT_TILE) * OCT_TILE

		# The blue octagon L, split at the strip's right edge so the two
		# styles never stack in the bottom-left corner (playtest round 3):
		# the strip owns its full column, the band owns everything right of
		# it. Both passes share one tiling grid and butt exactly at strip_w.
		draw_texture_rect(StartMenuMainSkin.tex_band(), Rect2(Vector2(strip_w, band_y), Vector2(w - strip_w, h - band_y)), false)
		var gx0 := int(strip_w / OCT_TILE)
		var gx1 := int(ceil(w / OCT_TILE)) + 1
		var gy0 := int(floor(band_y / OCT_TILE))
		var gy1 := int(ceil(h / OCT_TILE)) + 1
		for gx in range(gx0, gx1):
			for gy in range(gy0, gy1):
				var origin := Vector2(gx * OCT_TILE, gy * OCT_TILE)
				var bottom_f := clampf((origin.y - band_y) / StartMenuMainSkin._s(50), 0.0, 1.0)
				var right_f := StartMenuMainSkin.band_right_fade(origin.x, w)
				var alpha := StartMenuMainSkin.C_OCT.a * bottom_f * right_f
				if alpha <= 0.01:
					continue
				_draw_oct_cell(origin, alpha)

		draw_rect(Rect2(Vector2.ZERO, Vector2(strip_w, h)), Color(StartMenuMainSkin.C_STRIP_BG, StartMenuMainSkin.STAGE_ALPHA))
		var sgx1 := int(strip_w / OCT_TILE)
		var sgy1 := int(ceil(h / OCT_TILE)) + 1
		for gx in range(-1, sgx1):
			for gy in range(-1, sgy1):
				_draw_oct_cell(Vector2(gx * OCT_TILE, gy * OCT_TILE), StartMenuMainSkin.C_OCT.a)
		draw_texture_rect(StartMenuMainSkin.tex_top_light(), Rect2(Vector2.ZERO, Vector2(strip_w, h * 0.55)), false)
		draw_texture_rect(StartMenuMainSkin.tex_strip_edge(), Rect2(Vector2(strip_w - StartMenuMainSkin._s(2), 0), Vector2(StartMenuMainSkin._s(2), h)), false)

	const OCT_TILE := 48.0  # mock 72px tile

	func _draw_oct_cell(origin: Vector2, alpha: float) -> void:
		# One cell of the mock's truncated-square tiling: a diamond (chamfer 14)
		# plus four tick segments crossing the cell borders so diamonds read as
		# connected octagons when tiled. Scaled by STAGE_ALPHA so the lines sit
		# ON the translucent stage rather than looking denser than its base.
		var col := Color(1, 1, 1, alpha * StartMenuMainSkin.STAGE_ALPHA)
		var line_w := StartMenuMainSkin._s(2.2)
		var cx := origin.x + 24.0
		var cy := origin.y + 24.0
		var ch := 14.0  # mock chamfer 21, scaled — also the diamond vertex offset
		var half := OCT_TILE * 0.5
		var diamond := PackedVector2Array([
			Vector2(cx, cy - ch),
			Vector2(cx + ch, cy),
			Vector2(cx, cy + ch),
			Vector2(cx - ch, cy),
		])
		StartMenuMainSkin._closed_polyline(self, diamond, col, line_w)
		draw_line(Vector2(cx, cy - half - 1), Vector2(cx, cy - ch), col, line_w)
		draw_line(Vector2(cx, cy + ch), Vector2(cx, cy + half + 1), col, line_w)
		draw_line(Vector2(cx - half - 1, cy), Vector2(cx - ch, cy), col, line_w)
		draw_line(Vector2(cx + ch, cy), Vector2(cx + half + 1, cy), col, line_w)


## One chamfered blue window: white halo, gradient body, scanlines, and any
## number of stroked inner windows (paper or sky tone). The mock's Frame.tsx.
class ChamferPanel extends Control:
	var outer := PackedVector2Array()
	var windows: Array = []  # [{"poly": PackedVector2Array, "tone": "paper"|"sky"}]

	func _init() -> void:
		# Tiled-pattern fills use UVs beyond 1.0, so repeat must be on.
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	func _draw() -> void:
		# 1. White outer halo (drawn first → reads as a glow outside the shape).
		StartMenuMainSkin._closed_polyline(self, outer, Color.WHITE, StartMenuMainSkin._s(6))
		# 2. Frame body, vertical gradient via per-vertex UVs on the polygon.
		draw_colored_polygon(outer, Color.WHITE, _uvs_vertical(outer), StartMenuMainSkin.tex_frame_grad())
		# 3. Scanlines over the frame body.
		draw_colored_polygon(outer, Color.WHITE, _uvs_tiled(outer), StartMenuMainSkin.tex_scan())
		StartMenuMainSkin._closed_polyline(self, outer, StartMenuMainSkin.C_CONTOUR, StartMenuMainSkin._s(2.5))
		# 4. Inner windows: tone pattern, white then navy over-stroke.
		for window in windows:
			var poly: PackedVector2Array = window.poly
			var tone_tex: ImageTexture = StartMenuMainSkin.tex_sky() if window.tone == "sky" else StartMenuMainSkin.tex_paper()
			draw_colored_polygon(poly, Color.WHITE, _uvs_tiled(poly), tone_tex)
			StartMenuMainSkin._closed_polyline(self, poly, Color.WHITE, StartMenuMainSkin._s(3.5))
			StartMenuMainSkin._closed_polyline(self, poly, StartMenuMainSkin.C_INNER_NAVY, StartMenuMainSkin._s(1.6))

	func _uvs_vertical(pts: PackedVector2Array) -> PackedVector2Array:
		# GradientTexture1D runs along X; map it to the panel's Y extent.
		var max_y := 1.0
		for pt in pts:
			max_y = maxf(max_y, pt.y)
		var uvs := PackedVector2Array()
		for pt in pts:
			uvs.append(Vector2(pt.y / max_y, 0.0))
		return uvs

	func _uvs_tiled(pts: PackedVector2Array) -> PackedVector2Array:
		var uvs := PackedVector2Array()
		for pt in pts:
			uvs.append(pt / 4.0)
		return uvs


## Leader star badge on the name panel's top edge.
class StarBadge extends Control:
	func _draw() -> void:
		var s := size.x / 22.0
		var pts := PackedVector2Array([
			Vector2(11, 1), Vector2(13.8, 7.8), Vector2(21, 8.3), Vector2(15.6, 12.8),
			Vector2(17.4, 20), Vector2(11, 16), Vector2(4.6, 20), Vector2(6.4, 12.8),
			Vector2(1, 8.3), Vector2(8.2, 7.8),
		])
		for i in pts.size():
			pts[i] *= s
		draw_colored_polygon(pts, StartMenuMainSkin.C_STAR_FILL)
		StartMenuMainSkin._closed_polyline(self, pts, StartMenuMainSkin.C_STAR_STROKE, StartMenuMainSkin._s(1.6))


## Red HP orb (radial gradient + double ring + specular glint).
class HpOrb extends Control:
	func _draw() -> void:
		draw_texture_rect(StartMenuMainSkin.tex_orb(), Rect2(Vector2.ZERO, size), false)
		var r := size.x * 0.5
		var center := Vector2(r, r)
		draw_arc(center, r - StartMenuMainSkin._s(0.7), 0, TAU, 40, StartMenuMainSkin.C_RING_WHITE, StartMenuMainSkin._s(2))
		draw_arc(center, r + StartMenuMainSkin._s(0.5), 0, TAU, 40, StartMenuMainSkin.C_RING_NAVY, StartMenuMainSkin._s(3.5))
		# Specular glint: mock 10x8 white radial at top-left of the sphere.
		var glint := Rect2(StartMenuMainSkin._v(Vector2(9, 6)), StartMenuMainSkin._v(Vector2(10, 8)))
		draw_texture_rect(StartMenuMainSkin.tex_glint(), glint, false)


## HP bar: dark track, gradient fill (animated width), white+navy rings.
class HpBar extends Control:
	## Fill texture override (the PP bar uses the blue variant); drawn
	## transposed like the HP fill — opaque-stop gradients transpose fine.
	var fill_tex: GradientTexture1D = null
	var fraction := 1.0:
		set(value):
			fraction = clampf(value, 0.0, 1.0)
			queue_redraw()

	func _draw() -> void:
		var ring := Rect2(Vector2.ZERO, size)
		draw_rect(ring, StartMenuMainSkin.C_HP_TRACK)
		var fill_w := size.x * fraction
		if fill_w > 0.5:
			# Round 4: the gloss sweeps ACROSS (light left → dark right),
			# matching the selection row — not top-to-bottom.
			var tex := fill_tex if fill_tex != null else StartMenuMainSkin.tex_hp()
			draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(fill_w, size.y)), false)
		draw_rect(ring, StartMenuMainSkin.C_RING_WHITE, false, StartMenuMainSkin._s(1.5))
		draw_rect(ring.grow(StartMenuMainSkin._s(1.0)), StartMenuMainSkin.C_RING_NAVY, false, StartMenuMainSkin._s(1.0))


## One selectable main-menu row: orange gradient + pulsing glow when selected,
## grey text when disabled; hover selects, click activates (mock MenuPanel).
class MenuRow extends Control:
	signal hover_requested(index: int)
	signal activate_requested(index: int)

	var index := 0
	var text := ""
	var selected := false:
		set(value):
			if selected == value:
				return
			selected = value
			queue_redraw()
	var disabled := false:
		set(value):
			if disabled == value:
				return
			disabled = value
			_refresh_label_color()
	var pulse := 0.0:
		set(value):
			pulse = value
			queue_redraw()

	var _label: Label
	var _pulse_tween: Tween

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void: hover_requested.emit(index))
		gui_input.connect(_on_gui_input)
		_label = Label.new()
		_label.text = text
		_label.mouse_filter = MOUSE_FILTER_IGNORE
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_override("font", StartMenuMainSkin.FONT)
		_label.add_theme_font_size_override("font_size", StartMenuMainSkin.FS_MAIN)
		_label.add_theme_color_override("font_color", StartMenuMainSkin.C_TEXT)
		_label.add_theme_constant_override("line_spacing", 0)
		_label.clip_text = true
		add_child(_label)

	func _on_gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			activate_requested.emit(index)

	func set_pulse_active(active: bool) -> void:
		if _pulse_tween != null:
			_pulse_tween.kill()
			_pulse_tween = null
		if active:
			_pulse_tween = create_tween().set_loops()
			_pulse_tween.tween_property(self, "pulse", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_pulse_tween.tween_property(self, "pulse", 0.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		else:
			pulse = 0.0

	func _refresh_label_color() -> void:
		if _label != null:
			_label.add_theme_color_override("font_color", StartMenuMainSkin.C_TEXT_DISABLED if disabled else StartMenuMainSkin.C_TEXT)

	func _draw() -> void:
		if not selected:
			return
		# Mock gradient runs 180deg (down); playtest round 3 wants it ACROSS —
		# light at the left, dark at the right, like PSO's selection sweep.
		draw_texture_rect(StartMenuMainSkin.tex_orange(), Rect2(Vector2.ZERO, size), false)
		draw_line(Vector2(0, 0.5), Vector2(size.x, 0.5), StartMenuMainSkin.C_SEL_TOP_INSET, 1.0)
		draw_line(Vector2(0, size.y - 0.5), Vector2(size.x, size.y - 0.5), StartMenuMainSkin.C_SEL_BOT_INSET, 1.0)
		if pulse > 0.01:
			var glow := Color(StartMenuMainSkin.C_SEL_GLOW, StartMenuMainSkin.C_SEL_GLOW.a * pulse)
			draw_rect(Rect2(Vector2(-1.33, -1.33), size + Vector2(2.67, 2.67)), glow, false, 2.67)


## Dark [L]/[R] shoulder chip above the stats pages; click flips the page.
class ShoulderKey extends Control:
	signal pressed_requested()

	var caption := "L"

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		gui_input.connect(_on_gui_input)
		var lbl := Label.new()
		lbl.text = caption
		lbl.mouse_filter = MOUSE_FILTER_IGNORE
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_override("font", StartMenuMainSkin.FONT)
		lbl.add_theme_font_size_override("font_size", StartMenuMainSkin.FS_SHOULDER)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		add_child(lbl)

	func _on_gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pressed_requested.emit()

	func _draw() -> void:
		# Mock rings: 2px white, then 3.5px navy outside it — two boxes.
		var white_ring := StyleBoxFlat.new()
		white_ring.bg_color = StartMenuMainSkin.C_SHOULDER_BG
		white_ring.set_corner_radius_all(2)
		white_ring.border_color = Color.WHITE
		white_ring.set_border_width_all(StartMenuMainSkin._s(2))
		draw_style_box(white_ring, Rect2(Vector2.ZERO, size))
		var sb := StyleBoxFlat.new()
		sb.bg_color = StartMenuMainSkin.C_SHOULDER_BG
		sb.set_corner_radius_all(2)
		sb.border_color = StartMenuMainSkin.C_SHOULDER_RING
		sb.set_border_width_all(StartMenuMainSkin._s(2.33))
		draw_style_box(sb, Rect2(Vector2.ZERO, size).grow(-StartMenuMainSkin._s(1.17)))


## Green page-flip triangle; hover brightens + nudges, click flips.
class PageArrow extends Control:
	signal pressed_requested()

	var pointing_left := false
	var _hovered := false

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; queue_redraw())
		gui_input.connect(_on_gui_input)

	func _on_gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pressed_requested.emit()

	func _draw() -> void:
		var fill := StartMenuMainSkin.C_ARROW_HOVER if _hovered else StartMenuMainSkin.C_ARROW_FILL
		# Mock triangle 26x34 in a 30x38 button → centered, scaled to fit.
		var pad := StartMenuMainSkin._s(4)
		var h := size.y - pad
		var cx: float = size.x * 0.5 + (StartMenuMainSkin._s(2) if (_hovered and pointing_left) else 0) - (StartMenuMainSkin._s(2) if (_hovered and not pointing_left) else 0)
		var half_w := StartMenuMainSkin._s(9)
		var pts: PackedVector2Array
		if pointing_left:
			pts = PackedVector2Array([Vector2(cx + half_w, 0), Vector2(cx + half_w, h), Vector2(cx - half_w, h * 0.5)])
		else:
			pts = PackedVector2Array([Vector2(cx - half_w, 0), Vector2(cx - half_w, h), Vector2(cx + half_w, h * 0.5)])
		pts[0].y += pad * 0.5
		pts[1].y -= pad * 0.5
		var origin := Vector2(0, (size.y - h) * 0.5)
		for i in pts.size():
			pts[i] += origin
		draw_colored_polygon(pts, fill)
		StartMenuMainSkin._closed_polyline(self, pts, StartMenuMainSkin.C_ARROW_STROKE, StartMenuMainSkin._s(2.5))


## One stat row: hoverable white wash + label + right-aligned value (numeric
## values get the mock's spaced-digit tracking).
class StatRow extends Control:
	var label_text := ""
	var value_text := ""
	var _hovered := false
	var _label: Label
	var _value: Label

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; queue_redraw())
		var row_h := size.y
		var label_w := size.x * 0.45
		_label = _make_label(label_text, StartMenuMainSkin.FONT)
		_label.position = Vector2(0, 0)
		_label.size = Vector2(label_w, row_h)
		add_child(_label)
		var numeric := value_text.strip_edges().is_valid_int()
		_value = _make_label(StartMenuMainSkin.spread_digits(value_text) if numeric else value_text, StartMenuMainSkin.FONT)
		_value.position = Vector2(label_w, 0)
		_value.size = Vector2(size.x - label_w, row_h)
		_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(_value)

	func _make_label(text: String, font: Font) -> Label:
		var lbl := Label.new()
		lbl.text = text
		lbl.mouse_filter = MOUSE_FILTER_IGNORE
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", StartMenuMainSkin.FS_MAIN)
		lbl.add_theme_color_override("font_color", StartMenuMainSkin.C_TEXT_STATS)
		lbl.add_theme_constant_override("line_spacing", 0)
		lbl.clip_text = true
		return lbl

	func _draw() -> void:
		if _hovered:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35))


## The name / HP / PP plate — the persistent gameplay HUD (HudStats). It
## replaced the legacy hp-pp.png panel in playtest round 3 and became the
## ONLY instance in round 4: the menu no longer draws its own copy, and at
## layer 200 this plate renders on top of the start menu while it's open.
## Geometry is the mock's NamePanel.
class NamePlate extends Control:
	var _name_label: Label
	var _hp_bar: HpBar
	var _pp_bar: HpBar
	var _hp_tween: Tween
	var _pp_tween: Tween

	func setup_plate(char_name: String) -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		size = StartMenuMainSkin._v(StartMenuMainSkin.NAME_SIZE)

		var frame := StartMenuMainSkin.ChamferPanel.new()
		frame.outer = StartMenuMainSkin._p(StartMenuMainSkin.NAME_OUTER)
		frame.windows = [{"poly": StartMenuMainSkin._p(StartMenuMainSkin.NAME_INNER), "tone": "paper"}]
		frame.position = Vector2.ZERO
		frame.size = size
		frame.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(frame)

		var star := StartMenuMainSkin.StarBadge.new()
		star.position = StartMenuMainSkin._v(StartMenuMainSkin.STAR_POS)
		star.size = Vector2.ONE * StartMenuMainSkin._s(StartMenuMainSkin.STAR_SIZE)
		star.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(star)

		var orb := StartMenuMainSkin.HpOrb.new()
		orb.position = StartMenuMainSkin._v(StartMenuMainSkin.ORB_POS)
		orb.size = Vector2.ONE * StartMenuMainSkin._s(StartMenuMainSkin.ORB_SIZE)
		orb.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(orb)

		_name_label = Label.new()
		_name_label.text = char_name
		_name_label.position = StartMenuMainSkin._v(Vector2(66, 26))
		_name_label.size = StartMenuMainSkin._v(Vector2(152, 48))
		_name_label.mouse_filter = MOUSE_FILTER_IGNORE
		_name_label.clip_text = true
		_name_label.add_theme_font_override("font", StartMenuMainSkin.FONT)
		_name_label.add_theme_font_size_override("font_size", StartMenuMainSkin.FS_MAIN)
		_name_label.add_theme_color_override("font_color", StartMenuMainSkin.C_TEXT)
		_name_label.add_theme_constant_override("line_spacing", 0)
		add_child(_name_label)

		_hp_bar = _make_bar(Vector2(68, 76), StartMenuMainSkin.tex_hp())
		_pp_bar = _make_bar(Vector2(68, 90), StartMenuMainSkin.tex_pp())

	func _make_bar(pos: Vector2, tex: GradientTexture1D) -> HpBar:
		var bar := HpBar.new()
		bar.fill_tex = tex
		bar.position = StartMenuMainSkin._v(pos)
		bar.size = StartMenuMainSkin._v(Vector2(195, 10))
		bar.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(bar)
		return bar

	func set_name_text(char_name: String) -> void:
		if _name_label != null:
			_name_label.text = char_name

	## Target fractions — the synchronous readback (the bars themselves
	## animate toward these over 500ms, so mid-tween reads aren't stable).
	var hp_target := 0.0
	var pp_target := 0.0

	## Bars sweep to their new fractions (mock: 500ms ease-out width).
	func set_fractions(hp: float, pp: float, animate: bool = true) -> void:
		hp_target = hp
		pp_target = pp
		_hp_tween = _bar_tween(_hp_bar, hp, animate, _hp_tween)
		_pp_tween = _bar_tween(_pp_bar, pp, animate, _pp_tween)

	func _bar_tween(bar: HpBar, target: float, animate: bool, prev: Tween) -> Tween:
		if prev != null:
			prev.kill()
		if not animate:
			bar.fraction = target
			return null
		var tw := create_tween()
		tw.tween_property(bar, "fraction", target, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		return tw


# ═══ Build / refresh ═══


func setup(controller: CanvasLayer) -> void:
	_c = controller
	position = Vector2.ZERO
	size = Vector2(VIEW_W, VIEW_H)
	mouse_filter = MOUSE_FILTER_IGNORE

	var backdrop := Backdrop.new()
	backdrop.position = Vector2.ZERO
	backdrop.size = Vector2(VIEW_W, VIEW_H)
	backdrop.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_build_menu_panel()
	_build_description_panel()
	_build_stats_panel()

	_refresh_all()
	_play_entry()


func _build_menu_panel() -> void:
	var holder := _holder(_v(MENU_POS), _v(MENU_SIZE))
	_add_chamfer(holder, MENU_OUTER, [{"poly": MENU_INNER, "tone": "paper"}])
	set_meta("holder_menu", holder)
	_rebuild_rows(_c._get_menu_labels())


func _rebuild_rows(labels: Array) -> void:
	var holder: Control = get_meta("holder_menu")
	for row in _rows:
		holder.remove_child(row)
		row.queue_free()
	_rows.clear()
	for i in labels.size():
		var row := MenuRow.new()
		row.index = i
		row.text = str(labels[i])
		row.position = _v(Vector2(ROW_X, ROW_Y + i * ROW_H))
		row.size = _v(Vector2(ROW_W, ROW_H - 4))
		row.hover_requested.connect(_on_row_hover)
		row.activate_requested.connect(_on_row_activate)
		holder.add_child(row)
		_rows.append(row)
	_last_labels = str(labels)


func _build_description_panel() -> void:
	var holder := _holder(_v(DESC_POS), _v(DESC_SIZE))
	_add_chamfer(holder, DESC_OUTER, [{"poly": DESC_INNER, "tone": "paper"}])

	_desc_label = _make_label("", FS_MAIN, C_TEXT)
	_desc_label.position = _v(Vector2(36, 44))
	_desc_label.size = Vector2(_s(DESC_SIZE.x - 36 - 30), _s(150))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	holder.add_child(_desc_label)
	_desc_base_x = _desc_label.position.x
	set_meta("holder_desc", holder)


func _build_stats_panel() -> void:
	# Pinned near the right edge with 40px of breathing room (round 5).
	var holder := _holder(Vector2(VIEW_W - _v(STATS_SIZE).x - 40.0, _v(STATS_POS).y), _v(STATS_SIZE))
	_add_chamfer(holder, STATS_OUTER, [{"poly": STATS_INNER, "tone": "sky"}])

	# Page header: [◀] [L] counter [R] [▶], centered in the frame band.
	var header_w := _s(30 + 48 + 96 + 48 + 30 + 4 * 12)
	var x := (STATS_SIZE.x * SCALE - header_w) * 0.5
	var header_y := _s(16 + 3)
	var header_h := _s(38)
	var prev := PageArrow.new()
	prev.pointing_left = true
	prev.position = Vector2(x, header_y)
	prev.size = Vector2(_s(30), header_h)
	prev.pressed_requested.connect(func() -> void: _c._info_page = wrapi(_c._info_page - 1, 0, 4))
	holder.add_child(prev)
	x += _s(30 + 12)
	var key_l := ShoulderKey.new()
	key_l.caption = "L"
	key_l.position = Vector2(x, header_y)
	key_l.size = Vector2(_s(48), header_h)
	key_l.pressed_requested.connect(func() -> void: _c._info_page = wrapi(_c._info_page - 1, 0, 4))
	holder.add_child(key_l)
	x += _s(48 + 12)
	_counter_label = _make_label("1/4", FS_COUNTER, C_TEXT_STATS)
	_counter_label.position = Vector2(x, header_y)
	_counter_label.size = Vector2(_s(96), header_h)
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	_counter_label.add_theme_constant_override("outline_size", 2)
	holder.add_child(_counter_label)
	x += _s(96 + 12)
	var key_r := ShoulderKey.new()
	key_r.caption = "R"
	key_r.position = Vector2(x, header_y)
	key_r.size = Vector2(_s(48), header_h)
	key_r.pressed_requested.connect(func() -> void: _c._info_page = wrapi(_c._info_page + 1, 0, 4))
	holder.add_child(key_r)
	x += _s(48 + 12)
	var next := PageArrow.new()
	next.position = Vector2(x, header_y)
	next.size = Vector2(_s(30), header_h)
	next.pressed_requested.connect(func() -> void: _c._info_page = wrapi(_c._info_page + 1, 0, 4))
	holder.add_child(next)

	_stats_rows = Control.new()
	_stats_rows.position = _v(Vector2(STATS_ROWS_X, STATS_ROWS_Y))
	_stats_rows.size = _v(Vector2(STATS_ROWS_W, STATS_ROW_H * 5))
	_stats_rows.mouse_filter = MOUSE_FILTER_IGNORE
	holder.add_child(_stats_rows)
	_stats_base_x = _stats_rows.position.x
	set_meta("holder_stats", holder)


# ── Refresh / sync ──────────────────────────────────────────────────────────────


## Called every frame by PsoStartMenu._process while the menu is open. Diffs
## controller state and refreshes only what changed, so StartMenuInput stays
## the single owner of input (it never learns the skin exists).
func sync() -> void:
	var in_main: bool = _c._mode == _c.Mode.MAIN
	if in_main != _last_in_main:
		_last_in_main = in_main
		visible = in_main
		# The input path queues its redraw while the skin may still be
		# covering the canvas (_draw_menu early-returns then); re-queue on
		# every coverage change so the layer below ALWAYS gets one repaint
		# after the skin steps aside. Without this, entering a sub-mode can
		# leave a blank frame that reads as "the menu closed" (the round-5
		# "legacy menu appears randomly" was the same race, won or lost
		# depending on whether input flushes before or after _process).
		_c._canvas.queue_redraw()
		if in_main:
			_refresh_all()
	if not in_main:
		return

	var labels: Array = _c._get_menu_labels()
	if str(labels) != _last_labels:
		_rebuild_rows(labels)
	if _c._menu_idx != _last_menu:
		_refresh_selection()
	if _c._info_page != _last_page:
		_refresh_stats(true)
	# Live name/HP/PP is the persistent HudStats plate's job (layer 200, so
	# it renders ON TOP of this skin while the menu is open — round 4).


func _refresh_all() -> void:
	_refresh_selection()
	_refresh_stats(false)


func _refresh_selection() -> void:
	_last_menu = _c._menu_idx
	var labels: Array = _c._get_menu_labels()
	for i in _rows.size():
		var row: MenuRow = _rows[i]
		var is_sel: bool = i == _c._menu_idx
		row.selected = is_sel
		row.set_pulse_active(is_sel)
	var key := str(labels[wrapi(_c._menu_idx, 0, labels.size())])
	_set_description(str(ITEM_DESC.get(key, "")))


func _refresh_stats(animate: bool) -> void:
	_last_page = _c._info_page
	var pages: Array = _c._build_stat_pages()
	var page: int = clampi(_c._info_page, 0, pages.size() - 1)
	_counter_label.text = "%d/%d" % [page + 1, pages.size()]
	for child in _stats_rows.get_children():
		_stats_rows.remove_child(child)
		child.queue_free()
	var rows: Array = pages[page]
	for i in rows.size():
		var row := StatRow.new()
		row.label_text = str(rows[i][0])
		row.value_text = str(rows[i][1])
		row.position = Vector2(0, _s(STATS_ROW_H) * i)
		row.size = Vector2(_s(STATS_ROWS_W), _s(STATS_ROW_H))
		_stats_rows.add_child(row)
	if animate:
		if _stats_tween != null:
			_stats_tween.kill()
		_stats_rows.position.x = _stats_base_x + _s(6)
		_stats_rows.modulate.a = 0.0
		_stats_tween = create_tween()
		_stats_tween.tween_property(_stats_rows, "position:x", _stats_base_x, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_stats_tween.parallel().tween_property(_stats_rows, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_stats_rows.position.x = _stats_base_x
		_stats_rows.modulate.a = 1.0


func _set_description(text: String) -> void:
	if _desc_label.text == text:
		return
	_desc_label.text = text
	if _desc_tween != null:
		_desc_tween.kill()
	_desc_label.position.x = _desc_base_x + _s(6)
	_desc_label.modulate.a = 0.0
	_desc_tween = create_tween()
	_desc_tween.tween_property(_desc_label, "position:x", _desc_base_x, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_desc_tween.parallel().tween_property(_desc_label, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Mock's staggered entry cascade: left panels slide in from the left, stats
## and footer slide up — 0/80/160/240/400ms, 550ms ease-out.
func _play_entry() -> void:
	var specs := [
		[get_meta("holder_menu"), Vector2(-28, 0), 0.08],
		[get_meta("holder_desc"), Vector2(-28, 0), 0.16],
		[get_meta("holder_stats"), Vector2(0, 28), 0.24],
	]
	for spec in specs:
		var h: Control = spec[0]
		var off: Vector2 = _v(spec[1])
		var delay: float = spec[2]
		var final_pos := h.position
		h.position = final_pos + off
		h.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(h, "position", final_pos, 0.55).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(h, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


# ── Helpers ═══


func _holder(pos: Vector2, sz: Vector2) -> Control:
	var h := Control.new()
	h.position = pos
	h.size = sz
	h.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(h)
	return h


func _add_chamfer(parent: Control, outer: PackedVector2Array, windows: Array) -> void:
	var panel := ChamferPanel.new()
	panel.outer = _p(outer)
	panel.windows = []
	for window in windows:
		panel.windows.append({"poly": _p(window.poly), "tone": window.tone})
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(panel)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", FONT)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("line_spacing", 0)
	return lbl


func _on_row_hover(index: int) -> void:
	if _c._menu_idx != index:
		_c._menu_idx = index
		_refresh_selection()


func _on_row_activate(index: int) -> void:
	_c._menu_idx = index
	_c._enter_sub(index)


# ── Test hooks ═══


func menu_row_count() -> int:
	return _rows.size()


func counter_text() -> String:
	return _counter_label.text

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
## The mock's stage base is opaque white, but the legacy start menu is a
## translucent non-pausing overlay (the player keeps walking while it's up,
## legacy C_BACKDROP alpha 0.82) — so the stage paints at 82% and the game
## shows through. Panels stay opaque for text readability.
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
const C_FOOTER := Color(0.153, 0.275, 0.463, 0.82)  # #274676 @ 0.82
const C_KBD_BORDER := Color(0.153, 0.275, 0.463, 0.4)

# ── Mock typography, scaled ────────────────────────────────────────────────────
const FS_MAIN := 32       # mock 48px body text
const FS_COUNTER := 29    # mock 44px page counter
const FS_SHOULDER := 28   # mock 42px L/R key labels
const FS_FOOTER := 19     # mock 28px hint text
const FS_KBD := 8         # mock 12px kbd chips

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
var _name_label: Label
var _desc_label: Label
var _desc_base_x := 0.0
var _desc_tween: Tween
var _counter_label: Label
var _stats_rows: Control
var _stats_base_x := 0.0
var _stats_tween: Tween
var _hp_bar: HpBar
var _last_in_main := false
var _last_menu := -1
var _last_page := -1
var _last_labels := ""
var _last_hp_frac := -1.0
var _numeric_font: Font


# ═══ Shared runtime-generated textures (PszStyle.scanline_texture precedent) ═══

static var _scan_tex: ImageTexture
static var _paper_tex: ImageTexture
static var _sky_tex: ImageTexture
static var _frame_grad: GradientTexture1D
static var _orange_grad: GradientTexture1D
static var _hp_grad: GradientTexture1D
static var _glow_radial: GradientTexture2D
static var _orb_radial: GradientTexture2D
static var _glint_radial: GradientTexture2D
static var _strip_edge_grad: GradientTexture1D
static var _top_light_grad: GradientTexture1D
static var _wash_grad: GradientTexture1D


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
		grad.add_point(0.35, Color("#7cf0aa"))
		grad.add_point(0.36, Color("#3bc87e"))
		grad.set_color(1, Color("#28aa63"))
		_hp_grad = GradientTexture1D.new()
		_hp_grad.gradient = grad
		_hp_grad.width = 8
	return _hp_grad


static func tex_glow() -> GradientTexture2D:
	if _glow_radial == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(0.765, 0.855, 0.963, 0.7))   # rgba(195,218,246,.7)
		grad.add_point(0.45, Color(0.824, 0.894, 0.973, 0.35))
		grad.set_color(1, Color(1, 1, 1, 0))
		_glow_radial = GradientTexture2D.new()
		_glow_radial.gradient = grad
		_glow_radial.fill = GradientTexture2D.FILL_RADIAL
		_glow_radial.fill_from = Vector2(0.5, 0.5)
		_glow_radial.fill_to = Vector2(1.0, 0.5)
	return _glow_radial


static func tex_orb() -> GradientTexture2D:
	if _orb_radial == null:
		var grad := Gradient.new()
		grad.set_color(0, Color("#ff9898"))
		grad.add_point(0.35, Color("#ee2c2c"))
		grad.add_point(0.85, Color("#9b0b0b"))
		grad.set_color(1, Color("#590404"))
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
		grad.add_point(0.8, Color(1, 1, 1, 0.0))
		grad.set_color(1, Color(1, 1, 1, 0.0))
		_glint_radial = GradientTexture2D.new()
		_glint_radial.gradient = grad
		_glint_radial.fill = GradientTexture2D.FILL_RADIAL
		_glint_radial.fill_from = Vector2(0.5, 0.5)
		_glint_radial.fill_to = Vector2(1.0, 0.5)
	return _glint_radial


static func tex_strip_edge() -> GradientTexture1D:
	if _strip_edge_grad == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0.95))
		grad.add_point(0.6, Color(1, 1, 1, 0.8))
		grad.set_color(1, Color(1, 1, 1, 0.4))
		_strip_edge_grad = GradientTexture1D.new()
		_strip_edge_grad.gradient = grad
		_strip_edge_grad.width = 8
	return _strip_edge_grad


static func tex_top_light() -> GradientTexture1D:
	if _top_light_grad == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0.65))
		grad.add_point(0.2, Color(1, 1, 1, 0.2))
		grad.add_point(0.55, Color(1, 1, 1, 0.0))
		grad.set_color(1, Color(1, 1, 1, 0.0))
		_top_light_grad = GradientTexture1D.new()
		_top_light_grad.gradient = grad
		_top_light_grad.width = 8
	return _top_light_grad


static func tex_wash() -> GradientTexture1D:
	if _wash_grad == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0.0))
		grad.add_point(0.25, Color("#d8e5f5"))
		grad.add_point(0.65, Color("#c8ddf3"))
		grad.set_color(1, Color("#bdd5f0"))
		_wash_grad = GradientTexture1D.new()
		_wash_grad.gradient = grad
		_wash_grad.width = 8
	return _wash_grad


## PSO's spaced-out digit readout (mock `.26em` tracking): VT323 has no glyph
## tracking we can set at runtime, so numeric values get thin space-joined
## digits instead — same intent, e.g. "1180" renders as "1 1 8 0".
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


## Full-stage backdrop: white base, atmospheric wash + glow, octagon-tiled left
## strip and bottom band (the mock's StageBackdrop layers).
class Backdrop extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var strip_w := StartMenuMainSkin._s(StartMenuMainSkin.STRIP_W)
		var band_y := StartMenuMainSkin._s(StartMenuMainSkin.BAND_Y)
		var stage_mod := Color(1, 1, 1, StartMenuMainSkin.STAGE_ALPHA)

		# 1. Base + bottom atmospheric wash (mock: from y=620 down).
		draw_rect(Rect2(Vector2.ZERO, size), stage_mod)
		var wash_h := h - StartMenuMainSkin._s(620)
		draw_texture_rect(StartMenuMainSkin.tex_wash(), Rect2(Vector2(0, h - wash_h), Vector2(w, wash_h)), false, stage_mod, true)

		# 2. Bottom-right radial glow (mock: ellipse anchored at 85%/90%).
		var glow_size := Vector2(StartMenuMainSkin._s(1000), StartMenuMainSkin._s(600))
		var glow_center := Vector2(w * 0.85, h * 0.9)
		draw_texture_rect(StartMenuMainSkin.tex_glow(), Rect2(glow_center - glow_size * 0.5, glow_size), false, stage_mod)

		# 3. Octagon band, bottom — solid near the strip, fading out to the
		# right (mock mask: opaque to 55%, gone by 92% of the band) and fading
		# in over the first 50px of height.
		var fade_start := strip_w + 0.55 * (w - strip_w)
		var fade_end := strip_w + 0.92 * (w - strip_w)
		var gx0 := int(floor(strip_w / OCT_TILE))
		var gx1 := int(ceil(w / OCT_TILE)) + 1
		var gy0 := int(floor(band_y / OCT_TILE))
		var gy1 := int(ceil(h / OCT_TILE)) + 1
		for gx in range(gx0, gx1):
			for gy in range(gy0, gy1):
				var origin := Vector2(gx * OCT_TILE, gy * OCT_TILE)
				var right_f := 1.0 - clampf((origin.x - fade_start) / maxi(int(fade_end - fade_start), 1), 0.0, 1.0)
				var bottom_f := clampf((origin.y - band_y) / StartMenuMainSkin._s(50), 0.0, 1.0)
				var alpha := right_f * bottom_f
				if alpha <= 0.01:
					continue
				_draw_oct_cell(origin, StartMenuMainSkin.C_OCT.a * alpha)

		# 4. Left strip: fill, octagon tiling, top light, right edge.
		draw_rect(Rect2(Vector2.ZERO, Vector2(strip_w, h)), Color(StartMenuMainSkin.C_STRIP_BG, StartMenuMainSkin.STAGE_ALPHA))
		var sgx1 := int(ceil(strip_w / OCT_TILE)) + 1
		var sgy1 := int(ceil(h / OCT_TILE)) + 1
		for gx in range(-1, sgx1):
			for gy in range(-1, sgy1):
				_draw_oct_cell(Vector2(gx * OCT_TILE, gy * OCT_TILE), StartMenuMainSkin.C_OCT.a)
		draw_texture_rect(StartMenuMainSkin.tex_top_light(), Rect2(Vector2.ZERO, Vector2(strip_w, h * 0.55)), false, stage_mod, true)
		draw_texture_rect(StartMenuMainSkin.tex_strip_edge(), Rect2(Vector2(strip_w - StartMenuMainSkin._s(2), 0), Vector2(StartMenuMainSkin._s(2), h)), false, stage_mod, true)

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
		var ch := 14.0  # mock chamfer 21
		var half := OCT_TILE * 0.5
		var diamond := PackedVector2Array([
			Vector2(cx, cy - half + ch),
			Vector2(cx + half - ch, cy),
			Vector2(cx, cy + half - ch),
			Vector2(cx - half + ch, cy),
		])
		StartMenuMainSkin._closed_polyline(self, diamond, col, line_w)
		draw_line(Vector2(cx, cy - half - 1), Vector2(cx, cy - half + ch), col, line_w)
		draw_line(Vector2(cx, cy + half - ch), Vector2(cx, cy + half + 1), col, line_w)
		draw_line(Vector2(cx - half - 1, cy), Vector2(cx - half + ch, cy), col, line_w)
		draw_line(Vector2(cx + half - ch, cy), Vector2(cx + half + 1, cy), col, line_w)


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
	var fraction := 1.0:
		set(value):
			fraction = clampf(value, 0.0, 1.0)
			queue_redraw()

	func _draw() -> void:
		var ring := Rect2(Vector2.ZERO, size)
		draw_rect(ring, StartMenuMainSkin.C_HP_TRACK)
		var fill_w := size.x * fraction
		if fill_w > 0.5:
			draw_texture_rect(StartMenuMainSkin.tex_hp(), Rect2(Vector2.ZERO, Vector2(fill_w, size.y)), false, Color.WHITE, true)
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
		draw_texture_rect(StartMenuMainSkin.tex_orange(), Rect2(Vector2.ZERO, size), false, Color.WHITE, true)
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


## Footer kbd chip: box + a row of glyph content. VT323 has no arrow
## codepoints, so arrows are drawn as tiny triangles instead of characters,
## laid out inline before/after text via draw_string.
class KbdChip extends Control:
	var items: Array = []  # [{"t": "ENTER"} | {"g": "up"|"down"|"left"|"right"}]

	const TRI_W := 4.0
	const GAP := 2.0

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func measure() -> float:
		var w := 6.0
		for item in items:
			if item.has("g"):
				w += TRI_W + GAP
			else:
				w += StartMenuMainSkin.FONT.get_string_size(str(item.t), HORIZONTAL_ALIGNMENT_LEFT, -1, StartMenuMainSkin.FS_KBD).x + GAP
		return w + 2.0

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.7)
		sb.border_color = StartMenuMainSkin.C_KBD_BORDER
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var x := 4.0
		var cy := size.y * 0.5
		for item in items:
			if item.has("g"):
				var kind := str(item.g)
				var pts := PackedVector2Array()
				match kind:
					"up": pts = [Vector2(x + TRI_W * 0.5, cy - 3), Vector2(x + TRI_W, cy + 2), Vector2(x, cy + 2)]
					"down": pts = [Vector2(x, cy - 2), Vector2(x + TRI_W, cy - 2), Vector2(x + TRI_W * 0.5, cy + 3)]
					"left": pts = [Vector2(x + TRI_W, cy - 3), Vector2(x + TRI_W, cy + 3), Vector2(x, cy)]
					"right": pts = [Vector2(x, cy - 3), Vector2(x, cy + 3), Vector2(x + TRI_W, cy)]
				draw_colored_polygon(pts, StartMenuMainSkin.C_FOOTER)
				x += TRI_W + GAP
			else:
				var text := str(item.t)
				var ascent: float = StartMenuMainSkin.FONT.get_ascent(StartMenuMainSkin.FS_KBD)
				draw_string(StartMenuMainSkin.FONT, Vector2(x, cy + ascent * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, StartMenuMainSkin.FS_KBD, StartMenuMainSkin.C_FOOTER)
				x += StartMenuMainSkin.FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, StartMenuMainSkin.FS_KBD).x + GAP


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

	_build_name_panel()
	_build_menu_panel()
	_build_description_panel()
	_build_stats_panel()
	_build_footer()

	_refresh_all()
	_play_entry()


func _build_name_panel() -> void:
	var holder := _holder(_v(NAME_POS), _v(NAME_SIZE))
	_add_chamfer(holder, NAME_OUTER, [{"poly": NAME_INNER, "tone": "paper"}])

	var star := StarBadge.new()
	star.position = _v(STAR_POS)
	star.size = Vector2.ONE * _s(STAR_SIZE)
	star.mouse_filter = MOUSE_FILTER_IGNORE
	holder.add_child(star)

	var orb := HpOrb.new()
	orb.position = _v(ORB_POS)
	orb.size = Vector2.ONE * _s(ORB_SIZE)
	orb.mouse_filter = MOUSE_FILTER_IGNORE
	holder.add_child(orb)

	_name_label = _make_label(_character_name(), FS_MAIN, C_TEXT)
	_name_label.position = _v(Vector2(66, 33))
	_name_label.size = Vector2(_s(150), _s(48))
	_name_label.clip_text = true
	holder.add_child(_name_label)

	_hp_bar = HpBar.new()
	_hp_bar.position = _v(Vector2(68, 80))
	_hp_bar.size = _v(Vector2(195, 18))
	_hp_bar.mouse_filter = MOUSE_FILTER_IGNORE
	holder.add_child(_hp_bar)
	set_meta("holder_name", holder)


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
	var holder := _holder(_v(STATS_POS), _v(STATS_SIZE))
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


func _build_footer() -> void:
	# Mock: [↑↓ / W S] Select [←→ / Q E] Page [ENTER] Confirm — adapted to the
	# game's real bindings (arrows/dpad, LB/RB page flip, Enter/Start accept).
	var holder := Control.new()
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(holder)
	set_meta("holder_footer", holder)

	var groups := [
		{"chip": [{"g": "up"}, {"g": "down"}, {"t": "/ D-PAD"}], "label": "Select"},
		{"chip": [{"g": "left"}, {"g": "right"}, {"t": "/ LB RB"}], "label": "Page"},
		{"chip": [{"t": "ENTER"}], "label": "Confirm"},
	]
	var gap := _s(24)
	var row_h := _s(30)
	var x := 0.0
	for group in groups:
		var chip := KbdChip.new()
		chip.items = group.chip
		chip.size = Vector2(chip.measure(), _s(24))
		chip.position = Vector2(x, (row_h - chip.size.y) * 0.5)
		holder.add_child(chip)
		x += chip.size.x + _s(10)
		var lbl := _make_label(str(group.label), FS_FOOTER, C_FOOTER)
		lbl.size = Vector2(FONT.get_string_size(str(group.label), HORIZONTAL_ALIGNMENT_LEFT, -1, FS_FOOTER).x + 2, row_h)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.position = Vector2(x, 0)
		holder.add_child(lbl)
		x += lbl.size.x + gap
	holder.size = Vector2(x, row_h)
	holder.position = Vector2(VIEW_W - _s(42) - x, VIEW_H - _s(24) - row_h)


# ── Refresh / sync ──────────────────────────────────────────────────────────────


## Called every frame by PsoStartMenu._process while the menu is open. Diffs
## controller state and refreshes only what changed, so StartMenuInput stays
## the single owner of input (it never learns the skin exists).
func sync() -> void:
	var in_main: bool = _c._mode == _c.Mode.MAIN
	if in_main != _last_in_main:
		_last_in_main = in_main
		visible = in_main
		HudStats.visible = not in_main  # NamePanel already shows name+HP
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
	var hp_frac := _hp_fraction()
	if absf(hp_frac - _last_hp_frac) > 0.001:
		_last_hp_frac = hp_frac
		_animate_hp(hp_frac)


func _refresh_all() -> void:
	_name_label.text = _character_name()
	_refresh_selection()
	_refresh_stats(false)
	_last_hp_frac = _hp_fraction()
	_animate_hp(_last_hp_frac)


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


func _animate_hp(target: float) -> void:
	var tw := create_tween()
	tw.tween_property(_hp_bar, "fraction", target, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Mock's staggered entry cascade: left panels slide in from the left, stats
## and footer slide up — 0/80/160/240/400ms, 550ms ease-out.
func _play_entry() -> void:
	var specs := [
		[get_meta("holder_name"), Vector2(-28, 0), 0.0],
		[get_meta("holder_menu"), Vector2(-28, 0), 0.08],
		[get_meta("holder_desc"), Vector2(-28, 0), 0.16],
		[get_meta("holder_stats"), Vector2(0, 28), 0.24],
		[get_meta("holder_footer"), Vector2(0, 28), 0.4],
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
	# HP bar sweeps up from empty (mock: 500ms ease-out width transition).
	_hp_bar.fraction = 0.0
	_last_hp_frac = _hp_fraction()
	_animate_hp(_last_hp_frac)


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


func _character_name() -> String:
	return str(_c._get_character().get("name", "???"))


func _hp_fraction() -> float:
	var ch: Dictionary = _c._get_character()
	var class_data = ClassRegistry.get_class_data(str(ch.get("class_id", "")))
	var level := int(ch.get("level", 1))
	var base_hp := 1
	if class_data != null:
		base_hp = class_data.get_stat_at_level("hp", level)
	var max_hp := maxi(base_hp + int(ch.get("material_bonuses", {}).get("hp", 0)), 1)
	var hp := int(ch.get("hp", max_hp))
	return clampf(float(hp) / float(max_hp), 0.0, 1.0)


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

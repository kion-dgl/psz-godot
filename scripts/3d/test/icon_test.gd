extends Control
## Test scene to debug HUD icon rendering at different sizes and backgrounds

var _icons: Array[Texture2D] = []
var _icon_names: Array[String] = []

func _ready() -> void:
	# Load a few test icons
	var test_files := ["attack.png", "Foie.png", "monomate.png", "dodge.png"]
	for f in test_files:
		var path: String = "res://assets/hud/" + f
		if ResourceLoader.exists(path):
			_icons.append(load(path))
			_icon_names.append(f)

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var y := 20.0

	# Row 1: Raw draw_texture_rect on default background
	draw_string(font, Vector2(10, y), "Raw (no background):", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	y += 20
	for i in range(_icons.size()):
		draw_texture_rect(_icons[i], Rect2(10 + i * 50, y, 40, 40), false)
	y += 50

	# Row 2: Black rect behind
	draw_string(font, Vector2(10, y), "Black rect behind:", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	y += 20
	for i in range(_icons.size()):
		var r := Rect2(10 + i * 50, y, 40, 40)
		draw_rect(r, Color.BLACK)
		draw_texture_rect(_icons[i], r, false)
	y += 50

	# Row 3: Dark grey pill behind
	draw_string(font, Vector2(10, y), "Dark pill behind (0.08, 0.08, 0.12):", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	y += 20
	for i in range(_icons.size()):
		var r := Rect2(10 + i * 50, y, 40, 40)
		draw_rect(r, Color(0.08, 0.08, 0.12, 0.7))
		draw_texture_rect(_icons[i], r, false)
	y += 50

	# Row 4: Smaller (28x28) with black rect
	draw_string(font, Vector2(10, y), "28x28 black rect:", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	y += 20
	for i in range(_icons.size()):
		var r := Rect2(10 + i * 40, y, 28, 28)
		draw_rect(r, Color.BLACK)
		draw_texture_rect(_icons[i], r, false)
	y += 38

	# Row 5: TEXTURE_FILTER_NEAREST + black rect
	draw_string(font, Vector2(10, y), "32x32 black rect + nearest filter (current approach):", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	y += 20
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for i in range(_icons.size()):
		var r := Rect2(10 + i * 42, y, 32, 32)
		draw_rect(r, Color.BLACK)
		draw_texture_rect(_icons[i], r, false)
	y += 42

	# Row 6: LINEAR filter + black rect
	draw_string(font, Vector2(10, y), "32x32 black rect + linear filter:", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	y += 20
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for i in range(_icons.size()):
		var r := Rect2(10 + i * 42, y, 32, 32)
		draw_rect(r, Color.BLACK)
		draw_texture_rect(_icons[i], r, false)
	y += 42

	# Row 7: Full size (200x173) for reference
	draw_string(font, Vector2(10, y), "Full size (200x173) for reference:", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	y += 20
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _icons.size() > 0:
		draw_texture_rect(_icons[0], Rect2(10, y, 200, 173), false)
		draw_texture_rect(_icons[1], Rect2(220, y, 200, 173), false)

	# Labels
	for i in range(_icons.size()):
		draw_string(font, Vector2(10 + i * 50, 110), _icon_names[i].get_basename(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.YELLOW)

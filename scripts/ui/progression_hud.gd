extends Control
## Four separate bent blocks follow the HUD rim; diagonal seams stay unfilled.
## Coordinates are relative to the backdrop, preserving its black center/bevels.
const BLOCKS := [
	[Vector2(31, 38), Vector2(46, 38), Vector2(58, 50), Vector2(53, 55), Vector2(43, 45), Vector2(34, 45), Vector2(29, 40)],
	[Vector2(61, 53), Vector2(61, 69), Vector2(50, 80), Vector2(45, 75), Vector2(54, 66), Vector2(54, 59), Vector2(60, 53)],
	[Vector2(47, 83), Vector2(46, 84), Vector2(31, 84), Vector2(20, 73), Vector2(25, 68), Vector2(34, 77), Vector2(41, 77)],
	[Vector2(17, 69), Vector2(16, 68), Vector2(16, 53), Vector2(27, 42), Vector2(32, 47), Vector2(23, 56), Vector2(23, 63)],
]
const ORIGIN := Vector2(16, 38)
const CENTER := Vector2(39, 61)
const FILL_COLOR := Color(1.0, 0.9, 0.0)
var _ratio: float = 0.0

func _ready() -> void:
	position = Vector2(16, 38)
	size = Vector2(46, 47)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
	var next_ratio := 0.0
	if not PhotonBlast.equipped_blast().is_empty():
		next_ratio = clampf(float(PhotonBlast.gauge) / PhotonBlast.MAX_GAUGE, 0.0, 1.0)
	if not is_equal_approx(next_ratio, _ratio):
		_ratio = next_ratio
		queue_redraw()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _ratio >= 1.0 else Control.CURSOR_ARROW

func _draw() -> void:
	if _ratio <= 0.0:
		return
	# Clip the four blocks by a clockwise sweep. The gaps are never painted.
	var sweep := PackedVector2Array([CENTER])
	var steps := maxi(1, ceili(64.0 * _ratio))
	for i in range(steps + 1):
		var angle := deg_to_rad(-112.5) + TAU * _ratio * float(i) / steps
		sweep.append(CENTER + Vector2(cos(angle), sin(angle)) * 64.0)
	for block in BLOCKS:
		var polygon := PackedVector2Array(block)
		var pieces: Array[PackedVector2Array] = [polygon]
		if _ratio < 1.0:
			pieces = Geometry2D.intersect_polygons(polygon, sweep)
		for piece in pieces:
			for i in piece.size():
				piece[i] -= ORIGIN
			draw_colored_polygon(piece, FILL_COLOR)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _ratio >= 1.0 and not GameState.is_gameplay_blocked():
			var player = get_tree().get_first_node_in_group("player")
			if player:
				PhotonBlast.activate(player)
		accept_event()

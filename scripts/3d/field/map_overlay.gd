extends Control
## Debug map overlay — draws grid cells with connections and current position.
## Added as child of a CanvasLayer, toggled with Tab key.

const CELL_SIZE := 40.0
const CELL_GAP := 4.0
const MARGIN := 20.0

var cells: Array = []
var current_pos: String = ""
var section_info: String = ""
var top_offset: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	if cells.is_empty():
		return

	# Find grid bounds
	var min_r := 999
	var max_r := -999
	var min_c := 999
	var max_c := -999
	for cell in cells:
		var pos: String = str(cell.get("pos", "0,0"))
		var parts := pos.split(",")
		var r := int(parts[0])
		var c := int(parts[1])
		min_r = mini(min_r, r)
		max_r = maxi(max_r, r)
		min_c = mini(min_c, c)
		max_c = maxi(max_c, c)

	var step: float = CELL_SIZE + CELL_GAP
	var grid_w: float = (max_c - min_c + 1) * step
	var grid_h: float = (max_r - min_r + 1) * step
	var viewport_size := get_viewport_rect().size
	var origin := Vector2(viewport_size.x - grid_w - MARGIN, MARGIN + 20 + top_offset)

	# Header
	draw_string(ThemeDB.fallback_font, Vector2(origin.x, origin.y - 4),
		section_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

	# Background
	draw_rect(Rect2(origin - Vector2(6, 6), Vector2(grid_w + 12, grid_h + 12)),
		Color(0, 0, 0, 0.7))

	# Compute cell centers
	var centers: Dictionary = {}
	for cell in cells:
		var pos: String = str(cell.get("pos", "0,0"))
		var parts := pos.split(",")
		var r := int(parts[0]) - min_r
		var c := int(parts[1]) - min_c
		centers[pos] = Vector2(origin.x + c * step + CELL_SIZE / 2.0,
			origin.y + r * step + CELL_SIZE / 2.0)

	# Draw connections (lines behind cells)
	for cell in cells:
		var pos: String = str(cell.get("pos", "0,0"))
		if not centers.has(pos):
			continue
		var from: Vector2 = centers[pos]
		var connections: Dictionary = cell.get("connections", {})
		for dir in connections:
			var target: String = str(connections[dir])
			if centers.has(target):
				draw_line(from, centers[target], Color(1, 1, 1, 0.3), 2.0)

	# Draw cells
	for cell in cells:
		var pos: String = str(cell.get("pos", "0,0"))
		var parts := pos.split(",")
		var r := int(parts[0]) - min_r
		var c := int(parts[1]) - min_c
		var x: float = origin.x + c * step
		var y: float = origin.y + r * step

		var color: Color
		if pos == current_pos:
			color = Color(0, 1, 0, 0.9)
		elif cell.get("is_start", false):
			color = Color(0.2, 0.6, 1.0, 0.8)
		elif cell.get("is_end", false):
			color = Color(1.0, 0.3, 0.3, 0.8)
		elif cell.get("is_branch", false):
			color = Color(0.8, 0.6, 0.2, 0.7)
		else:
			color = Color(0.5, 0.5, 0.5, 0.7)

		draw_rect(Rect2(x, y, CELL_SIZE, CELL_SIZE), color)

		# Short stage label (e.g., "lb1" from "s01a_lb1")
		var stage_id: String = str(cell.get("stage_id", ""))
		var label: String = stage_id.substr(stage_id.rfind("_") + 1)
		draw_string(ThemeDB.fallback_font, Vector2(x + 2, y + CELL_SIZE / 2.0 + 4),
			label, HORIZONTAL_ALIGNMENT_LEFT, int(CELL_SIZE - 4), 10, Color.WHITE)

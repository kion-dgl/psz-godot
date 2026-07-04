extends Control
## PSZ area-map overlay (spec /states/area-map): a centered plate at ~70%
## opacity and 50% of the viewport height, toggled with the `area_map`
## action (R2 trigger / M). Replaces both the debug map_overlay and the
## top-right grid_minimap.
##
## Fog of war: only cells the player has VISITED render; everything else
## stays a dark window. DebugConfig.reveal_map (the tester toggle in the
## start-menu options) shows the full grid. Revealed cells draw their doors
## (green = open, red = locked), the start cell carries the return-warp
## marker (cyan — the warp back to the city), and the section's exit edge
## the area-warp marker (blue) to the next grid.
##
## Drawn over assets/ui/hud/map_grid.png when present — kion's 5×5 grid
## sheet (1024 px wide, cell windows 107 px at 139 + col·120 / 219 + row·120).
## Until the sprite lands in the pack, a procedural plate with identical
## geometry stands in, so dropping the PNG changes only the skin.

const SPRITE_PATH := "res://assets/ui/hud/map_grid.png"

# Sprite-sheet geometry (kion's map grid sprite)
const SHEET_W := 1024.0
const SHEET_H := 977.0
const CELL0 := Vector2(139.0, 219.0)
const CELL_PX := 107.0
const CELL_STRIDE := 120.0
const GRID_N := 5

const OVERLAY_ALPHA := 0.7
const HEIGHT_FRAC := 0.5

# PSZ palette (procedural fallback mirrors the sprite's colors)
const PLATE_BG := Color(0.78, 0.86, 0.94)
const PLATE_BORDER := Color(0.45, 0.55, 0.68)
const WINDOW_BG := Color(0.13, 0.17, 0.23)
const VISITED_COLOR := Color(0.25, 0.45, 0.72, 0.9)
const CURRENT_COLOR := Color(0.35, 0.85, 0.45, 0.95)
const DOOR_OPEN_COLOR := Color(0.27, 1.0, 0.27)
const DOOR_LOCKED_COLOR := Color(1.0, 0.3, 0.3)
const RETURN_WARP_COLOR := Color(0.3, 0.95, 1.0)
const AREA_WARP_COLOR := Color(0.29, 0.62, 1.0)
const HEADER_TEXT := Color(0.16, 0.22, 0.34)

const DIR_OFFSETS := {
	"north": Vector2i(-1, 0),
	"south": Vector2i(1, 0),
	"east": Vector2i(0, 1),
	"west": Vector2i(0, -1),
}

var _cells: Array = []
var _current_pos: String = ""
var _visited_cells: Dictionary = {}
var _gate_states: Dictionary = {}  # "pos>dir" → "open"|"locked"|"exit"
var _section_label: String = ""
var _cell_lookup: Dictionary = {}
var _min_row: int = 0
var _min_col: int = 0
var _row_off: int = 0  # centers smaller grids inside the 5×5 windows
var _col_off: int = 0
var _sheet_tex: Texture2D = null


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	modulate.a = OVERLAY_ALPHA
	if ResourceLoader.exists(SPRITE_PATH):
		_sheet_tex = load(SPRITE_PATH)
	_update_layout()
	get_viewport().size_changed.connect(_update_layout)


## Same wiring contract the grid_minimap had — the field controller calls
## setup on every cell load and set_gate_state on gate changes.
func setup(cells: Array, current_pos: String, visited_cells: Dictionary,
		section_label: String) -> void:
	_cells = cells
	_current_pos = current_pos
	_visited_cells = visited_cells
	_section_label = section_label

	_cell_lookup.clear()
	_min_row = 999
	_min_col = 999
	var max_row := -999
	var max_col := -999
	for cell in _cells:
		var pos: String = str(cell.get("pos", "0,0"))
		_cell_lookup[pos] = cell
		var rc := _parse_pos(pos)
		_min_row = mini(_min_row, rc.x)
		_min_col = mini(_min_col, rc.y)
		max_row = maxi(max_row, rc.x)
		max_col = maxi(max_col, rc.y)
	_row_off = maxi(0, (GRID_N - (max_row - _min_row + 1)) / 2)
	_col_off = maxi(0, (GRID_N - (max_col - _min_col + 1)) / 2)

	_init_gate_states()
	queue_redraw()


func _init_gate_states() -> void:
	for cell in _cells:
		var pos: String = str(cell.get("pos", "0,0"))
		var connections: Dictionary = cell.get("connections", {})
		for dir in connections:
			var key := "%s>%s" % [pos, dir]
			if not _gate_states.has(key):
				_gate_states[key] = "open"
		var warp_edge: String = str(cell.get("warp_edge", ""))
		if not warp_edge.is_empty():
			_gate_states["%s>%s" % [pos, warp_edge]] = "exit"


func set_gate_state(cell_pos: String, direction: String, state: String) -> void:
	_gate_states["%s>%s" % [cell_pos, direction]] = state
	queue_redraw()


## Fog of war (spec /states/area-map): a cell renders only once visited —
## or when the tester reveal toggle is on.
func _is_revealed(pos: String) -> bool:
	if DebugConfig.reveal_map:
		return true
	return pos == _current_pos or _visited_cells.has(pos)


## Centered, 50% of the viewport height, width from the sheet aspect.
func _update_layout() -> void:
	var vp_h := 600.0
	if is_inside_tree():
		vp_h = get_viewport_rect().size.y
	var h := vp_h * HEIGHT_FRAC
	var w := h * (SHEET_W / SHEET_H)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = -h * 0.5
	offset_bottom = h * 0.5
	size = Vector2(w, h)
	queue_redraw()


func _window_rect(pos: String, sc: float) -> Rect2:
	var rc := _parse_pos(pos)
	var row: int = rc.x - _min_row + _row_off
	var col: int = rc.y - _min_col + _col_off
	row = clampi(row, 0, GRID_N - 1)
	col = clampi(col, 0, GRID_N - 1)
	return Rect2(
		(CELL0.x + col * CELL_STRIDE) * sc,
		(CELL0.y + row * CELL_STRIDE) * sc,
		CELL_PX * sc, CELL_PX * sc)


func _draw() -> void:
	if _cells.is_empty():
		return
	var sc: float = size.x / SHEET_W
	var font := ThemeDB.fallback_font

	# Backdrop: the sprite sheet, or the procedural stand-in with the same
	# window geometry.
	if _sheet_tex:
		draw_texture_rect(_sheet_tex, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), PLATE_BG)
		draw_rect(Rect2(Vector2.ZERO, size), PLATE_BORDER, false, 3.0 * sc)
		for row in range(GRID_N):
			for col in range(GRID_N):
				draw_rect(Rect2(
					(CELL0.x + col * CELL_STRIDE) * sc,
					(CELL0.y + row * CELL_STRIDE) * sc,
					CELL_PX * sc, CELL_PX * sc), WINDOW_BG)

	# Section label along the sprite's top bar
	draw_string(font, Vector2(CELL0.x * sc, 100.0 * sc), _section_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(40.0 * sc), HEADER_TEXT)

	for cell in _cells:
		var pos: String = str(cell.get("pos", "0,0"))
		if not _is_revealed(pos):
			continue
		var win := _window_rect(pos, sc)
		var inset: float = 6.0 * sc
		var fill := win.grow(-inset)
		draw_rect(fill, CURRENT_COLOR if pos == _current_pos else VISITED_COLOR)

		# Doors on each connected edge: green open / red locked
		var connections: Dictionary = cell.get("connections", {})
		for dir in connections:
			var state: String = str(_gate_states.get("%s>%s" % [pos, dir], "open"))
			var color: Color = DOOR_LOCKED_COLOR if state == "locked" else DOOR_OPEN_COLOR
			_draw_edge_marker(win, dir, color, sc, false)

		# Area warp to the next grid on the exit edge (blue, arrow-ish)
		var warp_edge: String = str(cell.get("warp_edge", ""))
		if not warp_edge.is_empty():
			var wstate: String = str(_gate_states.get("%s>%s" % [pos, warp_edge], "exit"))
			var wcolor: Color = DOOR_LOCKED_COLOR if wstate == "locked" else AREA_WARP_COLOR
			_draw_edge_marker(win, warp_edge, wcolor, sc, true)

		# Return warp to the city lives in the start cell (cyan ring)
		if cell.get("is_start", false):
			var c := win.get_center()
			draw_arc(c, 16.0 * sc, 0.0, TAU, 20, RETURN_WARP_COLOR, 4.0 * sc)


## Door / warp notch centered on one edge of a cell window. Warp markers are
## longer and extend outward so they read as "leads out of the grid".
func _draw_edge_marker(win: Rect2, dir: String, color: Color, sc: float, is_warp: bool) -> void:
	var length: float = (46.0 if is_warp else 34.0) * sc
	var thickness: float = (14.0 if is_warp else 10.0) * sc
	var c := win.get_center()
	var half_w := win.size.x * 0.5
	var half_h := win.size.y * 0.5
	match dir:
		"north":
			draw_rect(Rect2(c.x - length * 0.5, win.position.y - thickness * 0.5, length, thickness), color)
		"south":
			draw_rect(Rect2(c.x - length * 0.5, win.position.y + half_h * 2.0 - thickness * 0.5, length, thickness), color)
		"east":
			draw_rect(Rect2(win.position.x + half_w * 2.0 - thickness * 0.5, c.y - length * 0.5, thickness, length), color)
		"west":
			draw_rect(Rect2(win.position.x - thickness * 0.5, c.y - length * 0.5, thickness, length), color)


func _parse_pos(pos: String) -> Vector2i:
	var parts := pos.split(",")
	if parts.size() >= 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO

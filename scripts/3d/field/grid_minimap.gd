extends Control
## Grid-level minimap HUD — shows the section grid layout with visited cells,
## current cell highlighted, and gate/door states color-coded.
## Toggled with M key. Drawn below the room minimap in the top-right corner.

const CELL_SIZE := 16.0
const CELL_GAP := 3.0
const GATE_THICKNESS := 3.0
const GATE_LENGTH := 8.0
const PANEL_PAD := 6.0

# PSZ palette
const PANEL_BG := Color(0.66, 0.80, 0.91, 0.5)
const PANEL_BORDER := Color(0.48, 0.63, 0.75, 0.4)
const SCANLINE_COLOR := Color(0.47, 0.63, 0.78, 0.06)
const UNVISITED_COLOR := Color(0.12, 0.18, 0.28, 0.5)
const VISITED_COLOR := Color(0.2, 0.4, 0.7, 0.6)
const CURRENT_COLOR := Color(0.2, 0.9, 0.3, 0.85)
const GATE_OPEN_COLOR := Color(0.27, 1.0, 0.27)
const GATE_LOCKED_COLOR := Color(1.0, 0.3, 0.3)
const GATE_EXIT_COLOR := Color(0.29, 0.62, 1.0)
const HEADER_BG := Color(0.16, 0.16, 0.22, 0.7)
const HEADER_TEXT := Color(1.0, 1.0, 1.0, 0.9)
const FONT_SIZE_HEADER := 9

# Direction offsets for connection lines (row, col deltas)
const DIR_OFFSETS := {
	"north": Vector2i(-1, 0),
	"south": Vector2i(1, 0),
	"east": Vector2i(0, 1),
	"west": Vector2i(0, -1),
}

# Data set by field controller
var _cells: Array = []
var _current_pos: String = ""
var _visited_cells: Dictionary = {}
var _gate_states: Dictionary = {}  # "from_pos>dir" → "open"|"locked"|"exit"
var _section_label: String = ""

# Parsed grid data
var _cell_lookup: Dictionary = {}  # pos → cell dict
var _min_row: int = 0
var _min_col: int = 0
var _max_row: int = 0
var _max_col: int = 0
var _grid_w: float = 0.0
var _grid_h: float = 0.0


func setup(cells: Array, current_pos: String, visited_cells: Dictionary,
		section_label: String) -> void:
	_cells = cells
	_current_pos = current_pos
	_visited_cells = visited_cells
	_section_label = section_label
	mouse_filter = MOUSE_FILTER_IGNORE

	# Build lookup and compute bounds
	_cell_lookup.clear()
	_min_row = 999
	_max_row = -999
	_min_col = 999
	_max_col = -999
	for cell in _cells:
		var pos: String = str(cell.get("pos", "0,0"))
		_cell_lookup[pos] = cell
		var rc := _parse_pos(pos)
		_min_row = mini(_min_row, rc.x)
		_max_row = maxi(_max_row, rc.x)
		_min_col = mini(_min_col, rc.y)
		_max_col = maxi(_max_col, rc.y)

	var cols: int = _max_col - _min_col + 1
	var rows: int = _max_row - _min_row + 1
	var step: float = CELL_SIZE + CELL_GAP
	_grid_w = cols * step - CELL_GAP
	_grid_h = rows * step - CELL_GAP

	var header_h := 16.0
	var total_w: float = _grid_w + PANEL_PAD * 2
	var total_h: float = _grid_h + PANEL_PAD * 2 + header_h
	custom_minimum_size = Vector2(total_w, total_h)
	size = Vector2(total_w, total_h)

	# Anchor top-right, below the room minimap (offset down ~150px)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -total_w - 12
	offset_right = -12
	offset_top = 150
	offset_bottom = 150 + total_h

	# Initialize gate states from cell connections
	_init_gate_states()


func _init_gate_states() -> void:
	## Build initial gate state for every connection.
	## By default gates between visited cells are open; gates to unvisited cells
	## start as open (they get locked by the field controller when enemies spawn).
	for cell in _cells:
		var pos: String = str(cell.get("pos", "0,0"))
		var connections: Dictionary = cell.get("connections", {})
		var warp_edge: String = str(cell.get("warp_edge", ""))
		for dir in connections:
			var key := "%s>%s" % [pos, dir]
			if not _gate_states.has(key):
				_gate_states[key] = "open"
		# Mark warp_edge as exit
		if not warp_edge.is_empty():
			var exit_key := "%s>%s" % [pos, warp_edge]
			_gate_states[exit_key] = "exit"


func set_gate_state(cell_pos: String, direction: String, state: String) -> void:
	## state: "open", "locked", or "exit"
	var key := "%s>%s" % [cell_pos, direction]
	_gate_states[key] = state
	queue_redraw()


# ── Drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _cells.is_empty():
		return

	var font := ThemeDB.fallback_font
	var total_w: float = size.x
	var total_h: float = size.y

	# Panel background
	var panel_rect := Rect2(Vector2.ZERO, Vector2(total_w, total_h))
	draw_rect(panel_rect, PANEL_BG)
	draw_rect(panel_rect, PANEL_BORDER, false, 2.0)

	# Scanlines
	for sy in range(0, int(total_h), 4):
		draw_rect(Rect2(0, sy + 2, total_w, 2), SCANLINE_COLOR)

	# Header
	var header_h := 16.0
	draw_rect(Rect2(0, 0, total_w, header_h), HEADER_BG)
	var header_text := "Map"
	if not _section_label.is_empty():
		header_text = _section_label
	draw_string(font, Vector2(PANEL_PAD, 11), header_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_HEADER, HEADER_TEXT)

	var step: float = CELL_SIZE + CELL_GAP
	var grid_origin := Vector2(PANEL_PAD, PANEL_PAD + header_h)

	# Draw gate/connection lines first (behind cells)
	var drawn_connections: Dictionary = {}  # Track drawn connections to avoid duplicates
	for cell in _cells:
		var pos: String = str(cell.get("pos", "0,0"))
		var rc := _parse_pos(pos)
		var cx: float = grid_origin.x + (rc.y - _min_col) * step + CELL_SIZE * 0.5
		var cy: float = grid_origin.y + (rc.x - _min_row) * step + CELL_SIZE * 0.5

		var connections: Dictionary = cell.get("connections", {})
		for dir in connections:
			var target_pos: String = str(connections[dir])
			# Create a unique key to avoid drawing the same connection twice
			var conn_key: String
			if pos < target_pos:
				conn_key = "%s-%s" % [pos, target_pos]
			else:
				conn_key = "%s-%s" % [target_pos, pos]
			if drawn_connections.has(conn_key):
				continue
			drawn_connections[conn_key] = true

			# Only draw if target cell exists
			if not _cell_lookup.has(target_pos):
				continue

			var target_rc := _parse_pos(target_pos)
			var tx: float = grid_origin.x + (target_rc.y - _min_col) * step + CELL_SIZE * 0.5
			var ty: float = grid_origin.y + (target_rc.x - _min_row) * step + CELL_SIZE * 0.5

			# Determine gate color from state
			var gate_key := "%s>%s" % [pos, dir]
			var state: String = _gate_states.get(gate_key, "open")
			var gate_color: Color
			match state:
				"locked":
					gate_color = GATE_LOCKED_COLOR
				"exit":
					gate_color = GATE_EXIT_COLOR
				_:
					gate_color = GATE_OPEN_COLOR

			# Draw the connection line in the gap between cells
			var midx: float = (cx + tx) * 0.5
			var midy: float = (cy + ty) * 0.5
			var offset: Vector2i = DIR_OFFSETS.get(dir, Vector2i.ZERO)
			if offset.x != 0:
				# Vertical connection (north/south) — draw horizontal gate bar at midpoint
				draw_rect(Rect2(midx - GATE_LENGTH * 0.5, midy - GATE_THICKNESS * 0.5,
					GATE_LENGTH, GATE_THICKNESS), gate_color)
			else:
				# Horizontal connection (east/west) — draw vertical gate bar at midpoint
				draw_rect(Rect2(midx - GATE_THICKNESS * 0.5, midy - GATE_LENGTH * 0.5,
					GATE_THICKNESS, GATE_LENGTH), gate_color)

		# Draw warp_edge (exit) gate on the outer edge
		var warp_edge: String = str(cell.get("warp_edge", ""))
		if not warp_edge.is_empty():
			var warp_key := "%s>%s" % [pos, warp_edge]
			var warp_state: String = _gate_states.get(warp_key, "exit")
			var warp_color: Color
			match warp_state:
				"locked":
					warp_color = GATE_LOCKED_COLOR
				_:
					warp_color = GATE_EXIT_COLOR

			var wo: Vector2i = DIR_OFFSETS.get(warp_edge, Vector2i.ZERO)
			var edge_x: float = cx + wo.y * (CELL_SIZE * 0.5 + CELL_GAP * 0.5)
			var edge_y: float = cy + wo.x * (CELL_SIZE * 0.5 + CELL_GAP * 0.5)
			if wo.x != 0:
				# North/south edge — horizontal bar
				draw_rect(Rect2(edge_x - GATE_LENGTH * 0.5, edge_y - GATE_THICKNESS * 0.5,
					GATE_LENGTH, GATE_THICKNESS), warp_color)
			else:
				# East/west edge — vertical bar
				draw_rect(Rect2(edge_x - GATE_THICKNESS * 0.5, edge_y - GATE_LENGTH * 0.5,
					GATE_THICKNESS, GATE_LENGTH), warp_color)

	# Draw cells
	for cell in _cells:
		var pos: String = str(cell.get("pos", "0,0"))
		var rc := _parse_pos(pos)
		var x: float = grid_origin.x + (rc.y - _min_col) * step
		var y: float = grid_origin.y + (rc.x - _min_row) * step

		var color: Color
		if pos == _current_pos:
			color = CURRENT_COLOR
		elif _visited_cells.has(pos):
			color = VISITED_COLOR
		else:
			color = UNVISITED_COLOR

		draw_rect(Rect2(x, y, CELL_SIZE, CELL_SIZE), color)

		# Draw a small dot for start/end cells
		if cell.get("is_start", false):
			draw_circle(Vector2(x + CELL_SIZE * 0.5, y + CELL_SIZE * 0.5), 2.0,
				Color(1.0, 1.0, 1.0, 0.6))
		if cell.get("is_end", false) or not str(cell.get("warp_edge", "")).is_empty():
			draw_rect(Rect2(x + CELL_SIZE * 0.25, y + CELL_SIZE * 0.25,
				CELL_SIZE * 0.5, CELL_SIZE * 0.5), Color(1.0, 1.0, 1.0, 0.4), false, 1.0)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _parse_pos(pos: String) -> Vector2i:
	var parts := pos.split(",")
	if parts.size() >= 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO

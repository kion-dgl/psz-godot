extends Control
## Room-level minimap HUD — parses SVG minimap text and draws floor shape,
## gate markers with directional labels, and a live player position arrow
## via _draw().  Added as a child of the MapOverlay CanvasLayer.
##
## Uses embedded metadata from SVG (data-scale, data-offset-x/y) for player
## position tracking, matching the web PreviewMinimap approach.

const DISPLAY_SIZE := 120.0
const PANEL_PAD := 5.0  # padding around map inside blue panel
# PSZ palette — semi-transparent for single-screen
const PANEL_BG := Color(0.66, 0.80, 0.91, 0.5)     # Pale icy blue, translucent
const PANEL_BORDER := Color(0.48, 0.63, 0.75, 0.4)
const SCANLINE_COLOR := Color(0.47, 0.63, 0.78, 0.06)
const BG_COLOR := Color(0.08, 0.15, 0.23, 0.7)      # Dark map background
const FLOOR_COLOR := Color(0.16, 0.16, 0.31)
const BOUNDARY_COLOR := Color(1.0, 1.0, 1.0, 0.6)
const PLAYER_COLOR := Color(0.0, 1.0, 0.0)
const GATE_OPEN := Color(0.27, 1.0, 0.27)
const GATE_LOCKED := Color(1.0, 0.3, 0.3)
const GATE_EXIT := Color(0.29, 0.62, 1.0)
const GATE_WALL := Color(0.4, 0.4, 0.4)
const KEY_LABEL_COLOR := Color(0.1, 0.1, 0.17, 0.8)
const KEY_BG_ACTIVE := Color(0.8, 0.53, 0.27, 0.8)  # Orange for collected
const KEY_BG_INACTIVE := Color(0.59, 0.71, 0.82, 0.3)

var _floor_triangles: Array = []   # Array[PackedVector2Array] — 3 verts each
var _boundary_lines: Array = []    # Array[[Vector2, Vector2]]
var _gate_entries: Array = []      # Array[{center, color, label, dir}]
var _gate_dir_index: Dictionary = {}  # direction → index in _gate_entries
var _player_display_pos := Vector2.ZERO
var _player_display_dir := Vector2(0, 1)  # arrow direction in display space
var _has_player_tracking := false

# Key counter (drawn below minimap)
var _keys_collected: int = 0
var _keys_total: int = 0

# Embedded SVG transform metadata (from data-* attributes)
var _svg_scale := 0.0
var _svg_offset_x := 0.0
var _svg_offset_y := 0.0
var _rotation_deg: int = 0

const MINIMAP_DIRECTIONS := ["north", "east", "south", "west"]


func setup(stage_id: String, area_folder: String, portal_data: Dictionary,
		connections: Dictionary, warp_edge: String,
		map_root: Node3D, rotation_deg: int = 0, entry_edge: String = "") -> void:
	_rotation_deg = rotation_deg
	mouse_filter = MOUSE_FILTER_IGNORE
	var total_w: float = DISPLAY_SIZE + PANEL_PAD * 2 + 22  # extra for key column
	var total_h: float = DISPLAY_SIZE + PANEL_PAD * 2
	custom_minimum_size = Vector2(total_w, total_h)
	size = Vector2(total_w, total_h)

	# Anchor top-right with margin
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -total_w - 12
	offset_right = -12
	offset_top = 12
	offset_bottom = 12 + total_h

	# Load SVG text (not as texture — we need to parse geometry)
	var subfolder: String = "%s_%s" % [area_folder, stage_id[3]] if stage_id.length() >= 4 else area_folder
	var svg_path := "res://assets/stages/%s/%s/lndmd/%s_minimap.svg" % [subfolder, stage_id, stage_id]
	if not FileAccess.file_exists(svg_path):
		return
	var file := FileAccess.open(svg_path, FileAccess.READ)
	if not file:
		return
	var svg_text := file.get_as_text()
	file.close()

	# Parse geometry
	_parse_floor(svg_text)
	_parse_boundaries(svg_text)

	# Parse embedded transform metadata
	_parse_embedded_metadata(svg_text)

	# Parse gates with their baked direction (data-gate-dir attribute)
	var svg_gates := _parse_gates_with_dirs(svg_text)

	print("[RoomMinimap] stage=%s  svg_gates=%d  scale=%.2f  offset=(%.1f, %.1f)  rot=%d" % [
		stage_id, svg_gates.size(), _svg_scale, _svg_offset_x, _svg_offset_y, _rotation_deg])

	# Build gate entries using baked directions from SVG
	_build_gate_entries(svg_gates, connections, warp_edge, portal_data, entry_edge)

	# Enable player tracking if we have embedded metadata
	if _svg_scale > 0.0:
		_has_player_tracking = true

	for gate in _gate_entries:
		print("[RoomMinimap]   gate_entry: center=%s  color=%s  label='%s'  dir='%s'" % [
			gate["center"], gate["color"], gate["label"], gate["dir"]])


func set_gate_locked(direction: String, locked: bool) -> void:
	if not _gate_dir_index.has(direction):
		return
	var idx: int = _gate_dir_index[direction]
	var entry: Dictionary = _gate_entries[idx]
	# Don't override EXIT gates
	if entry["color"] == GATE_EXIT:
		return
	entry["color"] = GATE_LOCKED if locked else GATE_OPEN
	queue_redraw()


func update_player(global_pos: Vector3, facing_rad: float, map_root: Node3D) -> void:
	if not _has_player_tracking:
		return
	var inv := map_root.global_transform.affine_inverse()
	var local: Vector3 = inv * global_pos

	# Map model-local position to SVG coordinates using embedded metadata.
	# svgX = localX * scale + offsetX
	# svgY = localZ * scale + offsetY
	var svg_pos := Vector2(
		local.x * _svg_scale + _svg_offset_x,
		local.z * _svg_scale + _svg_offset_y)
	_player_display_pos = _svg_to_display(svg_pos)

	# Compute arrow direction by transforming a small forward step through the
	# same pipeline so it matches the display.
	var step_3d := global_pos + Vector3(sin(facing_rad), 0, cos(facing_rad)) * 0.5
	var step_local: Vector3 = inv * step_3d
	var step_svg := Vector2(
		step_local.x * _svg_scale + _svg_offset_x,
		step_local.z * _svg_scale + _svg_offset_y)
	var step_display := _svg_to_display(step_svg)
	var dir := (step_display - _player_display_pos)
	if dir.length_squared() > 0.0001:
		_player_display_dir = dir.normalized()
	queue_redraw()


# ── Drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var total_w: float = size.x
	var total_h: float = size.y

	# Blue panel background
	var panel_rect := Rect2(Vector2.ZERO, Vector2(total_w, total_h))
	draw_rect(panel_rect, PANEL_BG)
	draw_rect(panel_rect, PANEL_BORDER, false, 2.0)

	# Scanlines on panel
	for sy in range(0, int(total_h), 4):
		draw_rect(Rect2(0, sy + 2, total_w, 2), SCANLINE_COLOR)

	# Key indicators — left column inside panel
	var key_x := PANEL_PAD
	var key_y_start := PANEL_PAD
	if _keys_total > 0:
		for ki in range(_keys_total):
			var ky: float = key_y_start + ki * 18.0
			var key_bg: Color = KEY_BG_ACTIVE if ki < _keys_collected else KEY_BG_INACTIVE
			var key_rect := Rect2(key_x, ky, 14, 14)
			draw_rect(key_rect, key_bg)
			draw_rect(key_rect, Color(0, 0, 0, 0.15), false, 1.0)
			var letter := char(65 + ki)  # A, B, C...
			var letter_color: Color = Color(1, 1, 1) if ki < _keys_collected else KEY_LABEL_COLOR
			draw_string(font, Vector2(key_x + 3, ky + 11), letter,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, letter_color)

	# Map area offset — right of key column
	var map_offset := Vector2(22 + PANEL_PAD, PANEL_PAD)

	# Dark map background
	draw_rect(Rect2(map_offset, Vector2(DISPLAY_SIZE, DISPLAY_SIZE)), BG_COLOR)
	draw_rect(Rect2(map_offset, Vector2(DISPLAY_SIZE, DISPLAY_SIZE)), Color(0, 0, 0, 0.3), false, 1.0)

	# Floor triangles
	for tri in _floor_triangles:
		var pts := PackedVector2Array()
		for v in tri:
			pts.append(_svg_to_display(v) + map_offset)
		draw_polygon(pts, [FLOOR_COLOR])

	# Boundary edges
	for seg in _boundary_lines:
		draw_line(_svg_to_display(seg[0]) + map_offset, _svg_to_display(seg[1]) + map_offset,
			BOUNDARY_COLOR, 1.5)

	# Gate markers
	for gate in _gate_entries:
		var c: Vector2 = _svg_to_display(gate["center"]) + map_offset
		var d := 5.0
		draw_polygon(PackedVector2Array([
			c + Vector2(-d, -d), c + Vector2(d, -d),
			c + Vector2(d, d), c + Vector2(-d, d),
		]), [gate["color"]])
		var lbl: String = gate["label"]
		if not lbl.is_empty():
			draw_string(font, c + Vector2(-4, -8), lbl,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, gate["color"])

	# Player arrow
	if _has_player_tracking:
		var fwd := _player_display_dir
		var sz := 6.0
		var pp := _player_display_pos + map_offset
		draw_polygon(PackedVector2Array([
			pp + fwd * sz,
			pp + fwd.rotated(2.4) * sz * 0.6,
			pp + fwd.rotated(-2.4) * sz * 0.6,
		]), [PLAYER_COLOR])


func update_keys(collected: int, total: int) -> void:
	_keys_collected = collected
	_keys_total = total
	queue_redraw()


# ── SVG → Display transform ─────────────────────────────────────────────────

func _svg_to_display(svg_pos: Vector2) -> Vector2:
	## Apply cell rotation and scale SVG coordinates to display size.
	## SVG Y already increases downward (north=top), matching display space.
	var pos := Vector2(svg_pos.x, svg_pos.y)
	if _rotation_deg != 0:
		var center := Vector2(200.0, 200.0)
		pos = (pos - center).rotated(deg_to_rad(float(_rotation_deg))) + center
	return pos * (DISPLAY_SIZE / 400.0)


# ── SVG parsing ─────────────────────────────────────────────────────────────

func _parse_embedded_metadata(svg_text: String) -> void:
	## Parse data-scale, data-offset-x, data-offset-y from SVG root element.
	## These are baked by the stage editor's SVG exporter.
	var first_line := ""
	for line in svg_text.split("\n"):
		if "<svg" in line:
			first_line = line
			break
	if first_line.is_empty():
		return

	var scale_str := _attr(first_line, "data-scale")
	var off_x_str := _attr(first_line, "data-offset-x")
	var off_y_str := _attr(first_line, "data-offset-y")

	if not scale_str.is_empty():
		_svg_scale = float(scale_str)
	if not off_x_str.is_empty():
		_svg_offset_x = float(off_x_str)
	if not off_y_str.is_empty():
		_svg_offset_y = float(off_y_str)


func _parse_floor(svg_text: String) -> void:
	for line in svg_text.split("\n"):
		if 'fill="#2a2a4e"' not in line:
			continue
		var d := _attr(line, "d")
		if d.is_empty():
			continue
		for chunk in d.split(" Z "):
			chunk = chunk.strip_edges()
			if chunk.ends_with(" Z"):
				chunk = chunk.substr(0, chunk.length() - 2)
			if chunk.is_empty():
				continue
			var tri := _parse_triangle(chunk)
			if tri.size() == 3:
				_floor_triangles.append(tri)


func _parse_boundaries(svg_text: String) -> void:
	for line in svg_text.split("\n"):
		if 'stroke="white"' not in line or 'fill="none"' not in line:
			continue
		var d := _attr(line, "d")
		if d.is_empty():
			continue
		for seg in d.split(" M "):
			seg = seg.strip_edges()
			if seg.begins_with("M "):
				seg = seg.substr(2)
			if seg.is_empty():
				continue
			var parts := seg.split(" L ")
			if parts.size() == 2:
				_boundary_lines.append([
					_pt(parts[0].strip_edges()),
					_pt(parts[1].strip_edges()),
				])


func _parse_gates_with_dirs(svg_text: String) -> Array:
	## Parse gate markers and their baked direction from data-gate-dir attribute.
	## Returns Array of {center: Vector2, dir: String}.
	var gates: Array = []
	for line in svg_text.split("\n"):
		line = line.strip_edges()
		# New format: <rect ... data-gate="true" data-gate-dir="south" .../>
		if line.begins_with("<rect") and 'data-gate="true"' in line:
			var x := float(_attr(line, "x"))
			var y := float(_attr(line, "y"))
			var w := float(_attr(line, "width"))
			var h := float(_attr(line, "height"))
			var gate_dir := _attr(line, "data-gate-dir")
			gates.append({
				"center": Vector2(x + w * 0.5, y + h * 0.5),
				"dir": gate_dir,
			})
		# Legacy format: <polygon fill="#4a9eff" .../>
		elif line.begins_with("<polygon") and 'fill="#4a9eff"' in line:
			var ps := _attr(line, "points")
			if ps.is_empty():
				continue
			var sum := Vector2.ZERO
			var n := 0
			for pt in ps.strip_edges().split(" "):
				pt = pt.strip_edges()
				if pt.is_empty():
					continue
				var xy := pt.split(",")
				if xy.size() == 2:
					sum += Vector2(float(xy[0]), float(xy[1]))
					n += 1
			if n > 0:
				gates.append({"center": sum / float(n), "dir": ""})
	return gates


# ── Gate entries ─────────────────────────────────────────────────────────────

func _build_gate_entries(svg_gates: Array, connections: Dictionary,
		warp_edge: String, portal_data: Dictionary, entry_edge: String = "") -> void:
	## Build gate display entries.  Uses data-gate-dir from SVG to identify
	## gate directions (base stage direction), then rotates to grid direction.
	for gate in svg_gates:
		var svg_center: Vector2 = gate["center"]
		var base_dir: String = gate["dir"]  # direction in unrotated stage
		var color: Color
		var label: String
		var grid_dir: String = ""

		if not base_dir.is_empty():
			# Convert base stage direction to grid direction using cell rotation
			grid_dir = _rotate_dir(base_dir, _rotation_deg)

		if not grid_dir.is_empty():
			if grid_dir == warp_edge and not warp_edge.is_empty():
				color = GATE_EXIT
				label = "EXIT"
			elif not entry_edge.is_empty() and grid_dir == entry_edge:
				color = GATE_EXIT
				label = grid_dir.substr(0, 1).to_upper()
			elif connections.has(grid_dir):
				color = GATE_OPEN
				label = grid_dir.substr(0, 1).to_upper()
			else:
				color = GATE_WALL
				label = ""
		else:
			color = GATE_WALL
			label = ""

		_gate_entries.append({"center": svg_center, "color": color, "label": label, "dir": grid_dir})
		if not grid_dir.is_empty():
			_gate_dir_index[grid_dir] = _gate_entries.size() - 1


## Rotate a direction CW by the given degrees.
func _rotate_dir(dir: String, rotation: int) -> String:
	if rotation == 0:
		return dir
	var idx: int = MINIMAP_DIRECTIONS.find(dir)
	if idx < 0:
		return dir
	var steps: int = (rotation / 90) % 4
	return MINIMAP_DIRECTIONS[(idx + steps) % 4]


# ── Helpers ──────────────────────────────────────────────────────────────────

func _attr(line: String, attr_name: String) -> String:
	var key := attr_name + '="'
	var idx := line.find(key)
	if idx < 0:
		return ""
	var start := idx + key.length()
	var end_idx := line.find('"', start)
	if end_idx < 0:
		return ""
	return line.substr(start, end_idx - start)


func _pt(s: String) -> Vector2:
	var parts := s.split(",")
	if parts.size() >= 2:
		return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))
	return Vector2.ZERO


func _parse_triangle(chunk: String) -> PackedVector2Array:
	var verts := PackedVector2Array()
	for tok in chunk.split(" "):
		tok = tok.strip_edges()
		if "," in tok:
			verts.append(_pt(tok))
	if verts.size() >= 3:
		return PackedVector2Array([verts[0], verts[1], verts[2]])
	return PackedVector2Array()

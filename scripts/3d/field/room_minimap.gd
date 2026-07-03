extends Control
## Room-level minimap HUD — parses SVG minimap text and draws floor shape,
## gate markers with directional labels, and a live player position arrow
## via _draw().  Added as a child of the MapOverlay CanvasLayer.
##
## Uses embedded metadata from SVG (data-scale, data-offset-x/y) for player
## position tracking, matching the web PreviewMinimap approach.

# Frame sprite (map.png) — committed in-repo under assets/ui/, so it ships with
# the binary rather than the asset pack (no pck republish to iterate on it). The
# map content and key-card count are drawn on top at the pixel coordinates baked
# into the sprite.
const FRAME_TEX := preload("res://assets/ui/hud/map.png")
const FRAME_W := 99.0
const FRAME_H := 96.0
const SCALE := 1.5  # upscale the 99x96 sprite so the HUD reads on a 1280x720 viewport
# Map viewport inside the frame's dark square (sprite-pixel coordinates).
const MAP_ORIGIN := Vector2(18, 15)
const MAP_AREA := 64.0
# Single-digit key-card count slot — right of the baked "keycard ×" glyphs.
const KEY_DIGIT_POS := Vector2(76, 80)
const KEY_DIGIT_SIZE := 8.0

# Rendered size of the map area (sprite px × SCALE); feeds _svg_to_display.
const DISPLAY_SIZE := MAP_AREA * SCALE

const FLOOR_COLOR := Color(0.16, 0.16, 0.31)
const BOUNDARY_COLOR := Color(1.0, 1.0, 1.0, 0.6)
const PLAYER_COLOR := Color(0.0, 1.0, 0.0)
const GATE_OPEN := Color(0.27, 1.0, 0.27)
const GATE_LOCKED := Color(1.0, 0.3, 0.3)
const GATE_EXIT := Color(0.29, 0.62, 1.0)
const GATE_WALL := Color(0.4, 0.4, 0.4)
const KEY_DIGIT_COLOR := Color(0.1, 0.1, 0.17)  # dark navy — reads on the light-blue frame

var _floor_triangles: Array = []   # Array[PackedVector2Array] — 3 verts each
var _boundary_lines: Array = []    # Array[[Vector2, Vector2]]
var _gate_entries: Array = []      # Array[{center, color, label, dir}]
var _gate_dir_index: Dictionary = {}  # direction → index in _gate_entries
var _player_display_pos := Vector2.ZERO
var _player_display_dir := Vector2(0, 1)  # arrow direction in display space
var _last_drawn_pos := Vector2(-999, -999)  # last position that triggered a redraw
const REDRAW_THRESHOLD := 1.5  # minimum pixel movement to trigger redraw
var _has_player_tracking := false

# Key-card count — number of key cards currently held (drawn as a single digit
# in the frame's key slot).
var _keys_collected: int = 0

# Embedded SVG transform metadata (from data-* attributes)
var _svg_scale := 0.0
var _svg_offset_x := 0.0
var _svg_offset_y := 0.0
var _rotation_deg: int = 0


func setup(stage_id: String, area_folder: String, portal_data: Dictionary,
		connections: Dictionary, warp_edge: String,
		_map_root: Node3D, rotation_deg: int = 0, entry_edge: String = "") -> void:
	_rotation_deg = rotation_deg
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var total_w: float = FRAME_W * SCALE
	var total_h: float = FRAME_H * SCALE
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
	var file := FileAccess.open(svg_path, FileAccess.READ)
	if not file:
		push_warning("[RoomMinimap] Could not open SVG: %s (error=%d)" % [svg_path, FileAccess.get_open_error()])
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
	# Only redraw when player moved enough to matter visually
	if _player_display_pos.distance_squared_to(_last_drawn_pos) > REDRAW_THRESHOLD * REDRAW_THRESHOLD:
		_last_drawn_pos = _player_display_pos
		queue_redraw()


# ── Drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var font := ThemeDB.fallback_font

	# Frame sprite fills the whole control (provides the border + dark map square
	# + baked key-card glyph).
	draw_texture_rect(FRAME_TEX, Rect2(Vector2.ZERO, size), false)

	# Map content is drawn inside the frame's dark square.
	var map_offset := MAP_ORIGIN * SCALE

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

	# Key-card count — single digit in the slot baked into the frame sprite.
	var digit_pos := KEY_DIGIT_POS * SCALE
	draw_string(font, digit_pos + Vector2(0, KEY_DIGIT_SIZE * SCALE), str(_keys_collected),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(KEY_DIGIT_SIZE * SCALE), KEY_DIGIT_COLOR)


func update_keys(collected: int, _total: int) -> void:
	_keys_collected = collected
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
		warp_edge: String, _portal_data: Dictionary, entry_edge: String = "") -> void:
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
			grid_dir = StageRotation.rotate_dir(base_dir, _rotation_deg)

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

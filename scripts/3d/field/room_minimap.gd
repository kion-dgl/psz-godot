extends Control
## Room-level minimap HUD — parses SVG minimap text and draws floor shape,
## gate markers with directional labels, and a live player position arrow
## via _draw().  Added as a child of the MapOverlay CanvasLayer.

const DISPLAY_SIZE := 180.0
const BG_COLOR := Color(0.1, 0.1, 0.18, 0.85)
const FLOOR_COLOR := Color(0.16, 0.16, 0.31)
const BOUNDARY_COLOR := Color(1.0, 1.0, 1.0, 0.6)
const PLAYER_COLOR := Color(0.0, 1.0, 0.0)
const GATE_OPEN := Color(0.27, 1.0, 0.27)
const GATE_LOCKED := Color(1.0, 0.3, 0.3)
const GATE_EXIT := Color(0.29, 0.62, 1.0)
const GATE_WALL := Color(0.4, 0.4, 0.4)

var _floor_triangles: Array = []   # Array[PackedVector2Array] — 3 verts each
var _boundary_lines: Array = []    # Array[[Vector2, Vector2]]
var _gate_entries: Array = []      # Array[{center, color, label, dir}]
var _gate_dir_index: Dictionary = {}  # direction → index in _gate_entries
var _player_display_pos := Vector2.ZERO
var _player_display_dir := Vector2(0, 1)  # arrow direction in display space
var _has_player_tracking := false

# Affine transform: svg_x = local_x * _ax + _bx,  svg_y = local_z * _ay + _by
var _ax := 0.0
var _bx := 0.0
var _ay := 0.0
var _by := 0.0

# Permutation search state (used by _find_best_assignment)
var _best_score: float
var _best_perm: Array
var _rotation_deg: int = 0

const MINIMAP_DIRECTIONS := ["north", "east", "south", "west"]


func setup(stage_id: String, area_folder: String, portal_data: Dictionary,
		connections: Dictionary, warp_edge: String,
		map_root: Node3D, rotation_deg: int = 0) -> void:
	_rotation_deg = rotation_deg
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(DISPLAY_SIZE, DISPLAY_SIZE)
	size = Vector2(DISPLAY_SIZE, DISPLAY_SIZE)

	# Anchor top-right with margin
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -DISPLAY_SIZE - 20
	offset_right = -20
	offset_top = 20
	offset_bottom = 20 + DISPLAY_SIZE

	# Load SVG text (not as texture — we need to parse geometry)
	var svg_path := "res://assets/environments/%s/%s_minimap.svg" % [area_folder, stage_id]
	if not FileAccess.file_exists(svg_path):
		return
	var file := FileAccess.open(svg_path, FileAccess.READ)
	if not file:
		return
	var svg_text := file.get_as_text()
	file.close()

	_parse_floor(svg_text)
	_parse_boundaries(svg_text)
	var svg_gates := _parse_gates(svg_text)

	print("[RoomMinimap] stage=%s  svg_gates=%d  portals=%s" % [
		stage_id, svg_gates.size(), str(portal_data.keys())])
	for i in range(svg_gates.size()):
		print("[RoomMinimap]   svg_gate[%d] center=%s" % [i, svg_gates[i]])

	# Match SVG gates to portal directions using GLB labels as source of truth
	var gate_match := _match_gates(svg_gates, portal_data)
	print("[RoomMinimap]   gate_match=%s" % str(gate_match))
	_compute_affine(svg_gates, gate_match, portal_data, map_root)
	print("[RoomMinimap]   affine: ax=%.2f bx=%.2f ay=%.2f by=%.2f  tracking=%s" % [
		_ax, _bx, _ay, _by, str(_has_player_tracking)])
	_build_gate_entries(svg_gates, gate_match, connections, warp_edge)
	for gate in _gate_entries:
		print("[RoomMinimap]   gate_entry: center=%s  color=%s  label='%s'" % [
			gate["center"], gate["color"], gate["label"]])


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
	var svg_pos := Vector2(local.x * _ax + _bx, local.z * _ay + _by)
	_player_display_pos = _svg_to_display(svg_pos)

	# Compute arrow direction by transforming a small forward step through the
	# same pipeline (affine + mirror + rotation) so it matches the display.
	var step_3d := global_pos + Vector3(sin(facing_rad), 0, cos(facing_rad)) * 0.5
	var step_local: Vector3 = inv * step_3d
	var step_svg := Vector2(step_local.x * _ax + _bx, step_local.z * _ay + _by)
	var step_display := _svg_to_display(step_svg)
	var dir := (step_display - _player_display_pos)
	if dir.length_squared() > 0.0001:
		_player_display_dir = dir.normalized()
	queue_redraw()


# ── Drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Background
	draw_rect(Rect2(Vector2.ZERO, Vector2(DISPLAY_SIZE, DISPLAY_SIZE)), BG_COLOR)

	# Floor triangles
	for tri in _floor_triangles:
		var pts := PackedVector2Array()
		for v in tri:
			pts.append(_svg_to_display(v))
		draw_polygon(pts, [FLOOR_COLOR])

	# Boundary edges
	for seg in _boundary_lines:
		draw_line(_svg_to_display(seg[0]), _svg_to_display(seg[1]),
			BOUNDARY_COLOR, 1.5)

	# Gate markers
	var font := ThemeDB.fallback_font
	for gate in _gate_entries:
		var c: Vector2 = _svg_to_display(gate["center"])
		var d := 5.0
		draw_polygon(PackedVector2Array([
			c + Vector2(0, -d), c + Vector2(d, 0),
			c + Vector2(0, d), c + Vector2(-d, 0),
		]), [gate["color"]])
		var lbl: String = gate["label"]
		if not lbl.is_empty():
			draw_string(font, c + Vector2(-4, -8), lbl,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, gate["color"])

	# Player arrow
	if _has_player_tracking:
		var fwd := _player_display_dir
		var sz := 6.0
		draw_polygon(PackedVector2Array([
			_player_display_pos + fwd * sz,
			_player_display_pos + fwd.rotated(2.4) * sz * 0.6,
			_player_display_pos + fwd.rotated(-2.4) * sz * 0.6,
		]), [PLAYER_COLOR])


# ── SVG → Display transform ─────────────────────────────────────────────────

func _svg_to_display(svg_pos: Vector2) -> Vector2:
	## Rotate SVG coordinates by cell rotation, then scale to display size.
	var pos := svg_pos
	if _rotation_deg != 0:
		var center := Vector2(200.0, 200.0)
		pos = (pos - center).rotated(deg_to_rad(float(_rotation_deg))) + center
	return pos * (DISPLAY_SIZE / 400.0)


# ── SVG parsing ─────────────────────────────────────────────────────────────

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


func _parse_gates(svg_text: String) -> Array:
	var centers: Array = []
	for line in svg_text.split("\n"):
		line = line.strip_edges()
		if line.begins_with("<polygon"):
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
				centers.append(sum / float(n))
		elif line.begins_with("<rect") and 'fill="#4a9eff"' in line:
			var x := float(_attr(line, "x"))
			var y := float(_attr(line, "y"))
			var w := float(_attr(line, "width"))
			var h := float(_attr(line, "height"))
			centers.append(Vector2(x + w * 0.5, y + h * 0.5))
	return centers


# ── Gate matching ────────────────────────────────────────────────────────────
# Uses GLB portal_data directions (source of truth) and scores each SVG gate
# by how well its position matches each expected direction.  Exhaustive search
# over all possible assignments (N ≤ 4 → max 24 permutations).

## Convert a grid-space direction back to the original GLB direction.
func _grid_to_original(grid_dir: String, rotation: int) -> String:
	if rotation == 0:
		return grid_dir
	var idx: int = MINIMAP_DIRECTIONS.find(grid_dir)
	if idx < 0:
		return grid_dir
	var steps: int = ((360 - rotation) / 90) % 4
	return MINIMAP_DIRECTIONS[(idx + steps) % 4]


func _match_gates(svg_centers: Array, portal_data: Dictionary) -> Dictionary:
	## Returns { gate_index: dir, ... } — maps each matched SVG gate to
	## its direction from portal_data.
	var dirs: Array = []  # [{grid: String, orig: String}, ...]
	for grid_dir in portal_data:
		if grid_dir == "default":
			continue
		dirs.append({"grid": grid_dir, "orig": _grid_to_original(grid_dir, _rotation_deg)})

	if dirs.is_empty() or svg_centers.is_empty():
		return {}

	# Score matrix: how well each SVG gate fits each direction
	var scores: Array = []
	for d in dirs:
		var row: Array = []
		for i in range(svg_centers.size()):
			row.append(_direction_score(svg_centers[i], d["orig"]))
		scores.append(row)

	# Find optimal assignment: best gate index per direction
	var assignment := _find_best_assignment(scores, dirs.size(), svg_centers.size())

	# Build result: gate_index → grid_dir
	var result: Dictionary = {}
	for di in range(assignment.size()):
		result[assignment[di]] = dirs[di]["grid"]
	return result


func _direction_score(svg_center: Vector2, orig_dir: String) -> float:
	## Score how well an SVG gate position matches a model-space direction.
	## Higher = better fit.  Uses mirrored-X convention (east = low SVG X).
	var dx: float = svg_center.x - 200.0
	var dy: float = svg_center.y - 200.0
	match orig_dir:
		"north": return -dy   # prefer small Y (top)
		"south": return dy    # prefer large Y (bottom)
		"east":  return -dx   # prefer small X (left, mirrored)
		"west":  return dx    # prefer large X (right, mirrored)
	return 0.0


func _find_best_assignment(scores: Array, n_dirs: int, n_gates: int) -> Array:
	## Exhaustive search over all ways to assign n_dirs directions to n_gates
	## SVG gates (each direction picks a unique gate).  Returns array of gate
	## indices, one per direction.
	_best_score = -1e18
	_best_perm = []
	_try_perms(scores, n_dirs, n_gates, [], {}, 0)
	return _best_perm


func _try_perms(scores: Array, n_dirs: int, n_gates: int,
		current: Array, used: Dictionary, dir_idx: int) -> void:
	if dir_idx == n_dirs:
		var total := 0.0
		for i in range(current.size()):
			total += scores[i][current[i]]
		if total > _best_score:
			_best_score = total
			_best_perm = current.duplicate()
		return
	for g in range(n_gates):
		if used.has(g):
			continue
		current.append(g)
		used[g] = true
		_try_perms(scores, n_dirs, n_gates, current, used, dir_idx + 1)
		current.pop_back()
		used.erase(g)


# ── Affine transform ────────────────────────────────────────────────────────

func _compute_affine(svg_centers: Array, gate_match: Dictionary,
		portal_data: Dictionary, map_root: Node3D) -> void:
	# Build matched pairs: SVG center ↔ model-local 3D position
	var pairs: Array = []
	for gate_idx in gate_match:
		var grid_dir: String = gate_match[gate_idx]
		var pd: Dictionary = portal_data[grid_dir]
		var gpos: Vector3 = pd.get("gate_pos", pd["trigger_pos"])
		var local: Vector3 = map_root.global_transform.affine_inverse() * gpos
		pairs.append({"svg": svg_centers[gate_idx], "local": local})

	if pairs.size() < 2:
		if pairs.size() == 1 and not _floor_triangles.is_empty():
			# Single gate: use SVG floor centroid mapped to model origin as
			# a virtual second reference point for scale estimation.
			pairs.append({"svg": _svg_floor_centroid(), "local": Vector3.ZERO})
		else:
			return

	# Pick pair with max spread in local.x for solving X affine
	var best_x := 0.0
	var xi := 0
	var xj := 1
	for i in range(pairs.size()):
		for j in range(i + 1, pairs.size()):
			var s: float = absf(pairs[j]["local"].x - pairs[i]["local"].x)
			if s > best_x:
				best_x = s
				xi = i
				xj = j

	# Pick pair with max spread in local.z for solving Z affine
	var best_z := 0.0
	var zi := 0
	var zj := 1
	for i in range(pairs.size()):
		for j in range(i + 1, pairs.size()):
			var s: float = absf(pairs[j]["local"].z - pairs[i]["local"].z)
			if s > best_z:
				best_z = s
				zi = i
				zj = j

	if best_x > 0.1:
		_ax = (pairs[xj]["svg"].x - pairs[xi]["svg"].x) / (pairs[xj]["local"].x - pairs[xi]["local"].x)
		_bx = pairs[xi]["svg"].x - pairs[xi]["local"].x * _ax
	if best_z > 0.1:
		_ay = (pairs[zj]["svg"].y - pairs[zi]["svg"].y) / (pairs[zj]["local"].z - pairs[zi]["local"].z)
		_by = pairs[zi]["svg"].y - pairs[zi]["local"].z * _ay

	# Coordinate convention requires positive scale (east=-X→low SVG X,
	# south=+Z→high SVG Y).  Centroid fallback can produce wrong signs when
	# the model origin doesn't match the geometric center.  Fix by enforcing
	# positive scale and recomputing offset from the gate pair (pairs[0]).
	if _ax < 0.0:
		_ax = -_ax
		_bx = pairs[0]["svg"].x - pairs[0]["local"].x * _ax
	if _ay < 0.0:
		_ay = -_ay
		_by = pairs[0]["svg"].y - pairs[0]["local"].z * _ay

	# Full tracking if both axes solved; single-axis fallback uses same scale
	if best_x > 0.1 and best_z > 0.1:
		_has_player_tracking = true
	elif best_x > 0.1:
		_ay = _ax
		_by = pairs[0]["svg"].y - pairs[0]["local"].z * _ay
		_has_player_tracking = true
	elif best_z > 0.1:
		_ax = _ay
		_bx = pairs[0]["svg"].x - pairs[0]["local"].x * _ax
		_has_player_tracking = true


func _build_gate_entries(svg_centers: Array, gate_match: Dictionary,
		connections: Dictionary, warp_edge: String) -> void:
	for i in range(svg_centers.size()):
		var color: Color
		var label: String
		var dir: String = ""
		if gate_match.has(i):
			var grid_dir: String = gate_match[i]
			dir = grid_dir
			if grid_dir == warp_edge and not warp_edge.is_empty():
				color = GATE_EXIT
				label = "EXIT"
			elif connections.has(grid_dir):
				color = GATE_OPEN
				label = grid_dir.substr(0, 1).to_upper()
			else:
				color = GATE_WALL
				label = ""
		else:
			color = GATE_WALL
			label = ""
		_gate_entries.append({"center": svg_centers[i], "color": color, "label": label, "dir": dir})
		if not dir.is_empty():
			_gate_dir_index[dir] = _gate_entries.size() - 1


func _svg_floor_centroid() -> Vector2:
	## Area-weighted centroid of all floor triangles in SVG coordinates.
	var sum := Vector2.ZERO
	var total_area := 0.0
	for tri in _floor_triangles:
		if tri.size() < 3:
			continue
		var a: Vector2 = tri[0]
		var b: Vector2 = tri[1]
		var c: Vector2 = tri[2]
		var area := absf((b - a).cross(c - a)) * 0.5
		sum += (a + b + c) / 3.0 * area
		total_area += area
	if total_area > 0.0:
		return sum / total_area
	return Vector2(200.0, 200.0)


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

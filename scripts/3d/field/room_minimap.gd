extends Control
## Room-level minimap HUD — parses SVG minimap text and draws floor shape,
## gate markers with directional labels, and a live player position arrow
## via _draw().  Added as a child of the MapOverlay CanvasLayer.
##
## Uses embedded metadata from SVG (data-scale, data-offset-x/y) for player
## position tracking, matching the web PreviewMinimap approach. The SVG
## parsing itself lives in MinimapSvg, shared with the area-map overlay.

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
# Enemy markers (#422, spec /states/enemies): filled orange dots, visually
# distinct from the green player arrow. Bosses get ≈8× the AREA of a normal
# dot (radius × sqrt(8)). Radius is sized for the frame's 64px inner map
# (96px rendered at SCALE) so dots stay legible without swallowing the arrow.
const ENEMY_COLOR := Color(1.0, 0.55, 0.13)
const ENEMY_DOT_RADIUS := 2.2
const BOSS_DOT_AREA_RATIO := 8.0

var _floor_triangles: Array = []   # Array[PackedVector2Array] — 3 verts each
var _boundary_lines: Array = []    # Array[[Vector2, Vector2]]
var _gate_entries: Array = []      # Array[{center, color, label, dir}]
var _gate_dir_index: Dictionary = {}  # direction → index in _gate_entries
var _player_display_pos := Vector2.ZERO
var _player_display_dir := Vector2(0, 1)  # arrow direction in display space
var _last_drawn_pos := Vector2(-999, -999)  # last position that triggered a redraw
const REDRAW_THRESHOLD := 1.5  # minimum pixel movement to trigger redraw
var _has_player_tracking := false

# Live enemy markers (#422) — enemies registered via track_enemy() while alive
# in the currently loaded cell. Death signals untrack; positions re-projected
# each frame by update_enemies() through the same SVG pipeline as the player.
var _tracked_enemies: Array = []       # alive enemy Node3Ds in this cell
var _enemy_markers: Dictionary = {}    # instance_id → {"pos": Vector2, "radius": float}

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
	var svg_path := MinimapSvg.svg_path(stage_id, area_folder)
	var file := FileAccess.open(svg_path, FileAccess.READ)
	if not file:
		push_warning("[RoomMinimap] Could not open SVG: %s (error=%d)" % [svg_path, FileAccess.get_open_error()])
		return
	var svg_text := file.get_as_text()
	file.close()

	# Parse geometry (shared parser — the area-map overlay reads the same SVGs)
	_floor_triangles = MinimapSvg.parse_floor(svg_text)
	_boundary_lines = MinimapSvg.parse_boundaries(svg_text)

	# Parse embedded transform metadata
	var meta := MinimapSvg.parse_metadata(svg_text)
	_svg_scale = meta["scale"]
	_svg_offset_x = meta["offset_x"]
	_svg_offset_y = meta["offset_y"]

	# Parse gates with their baked direction (data-gate-dir attribute)
	var svg_gates := MinimapSvg.parse_gates(svg_text)

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


# ── Enemy markers (#422) ─────────────────────────────────────────────────────

## Register a live enemy for dot tracking. Scoping mirrors the player marker
## exactly: the minimap instance is rebuilt per loaded cell, so only this
## cell's enemies ever register — no off-cell markers, no cap. Death removes
## the marker via the enemy's own death signal (EnemyBase emits `died(enemy)`,
## legacy EnemySpawn emits `defeated`), so no stale dots survive a kill.
func track_enemy(enemy: Node3D) -> void:
	if enemy == null or _tracked_enemies.has(enemy):
		return
	_tracked_enemies.append(enemy)
	if enemy.has_signal("died"):
		enemy.connect("died", _on_tracked_enemy_died)
	elif enemy.has_signal("defeated"):
		enemy.connect("defeated", untrack_enemy.bind(enemy))
	queue_redraw()


func _on_tracked_enemy_died(enemy: Node) -> void:
	untrack_enemy(enemy)


func untrack_enemy(enemy: Node) -> void:
	_tracked_enemies.erase(enemy)
	if enemy != null:
		_enemy_markers.erase(enemy.get_instance_id())
	queue_redraw()


## Live marker count — the autopilot probe asserts this against the alive
## enemy roster. Freed instances (death animation finished → queue_free)
## are swept first so the count never includes dangling references.
func get_enemy_marker_count() -> int:
	_sweep_tracked_enemies()
	return _tracked_enemies.size()


func _sweep_tracked_enemies() -> void:
	for i in range(_tracked_enemies.size() - 1, -1, -1):
		if not is_instance_valid(_tracked_enemies[i]):
			_tracked_enemies.remove_at(i)


## Project every tracked enemy into display space — same SVG-metadata pipeline
## (and therefore the same loaded-cell scoping) as update_player(). Called
## per-frame by the field controller alongside the player update.
func update_enemies(map_root: Node3D) -> void:
	if not _has_player_tracking:
		return
	_sweep_tracked_enemies()
	var inv := map_root.global_transform.affine_inverse()
	var markers: Dictionary = {}
	var needs_redraw: bool = false
	for enemy in _tracked_enemies:
		if not enemy.is_inside_tree():
			continue
		var local: Vector3 = inv * (enemy as Node3D).global_position
		var svg := Vector2(
			local.x * _svg_scale + _svg_offset_x,
			local.z * _svg_scale + _svg_offset_y)
		var id: int = enemy.get_instance_id()
		var entry := {
			"pos": _svg_to_display(svg),
			"radius": enemy_marker_radius(_is_boss_enemy(enemy)),
		}
		markers[id] = entry
		var prev: Dictionary = _enemy_markers.get(id, {})
		if prev.is_empty() or entry["pos"].distance_squared_to(prev["pos"]) > REDRAW_THRESHOLD * REDRAW_THRESHOLD:
			needs_redraw = true
	if markers.size() != _enemy_markers.size():
		needs_redraw = true
	if needs_redraw:
		_enemy_markers = markers
		queue_redraw()


## Boss dots carry ≈8× the AREA of a normal dot → radius × sqrt(8).
static func enemy_marker_radius(is_boss: bool) -> float:
	return ENEMY_DOT_RADIUS * sqrt(BOSS_DOT_AREA_RATIO) if is_boss else ENEMY_DOT_RADIUS


func _is_boss_enemy(enemy: Node) -> bool:
	var edata: Variant = enemy.get("enemy_data")
	if edata is Resource:
		return bool(edata.get("is_boss"))
	return false


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

	# Enemy markers — filled orange dots (#422); player arrow draws on top
	for entry in _enemy_markers.values():
		draw_circle(entry["pos"] + map_offset, entry["radius"], ENEMY_COLOR)

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
	return MinimapSvg.svg_to_view(svg_pos, _rotation_deg,
		Rect2(Vector2.ZERO, Vector2.ONE * DISPLAY_SIZE))


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

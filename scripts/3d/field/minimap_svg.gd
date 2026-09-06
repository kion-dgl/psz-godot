class_name MinimapSvg
extends RefCounted
## Shared parser for the stage minimap SVGs baked by the web stage editor
## (assets/stages/<area>_<variant>/<stage_id>/lndmd/<stage_id>_minimap.svg).
##
## Extracted from room_minimap.gd (which kept its own copy) so the area-map
## overlay can draw each cell's real room footprint — the player-facing ask
## that the map read as actual rooms instead of uniform squares. Same
## string-matching approach as always: floor triangles from the
## `fill="#2a2a4e"` path, boundary edges from the `stroke="white"` path, gate
## rects from data-gate attributes, transform metadata from the root data-*.
##
## load_stage() caches per stage — a section's cells reuse a handful of stage
## variants, so each SVG is read and parsed once per run. Stages without an
## SVG (≈10 rooms ship none; CI runs without pack assets) cache an empty
## result and callers fall back to their plain rendering.

const STAGES_ROOT := "res://assets/stages"
const VIEW_SIZE := 400.0  # every minimap SVG uses viewBox="0 0 400 400"

const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")

static var _cache: Dictionary = {}  # "stage_id|area_folder" → {triangles, boundaries}


## Floor + boundary geometry for a stage, in SVG space (0..400, y down =
## south). Empty arrays when the stage has no readable SVG.
static func load_stage(stage_id: String, area_folder: String = "") -> Dictionary:
	var key := "%s|%s" % [stage_id, area_folder]
	if _cache.has(key):
		return _cache[key]
	var result := {"triangles": [], "boundaries": []}
	var path := svg_path(stage_id, area_folder)
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var svg_text := file.get_as_text()
			file.close()
			result["triangles"] = parse_floor(svg_text)
			result["boundaries"] = parse_boundaries(svg_text)
	_cache[key] = result
	return result


## res:// path of a stage's minimap SVG. Subfolder derivation mirrors
## valley_field_controller._get_stage_subfolder ("s01a_ga1" + "valley" →
## "valley_a"); without an explicit folder the area is reverse-looked up from
## the stage_id prefix. Empty string when the prefix is unknown.
static func svg_path(stage_id: String, area_folder: String = "") -> String:
	var folder := area_folder
	if folder.is_empty():
		folder = folder_for_prefix(stage_id.substr(0, 3))
	if folder.is_empty():
		return ""
	var subfolder := folder
	if stage_id.length() >= 4:
		subfolder = "%s_%s" % [folder, stage_id[3]]
	return "%s/%s/%s/lndmd/%s_minimap.svg" % [STAGES_ROOT, subfolder, stage_id, stage_id]


static func folder_for_prefix(prefix: String) -> String:
	for area_id in GridGenerator.AREA_CONFIG:
		var cfg: Dictionary = GridGenerator.AREA_CONFIG[area_id]
		if str(cfg.get("prefix", "")) == prefix:
			return str(cfg.get("folder", ""))
	return ""


## Map SVG-space coordinates (0..400, y down) into a destination view rect,
## rotating about the viewBox center by the cell's rotation first — the same
## convention the room minimap's display transform always used, so a room's
## gates stay glued to the edges its (relabeled) grid directions claim.
static func svg_to_view(svg_pos: Vector2, rotation_deg: int, view: Rect2) -> Vector2:
	var p := svg_pos
	if rotation_deg != 0:
		var center := Vector2(VIEW_SIZE * 0.5, VIEW_SIZE * 0.5)
		p = (p - center).rotated(deg_to_rad(float(rotation_deg))) + center
	return view.position + p * (view.size / VIEW_SIZE)


# ── Parsing (all pure: SVG text in, geometry out) ────────────────────────────

static func parse_metadata(svg_text: String) -> Dictionary:
	## data-scale / data-offset-x / data-offset-y from the root <svg> line —
	## the transform metadata the stage editor bakes for live markers.
	var meta := {"scale": 0.0, "offset_x": 0.0, "offset_y": 0.0}
	var first_line := ""
	for line in svg_text.split("\n"):
		if "<svg" in line:
			first_line = line
			break
	if first_line.is_empty():
		return meta
	var scale_str := attr(first_line, "data-scale")
	var off_x_str := attr(first_line, "data-offset-x")
	var off_y_str := attr(first_line, "data-offset-y")
	if not scale_str.is_empty():
		meta["scale"] = float(scale_str)
	if not off_x_str.is_empty():
		meta["offset_x"] = float(off_x_str)
	if not off_y_str.is_empty():
		meta["offset_y"] = float(off_y_str)
	return meta


static func parse_floor(svg_text: String) -> Array:
	var triangles: Array = []
	for line in svg_text.split("\n"):
		if 'fill="#2a2a4e"' not in line:
			continue
		var d := attr(line, "d")
		if d.is_empty():
			continue
		for chunk in d.split(" Z "):
			chunk = chunk.strip_edges()
			if chunk.ends_with(" Z"):
				chunk = chunk.substr(0, chunk.length() - 2)
			if chunk.is_empty():
				continue
			var tri := parse_triangle(chunk)
			if tri.size() == 3:
				triangles.append(tri)
	return triangles


static func parse_boundaries(svg_text: String) -> Array:
	var segments: Array = []
	for line in svg_text.split("\n"):
		if 'stroke="white"' not in line or 'fill="none"' not in line:
			continue
		var d := attr(line, "d")
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
				segments.append([
					pt(parts[0].strip_edges()),
					pt(parts[1].strip_edges()),
				])
	return segments


static func parse_gates(svg_text: String) -> Array:
	## Gate markers + their baked direction. Returns [{center: Vector2, dir: String}].
	var gates: Array = []
	for line in svg_text.split("\n"):
		line = line.strip_edges()
		# New format: <rect ... data-gate="true" data-gate-dir="south" .../>
		if line.begins_with("<rect") and 'data-gate="true"' in line:
			var x := float(attr(line, "x"))
			var y := float(attr(line, "y"))
			var w := float(attr(line, "width"))
			var h := float(attr(line, "height"))
			gates.append({
				"center": Vector2(x + w * 0.5, y + h * 0.5),
				"dir": attr(line, "data-gate-dir"),
			})
		# Legacy format: <polygon fill="#4a9eff" .../>
		elif line.begins_with("<polygon") and 'fill="#4a9eff"' in line:
			var ps := attr(line, "points")
			if ps.is_empty():
				continue
			var sum := Vector2.ZERO
			var n := 0
			for p in ps.strip_edges().split(" "):
				p = p.strip_edges()
				if p.is_empty():
					continue
				var xy := p.split(",")
				if xy.size() == 2:
					sum += Vector2(float(xy[0]), float(xy[1]))
					n += 1
			if n > 0:
				gates.append({"center": sum / float(n), "dir": ""})
	return gates


# ── Token helpers ────────────────────────────────────────────────────────────

static func attr(line: String, attr_name: String) -> String:
	var key := attr_name + '="'
	var idx := line.find(key)
	if idx < 0:
		return ""
	var start := idx + key.length()
	var end_idx := line.find('"', start)
	if end_idx < 0:
		return ""
	return line.substr(start, end_idx - start)


static func pt(s: String) -> Vector2:
	var parts := s.split(",")
	if parts.size() >= 2:
		return Vector2(float(parts[0].strip_edges()), float(parts[1].strip_edges()))
	return Vector2.ZERO


static func parse_triangle(chunk: String) -> PackedVector2Array:
	var verts := PackedVector2Array()
	for tok in chunk.split(" "):
		tok = tok.strip_edges()
		if "," in tok:
			verts.append(pt(tok))
	if verts.size() >= 3:
		return PackedVector2Array([verts[0], verts[1], verts[2]])
	return PackedVector2Array()

extends RefCounted
class_name CityBoundaryBuilder
## Runtime builder for traced city floor polygons and extruded perimeter/cutout
## collision walls (spec /states/city-boundaries, issue #371).

const ROOT := "res://data/stage_configs/city-boundaries/"


static func load_config(area_id: String) -> Dictionary:
	var path := ROOT + area_id + ".json"
	if not FileAccess.file_exists(path):
		push_warning("[CityBoundary] missing config: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[CityBoundary] failed to open: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[CityBoundary] malformed JSON: %s" % path)
		return {}
	return parsed as Dictionary


static func parse_points(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw as Array:
		if typeof(item) == TYPE_ARRAY and (item as Array).size() >= 2:
			var pair := item as Array
			out.append(Vector2(float(pair[0]), float(pair[1])))
	return out


static func is_point_walkable(config: Dictionary, xz: Vector2, y: float = INF) -> bool:
	var perim := parse_points(config.get("perimeter", []))
	if perim.size() < 3 or not Geometry2D.is_point_in_polygon(xz, perim):
		return false
	var floor_y := float(config.get("floorY", 0.0))
	var wall_h := float(config.get("wallHeight", 4.0))
	var cutouts: Variant = config.get("cutouts", [])
	if typeof(cutouts) != TYPE_ARRAY:
		return true
	for raw_cutout in cutouts as Array:
		if typeof(raw_cutout) != TYPE_DICTIONARY:
			continue
		var cutout := raw_cutout as Dictionary
		var sub_floor := bool(cutout.get("subtractFloor", true))
		var wb := float(cutout.get("wallBottomY", floor_y))
		var wh := float(cutout.get("wallHeight", wall_h))
		var blocks_y := is_inf(y) or (y >= wb - 0.1 and y <= wb + wh + 0.1)
		if (sub_floor or blocks_y) and Geometry2D.is_point_in_polygon(xz, parse_points(cutout.get("points", []))):
			return false
	return true


static func triangulate_walkable_polygons(config: Dictionary) -> Array[PackedVector2Array]:
	var perim := parse_points(config.get("perimeter", []))
	var pieces: Array[PackedVector2Array] = []
	if perim.size() < 3:
		return pieces
	pieces.append(perim)
	var cutouts: Variant = config.get("cutouts", [])
	if typeof(cutouts) == TYPE_ARRAY:
		for raw_cutout in cutouts as Array:
			if typeof(raw_cutout) != TYPE_DICTIONARY:
				continue
			var cutout := raw_cutout as Dictionary
			if not bool(cutout.get("subtractFloor", true)):
				continue
			var hole := parse_points(cutout.get("points", []))
			if hole.size() >= 3:
				pieces = _subtract_hole(pieces, hole)
	return pieces


static func _subtract_hole(pieces: Array[PackedVector2Array], hole: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var split_x := _centroid_x(hole)
	for piece in pieces:
		var clipped := Geometry2D.clip_polygons(piece, hole)
		var has_inner_hole := false
		for poly in clipped:
			if Geometry2D.is_polygon_clockwise(poly):
				has_inner_hole = true
				break
		if not has_inner_hole:
			for poly in clipped:
				if poly.size() >= 3:
					out.append(poly)
			continue
		for half in _split_polygon_at_x(piece, split_x):
			for sub in Geometry2D.clip_polygons(half, hole):
				if sub.size() >= 3 and not Geometry2D.is_polygon_clockwise(sub):
					out.append(sub)
	return out


static func _centroid_x(poly: PackedVector2Array) -> float:
	var sum_x := 0.0
	for p in poly:
		sum_x += p.x
	return sum_x / float(maxi(poly.size(), 1))


static func _split_polygon_at_x(poly: PackedVector2Array, split_x: float) -> Array[PackedVector2Array]:
	var min_p := poly[0]
	var max_p := poly[0]
	for p in poly:
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	var pad := 16.0
	var left_box := PackedVector2Array([
		Vector2(min_p.x - pad, min_p.y - pad),
		Vector2(split_x, min_p.y - pad),
		Vector2(split_x, max_p.y + pad),
		Vector2(min_p.x - pad, max_p.y + pad),
	])
	var right_box := PackedVector2Array([
		Vector2(split_x, min_p.y - pad),
		Vector2(max_p.x + pad, min_p.y - pad),
		Vector2(max_p.x + pad, max_p.y + pad),
		Vector2(split_x, max_p.y + pad),
	])
	var halves: Array[PackedVector2Array] = []
	for box in [left_box, right_box]:
		for part in Geometry2D.intersect_polygons(poly, box):
			if part.size() >= 3 and not Geometry2D.is_polygon_clockwise(part):
				halves.append(part)
	return halves


static func build_floor_faces(config: Dictionary) -> PackedVector3Array:
	var faces := PackedVector3Array()
	if not bool(config.get("buildFloor", true)):
		return faces
	var floor_y := float(config.get("floorY", 0.0))
	for poly in triangulate_walkable_polygons(config):
		var indices := Geometry2D.triangulate_polygon(poly)
		var tri_count := indices.size() / 3
		for t in range(tri_count):
			var p0 := poly[indices[t * 3]]
			var p1 := poly[indices[t * 3 + 1]]
			var p2 := poly[indices[t * 3 + 2]]
			var a := Vector3(p0.x, floor_y, p0.y)
			var b := Vector3(p1.x, floor_y, p1.y)
			var c := Vector3(p2.x, floor_y, p2.y)
			if (b - a).cross(c - a).y < 0.0:
				var tmp := b
				b = c
				c = tmp
			faces.append(a)
			faces.append(b)
			faces.append(c)
	return faces


static func build_wall_faces(config: Dictionary) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var perim := parse_points(config.get("perimeter", []))
	var floor_y := float(config.get("floorY", 0.0))
	var wall_bottom := float(config.get("wallBottomY", floor_y))
	var wall_h := float(config.get("wallHeight", 4.0))
	if perim.size() >= 3 and wall_h > 0.0:
		var openings: Array = config.get("openings", []) if typeof(config.get("openings", [])) == TYPE_ARRAY else []
		for i in range(perim.size()):
			var a := perim[i]
			var b := perim[(i + 1) % perim.size()]
			for span in _solid_edge_spans(i, openings):
				var s0 := a.lerp(b, span.x)
				var s1 := a.lerp(b, span.y)
				_append_double_sided_quad(faces, s0, s1, wall_bottom, wall_bottom + wall_h)
	var cutouts: Variant = config.get("cutouts", [])
	if typeof(cutouts) == TYPE_ARRAY:
		for raw_cutout in cutouts as Array:
			if typeof(raw_cutout) != TYPE_DICTIONARY:
				continue
			var cutout := raw_cutout as Dictionary
			var pts := parse_points(cutout.get("points", []))
			var cb := float(cutout.get("wallBottomY", floor_y))
			var ch := float(cutout.get("wallHeight", wall_h))
			if pts.size() < 3 or ch <= 0.0:
				continue
			for j in range(pts.size()):
				_append_double_sided_quad(faces, pts[j], pts[(j + 1) % pts.size()], cb, cb + ch)
	return faces


static func _solid_edge_spans(edge_idx: int, openings: Array) -> Array[Vector2]:
	var gaps: Array[Vector2] = []
	for raw_op in openings:
		if typeof(raw_op) != TYPE_DICTIONARY:
			continue
		var op := raw_op as Dictionary
		if bool(op.get("portalOnly", false)) or int(op.get("edge", -1)) != edge_idx:
			continue
		var t0 := clampf(float(op.get("tStart", 0.0)), 0.0, 1.0)
		var t1 := clampf(float(op.get("tEnd", 1.0)), 0.0, 1.0)
		if t1 > t0 + 0.001:
			gaps.append(Vector2(t0, t1))
	if gaps.is_empty():
		return [Vector2(0.0, 1.0)]
	gaps.sort_custom(func(u: Vector2, v: Vector2) -> bool: return u.x < v.x)
	var spans: Array[Vector2] = []
	var cursor := 0.0
	for g in gaps:
		if g.x > cursor + 0.001:
			spans.append(Vector2(cursor, g.x))
		cursor = maxf(cursor, g.y)
	if cursor < 0.999:
		spans.append(Vector2(cursor, 1.0))
	return spans


static func _append_double_sided_quad(
	faces: PackedVector3Array, p0: Vector2, p1: Vector2, y0: float, y1: float
) -> void:
	if p0.distance_squared_to(p1) < 0.0001:
		return
	var bot0 := Vector3(p0.x, y0, p0.y)
	var bot1 := Vector3(p1.x, y0, p1.y)
	var top1 := Vector3(p1.x, y1, p1.y)
	var top0 := Vector3(p0.x, y1, p0.y)
	faces.append(bot0)
	faces.append(bot1)
	faces.append(top1)
	faces.append(bot0)
	faces.append(top1)
	faces.append(top0)
	faces.append(bot0)
	faces.append(top1)
	faces.append(bot1)
	faces.append(bot0)
	faces.append(top0)
	faces.append(top1)


static func build_into(parent: Node3D, config: Dictionary) -> StaticBody3D:
	if config.is_empty():
		return null
	var body := StaticBody3D.new()
	body.name = "CityBoundary"
	body.collision_layer = 1
	body.collision_mask = 0
	var floor_faces := build_floor_faces(config)
	if floor_faces.size() >= 3:
		var floor_shape := ConcavePolygonShape3D.new()
		floor_shape.backface_collision = true
		floor_shape.set_faces(floor_faces)
		var floor_col := CollisionShape3D.new()
		floor_col.name = "FloorShape"
		floor_col.shape = floor_shape
		body.add_child(floor_col)
	var wall_faces := build_wall_faces(config)
	if wall_faces.size() >= 3:
		var wall_shape := ConcavePolygonShape3D.new()
		wall_shape.backface_collision = true
		wall_shape.set_faces(wall_faces)
		var wall_col := CollisionShape3D.new()
		wall_col.name = "WallShape"
		wall_col.shape = wall_shape
		body.add_child(wall_col)
	parent.add_child(body)
	return body

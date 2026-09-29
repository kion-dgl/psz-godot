extends RefCounted
## Procedural Principal's-office "library" room (#356).
##
## Modeled against the user's original DS emulator office reference:
## broad raised library landing, central stairs and timber railings, tall
## bookcases with ladders, pale fluted columns and the turquoise sun panel.
##
## Composition, not inheritance (Android export breaks on cross-script office
## scene inheritance — docs/shop-dedup.md): the office controller calls
## OfficeLibraryRoom.build(self) from _ready. Pack textures are load()ed at
## runtime (not preload) so the script still parses in repo-only CI; a missing
## texture falls back to a flat stone color rather than crashing.

const R := 9.0          # room radius (matches LibrarySet R)
const WALL_H := 8.2
const LANDING_H := 1.05
const LANDING_FRONT := -2.6
const STAIR_WIDTH := 3.5
const STAIR_RUN := 2.52
const STAIR_COUNT := 6
const STAIR_FOOT := LANDING_FRONT + STAIR_RUN
const ARC_HALF := 0.75 * PI   # wall spans ±135° from back-centre (270°, +Z open)

# Pack textures (city_e) — load() at runtime, may be null in repo-only CI.
const TILE1B := "res://assets/stages/city_e/market/s00_0_tile1b.png"
const GUILD_SUN := "res://assets/stages/city_e/s00e_sa3/lndmd/s00_0_mark02.png"
const GUILD_TRIM := "res://assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m_s00_0_waku.png"
const WPWALL03 := "res://assets/stages/city_e/s00e_sa2/lndmd/s00_0_wpwall03.png"
# CC0 wood — vendored in-repo (assets/cc0_textures), always present.
const WOOD_TEX := "res://assets/cc0_textures/wood062_color.jpg"

const STONE_DARK := Color(0.353, 0.318, 0.278)   # #5a5147 border / trim
const STONE_PALE := Color(0.804, 0.765, 0.667)   # #cdc3aa column stone
const WOOD_WARM := Color(0.78, 0.60, 0.37)       # #c79a5e shelf/desk tint

const SPINE_COLORS := [
	Color("844733"), Color("a28352"), Color("b59a6b"), Color("68553a"), Color("9b6b3f"),
	Color("713e31"), Color("666b4e"), Color("c4ad7c"), Color("756850"), Color("987849"),
]

const SHELF_PHIS := [-2.2, -1.68, -1.08, -0.70, 0.70, 1.08, 1.68, 2.2]
const COLUMN_PHIS := [-0.42, 0.42, -2.45, 2.45]


## Position + facing for an object on the room arc at angle phi (0 = back-centre,
## +phi toward the right), facing the centre. Mirrors LibrarySet.onArc.
static func _on_arc(phi: float, radius: float) -> Dictionary:
	var x := sin(phi) * radius
	var z := -cos(phi) * radius
	return {"pos": Vector3(x, 0.0, z), "rot_y": atan2(x, z) + PI}


static func _tex(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var t = load(path)
	return t if t is Texture2D else null


## StandardMaterial3D with an optional tiled texture; falls back to `tint` when
## the texture is pack-only and absent (repo-only CI).
static func _mat(path: String, tint: Color, uv_scale: Vector2 = Vector2.ONE, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	var t := _tex(path)
	if t:
		m.albedo_texture = t
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	return m


static func _emissive(color: Color, intensity: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = intensity
	m.roughness = 0.35
	return m


static func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## Flat disc (a thin cylinder) lying in the XZ plane, top face at +y of `pos`.
## Tiling is configured on `mat` (uv1_scale) by the caller, not here.
static func _disc(parent: Node3D, radius: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 0.04
	c.radial_segments = 64
	c.rings = 0
	return _add_mesh(parent, c, mat, pos)


static func _cyl(parent: Node3D, top_r: float, bot_r: float, h: float, mat: Material, pos: Vector3, segs := 20) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bot_r
	c.height = h
	c.radial_segments = segs
	return _add_mesh(parent, c, mat, pos)


static func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add_mesh(parent, b, mat, pos, rot)


## Rear library landing: curved back follows the room; the front is a broad
## straight retaining wall with a central staircase, as in the DS reference.
static func _build_landing(parent: Node3D) -> void:
	var stone := _mat("", STONE_PALE)
	var face := _mat(WPWALL03, Color("c1b99f"), Vector2(5, 1))
	var floor_mat := _mat(TILE1B, Color("c3bba0"), Vector2.ONE)
	var outline: Array[Vector3] = []
	var half_arc := acos(-LANDING_FRONT / (R - 0.08))
	for i in range(49):
		var phi := lerpf(-half_arc, half_arc, float(i) / 48.0)
		outline.append(Vector3(sin(phi) * (R - 0.08), 0, -cos(phi) * (R - 0.08)))
	var top := SurfaceTool.new()
	var sides := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, LANDING_H, -5.7)
	var hull := PackedVector3Array()
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var at := a + Vector3.UP * LANDING_H
		var bt := b + Vector3.UP * LANDING_H
		for vertex in [center, at, bt]:
			_wall_vert(top, Vector3.UP, Vector2(vertex.x, vertex.z) * 0.45, vertex)
		var normal := Vector3(b.z - a.z, 0, a.x - b.x).normalized()
		var verts := [a, b, bt, at]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for j in [0, 1, 2, 0, 2, 3]:
			_wall_vert(sides, normal, uvs[j], verts[j])
		hull.append(a)
		hull.append(at)
	_add_mesh(parent, top.commit(), floor_mat, Vector3.ZERO).name = "LandingSurface"
	_add_mesh(parent, sides.commit(), face, Vector3.ZERO)
	var platform_shape := ConvexPolygonShape3D.new()
	platform_shape.points = hull
	_solid(parent, "LandingCollision", platform_shape)
	# Six stone treads. The collision ramp is continuous for smooth walking.
	var step_depth := STAIR_RUN / STAIR_COUNT
	for i in range(STAIR_COUNT):
		var height := LANDING_H * float(i + 1) / STAIR_COUNT
		var z := STAIR_FOOT - (i + 0.5) * step_depth
		_box(parent, Vector3(STAIR_WIDTH, height, step_depth), stone, Vector3(0, height * 0.5, z))
		_box(parent, Vector3(STAIR_WIDTH + 0.08, 0.045, 0.09), stone,
			Vector3(0, height - 0.0225, z + step_depth * 0.5 - 0.02))
	var ramp := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for x in [-STAIR_WIDTH * 0.5, STAIR_WIDTH * 0.5]:
		points.append(Vector3(x, 0, STAIR_FOOT))
		points.append(Vector3(x, 0, LANDING_FRONT))
		points.append(Vector3(x, LANDING_H, LANDING_FRONT))
	ramp.points = points
	_solid(parent, "StairRampCollision", ramp)
	# Side parapets frame the stair opening, with carved stone copings.
	var rail_wood := _mat(WOOD_TEX, Color("97713d"))
	var brass := _mat("", Color("b89a54"), Vector2.ONE, 0.45)
	for side in [-1.0, 1.0]:
		var x0: float = side * (STAIR_WIDTH * 0.5 + 0.17)
		var x1: float = side * 7.65
		var rail_y := LANDING_H + 0.86
		_box(parent, Vector3(absf(x1 - x0) + 0.3, 0.13, 0.45), stone,
			Vector3((x0 + x1) * 0.5, LANDING_H - 0.015, LANDING_FRONT))
		_beam(parent, Vector3(x0, rail_y, LANDING_FRONT), Vector3(x1, rail_y, LANDING_FRONT), 0.17, rail_wood)
		_beam(parent, Vector3(x0, LANDING_H + 0.18, LANDING_FRONT), Vector3(x1, LANDING_H + 0.18, LANDING_FRONT), 0.11, rail_wood)
		for i in range(13):
			var x := lerpf(x0, x1, float(i) / 12.0)
			_box(parent, Vector3(0.11, 0.75, 0.12), rail_wood, Vector3(x, LANDING_H + 0.44, LANDING_FRONT))
			if i < 12:
				var next_x := lerpf(x0, x1, float(i + 1) / 12.0)
				_beam(parent, Vector3(x, LANDING_H + 0.23, LANDING_FRONT), Vector3(next_x, rail_y - 0.08, LANDING_FRONT), 0.055, brass)
		var barrier := BoxShape3D.new()
		barrier.size = Vector3(absf(x1 - x0) + 0.12, 0.9, 0.18)
		_solid(parent, "LandingRailing", barrier).position = Vector3((x0 + x1) * 0.5, LANDING_H + 0.45, LANDING_FRONT)
		# Walkable stair stays clear between these sloping handrails.
		var foot := Vector3(x0, 0.90, STAIR_FOOT + 0.05)
		var head := Vector3(x0, rail_y, LANDING_FRONT)
		_beam(parent, foot, head, 0.17, rail_wood)
		for i in range(5):
			var t := float(i) / 4.0
			var pos := foot.lerp(head, t)
			_box(parent, Vector3(0.12, 0.84, 0.12), rail_wood, pos - Vector3.UP * 0.42)
			_cyl(parent, 0.11, 0.11, 0.07, brass, pos + Vector3.UP * 0.08, 12)


static func _solid(parent: Node3D, node_name: String, shape: Shape3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body


static func _beam(parent: Node3D, start: Vector3, end: Vector3, width: float, mat: Material) -> void:
	var delta := end - start
	var beam := _box(parent, Vector3(width, delta.length(), width), mat, (start + end) * 0.5)
	beam.quaternion = Quaternion(Vector3.UP, delta.normalized())


## Leaning wooden library ladders, with rungs and brass runners at the feet.
static func _build_ladder(parent: Node3D, height: float, wood: Material, brass: Material) -> void:
	var foot_z := 1.05
	var top_z := 0.34
	for x in [-0.34, 0.34]:
		_beam(parent, Vector3(x, 0.10, foot_z), Vector3(x, height, top_z), 0.085, wood)
		var wheel := _cyl(parent, 0.09, 0.09, 0.065, brass, Vector3(x, 0.1, foot_z), 12)
		wheel.rotation.z = PI / 2.0
	var rungs := int(height / 0.35)
	for i in range(1, rungs):
		var t := float(i) / rungs
		_box(parent, Vector3(0.68, 0.065, 0.12), wood, Vector3(0, lerpf(0.10, height, t), lerpf(foot_z, top_z, t)))


# ── Entry point ───────────────────────────────────────────────────────────
static func build(parent: Node3D) -> void:
	_build_floor(parent)
	_build_arc_wall(parent)
	_build_mouldings(parent)
	_build_landing(parent)
	_build_runner(parent)
	_build_columns(parent)
	_build_sun_window(parent)
	_build_bookshelves(parent)
	_build_desk(parent)
	_build_lights(parent)


static func _build_floor(parent: Node3D) -> void:
	# Field — tiled octagonal stone across the whole circle.
	_disc(parent, R, _mat(TILE1B, Color(0.82, 0.78, 0.66), Vector2(10, 10), 0.8), Vector3(0, 0, 0))


## Curved apse wall: a 270° arc strip (SurfaceTool), inward-facing, tiled
## wpwall03. theta runs from -ARC_HALF..+ARC_HALF around the back; the +Z front
## stays open for the entrance.
static func _build_arc_wall(parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 64
	var u_tiles := 12.0
	var v_tiles := 3.0
	for i in range(segs):
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var th0 := lerpf(-ARC_HALF, ARC_HALF, t0)
		var th1 := lerpf(-ARC_HALF, ARC_HALF, t1)
		var p0 := Vector3(sin(th0) * R, 0.0, -cos(th0) * R)
		var p1 := Vector3(sin(th1) * R, 0.0, -cos(th1) * R)
		# Inward normals (toward the centre) so the wall is lit from the room.
		var n0 := Vector3(-sin(th0), 0.0, cos(th0))
		var n1 := Vector3(-sin(th1), 0.0, cos(th1))
		var u0 := t0 * u_tiles
		var u1 := t1 * u_tiles
		# Two triangles per quad (bottom y=0, top y=WALL_H), wound for inward faces.
		_wall_vert(st, n0, Vector2(u0, v_tiles), p0 + Vector3(0, 0, 0))
		_wall_vert(st, n1, Vector2(u1, v_tiles), p1 + Vector3(0, 0, 0))
		_wall_vert(st, n1, Vector2(u1, 0), p1 + Vector3(0, WALL_H, 0))
		_wall_vert(st, n0, Vector2(u0, v_tiles), p0 + Vector3(0, 0, 0))
		_wall_vert(st, n1, Vector2(u1, 0), p1 + Vector3(0, WALL_H, 0))
		_wall_vert(st, n0, Vector2(u0, 0), p0 + Vector3(0, WALL_H, 0))
	var mesh := st.commit()
	var mat := _mat(WPWALL03, Color(0.62, 0.58, 0.5), Vector2.ONE, 0.9)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # visible from both sides
	_add_mesh(parent, mesh, mat, Vector3.ZERO)


static func _wall_vert(st: SurfaceTool, n: Vector3, uv: Vector2, p: Vector3) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)


## Stepped cornice and skirting follow the apse, giving the wall real depth.
static func _build_mouldings(parent: Node3D) -> void:
	var stone := _mat(GUILD_TRIM, STONE_PALE)
	var dark := _mat("", STONE_DARK)
	for level in [Vector3(0.18, 0.36, 0.28), Vector3(WALL_H - 0.3, 0.18, 0.22), Vector3(WALL_H - 0.06, 0.3, 0.44)]:
		# One continuous mesh per course, instead of 64 overlapping boxes.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var inner: float = R - level.z
		var bottom: float = level.x - level.y * 0.5
		var top: float = level.x + level.y * 0.5
		for i in range(64):
			var phi0 := -ARC_HALF + i * ARC_HALF * 2.0 / 64.0
			var phi1 := -ARC_HALF + (i + 1) * ARC_HALF * 2.0 / 64.0
			var a := Vector3(sin(phi0), 0, -cos(phi0))
			var b := Vector3(sin(phi1), 0, -cos(phi1))
			var v := [a * inner + Vector3.UP * bottom, b * inner + Vector3.UP * bottom,
				b * inner + Vector3.UP * top, a * inner + Vector3.UP * top,
				a * R + Vector3.UP * bottom, b * R + Vector3.UP * bottom,
				b * R + Vector3.UP * top, a * R + Vector3.UP * top]
			# Front face follows the guild's gold / dark teal / carved-stone frieze.
			var u0 := float(i) * 24.0 / 64.0
			var u1 := float(i + 1) * 24.0 / 64.0
			_trim_quad(st, v, [0, 1, 2, 3], [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0)])
			for face in [[3, 2, 6, 7], [4, 5, 1, 0], [7, 6, 5, 4]]:
				_trim_quad(st, v, face)
			if i == 0:
				_trim_quad(st, v, [4, 0, 3, 7])
			if i == 63:
				_trim_quad(st, v, [1, 5, 6, 2])
		_add_mesh(parent, st.commit(), stone if level.x > WALL_H - 0.2 else dark, Vector3.ZERO)


static func _trim_quad(st: SurfaceTool, vertices: Array, face: Array, uvs: Array = []) -> void:
	var a: Vector3 = vertices[face[0]]
	var b: Vector3 = vertices[face[1]]
	var c: Vector3 = vertices[face[2]]
	var normal := (b - a).cross(c - a).normalized()
	for index in [0, 2, 1, 0, 3, 2]:
		st.set_normal(normal)
		st.set_uv(uvs[index] if not uvs.is_empty() else Vector2.ZERO)
		st.add_vertex(vertices[face[index]])


## A woven processional runner leads from the entrance toward the desk.
## Kept flat so player and briefing positions continue to use the existing floor.
static func _build_runner(parent: Node3D) -> void:
	var cloth := _mat("", Color("254d50"), Vector2.ONE, 1.0)
	var border := _mat("", Color("b29861"), Vector2.ONE, 0.9)
	var dark := _mat("", Color("183638"))
	_box(parent, Vector3(2.7, 0.014, 5.7), dark, Vector3(0, 0.032, 2.75))
	_box(parent, Vector3(2.56, 0.008, 5.56), border, Vector3(0, 0.044, 2.75))
	_box(parent, Vector3(2.43, 0.008, 5.43), cloth, Vector3(0, 0.053, 2.75))
	for z in [0.35, 5.15]:
		for x in [-0.94, 0.94]:
			_box(parent, Vector3(0.16, 0.006, 0.16), border,
				Vector3(x, 0.061, z), Vector3(0, PI / 4.0, 0))
	# An eight-point sun repeats the window motif in woven gold thread.
	for i in range(8):
		var angle := i * TAU / 8.0
		_box(parent, Vector3(0.035, 0.006, 0.26), border,
			Vector3(sin(angle) * 0.42, 0.061, cos(angle) * 0.42 + 3.9),
			Vector3(0, angle, 0))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.23
	ring.outer_radius = 0.25
	ring.rings = 32
	ring.ring_segments = 6
	_add_mesh(parent, ring, border, Vector3(0, 0.062, 3.9), Vector3.ZERO).scale.y = 0.1


## Torus in the XY plane: raised stone tracery and metal glazing bars.
static func _window_ring(parent: Node3D, radius: float, thickness: float, mat: Material, depth: float) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = radius - thickness
	ring.outer_radius = radius + thickness
	ring.rings = 64
	ring.ring_segments = 8
	_add_mesh(parent, ring, mat, Vector3(0, 0, depth), Vector3(PI / 2.0, 0, 0))


static func _build_columns(parent: Node3D) -> void:
	var stone := _mat("", STONE_PALE, Vector2.ONE, 0.85)
	var recess := _mat("", Color("8c8873"))
	for phi in COLUMN_PHIS:
		var a := _on_arc(phi, R - 0.55)
		var col := Node3D.new()
		col.position = a["pos"]
		if absf(phi) < 1.0:
			col.position.y = LANDING_H
		var height := WALL_H - col.position.y
		parent.add_child(col)
		# Stepped bases and capitals give the silhouette a carved profile.
		for step in [Vector3(0.65, 0.20, 0.10), Vector3(0.56, 0.16, 0.28),
				Vector3(0.49, 0.15, 0.435), Vector3(0.49, 0.16, height - 0.55),
				Vector3(0.56, 0.20, height - 0.37), Vector3(0.66, 0.24, height - 0.15)]:
			_cyl(col, step.x, step.x, step.y, stone, Vector3(0, step.z, 0), 32)
		# Actual fluting stays readable under light, without a stretched atlas.
		_cyl(col, 0.36, 0.40, height - 1.1, recess, Vector3(0, height * 0.5 - 0.05, 0), 32)
		for i in range(16):
			var angle := i * TAU / 16.0
			_cyl(col, 0.065, 0.075, height - 1.1, stone,
				Vector3(cos(angle) * 0.37, height * 0.5 - 0.05, sin(angle) * 0.37), 8)


static func _build_sun_window(parent: Node3D) -> void:
	# Tall pale-green inset and gold borders tie the sun to the desk alcove.
	var panel := _mat("", Color("92a697"))
	var gold := _mat("", Color("b49b62"), Vector2.ONE, 0.55)
	_box(parent, Vector3(5.55, WALL_H - LANDING_H - 0.25, 0.12), panel,
		Vector3(0, (WALL_H + LANDING_H) * 0.5 - 0.125, -8.42))
	for x in [-2.67, 2.67]:
		_box(parent, Vector3(0.10, WALL_H - LANDING_H - 0.3, 0.08), gold,
			Vector3(x, (WALL_H + LANDING_H) * 0.5 - 0.15, -8.31))
	var win := Node3D.new()
	win.position = Vector3(0, 5.0, -R + 0.85)
	win.scale = Vector3.ONE * 0.78
	parent.add_child(win)
	# mark02 is the turquoise sun panel visible behind the Principal in-game.
	# Its atlas stores the left half of a tall panel. Reconstruct the circular
	# detail from the lower sun quadrant (centre y=70, lower ring edge y=114),
	# keeping the unrelated upper panes out of the circular mesh.
	# Separate quadrant triangles keep interpolation off the mirror seams.
	var sun := _mat(GUILD_SUN, Color.WHITE, Vector2.ONE, 0.85)
	sun.texture_repeat = false
	sun.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(64):
		var a0 := i * TAU / 64.0
		var a1 := (i + 1) * TAU / 64.0
		# Clockwise when viewed from +Z, facing the room.
		for point in [Vector2.ZERO, Vector2(cos(a1), sin(a1)), Vector2(cos(a0), sin(a0))]:
			st.set_normal(Vector3(0, 0, 1))
			st.set_uv(Vector2(1.0 - absf(point.x), (70.0 + absf(point.y) * 44.0) / 128.0))
			st.add_vertex(Vector3(point.x * 3.03, point.y * 3.03, 0.03))
	_add_mesh(win, st.commit(), sun, Vector3.ZERO)
	# The texture contains its own rings and rays; raised outer stonework
	# adds depth without drawing bars across the original painted design.
	_window_ring(win, 3.12, 0.10, gold, 0.0)
	var rim := _cyl(win, 3.24, 3.24, 0.2, _mat("", Color("d8cdb0")), Vector3(0, 0, -0.15), 64)
	rim.rotation = Vector3(PI / 2.0, 0, 0)


static func _build_bookshelves(parent: Node3D) -> void:
	var wood := _mat(WOOD_TEX, Color(0.61, 0.46, 0.28), Vector2(1, 2), 0.85)
	var shelf_wood := _mat(WOOD_TEX, WOOD_WARM, Vector2(1, 2), 0.8)
	for phi in SHELF_PHIS:
		_bookshelf(parent, phi, wood, shelf_wood)


static func _bookshelf(parent: Node3D, phi: float, wood: Material, shelf_wood: Material) -> void:
	var shelves := 8
	var unit_w := 3.15
	var base_height := LANDING_H if absf(phi) < 1.3 else 0.0
	var unit_h := WALL_H - 0.4 - base_height
	var a := _on_arc(phi, R - 0.5)
	var node := Node3D.new()
	node.position = a["pos"]
	node.position.y = base_height
	node.rotation.y = a["rot_y"]
	parent.add_child(node)
	# Back panel + two sides.
	_box(node, Vector3(unit_w, unit_h, 0.12), wood, Vector3(0, unit_h / 2.0, -0.18))
	for sx in [-unit_w / 2.0, unit_w / 2.0]:
		_box(node, Vector3(0.16, unit_h, 0.5), wood, Vector3(sx, unit_h / 2.0, 0))
	# Plinth and projecting crown frame the cabinet silhouette.
	_box(node, Vector3(unit_w + 0.25, 0.24, 0.64), wood, Vector3(0, 0.16, 0))
	_box(node, Vector3(unit_w + 0.25, 0.18, 0.64), shelf_wood, Vector3(0, unit_h + 0.08, 0))
	# Shelf boards.
	var gap := (unit_h - 0.5) / shelves
	for s in range(shelves + 1):
		_box(node, Vector3(unit_w, 0.08, 0.46), shelf_wood, Vector3(0, 0.4 + s * gap, 0))
	# A heavy mid-height shelf and a projecting ladder rail match the original library.
	_box(node, Vector3(unit_w + 0.16, 0.20, 0.58), wood, Vector3(0, 0.4 + gap * 4, 0.08))
	var ladder_wood := _mat(WOOD_TEX, Color("ba9650"))
	var ladder_brass := _mat("", Color("b79b5c"), Vector2.ONE, 0.45)
	_box(node, Vector3(unit_w, 0.07, 0.07), ladder_brass, Vector3(0, unit_h - 0.5, 0.39))
	if absf(absf(phi) - 0.70) < 0.01 or absf(absf(phi) - 1.68) < 0.01:
		_build_ladder(node, unit_h - 0.4, ladder_wood, ladder_brass)
	# Reuse the palette across books. posmod keeps left-arc seeds positive.
	var book_mats: Array[StandardMaterial3D] = []
	for color in SPINE_COLORS:
		book_mats.append(_mat("", color, Vector2.ONE, 0.7))
	var gilt := _mat("", Color("bd9d62"))
	# Deterministic book spines with enough clearance below the next board.
	for s in range(shelves):
		var y := 0.4 + s * gap
		var x := -unit_w / 2.0 + 0.2
		var i := s * 7 + int(round(phi * 13.0))
		while x < unit_w / 2.0 - 0.2:
			var w := 0.12 + float(posmod(i * 37, 9)) / 60.0
			var h := gap * (0.6 + float(posmod(i * 53, 5)) / 16.0)
			w = minf(w, unit_w / 2.0 - 0.2 - x)
			var bm := book_mats[posmod(i * 17, book_mats.size())]
			_box(node, Vector3(w, h, 0.28), bm, Vector3(x + w / 2.0, y + 0.04 + h / 2.0, 0.05))
			if posmod(i, 3) == 0:
				_box(node, Vector3(w * 0.7, 0.025, 0.012), gilt, Vector3(x + w / 2.0, y + h * 0.8, 0.196))
			x += w + 0.03
			i += 1


static func _build_desk(parent: Node3D) -> void:
	var desk := Node3D.new()
	desk.position = Vector3(0, LANDING_H - 0.2, -4.5)
	parent.add_child(desk)
	var wood := _mat(WOOD_TEX, Color(0.55, 0.42, 0.27), Vector2.ONE, 0.7)
	var wood_top := _mat(WOOD_TEX, WOOD_WARM, Vector2.ONE, 0.6)
	# Desk body + top.
	_box(desk, Vector3(3.2, 0.9, 1.3), wood, Vector3(0, 0.65, 0))
	_box(desk, Vector3(3.4, 0.25, 1.5), wood_top, Vector3(0, 1.2, 0))

	var brass := _mat("", Color("b99a59"), Vector2.ONE, 0.38)
	brass.metallic = 0.65
	var leather := _mat("", Color("244b48"))
	var paper := _mat("", Color("e4d7b1"))
	# Raised front panels, inset fields and a continuous brass bead.
	for x in [-1.05, 0.0, 1.05]:
		_box(desk, Vector3(0.94, 0.64, 0.08), wood_top, Vector3(x, 0.73, 0.68))
		_box(desk, Vector3(0.8, 0.49, 0.025), wood, Vector3(x, 0.73, 0.731))
	_box(desk, Vector3(3.36, 0.035, 1.46), brass, Vector3(0, 1.08, 0))
	_box(desk, Vector3(1.5, 0.018, 0.85), leather, Vector3(0, 1.334, 0))
	# Open ledger with separate covers, pages and central binding.
	for side in [-1.0, 1.0]:
		_box(desk, Vector3(0.35, 0.035, 0.48), wood, Vector3(side * 0.18, 1.365, 0), Vector3(0, 0, side * 0.08))
		_box(desk, Vector3(0.32, 0.022, 0.45), paper, Vector3(side * 0.18, 1.393, 0), Vector3(0, 0, side * 0.08))
	for i in range(3):
		_box(desk, Vector3(0.5, 0.1, 0.36), _mat("", SPINE_COLORS[i]), Vector3(-1.12, 1.38 + i * 0.11, -0.1), Vector3(0, i * 0.13, 0))
	# Small shaded desk lamp, kept below the Principal's face.
	_cyl(desk, 0.17, 0.2, 0.045, brass, Vector3(1.1, 1.35, 0))
	_cyl(desk, 0.025, 0.025, 0.4, brass, Vector3(1.1, 1.57, 0))
	_cyl(desk, 0.12, 0.27, 0.23, leather, Vector3(1.1, 1.84, 0))
	_cyl(desk, 0.23, 0.23, 0.015, _emissive(Color("ffd596"), 0.7), Vector3(1.1, 1.725, 0))


static func _build_lights(parent: Node3D) -> void:
	# Warm scholarly key over the room + a cool glow from the window, mirroring
	# LibrarySet's two point lights. OmniLight range covers the R=9 hall.
	var warm := OmniLight3D.new()
	warm.position = Vector3(0, 5, 2)
	warm.light_color = Color("ffd9a0")
	warm.light_energy = 3.2
	warm.omni_range = 22.0
	parent.add_child(warm)
	var cool := OmniLight3D.new()
	cool.position = Vector3(0, 4, -7)
	cool.light_color = Color("9fe8ff")
	cool.light_energy = 2.2
	cool.omni_range = 16.0
	parent.add_child(cool)

extends RefCounted
## Procedural Principal's-office "library" room (#356).
##
## A GDScript port of web/src/office-editor/LibrarySet.tsx — the look the user
## approved in the R3F screenshot loop. Built from primitives + one SurfaceTool
## arc so it renders without the old in-house office GLB:
##
##   • a circular tile1b stone floor, a dark border ring + ornate floor05
##     medallion under the desk,
##   • a curved apse wall (wpwall03) wrapping the back 270°, open at the +Z front,
##   • fluted columns (set02) flanking the sun window and at the apse opening,
##   • an emissive "sun" stained-glass window at the back-centre,
##   • bookshelves along the arc (CC0 wood + colored procedural book spines),
##   • a wood desk on a low stone dais at the room centre.
##
## Composition, not inheritance (Android export breaks on cross-script office
## scene inheritance — docs/shop-dedup.md): the office controller calls
## OfficeLibraryRoom.build(self) from _ready. Pack textures are load()ed at
## runtime (not preload) so the script still parses in repo-only CI; a missing
## texture falls back to a flat stone color rather than crashing.

const R := 9.0          # room radius (matches LibrarySet R)
const WALL_H := 6.0
const ARC_HALF := 0.75 * PI   # wall spans ±135° from back-centre (270°, +Z open)

# Pack textures (city_e) — load() at runtime, may be null in repo-only CI.
const TILE1B := "res://assets/stages/city_e/market/s00_0_tile1b.png"
const FLOOR05 := "res://assets/stages/city_e/market/s00_0_floor05.png"
const WPWALL03 := "res://assets/stages/city_e/s00e_sa2/lndmd/s00_0_wpwall03.png"
const COLUMN_TEX := "res://assets/stages/city_e/market/s00_0_set02.png"
# CC0 wood — vendored in-repo (assets/cc0_textures), always present.
const WOOD_TEX := "res://assets/cc0_textures/wood062_color.jpg"

const STONE_DARK := Color(0.353, 0.318, 0.278)   # #5a5147 border / trim
const STONE_PALE := Color(0.804, 0.765, 0.667)   # #cdc3aa column stone
const WOOD_WARM := Color(0.78, 0.60, 0.37)       # #c79a5e shelf/desk tint

const SPINE_COLORS := [
	Color("7c3b2f"), Color("3b5a7c"), Color("4a7c3b"), Color("7c6a3b"), Color("5a3b7c"),
	Color("7c3b5a"), Color("3b7c6a"), Color("6a3b3b"), Color("3b6a7c"), Color("7c5a3b"),
]

const SHELF_PHIS := [-2.2, -1.7, -1.2, -0.7, 0.7, 1.2, 1.7, 2.2]
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
		m.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	return m


static func _emissive(color: Color, intensity: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
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


# ── Entry point ───────────────────────────────────────────────────────────
static func build(parent: Node3D) -> void:
	_build_floor(parent)
	_build_arc_wall(parent)
	_build_columns(parent)
	_build_sun_window(parent)
	_build_bookshelves(parent)
	_build_desk(parent)
	_build_lights(parent)


static func _build_floor(parent: Node3D) -> void:
	# Field — tiled octagonal stone across the whole circle.
	_disc(parent, R, _mat(TILE1B, Color(0.82, 0.78, 0.66), Vector2(5, 5), 0.8), Vector3(0, 0, 0))
	# Dark border ring (a dark disc the medallion sits on, leaving a 0.4 rim).
	_disc(parent, 4.4, _mat("", STONE_DARK, Vector2.ONE, 0.9), Vector3(0, 0.012, -4.5))
	# Ornate marble medallion — shown once under the desk dais.
	_disc(parent, 4.0, _mat(FLOOR05, Color(0.85, 0.80, 0.66), Vector2.ONE, 0.65), Vector3(0, 0.02, -4.5))


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


static func _build_columns(parent: Node3D) -> void:
	var fluted := _mat(COLUMN_TEX, STONE_PALE, Vector2(4, 1), 0.8)
	var stone := _mat("", STONE_PALE, Vector2.ONE, 0.85)
	for phi in COLUMN_PHIS:
		var a := _on_arc(phi, R - 0.55)
		var base: Vector3 = a["pos"]
		var col := Node3D.new()
		col.position = base
		parent.add_child(col)
		var h := WALL_H - 1.0
		_cyl(col, 0.55, 0.62, 0.7, stone, Vector3(0, 0.35, 0), 16)            # base
		_cyl(col, 0.42, 0.48, h, fluted, Vector3(0, 0.7 + h / 2.0, 0), 20)    # shaft
		_cyl(col, 0.64, 0.5, 0.5, stone, Vector3(0, 0.7 + h + 0.25, 0), 16)   # capital


static func _build_sun_window(parent: Node3D) -> void:
	var win := Node3D.new()
	win.position = Vector3(0, 3.2, -R + 0.3)
	parent.add_child(win)
	# Concentric emissive discs (the stained-glass "sun"), facing +Z.
	var rings := [
		{"r": 3.0, "c": Color("2c6e7a"), "e": 0.5},
		{"r": 2.3, "c": Color("3fa9c9"), "e": 0.85},
		{"r": 1.5, "c": Color("bfe9f2"), "e": 1.1},
		{"r": 0.7, "c": Color("f2c94c"), "e": 1.5},
	]
	for i in range(rings.size()):
		var ring: Dictionary = rings[i]
		var disc := _disc(win, ring["r"], _emissive(ring["c"], ring["e"]), Vector3(0, 0, i * 0.015))
		disc.rotation = Vector3(PI / 2.0, 0, 0)   # face +Z
	# 12 golden rays.
	var ray_mat := _emissive(Color("e8d28a"), 0.6)
	for i in range(12):
		var ang := (float(i) / 12.0) * TAU
		_box(win, Vector3(1.5, 0.16, 0.04), ray_mat,
			Vector3(cos(ang) * 1.9, sin(ang) * 1.9, 0.07), Vector3(0, 0, ang))
	# Stone outer rim.
	var rim := _cyl(win, 3.5, 3.5, 0.2, _mat("", Color("d8cdb0"), Vector2.ONE, 1.0), Vector3(0, 0, -0.15))
	rim.rotation = Vector3(PI / 2.0, 0, 0)


static func _build_bookshelves(parent: Node3D) -> void:
	var wood := _mat(WOOD_TEX, Color(0.61, 0.46, 0.28), Vector2(1, 2), 0.85)
	var shelf_wood := _mat(WOOD_TEX, WOOD_WARM, Vector2(1, 2), 0.8)
	for phi in SHELF_PHIS:
		_bookshelf(parent, phi, wood, shelf_wood)


static func _bookshelf(parent: Node3D, phi: float, wood: Material, shelf_wood: Material) -> void:
	var shelves := 6
	var unit_w := 2.6
	var unit_h := 5.2
	var a := _on_arc(phi, R - 0.5)
	var node := Node3D.new()
	node.position = a["pos"]
	node.rotation.y = a["rot_y"]
	parent.add_child(node)
	# Back panel + two sides.
	_box(node, Vector3(unit_w, unit_h, 0.12), wood, Vector3(0, unit_h / 2.0, -0.18))
	for sx in [-unit_w / 2.0, unit_w / 2.0]:
		_box(node, Vector3(0.16, unit_h, 0.5), wood, Vector3(sx, unit_h / 2.0, 0))
	# Shelf boards.
	var gap := unit_h / shelves
	for s in range(shelves + 1):
		_box(node, Vector3(unit_w, 0.08, 0.46), shelf_wood, Vector3(0, 0.4 + s * gap, 0))
	# Procedural book spines (same integer-hash layout as LibrarySet).
	for s in range(shelves):
		var y := 0.4 + s * gap
		var x := -unit_w / 2.0 + 0.2
		var i := s * 7 + int(round(phi * 13.0))
		while x < unit_w / 2.0 - 0.2:
			var w := 0.12 + float((i * 37) % 9) / 60.0
			var h := gap * (0.6 + float((i * 53) % 5) / 12.0)
			var color: Color = SPINE_COLORS[(i * 17) % SPINE_COLORS.size()]
			var bm := StandardMaterial3D.new()
			bm.albedo_color = color
			bm.roughness = 0.7
			_box(node, Vector3(w, h, 0.28), bm, Vector3(x + w / 2.0, y + h / 2.0, 0.05))
			x += w + 0.03
			i += 1


static func _build_desk(parent: Node3D) -> void:
	var desk := Node3D.new()
	desk.position = Vector3(0, 0, -4.5)
	parent.add_child(desk)
	var wood := _mat(WOOD_TEX, Color(0.55, 0.42, 0.27), Vector2.ONE, 0.7)
	var wood_top := _mat(WOOD_TEX, WOOD_WARM, Vector2.ONE, 0.6)
	# Low stone dais.
	_cyl(desk, 3.2, 3.4, 0.3, _mat("", STONE_DARK, Vector2.ONE, 0.8), Vector3(0, 0.15, 0), 32)
	# Desk body + top.
	_box(desk, Vector3(3.2, 0.9, 1.3), wood, Vector3(0, 0.65, 0))
	_box(desk, Vector3(3.4, 0.25, 1.5), wood_top, Vector3(0, 1.2, 0))


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

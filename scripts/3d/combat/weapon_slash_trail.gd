extends MeshInstance3D
## PSO TAttackTrace-inspired translucent photon blade ribbon for melee swings.
## Lives in world space (`top_level = true`) as a child of the player so it
## cleans up automatically with no leaks and no screen-flashing VFX.

const LIFETIME := 0.16
const MAX_SAMPLES := 18
const PEAK_ALPHA := 0.46

var _samples: Array = []
var _imm: ImmediateMesh
var _mat: StandardMaterial3D


func _init() -> void:
	name = "WeaponSlashTrail"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_imm = ImmediateMesh.new()
	mesh = _imm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mat.vertex_color_use_as_albedo = true
	material_override = _mat
	visible = false


static func compute_blade_endpoints(weapon: Node3D) -> Dictionary:
	var fallback := {"base": Vector3(0.0, 0.0, 0.12), "tip": Vector3(0.0, 0.0, 0.95)}
	if not is_instance_valid(weapon):
		return fallback
	var bounds := _collect_local_bounds(weapon, Transform3D.IDENTITY)
	if not bounds.valid:
		return fallback
	var aabb: AABB = bounds.aabb
	var center := aabb.position + aabb.size * 0.5
	var sx := aabb.size.x
	var sy := aabb.size.y
	var sz := aabb.size.z
	var max_span := maxf(sx, maxf(sy, sz))
	if max_span < 0.08:
		return fallback
	if sy >= sx and sy >= sz:
		var b_y := aabb.position.y + sy * 0.18
		var t_y := aabb.position.y + sy
		return {"base": Vector3(center.x, b_y, center.z), "tip": Vector3(center.x, t_y, center.z)}
	if sx >= sy and sx >= sz:
		var b_x := aabb.position.x + sx * 0.18
		var t_x := aabb.position.x + sx
		return {"base": Vector3(b_x, center.y, center.z), "tip": Vector3(t_x, center.y, center.z)}
	var b_z := aabb.position.z + sz * 0.18
	var t_z := aabb.position.z + sz
	return {"base": Vector3(center.x, center.y, b_z), "tip": Vector3(center.x, center.y, t_z)}


static func _collect_local_bounds(node: Node, to_root: Transform3D) -> Dictionary:
	var valid := false
	var aabb := AABB()
	if node is MeshInstance3D and node.mesh != null:
		var local_box: AABB = node.mesh.get_aabb()
		for i in range(8):
			var p: Vector3 = to_root * local_box.get_endpoint(i)
			if not valid:
				aabb = AABB(p, Vector3.ZERO)
				valid = true
			else:
				aabb = aabb.expand(p)
	for child in node.get_children():
		var xf: Transform3D = to_root * (child as Node3D).transform if child is Node3D else to_root
		var sub := _collect_local_bounds(child, xf)
		if sub.valid:
			aabb = sub.aabb if not valid else aabb.merge(sub.aabb)
			valid = true
	return {"valid": valid, "aabb": aabb}


func clear_trail() -> void:
	_samples.clear()
	_imm.clear_surfaces()
	visible = false


func step_trail(weapon: Node3D, endpoints: Dictionary, active: bool, tint: Color, delta: float) -> void:
	var kept: Array = []
	for s in _samples:
		s.age += delta
		if s.age < LIFETIME:
			kept.append(s)
	_samples = kept
	if active and is_instance_valid(weapon) and weapon.is_inside_tree():
		var base_w: Vector3 = weapon.to_global(endpoints.base)
		var tip_w: Vector3 = weapon.to_global(endpoints.tip)
		if _samples.is_empty() or base_w.distance_squared_to(_samples[-1].base) + tip_w.distance_squared_to(_samples[-1].tip) > 0.0004:
			_samples.append({"base": base_w, "tip": tip_w, "age": 0.0})
			while _samples.size() > MAX_SAMPLES:
				_samples.pop_front()
	_rebuild_mesh(tint)


func _rebuild_mesh(tint: Color) -> void:
	_imm.clear_surfaces()
	if _samples.size() < 2:
		visible = false
		return
	visible = true
	_imm.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s in _samples:
		var frac := clampf(1.0 - float(s.age) / LIFETIME, 0.0, 1.0)
		var alpha := frac * frac * PEAK_ALPHA
		var tip_col := Color(tint.r, tint.g, tint.b, alpha)
		var base_col := Color(tint.r, tint.g, tint.b, alpha * 0.28)
		_imm.surface_set_color(base_col)
		_imm.surface_add_vertex(s.base)
		_imm.surface_set_color(tip_col)
		_imm.surface_add_vertex(s.tip)
	_imm.surface_end()

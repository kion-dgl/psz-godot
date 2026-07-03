class_name ConeTargeting
## The per-weapon hit cone (spec /mechanics/targeting), shared by targeting,
## reticles, the target-info HUD, and melee hit resolution — one geometry.
##
## PSO:BB model (check_enemy_is_targetable + ItemPMT): the cone's apex sits
## v_dist BEHIND the origin along -facing, reach from the apex is
## h_dist + v_dist + the target's own collision radius, and the half-angle
## is tested in the XZ plane. Pure/static so the unit tests hit it directly.


## True when the target passes the cone. All positions are world-space;
## only X/Z are read (the vertical test is out of scope for PSZ's arenas).
static func in_cone(
	origin: Vector3, yaw: float,
	h_dist: float, v_dist: float, half_angle_deg: float,
	target_pos: Vector3, target_radius: float,
) -> bool:
	return distance_in_cone(origin, yaw, h_dist, v_dist, half_angle_deg, target_pos, target_radius) >= 0.0


## Distance from the apex to the target (XZ) when it passes the cone,
## -1.0 when it does not. The distance is what candidates sort by.
static func distance_in_cone(
	origin: Vector3, yaw: float,
	h_dist: float, v_dist: float, half_angle_deg: float,
	target_pos: Vector3, target_radius: float,
) -> float:
	var fx := sin(yaw)
	var fz := cos(yaw)
	var ax := origin.x - fx * v_dist
	var az := origin.z - fz * v_dist
	var dx := target_pos.x - ax
	var dz := target_pos.z - az
	var dist := sqrt(dx * dx + dz * dz)
	var reach := h_dist + v_dist + target_radius
	if dist > reach:
		return -1.0
	if dist > 0.0001:
		var cos_a := (dx * fx + dz * fz) / dist
		if cos_a < cos(deg_to_rad(half_angle_deg)):
			return -1.0
	return dist

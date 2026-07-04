class_name ConeTargeting
## The per-weapon hit cone (spec /mechanics/targeting), shared by targeting,
## reticles, the target-info HUD, and melee hit resolution — one geometry.
##
## PSO:BB model (check_enemy_is_targetable + ItemPMT): the cone's apex sits
## v_dist BEHIND the origin along -facing, reach from the apex is
## h_dist + v_dist + the target's own collision radius, the horizontal
## half-angle is tested in the XZ plane, and the VERTICAL half-angle bounds
## the slope from the apex (dot of the flattened vs full 3D direction —
## v_angle_deg >= 90 means unbounded, PSO's launchers/cards). The origin is
## the weapon position (player + weapon height), the target position its
## hitbox center. Pure/static so the unit tests hit it directly.


## True when the target passes the cone.
static func in_cone(
	origin: Vector3, yaw: float,
	h_dist: float, v_dist: float, half_angle_deg: float, v_angle_deg: float,
	target_pos: Vector3, target_radius: float,
) -> bool:
	return distance_in_cone(origin, yaw, h_dist, v_dist, half_angle_deg, v_angle_deg, target_pos, target_radius) >= 0.0


## Distance from the apex to the target (XZ) when it passes the cone,
## -1.0 when it does not. The distance is what candidates sort by.
static func distance_in_cone(
	origin: Vector3, yaw: float,
	h_dist: float, v_dist: float, half_angle_deg: float, v_angle_deg: float,
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
		# Vertical slope from the apex (PSO): the angle between the flat and
		# the full 3D direction to the target must stay inside v_angle_deg.
		if v_angle_deg < 90.0:
			var dy := target_pos.y - origin.y
			var full_len := sqrt(dist * dist + dy * dy)
			if full_len > 0.0001:
				var cos_v := dist / full_len
				if cos_v < cos(deg_to_rad(v_angle_deg)):
					return -1.0
	return dist

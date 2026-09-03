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


## Alive members of `enemies` passing the cone described by a weapon-type
## config dict (hit_h_dist / hit_v_dist / hit_h_angle_deg / hit_v_angle_deg),
## sorted nearest-first. Targets are tested at their hitbox center using the
## EnemyData collision shape when present. Used by the companion's swing
## (spec /states/companion-combat); the player's _enemies_in_hit_cone is the
## same geometry with technique-widened bounds layered on.
static func scan_enemies(enemies: Array, origin: Vector3, yaw: float, config: Dictionary) -> Array:
	var found: Array = []
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if not enemy.get("is_alive"):
			continue
		var radius: float = 0.5
		var height: float = 1.5
		var ed = enemy.get("enemy_data")
		if ed != null:
			radius = float(ed.collision_radius)
			height = float(ed.collision_height)
		# Per-node override for destructibles riding the group without
		# enemy_data: a wall is far wider than the 0.5 default, and testing
		# its centre point alone would leave most of its face outside any
		# weapon's cone.
		radius = maxf(radius, float(enemy.get("target_radius") or 0.0))
		height = maxf(height, float(enemy.get("target_height") or 0.0))
		var center: Vector3 = enemy.global_position + Vector3(0, height * 0.5, 0)
		var d := distance_in_cone(
			origin, yaw,
			float(config.get("hit_h_dist", 2.4)), float(config.get("hit_v_dist", 0.5)),
			float(config.get("hit_h_angle_deg", 30.0)), float(config.get("hit_v_angle_deg", 40.0)),
			center, radius)
		if d >= 0.0:
			found.append({"enemy": enemy, "dist": d})
	found.sort_custom(func(a, b): return a.dist < b.dist)
	return found.map(func(c): return c.enemy)


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

class_name ProjectileSweep extends RefCounted
## Continuous sphere contact against actual Hurtbox shapes (spec /mechanics/targeting).
## The capsule gathers the swept volume; per-collider casts order contacts by
## entry time, not owner centers (large/bone-attached hitboxes can extend forward).

static func contacts(space: PhysicsDirectSpaceState3D, start: Vector3,
		motion: Vector3, radius: float) -> Array:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = motion.length() + radius * 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 32
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.margin = 0.0
	var basis := Basis.IDENTITY
	if not motion.is_zero_approx():
		basis = Basis(Quaternion(Vector3.UP, motion.normalized()))
	query.transform = Transform3D(basis, start + motion * 0.5)
	var candidates: Array = []
	var excluded: Array[RID] = []
	# Page through results so a crowded fight cannot silently hide a near hit.
	while true:
		query.exclude = excluded
		var batch := space.intersect_shape(query, 32)
		if batch.is_empty():
			break
		for hit in batch:
			if hit.rid not in excluded:
				excluded.append(hit.rid)
				candidates.append(hit)

	if candidates.is_empty():
		return []

	var sphere := SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, start)
	var found: Array = []
	for hit in candidates:
		if not hit.collider is Hurtbox:
			continue
		var others: Array[RID] = excluded.duplicate()
		others.erase(hit.rid)
		query.exclude = others
		query.motion = Vector3.ZERO
		var fraction := 0.0  # cast_motion alone ignores initial overlaps
		if space.intersect_shape(query, 1).is_empty():
			query.motion = motion
			fraction = space.cast_motion(query)[1]
		found.append({"hurtbox": hit.collider, "fraction": fraction})
	found.sort_custom(func(a, b): return a.fraction < b.fraction)
	return found


## First contact of an XZ segment with a circle, or -1 for a miss.
## Enemy shots intentionally use planar gameplay geometry, as does the web sim.
static func planar_fraction(start: Vector3, motion: Vector3, center: Vector3, radius: float) -> float:
	var offset := Vector2(start.x - center.x, start.z - center.z)
	var travel := Vector2(motion.x, motion.z)
	var c := offset.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var a := travel.length_squared()
	if a <= 0.0000001:
		return -1.0
	var b := offset.dot(travel)
	var discriminant := b * b - a * c
	if discriminant < 0.0:
		return -1.0
	var t := (-b - sqrt(discriminant)) / a
	return t if t >= 0.0 and t <= 1.0 else -1.0

class_name ReyburnFloor extends RefCounted
## Collision-backed support checks, independent of the dragon's airborne Y.
const RADIUS := 4.0

static func sample(boss, point: Vector3) -> Dictionary:
	var ground := Vector3.ZERO
	for index in 9:
		var offset := Vector3.ZERO if index == 0 else Vector3(cos((index-1)*TAU/8),0,sin((index-1)*TAU/8))*RADIUS
		var origin := point + offset
		origin.y = boss._ground_height + 16.0
		var end := origin - Vector3.UP * 24.0
		var query := PhysicsRayQueryParameters3D.create(origin,end,1,[boss.get_rid()])
		var hit: Dictionary = boss.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.normal.y < 0.8: return {}
		if index == 0: ground = hit.position
		elif absf(hit.position.y-ground.y) > 1.0: return {}
	return {"position":ground}

static func landing(boss, preferred: Vector3) -> Dictionary:
	var result := sample(boss,preferred)
	if not result.is_empty(): return result
	# Pick the closest supported alternative, not the first home candidate:
	# otherwise every rejected aerial waypoint collapses to the same hover spot.
	var best: Dictionary = {}
	var best_distance := INF
	for radius in [0.0,8.0,16.0,24.0,32.0]:
		for index in (1 if radius == 0.0 else 16):
			var point: Vector3 = boss._home + Vector3(cos(index*TAU/16),0,sin(index*TAU/16))*radius
			var distance := Vector2(point.x-preferred.x,point.z-preferred.z).length_squared()
			if distance >= best_distance: continue
			result = sample(boss,point)
			if not result.is_empty():
				best = result
				best_distance = distance
	return best

class_name EnemyAttackLogic
## Pure, side-effect-free attack math — the Godot port of the normative reference
## `web/src/enemy-room/fsm.ts` (`selectAttack`, `arcHitTest`). Kept static + free of
## node state so test_runner can pin it directly against the web unit tests
## (spec /mechanics/enemy-attacks). #509.


## Weighted-random attack selection by range band. Port of fsm.ts `selectAttack`.
## `attacks` are already resolved dicts (defaults merged, berserk pre-filtered by caller).
## Candidates = attacks whose [min_range, max_range] band contains `dist`; the pick is
## weighted-random among them. An empty candidate set falls back to the attack whose band
## is nearest to `dist` — a non-empty table never yields "no attack". Empty table → {}.
static func select_attack(attacks: Array, dist: float, rng: RandomNumberGenerator) -> Dictionary:
	if attacks.is_empty():
		return {}

	var candidates: Array = []
	for a in attacks:
		if dist >= float(a.get("min_range", 0.0)) and dist <= float(a.get("max_range", 999.0)):
			candidates.append(a)

	if candidates.is_empty():
		var best: Dictionary = attacks[0]
		var best_gap := INF
		for a in attacks:
			var lo := float(a.get("min_range", 0.0))
			var hi := float(a.get("max_range", 999.0))
			var gap := (lo - dist) if dist < lo else (dist - hi)
			if gap < best_gap:
				best_gap = gap
				best = a
		return best

	var total := 0.0
	for a in candidates:
		total += maxf(float(a.get("weight", 1.0)), 0.0)
	if total <= 0.0:
		return candidates[0]

	var roll := rng.randf() * total
	for a in candidates:
		roll -= maxf(float(a.get("weight", 1.0)), 0.0)
		if roll <= 0.0:
			return a
	return candidates[candidates.size() - 1]


## Flat arc hit test on the XZ plane. Port of fsm.ts `arcHitTest`. Apex at the enemy
## origin, aimed along the facing locked at attack start. A target is inside iff its XZ
## distance <= hit_reach + target radius AND the XZ angle from facing <= half_angle_deg
## (boundary inclusive). No vertical bound, no apex pull-back — deliberately simpler than
## the player weapon cone (spec /mechanics/enemy-attacks "Hit shape").
static func arc_hit_test(enemy_pos: Vector3, facing: Vector3, target_pos: Vector3,
		target_radius: float, half_angle_deg: float, reach: float) -> bool:
	var to := target_pos - enemy_pos
	to.y = 0.0
	var d := to.length()
	if d > reach + target_radius:
		return false
	if d < 1e-6:
		return true  # standing inside the enemy
	var dir := to / d
	var f := Vector3(facing.x, 0.0, facing.z)
	if f.length() < 1e-6:
		return false
	f = f.normalized()
	var dot := clampf(dir.x * f.x + dir.z * f.z, -1.0, 1.0)
	var angle := rad_to_deg(acos(dot))
	return angle <= half_angle_deg + 1e-9  # boundary inclusive

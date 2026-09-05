class_name EnemyLocomotionLogic
## Pure, side-effect-free per-archetype locomotion decisions — the Godot port of the
## chase branches in the normative reference `web/src/enemy-room/fsm.ts`. Kept static +
## node-free so test_runner can pin the geometry directly (spec /states/enemies, #494).
## The functions return a movement INTENT (world direction on XZ + which side); EnemyBase
## maps that to speed tier / clip per rig and applies the physics (floor guard, facing).


## Standoff 3-band kite decision — shared by quad_machine / shooter / roller
## (fsm.ts:736-767, 894-915, 924-948). `radial` is the unit XZ vector toward the target.
## Returns {mode, dir, side_left}: retreat (too close, back out along -radial),
## close (too far, in along radial), strafe (in band, lateral tangent by arc_side), or
## hold (in band with strafe off — stand and act). `dir` is a unit XZ vector (ZERO for hold).
static func standoff_move(dist: float, standoff: float, radial: Vector3, arc_side: float,
		near_mult: float, far_mult: float, strafe: bool) -> Dictionary:
	if dist < standoff * near_mult:
		return {"mode": "retreat", "dir": -radial, "side_left": false}
	if dist > standoff * far_mult:
		return {"mode": "close", "dir": radial, "side_left": false}
	if not strafe:
		return {"mode": "hold", "dir": Vector3.ZERO, "side_left": false}
	var tangent := Vector3(-radial.z * arc_side, 0.0, radial.x * arc_side)
	# left-of-facing (y-up) = (facing.z, -facing.x); which side the tangent leans.
	var left_dot := tangent.x * radial.z + tangent.z * (-radial.x)
	return {"mode": "strafe", "dir": tangent, "side_left": left_dot > 0.0}


## Quadruped arc/dash decision (fsm.ts:689-725). Quadrupeds (head-turned rigs) MUST NOT
## walk straight while circling — only the `dash` closes straight. Arc = tangent blended
## with a gentle 0.45 inward spiral. Returns {dir, dash, side_left}; side_left picks
## wlk_l vs wlk_r by which side of the enemy's heading the target sits.
static func quadruped_move(radial: Vector3, arc_side: float, dash: bool) -> Dictionary:
	if dash:
		return {"dir": radial, "dash": true, "side_left": false}
	var tangent := Vector3(-radial.z * arc_side, 0.0, radial.x * arc_side)
	var dir := (tangent + radial * 0.45).normalized()
	var left_dot := radial.x * dir.z + radial.z * (-dir.x)
	return {"dir": dir, "dash": false, "side_left": left_dot > 0.0}


## Flyer approach/orbit decision (fsm.ts:861-886, spec /states/enemies §flyer): beyond
## 1.4x the orbit radius flap straight in (fly); inside it, hover-orbit on the tangent
## (tk) while watching the target. Returns {mode, dir} with dir a unit XZ vector.
static func flyer_move(dist: float, orbit: float, radial: Vector3, arc_side: float) -> Dictionary:
	if dist > orbit * 1.4:
		return {"mode": "approach", "dir": radial}
	var tangent := Vector3(-radial.z * arc_side, 0.0, radial.x * arc_side)
	return {"mode": "orbit", "dir": tangent}

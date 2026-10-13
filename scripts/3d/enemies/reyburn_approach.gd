class_name ReyburnApproach extends RefCounted
## Bounded repositioning with a ranged-attack goal, not indefinite pursuit.
var active := false
var ticks := 0
var goal := Vector3.ZERO
var turning := false

func reset() -> void:
	active = false
	ticks = 0
	turning = false

func begin(boss) -> void:
	reset()
	active = true
	goal = boss.global_position
	if not is_instance_valid(boss.target): return
	# Dash ahead and to a flank, making room to turn back toward the player.
	for side in [1.0,-1.0,0.0]:
		var preferred: Vector3 = boss.global_position + boss.global_basis.z*20.0 + boss.global_basis.x*12.0*side
		var floor_hit := ReyburnFloor.landing(boss,preferred)
		if floor_hit.is_empty(): continue
		var point: Vector3 = floor_hit.position
		if point.distance_to(boss.target.global_position) >= 18.0 and point.distance_to(boss.global_position) >= 6.0:
			goal = point
			break
	boss.ground_motion.reset()

func tick(boss) -> Dictionary:
	ticks += 1
	var distance: float = boss._distance()
	var bearing: float = absf(boss._bearing())
	# Commit as soon as a useful firing angle exists; do not finish walking
	# an arbitrary route while an attack opportunity is already available.
	if distance >= 15.0 and distance <= 40.0 and bearing <= PI/4.0 and boss.controller.breath_timer <= 0:
		return {"id":6,"types":[0],"counts":[1]}
	if not turning and (ticks >= 90 or boss.global_position.distance_to(goal) < 3.0):
		turning = true
		boss.ground_motion.reset()
	if ticks >= 210:
		# A moving player can deny the firing angle. End the maneuver instead
		# of circling forever; close targets get a wing attack, distant ones a roar.
		return {"id":7,"duration":60} if distance < 12.0 else {"id":3}
	var animation := 5 if turning else 6
	if boss.action_id != animation: boss.play_action(animation,{0:-1})
	boss.ground_motion.step(boss,2.4 if turning else 8.0,null if turning else goal)
	return {"id":-1}

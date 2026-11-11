extends RefCounted
## Explicit selection: no automatic replacement when the selected enemy disappears.
const ACQUIRE_RANGE := 20.0
const KEEP_RANGE := 24.0
const OCCLUSION_GRACE := 0.5
var target: Node3D
var obscured := 0.0

func clear() -> void:
	target = null
	obscured = 0.0

static func living(enemy) -> bool:
	return is_instance_valid(enemy) and enemy.is_inside_tree() and not enemy.is_queued_for_deletion() and enemy is EnemyBase and enemy.enemy_data != null and enemy.is_alive and enemy.current_hp > 0

static func point(enemy: Node3D) -> Vector3:
	return enemy.global_position + Vector3.UP * enemy.enemy_data.collision_height * 0.5

func visible(orbit, enemy: Node3D) -> bool:
	var start: Vector3 = orbit.target.global_position + Vector3.UP
	var ray := PhysicsRayQueryParameters3D.create(start, point(enemy), 1)
	return orbit.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func candidates(orbit) -> Array:
	var found: Array = []
	var camera: Camera3D = orbit.camera
	var screen: Rect2 = orbit.get_viewport().get_visible_rect()
	for enemy in orbit.get_tree().get_nodes_in_group("enemies"):
		if not living(enemy): continue
		if orbit.target.global_position.distance_to(enemy.global_position) > ACQUIRE_RANGE: continue
		var position := point(enemy)
		if camera.is_position_behind(position): continue
		var pixel := camera.unproject_position(position)
		if not screen.has_point(pixel) or not visible(orbit, enemy): continue
		found.append({"enemy": enemy, "score": pixel.distance_squared_to(screen.get_center()), "x": pixel.x})
	found.sort_custom(func(a, b): return a.score < b.score if a.score != b.score else a.enemy.get_instance_id() < b.enemy.get_instance_id())
	return found

func select(orbit, cycle := false) -> void:
	var choices := candidates(orbit)
	if choices.is_empty(): return
	var next: Node3D = choices[0].enemy
	if cycle:
		choices.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.enemy.get_instance_id() < b.enemy.get_instance_id())
		for i in range(choices.size()):
			if choices[i].enemy == target:
				next = choices[(i + 1) % choices.size()].enemy
				break
	target = next
	obscured = 0.0

func update(orbit, delta: float) -> void:
	if not living(target):
		clear()
		return
	if orbit.target.global_position.distance_to(target.global_position) > KEEP_RANGE:
		clear()
		return
	obscured = 0.0 if visible(orbit, target) else obscured + delta
	if obscured >= OCCLUSION_GRACE: clear()

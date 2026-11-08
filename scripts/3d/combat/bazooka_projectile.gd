extends Projectile
## Isolated bazooka fixture: one impact, one bounded splash.
const BLAST_RADIUS := 2.5

func _on_area_entered(area: Area3D) -> void:
	if _spent or is_queued_for_deletion() or not area is Hurtbox or not area.monitorable: return
	var primary = area.owner_node
	if not is_instance_valid(primary) or primary == owner_node or primary.get("is_alive") == false: return
	_spent = true
	var center: Vector3 = primary.global_position
	var victims := _blast_victims(primary, center)
	for enemy in victims:
		if _hit_targets.size() >= max_hits: break
		var hurtbox = enemy.get("hurtbox")
		if not hurtbox is Hurtbox or not hurtbox.monitorable: continue
		var ray := PhysicsRayQueryParameters3D.create(center + Vector3.UP, enemy.global_position + Vector3.UP, 1)
		if enemy != primary and not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		_hit_targets.append(enemy)
		var push: Vector3 = enemy.global_position - center
		if push.is_zero_approx(): push = direction
		_deliver(hurtbox, push.normalized() * knockback)
	if is_instance_valid(owner_node):
		owner_node._spawn_aoe_visual(center + Vector3.UP * 0.5, Color(1.0, 0.45, 0.1), BLAST_RADIUS)
	queue_free()

func _blast_victims(primary, center: Vector3) -> Array:
	var victims: Array = [primary]
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == primary or not enemy.is_visible_in_tree() or enemy.get("dormant") == true or enemy.get("is_alive") == false: continue
		if enemy.global_position.distance_to(center) <= BLAST_RADIUS: victims.append(enemy)
	victims.sort_custom(func(a, b): return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	return victims

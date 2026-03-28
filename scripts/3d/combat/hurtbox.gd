class_name Hurtbox extends Area3D
## Hurtbox component for receiving damage from Hitbox areas.
## Attach to player, enemies, destructible objects, etc.

## Who owns this hurtbox
var owner_node: Node3D

## Emitted when this hurtbox is hit
signal hit_received(damage: int, knockback: Vector3, accuracy: int)


func _ready() -> void:
	collision_layer = 32  # Layer 5 = hitboxes
	collision_mask = 0
	monitoring = false
	set_deferred("monitorable", true)


## Called by Hitbox when we're hit
func take_hit(damage: int, knockback: Vector3, accuracy: int = 100) -> void:
	hit_received.emit(damage, knockback, accuracy)

	# If owner has take_damage method, call it
	if owner_node and owner_node.has_method("take_damage"):
		owner_node.take_damage(damage, knockback, accuracy)

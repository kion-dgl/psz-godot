class_name Hitbox extends Area3D
## Hitbox component for dealing damage to Hurtbox areas.
## Attach to player attacks, enemy attacks, projectiles, etc.

## Damage to deal on hit
@export var damage: int = 10

## Knockback force
@export var knockback: float = 5.0

## Who owns this hitbox (used to prevent self-damage)
var owner_node: Node3D

## Track what we've already hit this attack (prevent multi-hit)
var _hit_targets: Array[Node3D] = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = 32  # Layer 5 = hitboxes (hurtboxes use this layer)
	monitoring = false  # Disabled by default, enabled during attacks
	monitorable = false

	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area3D) -> void:
	if area is Hurtbox:
		var hurtbox := area as Hurtbox

		# Don't hit ourselves
		if hurtbox.owner_node == owner_node:
			return

		# Don't hit same target twice per attack
		if hurtbox.owner_node in _hit_targets:
			return

		_hit_targets.append(hurtbox.owner_node)

		# Calculate knockback direction
		var knockback_dir := Vector3.ZERO
		if owner_node and hurtbox.owner_node:
			knockback_dir = (hurtbox.owner_node.global_position - owner_node.global_position).normalized()
			knockback_dir.y = 0

		# Deal damage
		hurtbox.take_hit(damage, knockback_dir * knockback)


## Enable the hitbox (call when attack starts)
func activate() -> void:
	_hit_targets.clear()
	monitoring = true


## Disable the hitbox (call when attack ends)
func deactivate() -> void:
	monitoring = false
	_hit_targets.clear()

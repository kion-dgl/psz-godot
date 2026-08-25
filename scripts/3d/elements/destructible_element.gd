extends GameElement
class_name DestructibleElement
## Base for elements the player breaks by attacking — boxes and walls.
##
## Holds what they share: a hurtbox that receives the attack hitbox, and the
## intact/destroyed toggle of visibility, physical collision, and hurtbox
## monitoring. Leaf classes own their own take_damage/destroy — a box drops loot
## on the first hit, a wall breaks on the third — but the plumbing that makes an
## attack register at all, and the state that turns it off once destroyed, lives
## here so it is written once.

## Collision body for physical presence.
var collision_body: StaticBody3D

## Hurtbox for receiving hits from the player's attack hitbox. Without it an
## attack never registers and the element can never be destroyed.
var hurtbox: Hurtbox


func _setup_hurtbox(hurtbox_name: String) -> void:
	hurtbox = Hurtbox.new()
	hurtbox.name = hurtbox_name
	hurtbox.owner_node = self
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Extend the hurtbox height so ranged projectiles can land on it too.
	var hb_size := Vector3(collision_size.x, maxf(collision_size.y, 2.0), collision_size.z)
	box.size = hb_size
	shape.shape = box
	shape.position.y = hb_size.y / 2
	hurtbox.add_child(shape)
	add_child(hurtbox)


func _apply_state() -> void:
	match element_state:
		"intact":
			set_element_visible(true)
			if collision_body:
				collision_body.collision_layer = 1
			if hurtbox:
				hurtbox.monitorable = true
		"destroyed":
			set_element_visible(false)
			if collision_body:
				collision_body.collision_layer = 0
			if hurtbox:
				hurtbox.set_deferred("monitorable", false)

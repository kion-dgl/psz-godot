class_name Hurtbox extends Area3D
## Hurtbox component for receiving damage from Hitbox areas.
## Attach to player, enemies, destructible objects, etc.

## Who owns this hurtbox
var owner_node: Node3D
var part_id := 0

## Emitted when this hurtbox is hit
signal hit_received(damage: int, knockback: Vector3, accuracy: int)


func _ready() -> void:
	collision_layer = 32  # Layer 5 = hitboxes
	collision_mask = 0
	monitoring = false
	set_deferred("monitorable", true)


## Called by Hitbox when we're hit
func take_hit(damage: int, knockback: Vector3, accuracy: int = 100, element: String = "", element_level: int = 0, player_credit: bool = false, attack_kind: String = "physical", source: Node3D = null) -> void:
	if owner_node and owner_node.has_method("can_receive_hit_from") and not owner_node.can_receive_hit_from(source): return
	var before: int = maxi(int(owner_node.current_hp), 0) if owner_node is EnemyBase else 0
	hit_received.emit(damage, knockback, accuracy)

	# If owner has _on_hit_received, call with element info
	if owner_node is EnemyBase:
		owner_node._set_hit_context(part_id, source)
		owner_node._on_hit_received(damage, knockback, accuracy, element, element_level, attack_kind)
		owner_node._set_hit_context(0, null)
	elif owner_node and owner_node.has_method("_on_hit_received"):
		owner_node._on_hit_received(damage, knockback, accuracy, element, element_level)
	elif owner_node and owner_node.has_method("take_damage"):
		owner_node.take_damage(damage, knockback, accuracy)

	if player_credit and owner_node is EnemyBase:
		PhotonBlast.gain_damage(maxi(before - maxi(owner_node.current_hp, 0), 0), owner_node.enemy_data.hp_base, false)


## Snapshot weapon stats at release; resolve family attributes against the struck target.
func take_attack(packet: Dictionary, knockback: Vector3, source: Node3D = null) -> void:
	var power: int = int(packet.get("damage", 0))
	if packet.has("base_attack") and owner_node is EnemyBase:
		var math = preload("res://scripts/utils/combat_math.gd")
		power = int(math.attribute_attack(int(packet.base_attack), int(packet.weapon_attack), packet.attributes, owner_node.enemy_data.element) * float(packet.power_multiplier))
	take_hit(power, knockback, int(packet.get("accuracy", 100)), str(packet.get("element", "")), int(packet.get("element_level", 0)), bool(packet.get("charge_pb", true)), str(packet.get("kind", "physical")), source)

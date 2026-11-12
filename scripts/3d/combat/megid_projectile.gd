extends Projectile

func _init() -> void:
	pierce = true
	max_hits = 0 # Continue through every distinct target until range/world collision.

func _deliver(hurtbox: Hurtbox, push: Vector3) -> void:
	var enemy := hurtbox.owner_node as EnemyBase
	if enemy == null or not enemy.is_alive or not enemy._accepts_damage(): return
	if enemy.has_method("can_receive_hit_from") and not enemy.can_receive_hit_from(owner_node): return
	# Reuse the existing turn-combat chance; bosses are immune in this prototype.
	var chance := clampf(0.20 + float(element_level) * 0.01, 0.0, 1.0)
	if enemy.enemy_data.is_boss or randf() >= chance:
		super._deliver(hurtbox, push)
		return
	var before := enemy.current_hp
	enemy.current_hp = 0
	enemy._die()
	PhotonBlast.gain_damage(before, enemy.enemy_data.hp_base, false)

func _contact_visual() -> void:
	pass # Piercing dark orb has no fire-colored contact burst.

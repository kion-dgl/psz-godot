extends RefCounted
## Clean, grounded combat hit feedback (audio + contact sparks, no screen shake,
## hitstop, or flashing).

const HIT_SFX := "res://assets/sfx/weapons/saber_hit.wav"
const CRIT_SFX := "res://assets/sfx/weapons/saber_crit.wav"


static func play_hit(enemy: Node3D, source: Node3D, strong: bool, critical: bool = false, finisher: bool = false) -> void:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	var heavy := strong or critical or finisher
	if is_instance_valid(source) and source.has_method("_get_equipped_weapon_type"):
		if source._get_equipped_weapon_type() in [WeaponData.WeaponType.DAGGERS, WeaponData.WeaponType.CLAW, WeaponData.WeaponType.DOUBLE_SABER]:
			var now := Time.get_ticks_msec()
			if now - int(enemy.get_meta("dagger_feedback_ms", -1000)) < 75:
				return
			enemy.set_meta("dagger_feedback_ms", now)

	_play_hit_sfx(enemy.global_position, heavy, critical)
	var scene := enemy.get_tree().current_scene
	if scene:
		_spawn_sparks(scene, _contact_pos(enemy, source), heavy, critical)


static func _play_hit_sfx(pos: Vector3, heavy: bool, critical: bool) -> void:
	if critical:
		SfxManager.play_at(CRIT_SFX, pos, 1.0, false, randf_range(0.96, 1.05))
	elif heavy:
		SfxManager.play_at(HIT_SFX, pos, 0.5, false, randf_range(0.88, 0.95))
	else:
		SfxManager.play_at(HIT_SFX, pos, -1.5, false, randf_range(0.96, 1.08))


static func _contact_pos(enemy: Node3D, source: Node3D) -> Vector3:
	var height := 1.0
	var edata: Variant = enemy.get("enemy_data")
	if edata != null:
		height = clampf(float(edata.collision_height) * 0.55, 0.6, 1.8)
	var toward := Vector3.ZERO
	if is_instance_valid(source):
		toward = source.global_position - enemy.global_position
		toward.y = 0.0
		if toward.length_squared() > 0.0001:
			toward = toward.normalized()
	return enemy.global_position + Vector3(0.0, height, 0.0) + toward * 0.35


static func _spawn_sparks(scene: Node, pos: Vector3, heavy: bool, critical: bool) -> void:
	var burst := CPUParticles3D.new()
	burst.name = "SaberContactSpark"
	burst.add_to_group("saber_contact_feedback")
	burst.one_shot = true
	burst.amount = 10 if (heavy or critical) else 6
	burst.lifetime = 0.18
	burst.explosiveness = 1.0
	burst.direction = Vector3.UP
	burst.spread = 110.0
	burst.initial_velocity_min = 0.8
	burst.initial_velocity_max = 1.8 if heavy else 1.2
	burst.gravity = Vector3(0, -2.5, 0)
	burst.scale_amount_min = 0.5
	burst.scale_amount_max = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.030 if heavy else 0.025
	mesh.height = mesh.radius * 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.82, 0.35) if (heavy or critical) else Color(0.8, 1.0, 1.0)
	mesh.material = material
	burst.mesh = mesh
	scene.add_child(burst)
	burst.global_position = pos
	burst.emitting = true
	burst.finished.connect(burst.queue_free)

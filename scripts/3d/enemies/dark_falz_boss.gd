class_name DarkFalzBoss extends DescriptorBoss
## ROM action chains and damage thresholds; authored first-pass spatial selector.
## Does not claim the ov19 multi-target, subobject or effect simulation is complete.

var damage_rules := BossPhaseRules.FalzDamage.new()
var pending_reaction := 0
var _relocate_to := Vector3.ZERO

func _setup_model() -> void:
	super._setup_model()
	if not model:
		return
	# This arena has no useful model lighting. Preserve the DS unlit palette
	# instead of inheriting the field-enemy relighting pass's black silhouette.
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface)
			if source is StandardMaterial3D:
				var material := source.duplicate() as StandardMaterial3D
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh.set_surface_override_material(surface, material)

func _ready() -> void:
	super._ready()
	play_sequence([0, 1])

func _after_damage_applied(amount: int) -> void:
	var request := damage_rules.hit(current_hp, encounter_max_hp, -amount)
	if current_hp > 0 and request != 0:
		pending_reaction = request

func _accepts_damage() -> bool:
	return action_id != 4

func _sequence_finished() -> void:
	if not is_alive:
		return
	if pending_reaction != 0:
		var reaction := pending_reaction
		pending_reaction = 0
		play_sequence([10 if reaction == 2 else 11, 1])
		return
	_aim_at_target()
	var distance := global_position.distance_to(target.global_position) if is_instance_valid(target) else 0.0
	var pick := _rng.randi_range(0, 3)
	if distance < 8.0 and pick == 0:
		play_sequence([{"id":12,"loops":{1:1}},14,{"id":15,"loops":{0:1}},16,1])
	elif distance > 25.0:
		_relocate_to = target.global_position - (target.global_position - global_position).normalized() * 12.0
		_relocate_to.y = global_position.y
		play_sequence([3, 4, 5, 1])
	elif pick == 1:
		play_sequence([{"id":19,"loops":{1:2}},20,1])
	elif pick == 2:
		play_sequence([{"id":12,"loops":{1:1}},13,{"id":15,"loops":{0:1}},16,1])
	elif pick == 3 and damage_rules.flags != 0:
		play_sequence([21,1])
	else:
		play_sequence([{"id":17,"loops":{1:4}},18,1])

func _physics_process(delta: float) -> void:
	if is_alive and action_id == 4:
		# Authored relocation, bounded to the existing floor; original swim physics TBD.
		var direction := _relocate_to - global_position
		direction.y = 0
		if direction.length() > 0.1 and _can_move_to(direction.normalized()):
			velocity = direction.normalized() * 6.0
			move_and_slide()
	super._physics_process(delta)

func _cycle_finished(stage_index: int, cycle: int) -> void:
	if action_id == 19 and stage_index == 1 and cycle <= 2:
		_shoot()

func _boss_notification(id: int, kind: String) -> void:
	if kind != "point":
		return
	if action_id == 18 and id == 2:
		for index in 5:
			_shoot(deg_to_rad(float(index - 2) * 12.5))
	elif action_id == 21 and id in [0,1]:
		_shoot()
	elif action_id in [13,14] and id == 13:
		for index in 12:
			_shoot(TAU * float(index) / 12.0)

func _death_action() -> int:
	return 22

extends FieldHazard
class_name GunTrap
## Aimed, wall-blocked, non-homing shots; values are remake tuning.
const RANGE := 14.0
const WARNING := 0.6
const COOLDOWN := 2.0
const SPIN_TIME := 0.9
var _spin_remaining := 0.0
var detonations := 0
var _target: Node3D
var _aim := Vector3.FORWARD
var shots_fired := 0

func _init() -> void:
	trap_kind = "gun_trap"
	model_path = "valley/o0c_gun01.glb"
	collision_size = Vector3(2.8, 2.4, 2.8)
	target_radius = 1.4
	target_height = 1.2

func _update_animation(delta: float) -> void:
	if _spin_remaining > 0.0:
		_step_destruction(delta)
		return
	if not is_alive: return
	timer = maxf(0.0, timer - delta)
	if element_state == "warning":
		pulse_warning()
		if timer <= 0.0: _fire()
	elif timer <= 0.0:
		_target = nearby_actor()
		if _target:
			_aim = _target.global_position - global_position
			_aim.y = 0.0
			_aim = _aim.normalized() if not _aim.is_zero_approx() else global_basis.z
			if model:
				var aim_local := global_basis.inverse() * _aim
				model.rotation.y = atan2(aim_local.x, aim_local.z)
			set_state("warning")
			timer = WARNING

func _fire() -> void:
	set_state("on")
	timer = COOLDOWN
	if model: model.scale = Vector3.ONE
	if not eligible_target(_target): return
	var bullet := preload("res://scripts/3d/elements/turret_projectile.gd").new()
	bullet.model_path = "res://assets/objects/valley/o0c_bullet01.glb"
	bullet.dir = _aim
	bullet.target = _target
	bullet.damage = 8
	bullet.max_range = RANGE
	add_child(bullet)
	bullet.place_at_muzzle(global_position + Vector3.UP * 0.8, _aim * 0.8)
	shots_fired += 1

func restore_hazard(record: Dictionary) -> void:
	super.restore_hazard(record)
	if element_state == "warning":
		element_state = "on"
		timer = maxf(timer, WARNING)


## Neutral hazard: nearest living actor in the authored cone; scenery in the
## enemies group is excluded. Ties favor the player. Shots remain target-locked.
static func eligible_target(actor: Node) -> bool:
	return living_player(actor) or (is_instance_valid(actor) and actor is EnemyBase and actor.is_alive)

func nearby_actor() -> Node3D:
	var nearest: Node3D
	var distance := INF
	var actors := get_tree().get_nodes_in_group("player")
	actors.append_array(get_tree().get_nodes_in_group("enemies"))
	for actor in actors:
		if not eligible_target(actor): continue
		if not in_cone(to_local(actor.global_position), RANGE) or not clear_sight(actor): continue
		var candidate := global_position.distance_squared_to(actor.global_position)
		if candidate < distance:
			nearest = actor
			distance = candidate
	return nearest

func take_damage(amount: int, _knockback := Vector3.ZERO, _accuracy: int = 100) -> void:
	if amount <= 0 or not is_alive: return
	# Persist spent immediately: leaving mid-spin must never resurrect the gun.
	_spin_remaining = SPIN_TIME
	set_state("spent")
	_target = null
	if model:
		model.visible = true
		model.scale = Vector3.ONE

func _step_destruction(delta: float) -> void:
	_spin_remaining = maxf(0.0, _spin_remaining - delta)
	var elapsed := SPIN_TIME - _spin_remaining
	if model:
		model.rotation.y += delta * (12.0 + elapsed * 18.0)
		model.rotation.x = sin(elapsed * 24.0) * 0.35
		model.rotation.z = cos(elapsed * 19.0) * 0.35
	if _spin_remaining > 0.0: return
	detonations += 1
	_spawn_break_effect(Color(0.7, 0.55, 0.35))
	preload("res://scripts/3d/elements/hazard_blast.gd").show_flash(self, 1.4)
	SfxManager.play_at("res://assets/sfx/common/common_160.wav", global_position)
	if model: model.visible = false

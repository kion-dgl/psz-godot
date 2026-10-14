extends FieldHazard
class_name GunTrap
## Aimed, wall-blocked, non-homing shots; values are remake tuning.
const RANGE := 14.0
const WARNING := 0.6
const COOLDOWN := 2.0
var _target: Node3D
var _aim := Vector3.FORWARD
var shots_fired := 0

func _init() -> void:
	trap_kind = "gun_trap"
	model_path = "valley/o0c_gun01.glb"

func _update_animation(delta: float) -> void:
	if not is_alive: return
	timer = maxf(0.0, timer - delta)
	if element_state == "warning":
		pulse_warning()
		if timer <= 0.0: _fire()
	elif timer <= 0.0:
		_target = nearby_player(RANGE)
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
	if not living_player(_target): return
	var bullet := EnemyProjectile.new()
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

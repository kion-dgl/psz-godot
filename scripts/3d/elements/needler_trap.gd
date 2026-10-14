extends FieldHazard
class_name NeedlerTrap
## Clay's source-sized directional sweep, not the ordinary needle floor plate.
const TRIGGER_RANGE := 3.0
const RANGE := 12.0
const WARNING := 0.75
const SWEEP_SECONDS := 0.6
const COOLDOWN := 12.0
const DAMAGE := 25 # Intentional flat HP tuning; original parameter is percentage-like.
var _hit_actors: Dictionary = {}
var sweeps := 0
var _sweep_materials: Array[ShaderMaterial] = []

func _ready() -> void:
	super._ready()
	apply_to_all_materials(func(mat: Material, _mesh: MeshInstance3D, _surface: int) -> void:
		if mat is ShaderMaterial: _sweep_materials.append(mat)
	)
	_reveal(1.5)

func _reveal(radius: float) -> void:
	for material in _sweep_materials: material.set_shader_parameter("reveal_radius", radius)

func _apply_state() -> void:
	super._apply_state()
	if element_state != "active": _reveal(1.5)

func _init() -> void:
	trap_kind = "needler_trap"
	model_path = "valley/o0c_clay1.glb"

func take_damage(amount: int, _knockback := Vector3.ZERO, _accuracy: int = 100) -> void:
	if amount > 0 and element_state == "on": _warn()

func _warn() -> void:
	set_state("warning")
	timer = WARNING

func _update_animation(delta: float) -> void:
	if not is_alive: return
	if element_state == "on":
		if nearby_player(TRIGGER_RANGE): _warn()
		return
	timer = maxf(0.0, timer - delta)
	match element_state:
		"warning":
			pulse_warning()
			if timer <= 0.0:
				set_state("active")
				timer = SWEEP_SECONDS
				_hit_actors.clear()
				sweeps += 1
		"active":
			var fraction := 1.0 - timer / SWEEP_SECONDS
			if model: model.scale = Vector3.ONE # Never use Storybook's preview scale.
			_reveal(maxf(1.5, RANGE * fraction))
			_sweep(RANGE * fraction)
			if timer <= 0.0:
				set_state("cooldown")
				timer = COOLDOWN
		"cooldown":
			if timer <= 0.0: set_state("on")

func _sweep(radius: float) -> void:
	for actor in get_tree().get_nodes_in_group("player"):
		if not living_player(actor) or _hit_actors.has(actor.get_instance_id()): continue
		if not in_cone(to_local(actor.global_position), radius) or not clear_sight(actor): continue
		# A dodge consumes this wave contact, so it cannot hit on the next frame.
		_hit_actors[actor.get_instance_id()] = true
		actor.take_damage(DAMAGE)

func save_hazard() -> Dictionary:
	if element_state == "active": return {"state": "cooldown", "timer": COOLDOWN}
	return super.save_hazard()

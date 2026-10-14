extends FieldHazard
class_name BombTrap
## Attack-triggered container; one warned blast, no contact damage or loot.
const WARNING := 0.6
const RADIUS := 4.0
const DAMAGE := 50 # Remake HP tuning; the source's 50 is a percentage parameter.
var detonations := 0

func _init() -> void:
	trap_kind = "burn_trap"
	model_path = "valley/o0c_bombcont.glb"

func take_damage(amount: int, _knockback := Vector3.ZERO, _accuracy: int = 100) -> void:
	if amount <= 0 or element_state != "on": return
	set_state("warning")
	timer = WARNING

func _update_animation(delta: float) -> void:
	if element_state != "warning": return
	pulse_warning()
	timer -= delta
	if timer <= 0.0: _detonate()

func _detonate() -> void:
	set_state("spent") # Latch before delivering any damage/signals.
	detonations += 1
	var actors: Array = get_tree().get_nodes_in_group("player")
	actors.append_array(get_tree().get_nodes_in_group("enemies"))
	for actor in actors:
		if not (living_player(actor) or (actor is EnemyBase and actor.is_alive)): continue
		if actor.global_position.distance_squared_to(global_position) > RADIUS * RADIUS or not clear_sight(actor): continue
		if actor is EnemyBase:
			actor.hurtbox.take_hit(DAMAGE, Vector3.ZERO, 1000)
		else:
			actor.take_damage(DAMAGE)
	_show_blast()

func _show_blast() -> void:
	preload("res://scripts/3d/elements/hazard_blast.gd").show_flash(self, RADIUS)

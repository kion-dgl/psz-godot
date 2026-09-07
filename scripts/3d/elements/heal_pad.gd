extends GameElement
class_name HealPad
## The goal room's heal pad (o0c_healhp, #644): exactly one authored record in
## every area's ga1 — the room that terminates every generated section since
## #643, which is what makes the pad worth porting.
##
## The name is the decoded behaviour — it heals HP. How MUCH the original
## restores is not measured (psz-re publishes the placement, not the parameter
## block), so this takes the reading the object's own name implies: standing
## on it restores HP to full. Reusable within a visit on a short cooldown,
## which keeps the element STATELESS — a revisit rebuilds it fresh and nothing
## about it enters the cell save.
##
## A trigger Area3D only (needle-trap layers): nothing solid for the autopilot
## backbone or the player to wedge on.

const HEAL_COOLDOWN := 3.0

var _trigger: Area3D = null
var _since_heal: float = HEAL_COOLDOWN
var _pulse: float = 0.0


func _init() -> void:
	model_path = "special_z/o0c_healhp.glb"
	element_state = "on"


func _ready() -> void:
	# Wide and low: the pad is stepped ON, not walked into at chest height.
	# (interactable/auto_collect stay at the base defaults — the pad is not an
	# E-key element and never auto-collects.)
	collision_size = Vector3(2.4, 0.8, 2.4)
	super._ready()
	_trigger = Area3D.new()
	_trigger.name = "HealArea"
	_trigger.collision_layer = 4  # Triggers layer — same as every element area
	_trigger.collision_mask = 2   # Player layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2.0
	_trigger.add_child(shape)
	_trigger.body_entered.connect(_on_body_entered)
	add_child(_trigger)


func _on_body_entered(body: Node3D) -> void:
	if element_state != "on":
		return
	if not (body.is_in_group("player") or body.name == "Player"):
		return
	if _since_heal < HEAL_COOLDOWN:
		return
	if GameState.hp >= GameState.max_hp:
		return
	_since_heal = 0.0
	_pulse = 1.0
	GameState.set_hp(GameState.max_hp)
	print("[HealPad] Restored HP to %d/%d at %s" % [GameState.hp, GameState.max_hp, global_position])


func _update_animation(delta: float) -> void:
	_since_heal += delta
	# Idle: a slow breathing pulse; a heal lands as one fast bright beat.
	_pulse = maxf(0.0, _pulse - delta * 1.5)
	if not model:
		return
	var breathe := 1.0 + 0.03 * sin(_time * 2.0)
	var s := breathe + 0.12 * _pulse
	model.scale = Vector3(s, s, s)

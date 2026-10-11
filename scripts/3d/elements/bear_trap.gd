extends GameElement
class_name BearTrap
## Floor bear trap. When stepped on: catches the player, holds them
## for a few seconds with a scrolling laser texture, then damages and releases.
## States: on (armed, prongs visible), off (triggered, prongs hidden)

const PRONG_TEX_NAME := "o0c_1_tora1"
const DAMAGE_AMOUNT := 20
const HOLD_DURATION := 2.5
const SCROLL_SPEED := 0.5

var _prong_materials: Array[ShaderMaterial] = []
var _caught_body: Node3D = null
var _hold_timer: float = 0.0
var _is_holding: bool = false


func _init() -> void:
	model_path = "valley/o0c_torabasami.glb"
	element_state = "on"
	collision_size = Vector3(2.0, 1.0, 2.0)
	auto_collect = false
	interactable = false


func _ready() -> void:
	super._ready()
	_setup_materials()
	_setup_trigger_area()
	_apply_state()


func _setup_materials() -> void:
	_prong_materials = _setup_split_materials(PRONG_TEX_NAME, Vector4(1.0, 1.0, 0.0, -2.31), false)

func _setup_trigger_area() -> void:
	var area := Area3D.new()
	area.name = "TriggerArea"
	area.collision_layer = 4
	area.collision_mask = 2

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	area.add_child(shape)

	area.body_entered.connect(_on_body_stepped)
	add_child(area)
	interaction_area = area


func _on_body_stepped(body: Node3D) -> void:
	if element_state != "on" or not body.is_in_group("player"):
		return
	if body.has_method("can_take_hit") and not body.can_take_hit():
		return
	if _is_holding:
		return
	_is_holding = true
	_caught_body = body
	_hold_timer = 0.0
	if body.has_method("transition_to") and body.get("PlayerState"):
		body.transition_to(body.PlayerState.CUTSCENE)
	print("[BearTrap] Caught player, holding for %.1fs" % HOLD_DURATION)


func _update_animation(delta: float) -> void:
	if element_state != "on":
		return
	for material in _prong_materials:
		var offset: Vector2 = material.get_shader_parameter("uv_offset")
		offset.y -= SCROLL_SPEED * delta
		material.set_shader_parameter("uv_offset", offset)

	if not _is_holding:
		return
	_hold_timer += delta
	if _hold_timer >= HOLD_DURATION:
		_release()


func _release() -> void:
	_is_holding = false
	if is_instance_valid(_caught_body):
		if _caught_body.has_method("take_damage"):
			_caught_body.take_damage(DAMAGE_AMOUNT)
		# Damage owns the resulting stagger, defeat or doll-recovery state.
		_release_hold()
	_caught_body = null
	set_state("off")
	print("[BearTrap] Released player, trap disabled")


func _apply_state() -> void:
	for material in _prong_materials:
		material.set_shader_parameter("visibility_alpha", 1.0 if element_state == "on" else 0.0)

	if interaction_area:
		var armed: bool = element_state == "on"
		interaction_area.set_deferred("monitoring", armed)
		interaction_area.set_deferred("monitorable", armed)


func _release_hold() -> void:
	if is_instance_valid(_caught_body) and _caught_body.get("current_state") == _caught_body.PlayerState.CUTSCENE:
		_caught_body.transition_to(_caught_body.PlayerState.IDLE)


func _exit_tree() -> void:
	# Room teardown must not strand a surviving player in the trap's hold.
	_release_hold()

extends GameElement
class_name BearTrap
## Floor bear trap. When stepped on: catches the player, holds them
## for a few seconds with a scrolling laser texture, then damages and releases.
## States: on (armed, prongs visible), off (triggered, prongs hidden)

const PRONG_TEX_NAME := "o0c_1_tora1"
const DAMAGE_AMOUNT := 20
const HOLD_DURATION := 2.5
const SCROLL_SPEED := 0.5

var _prong_material: StandardMaterial3D = null
var _base_material: StandardMaterial3D = null
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
	var mats := _setup_split_materials(PRONG_TEX_NAME)
	_prong_material = mats["feature"]
	_base_material = mats["base"]


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
	if element_state != "on":
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
	if not _is_holding:
		return

	if _prong_material:
		_prong_material.uv1_offset.y -= SCROLL_SPEED * delta

	_hold_timer += delta
	if _hold_timer >= HOLD_DURATION:
		_release()


func _release() -> void:
	_is_holding = false
	if is_instance_valid(_caught_body):
		if _caught_body.has_method("take_damage"):
			_caught_body.take_damage(DAMAGE_AMOUNT)
		if _caught_body.has_method("transition_to") and _caught_body.get("PlayerState"):
			var has_input: bool = Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_backward") or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")
			if has_input:
				_caught_body.transition_to(_caught_body.PlayerState.RUNNING)
			else:
				_caught_body.transition_to(_caught_body.PlayerState.IDLE)
	_caught_body = null
	set_state("off")
	print("[BearTrap] Released player, trap disabled")


func _apply_state() -> void:
	if _prong_material:
		match element_state:
			"on":
				_prong_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				_prong_material.albedo_color.a = 1.0
				_prong_material.alpha_scissor_threshold = 0.5
			"off":
				_prong_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				_prong_material.albedo_color.a = 0.0
				_prong_material.alpha_scissor_threshold = 1.0

	if interaction_area:
		var armed: bool = element_state == "on"
		interaction_area.set_deferred("monitoring", armed)
		interaction_area.set_deferred("monitorable", armed)

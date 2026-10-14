extends DestructibleElement
class_name BearTrap
## Dormant/off -> warning (escape window) -> on (capture) -> spent.
const PRONG_TEX_NAME := "o0c_1_tora1"
## Original NSBMD Max-mode SRT and per-surface wrap bits; /states/trap-validation.
const MATERIAL_PROFILES := {
	"o0c_1_tora1": {"uv_scale": Vector2(2.0, -1.0), "uv_offset": Vector2(0.0, 1.0), "mirror_x": true, "mirror_y": false},
	"o0c_1_tora2": {"uv_scale": Vector2(2.0, -2.0), "uv_offset": Vector2(0.0, 1.0), "mirror_x": true, "mirror_y": true},
}
const DAMAGE_AMOUNT := 20
const ESCAPE_DURATION := 0.6
const HOLD_DURATION := 2.5
const SCROLL_SPEED := 0.5
var _prong_materials: Array[ShaderMaterial] = []
var _caught_body: Node3D
var _hold_timer := 0.0
var _is_holding := false
var target_radius := 1.0
var target_height := 1.0
var is_alive: bool:
	get: return element_state in ["warning", "on"]

func _init() -> void:
	model_path = "valley/o0c_torabasami.glb"
	element_state = "off"
	collision_size = Vector3(2, 1, 2)
	auto_collect = false
	interactable = false

func _ready() -> void:
	super._ready()
	_prong_materials = _setup_split_materials(PRONG_TEX_NAME, MATERIAL_PROFILES)
	_setup_trigger_area()
	_setup_hurtbox("BearHurtbox")
	_setup_reticle(target_height)
	add_to_group("targetable_traps")
	_apply_state()

func _setup_trigger_area() -> void:
	interaction_area = Area3D.new()
	interaction_area.name = "TriggerArea"
	interaction_area.collision_layer = 4
	interaction_area.collision_mask = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	interaction_area.add_child(shape)
	interaction_area.body_entered.connect(_on_body_stepped)
	add_child(interaction_area)

func _eligible(body: Node3D) -> bool:
	return FieldHazard.living_player(body) and body.current_state != body.PlayerState.CUTSCENE and body.can_take_hit()

func _on_body_stepped(body: Node3D) -> void:
	if element_state != "off" or not _eligible(body): return
	set_state("warning")

func _capture_remaining() -> void:
	set_state("on")
	for body in interaction_area.get_overlapping_bodies():
		if not _eligible(body): continue
		_caught_body = body
		_is_holding = true
		body.transition_to(body.PlayerState.CUTSCENE)
		break

func _update_animation(delta: float) -> void:
	_update_visibility()
	if element_state == "spent": return
	if element_state == "off":
		for body in interaction_area.get_overlapping_bodies(): _on_body_stepped(body)
		return
	for material in _prong_materials:
		var offset: Vector2 = material.get_shader_parameter("uv_offset")
		offset.y -= SCROLL_SPEED * delta
		material.set_shader_parameter("uv_offset", offset)
	_hold_timer += delta
	if element_state == "warning":
		if _hold_timer >= ESCAPE_DURATION: _capture_remaining()
		return
	if _is_holding and (not is_instance_valid(_caught_body) or _caught_body.current_state != _caught_body.PlayerState.CUTSCENE):
		set_state("spent")
		return
	if _hold_timer >= HOLD_DURATION: _release()

func _release() -> void:
	var victim := _caught_body
	set_state("spent") # Release control before damage takes ownership of stagger/death.
	if is_instance_valid(victim): victim.take_damage(DAMAGE_AMOUNT)
	_show_blast()

func can_receive_hit_from(source: Node3D) -> bool:
	# Reject a trapped player's already-airborne projectile too.
	return is_alive and is_instance_valid(source) and source.is_in_group("player") and source != _caught_body and source.get("current_state") != source.PlayerState.CUTSCENE

func take_damage(amount: int, _knockback := Vector3.ZERO, _accuracy: int = 100) -> void:
	if amount <= 0 or not is_alive: return
	_release_hold()
	set_state("spent")

func _apply_state() -> void:
	if element_state != "on": _release_hold()
	_hold_timer = 0.0
	_update_visibility()
	for material in _prong_materials:
		material.set_shader_parameter("visibility_alpha", 1.0 if is_alive else 0.0)
	if interaction_area:
		interaction_area.set_deferred("monitoring", element_state != "spent")
	if hurtbox: hurtbox.set_deferred("monitorable", is_alive)
	if not is_alive: hide_reticle()

func _update_visibility() -> void:
	if model: model.visible = is_alive or (element_state == "off" and TrapBall.traps_are_visible())

func _release_hold() -> void:
	if is_instance_valid(_caught_body) and _caught_body.current_state == _caught_body.PlayerState.CUTSCENE:
		_caught_body.transition_to(_caught_body.PlayerState.IDLE)
	_is_holding = false
	_caught_body = null
	_hold_timer = 0.0

func _show_blast() -> void:
	preload("res://scripts/3d/elements/hazard_blast.gd").show_flash(self, 1.2)

func _exit_tree() -> void:
	_release_hold()

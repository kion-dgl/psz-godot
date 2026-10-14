extends DestructibleElement
class_name FieldHazard
## Attackable environmental hazards. Behavior contract: /states/trap-validation.
## Shared targeting, source materials, sight tests and persistence; leaves own delivery.
var trap_kind := ""
var timer := 0.0
var _warning: Label3D
var target_radius := 0.8
var target_height := 1.2
var is_alive: bool:
	get: return element_state not in ["off", "spent"]

func _init() -> void:
	element_state = "on"
	collision_size = Vector3(1.2, 1.2, 1.2)

func _ready() -> void:
	super._ready()
	add_to_group("targetable_traps")
	_setup_hurtbox("HazardHurtbox")
	_setup_reticle(target_height)
	_warning = Label3D.new()
	_warning.text = "!"
	_warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_warning.font_size = 64
	_warning.pixel_size = 0.012
	_warning.modulate = Color(1, 0.4, 0.05)
	_warning.position.y = 2.0
	add_child(_warning)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/environment_traps.json"))
	var profiles: Dictionary = reference.materials.get(model_path.get_file().get_basename(), {}).duplicate(true)
	for profile in profiles.values():
		for key in ["uv_scale", "uv_offset"]:
			profile[key] = Vector2(profile[key][0], profile[key][1])
	if not profiles.is_empty(): _setup_split_materials("", profiles)
	_apply_state()

func take_damage(amount: int, _knockback := Vector3.ZERO, _accuracy: int = 100) -> void:
	if amount > 0 and is_alive: set_state("spent")

func _apply_state() -> void:
	set_element_visible(element_state != "spent")
	if _warning: _warning.visible = element_state == "warning"
	if hurtbox: hurtbox.set_deferred("monitorable", is_alive)
	if not is_alive:
		hide_reticle()
		for child in get_children():
			if child is EnemyProjectile: child.queue_free()

static func in_cone(local: Vector3, radius: float, half_angle: float = PI / 3.0) -> bool:
	if absf(local.y) > 2.0: return false
	var flat := Vector2(local.x, local.z)
	return flat.length_squared() <= radius * radius and (flat.is_zero_approx() or flat.y / flat.length() >= cos(half_angle))

static func living_player(body: Node) -> bool:
	return is_instance_valid(body) and body.is_in_group("player") and GameState.hp > 0 and body.get("_is_defeated") != true

func clear_sight(body: Node3D) -> bool:
	var origin := global_position + Vector3.UP * 0.7
	var motion := body.global_position + Vector3.UP * 0.7 - origin
	return ProjectileSweep.environment_fraction(get_world_3d().direct_space_state, origin, motion, 0.05) < 0.0

func nearby_player(radius: float) -> Node3D:
	for body in get_tree().get_nodes_in_group("player"):
		if living_player(body) and in_cone(to_local(body.global_position), radius) and clear_sight(body): return body
	return null

func save_hazard() -> Dictionary:
	return {"timer": timer}

func restore_hazard(record: Dictionary) -> void:
	timer = float(record.get("timer", 0.0))

func pulse_warning() -> void:
	if model: model.scale = Vector3.ONE * (1.0 + 0.04 * sin(_time * 22.0))

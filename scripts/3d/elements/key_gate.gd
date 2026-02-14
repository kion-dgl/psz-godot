extends GameElement
class_name KeyGate
## Gate that requires a specific key to open.
## States: locked, open

## Key ID required to unlock this gate
@export var required_key_id: String = "default"

## Laser texture identifier (used to find the laser surface)
const LASER_TEXTURE_NAME := "o0c_1_gate"

## Laser scroll speed (offset.x, units/sec)
const LASER_SCROLL_SPEED := 0.40

## Collision body for blocking when locked
var collision_body: StaticBody3D
var _laser_material: StandardMaterial3D = null
var _prompt_label: Label3D
var _player_nearby: bool = false


func _init() -> void:
	model_path = "valley/o0c_gatet.glb"
	interactable = true
	element_state = "locked"
	collision_size = Vector3(3, 3, 1.5)


func _ready() -> void:
	super._ready()
	_setup_gate_collision()
	_setup_laser_material()
	_setup_prompt()
	# Re-apply state now that laser material and collision are set up
	# (super._ready() calls _apply_state before _setup_laser_material runs)
	_apply_state()


func _setup_gate_collision() -> void:
	collision_body = StaticBody3D.new()
	collision_body.name = "KeyGateCollision"
	collision_body.collision_layer = 1
	collision_body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, 0.3)
	shape.shape = box
	shape.position.y = 1.5
	collision_body.add_child(shape)

	add_child(collision_body)


func _setup_laser_material() -> void:
	if not model:
		return
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if std_mat.albedo_texture and LASER_TEXTURE_NAME in std_mat.albedo_texture.resource_path:
				var dup := std_mat.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(surface, dup)
				_laser_material = dup
	)


func _setup_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.text = "[E] Unlock"
	_prompt_label.font_size = 28
	_prompt_label.pixel_size = 0.01
	_prompt_label.position = Vector3(0, 3.0, 0)
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.modulate = Color(1.0, 0.4, 0.4)
	_prompt_label.outline_size = 8
	_prompt_label.outline_modulate = Color(0, 0, 0)
	_prompt_label.visible = false
	add_child(_prompt_label)


func _update_animation(delta: float) -> void:
	if _laser_material:
		_laser_material.uv1_offset.x -= LASER_SCROLL_SPEED * delta


func _apply_state() -> void:
	if _laser_material:
		match element_state:
			"locked":
				_laser_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				_laser_material.albedo_color.a = 1.0
			"open":
				_laser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_laser_material.albedo_color.a = 0.0

	if collision_body:
		match element_state:
			"locked":
				collision_body.collision_layer = 1
			"open":
				collision_body.collision_layer = 0

	if _prompt_label:
		if element_state == "open":
			_prompt_label.visible = false


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		_player_nearby = true
		if element_state == "locked":
			_prompt_label.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		_player_nearby = false
		_prompt_label.visible = false


func _on_interact(_player: Node3D) -> void:
	if element_state == "open":
		return

	if Inventory.has_item(required_key_id):
		Inventory.remove_item(required_key_id, 1)
		open()
	else:
		print("[KeyGate] Requires key: ", required_key_id)


## Open the gate
func open() -> void:
	set_state("open")
	print("[KeyGate] Opened with key: ", required_key_id)


## Lock the gate
func lock() -> void:
	set_state("locked")

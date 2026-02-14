extends GameElement
class_name KeyPickup
## Pickup item that unlocks key-gates. Floats and rotates when available.
## Press E to pick up. States: available, collected

## Unique ID for this key (used to track which keys are collected)
@export var key_id: String = "default"

## Spin speed (radians per second)
const SPIN_SPEED: float = 2.0

## Bob amplitude and speed
const BOB_AMPLITUDE: float = 0.1
const BOB_SPEED: float = 3.0

var _base_y: float = 0.0
var _prompt_label: Label3D
var _player_nearby: bool = false


func _init() -> void:
	model_path = "valley/o0c_key.glb"
	interactable = true
	auto_collect = false
	collision_size = Vector3(2.5, 2.5, 2.5)
	element_state = "available"


func _ready() -> void:
	super._ready()
	_base_y = position.y
	_setup_prompt()


func _setup_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.text = "[E] Pick up"
	_prompt_label.font_size = 28
	_prompt_label.pixel_size = 0.01
	_prompt_label.position = Vector3(0, 2.0, 0)
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.modulate = Color(1.0, 0.4, 0.4)
	_prompt_label.outline_size = 8
	_prompt_label.outline_modulate = Color(0, 0, 0)
	_prompt_label.visible = false
	add_child(_prompt_label)


func _update_animation(delta: float) -> void:
	if element_state != "available" or not model:
		return

	# Spin
	model.rotation.y += SPIN_SPEED * delta

	# Bob up and down
	position.y = _base_y + sin(_time * BOB_SPEED) * BOB_AMPLITUDE


func _apply_state() -> void:
	match element_state:
		"available":
			set_element_visible(true)
			set_process(true)
		"collected":
			set_element_visible(false)
			set_process(false)
			if _prompt_label:
				_prompt_label.visible = false


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		_player_nearby = true
		if element_state == "available":
			_prompt_label.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		_player_nearby = false
		_prompt_label.visible = false


func _on_interact(_player: Node3D) -> void:
	if element_state != "available":
		return

	set_state("collected")

	# Add to inventory
	var item_to_add = key_id if key_id != "default" else "key_valley"
	if Inventory.add_item(item_to_add, 1):
		print("[Key] Collected key: ", item_to_add)
	else:
		print("[Key] Failed to add key to inventory: ", item_to_add)

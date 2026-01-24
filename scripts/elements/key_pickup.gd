extends GameElement
class_name KeyPickup
## Pickup item that unlocks key-gates. Floats and rotates when available.
## States: available, collected

## Unique ID for this key (used to track which keys are collected)
@export var key_id: String = "default"

## Spin speed (radians per second)
const SPIN_SPEED: float = 2.0

## Bob amplitude and speed
const BOB_AMPLITUDE: float = 0.1
const BOB_SPEED: float = 3.0

var _base_y: float = 0.0


func _init() -> void:
	model_path = "valley/o0c_key.glb"
	auto_collect = true
	collision_size = Vector3(1.5, 1.5, 1.5)
	element_state = "available"


func _ready() -> void:
	super._ready()
	_base_y = position.y


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


func _on_collected(player: Node3D) -> void:
	if element_state == "collected":
		return

	set_state("collected")
	print("[Key] Collected key: ", key_id)

	# TODO: Add to player inventory / game state
	# GameState.add_key(key_id)

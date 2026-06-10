extends GameElement
class_name KeyPickup
## Pickup item that unlocks key-gates. Floats and rotates when available.
## Press E to pick up. States: available, collected

## Unique ID for this key (used to track which keys are collected)
@export var key_id: String = "default"

## Spin speed (radians per second)
const SPIN_SPEED: float = 2.0

var _prompt_label: Label3D
var _player_nearby: bool = false
var _collected: bool = false


func _init() -> void:
	model_path = "valley/o0c_key.glb"
	interactable = true
	auto_collect = false
	collision_size = Vector3(2.5, 2.5, 2.5)
	element_state = "available"


func _ready() -> void:
	super._ready()
	_setup_prompt()


func _setup_prompt() -> void:
	_prompt_label = _build_prompt_label("Pick up", Color(1.0, 0.4, 0.4), 2.0)
	add_child(_prompt_label)


func _update_animation(delta: float) -> void:
	if element_state != "available" or not model:
		return

	# Spin
	model.rotation.y += SPIN_SPEED * delta


func _apply_state() -> void:
	match element_state:
		"available":
			visible = true
			set_process(true)
			interactable = true
		"collected":
			visible = false
			set_process(false)
			interactable = false
			if interaction_area:
				interaction_area.monitoring = false
				interaction_area.monitorable = false
			if _prompt_label:
				_prompt_label.visible = false
			queue_free()


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
	if _collected or element_state != "available":
		return
	_collected = true
	interactable = false

	SfxManager.play("res://assets/sfx/ui/item_pickup.wav")
	set_state("collected")

	# Store as quest key (separate from main inventory)
	var item_to_add = key_id if key_id != "default" else "key_valley"
	Inventory.add_key(item_to_add)

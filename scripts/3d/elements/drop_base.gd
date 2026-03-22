extends GameElement
class_name DropBase
## Base class for drop items (meseta, weapons, armor, items).
## Non-meseta drops require pressing E to pick up and show a name label.
## States: available, collected

## Amount of meseta (for meseta drops) or item quantity
@export var amount: int = 1

## Item ID that references an ItemData resource in ItemRegistry
@export var item_id: String = ""

## Spin speed (radians per second)
const SPIN_SPEED: float = 2.0

var _prompt_label: Label3D
var _player_nearby: bool = false


func _init() -> void:
	interactable = true
	auto_collect = false
	collision_size = Vector3(1.5, 1.5, 1.5)
	element_state = "available"


func _ready() -> void:
	super._ready()
	_setup_prompt()


func _setup_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.text = _get_display_name()
	_prompt_label.font_size = 24
	_prompt_label.pixel_size = 0.01
	_prompt_label.position = Vector3(0, 1.2, 0)
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.modulate = Color(0.4, 1.0, 0.6)
	_prompt_label.outline_size = 8
	_prompt_label.outline_modulate = Color(0, 0, 0)
	_prompt_label.visible = false
	add_child(_prompt_label)


## Override in subclasses to provide a display name for the prompt label.
func _get_display_name() -> String:
	return item_id


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
				interaction_area.set_deferred("monitoring", false)
				interaction_area.set_deferred("monitorable", false)
			if _prompt_label:
				_prompt_label.visible = false
			queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		if auto_collect:
			_collect(body)
			return
		_player_nearby = true
		if element_state == "available" and _prompt_label:
			_prompt_label.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		_player_nearby = false
		if _prompt_label:
			_prompt_label.visible = false


func _on_interact(_player: Node3D) -> void:
	if element_state != "available":
		return

	set_state("collected")
	_give_reward()


func _on_collected(_player: Node3D) -> void:
	if element_state == "collected":
		return

	set_state("collected")
	_give_reward()


## Override to give the appropriate reward
func _give_reward() -> void:
	pass

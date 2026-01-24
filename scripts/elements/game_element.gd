extends Node3D
class_name GameElement
## Base class for interactive game elements (gates, switches, pickups, etc.)
## Ported from psz-sketch element patterns

signal state_changed(old_state: String, new_state: String)
signal interacted(player: Node3D)
signal collected(element: GameElement)

## Current state of the element
@export var element_state: String = "default"

## Whether this element can be interacted with by pressing E
@export var interactable: bool = false

## Whether this element auto-collects when player touches it
@export var auto_collect: bool = false

## Model GLB path (relative to assets/objects/)
@export var model_path: String = ""

## Collision size for interaction/collection detection
@export var collision_size: Vector3 = Vector3(1, 1, 1)

# Internal references
var model: Node3D
var interaction_area: Area3D
var _time: float = 0.0


func _ready() -> void:
	_load_model()
	_setup_collision()
	_apply_state()


func _process(delta: float) -> void:
	_time += delta
	_update_animation(delta)


## Override to load the element's model
func _load_model() -> void:
	if model_path.is_empty():
		return

	var full_path := "res://assets/objects/" + model_path
	var packed := load(full_path) as PackedScene
	if not packed:
		push_warning("GameElement: Failed to load model: " + full_path)
		return

	model = packed.instantiate()
	add_child(model)


## Set up collision area for interaction/collection
func _setup_collision() -> void:
	if not interactable and not auto_collect:
		return

	interaction_area = Area3D.new()
	interaction_area.name = "InteractionArea"
	interaction_area.collision_layer = 4  # Triggers layer (layer 3)
	interaction_area.collision_mask = 2  # Player layer

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	interaction_area.add_child(shape)

	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

	add_child(interaction_area)


## Override to apply visual changes based on state
func _apply_state() -> void:
	pass


## Override for per-frame animation updates (spin, bob, etc.)
func _update_animation(_delta: float) -> void:
	pass


## Change the element's state
func set_state(new_state: String) -> void:
	if new_state == element_state:
		return

	var old_state := element_state
	element_state = new_state
	_apply_state()
	state_changed.emit(old_state, new_state)


## Called when player interacts with this element (E key)
func interact(player: Node3D) -> void:
	if not interactable:
		return
	interacted.emit(player)
	_on_interact(player)


## Override to handle interaction
func _on_interact(_player: Node3D) -> void:
	pass


## Called when player enters the element's area
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		if auto_collect:
			_collect(body)


func _on_body_exited(_body: Node3D) -> void:
	pass


## Collect/pickup this element
func _collect(player: Node3D) -> void:
	collected.emit(self)
	_on_collected(player)


## Override to handle collection
func _on_collected(_player: Node3D) -> void:
	pass


## Utility: Find a mesh by name in the model
func find_mesh_by_name(mesh_name: String) -> MeshInstance3D:
	if not model:
		return null
	return _find_mesh_recursive(model, mesh_name)


func _find_mesh_recursive(node: Node, mesh_name: String) -> MeshInstance3D:
	if node.name == mesh_name and node is MeshInstance3D:
		return node as MeshInstance3D

	for child in node.get_children():
		var found := _find_mesh_recursive(child, mesh_name)
		if found:
			return found

	return null


## Utility: Apply material properties to all meshes
func apply_to_all_materials(callback: Callable) -> void:
	if not model:
		return
	_apply_materials_recursive(model, callback)


func _apply_materials_recursive(node: Node, callback: Callable) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat:
				callback.call(mat, mesh_inst, i)

	for child in node.get_children():
		_apply_materials_recursive(child, callback)


## Utility: Set visibility of a specific mesh
func set_mesh_visible(mesh_name: String, is_visible: bool) -> void:
	var mesh := find_mesh_by_name(mesh_name)
	if mesh:
		mesh.visible = is_visible


## Utility: Set overall visibility (hides when collected)
func set_element_visible(is_visible: bool) -> void:
	if model:
		model.visible = is_visible

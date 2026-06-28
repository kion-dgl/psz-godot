extends Node3D
class_name GameElement
## Base class for interactive game elements (gates, switches, pickups, etc.)
## Ported from psz-sketch element patterns

const MIRROR_SHADER := preload("res://scripts/3d/shaders/mirror_repeat.gdshader")

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


## Build + attach a StaticBody3D environment collider sized to collision_size,
## and return it. Shared by wall/box/fence/enemy_spawn, whose per-subclass
## setups were byte-identical except the node name (#294 dedup).
func _build_static_collision(body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1  # Environment layer
	body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2
	body.add_child(shape)

	add_child(body)
	return body


## Build a billboarded, hidden interaction-prompt Label3D (e.g. "Pick up",
## "Unlock", "Read"). Shared by the element subclasses' `_setup_prompt` — they
## differ only in text/color/height (#294). Caller adds it to the tree and keeps
## the reference; the label starts invisible.
func _build_prompt_label(text: String, modulate_color: Color, y_offset: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 28
	label.pixel_size = 0.01
	label.position = Vector3(0, y_offset, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = modulate_color
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0)
	label.visible = false
	return label


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


## Duplicate every StandardMaterial3D as a per-instance override with
## nearest filtering, split into {"feature": …, "base": …} by whether the
## albedo texture path contains `feature_tex`. Shared by the trap elements
## (bear prongs / needle spikes, #215-C2); last non-matching surface wins
## the "base" slot, matching the original per-trap behavior.
func _setup_split_materials(feature_tex: String) -> Dictionary:
	var result := {"feature": null, "base": null}
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int) -> void:
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			var dup := std_mat.duplicate() as StandardMaterial3D
			dup.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			# NO `albedo_texture.flags_mirrored_repeat = true` here: that was a
			# Godot-3 Texture flag that DOESN'T EXIST in Godot 4. The assignment
			# threw `Invalid assignment of property 'flags_mirrored_repeat'` at
			# runtime, aborting THIS callback before the override below — so
			# feature/base came back null and bear_trap/needle_trap silently lost
			# their scroll/alpha materials (prongs never hid, laser never scrolled).
			# MirroredRepeatWrapping must be emulated with the UV-fold shader
			# instead (mirror_repeat.gdshader / _setup_mirror_textures); these trap
			# surfaces don't tile past [0,1], so plain repeat is correct here.
			# See /engineering/mirrored-repeat-wrapping (#381).
			mesh.set_surface_override_material(surface, dup)
			if std_mat.albedo_texture and feature_tex in std_mat.albedo_texture.resource_path:
				result["feature"] = dup
			else:
				result["base"] = dup
	)
	return result


## Build the glowing translucent warp cylinder (telepipe / warp point —
## identical but for tint and node name, #215-C3). Returns the mesh,
## already positioned and added as a child.
func _build_warp_cylinder(tint: Color, mesh_name: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.8
	cyl.bottom_radius = 0.8
	cyl.height = 3.0
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	mesh.name = mesh_name
	mesh.position.y = 1.5
	add_child(mesh)
	return mesh


## Replace every albedo-textured StandardMaterial3D on the model with the
## mirror-repeat shader (2x2 UV, mirrored both axes). `uv_offset` shifts the
## palette row — Box passes (0, 1) for rare variants. Shared by the
## destructible elements — wall, box (#294).
func _setup_mirror_textures(uv_offset := Vector2.ZERO) -> void:
	if not model:
		return
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if std_mat.albedo_texture:
				var smat := ShaderMaterial.new()
				smat.shader = MIRROR_SHADER
				smat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
				smat.set_shader_parameter("uv_scale", Vector2(2, 2))
				smat.set_shader_parameter("mirror_x", true)
				smat.set_shader_parameter("mirror_y", true)
				if uv_offset != Vector2.ZERO:
					smat.set_shader_parameter("uv_offset", uv_offset)
				mesh.set_surface_override_material(surface, smat)
	)


## Find the surface whose albedo texture path contains `texture_name`, duplicate
## that StandardMaterial3D as a per-surface override (so per-instance scroll
## animation doesn't mutate the shared mesh material) and return the duplicate.
## Returns null when `model` is unset or no surface matches. Shared by the
## scrolling-texture elements — gate/key_gate laser, message_pack scroll (#294).
func _override_textured_material(texture_name: String) -> StandardMaterial3D:
	var found: Array[StandardMaterial3D] = []
	apply_to_all_materials(func(mat: Material, mesh: MeshInstance3D, surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			if std_mat.albedo_texture and texture_name in std_mat.albedo_texture.resource_path:
				var dup := std_mat.duplicate() as StandardMaterial3D
				mesh.set_surface_override_material(surface, dup)
				found.append(dup)
	)
	return found.back() if not found.is_empty() else null


## Utility: Set overall visibility (hides when collected)
func set_element_visible(visible_state: bool) -> void:
	if model:
		model.visible = visible_state

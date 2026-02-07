extends CharacterBody3D
## Player controller - handles movement, rotation, and animation states
## Ported from psz-sketch PlayerMovementDemo.tsx

# Movement settings
const MOVE_SPEED: float = 6.0
const ROTATE_SPEED: float = 5.0
const GRAVITY: float = 20.0
const FALL_RESPAWN_Y: float = -10.0  # Respawn if player falls below this

# Spawn tracking
var spawn_position: Vector3 = Vector3.ZERO

# Player state machine
enum PlayerState {
	IDLE,
	RUNNING,
	ATTACKING,
	DODGING,
	DAMAGED,
	DOWN,
	STUNNED
}

# Animation name mapping (from R3F ANIMATION_MAP)
const ANIMATION_MAP: Dictionary = {
	"pmsa_wait": "wait",
	"pmsa_run": "run",
	"pmsa_esc_f": "dodge",
	"pmsa_atk1": "atk1",
	"pmsa_atk2": "atk2",
	"pmsa_atk3": "atk3",
	"pmsa_dam_n": "dam_n",
	"pmsa_dam_h": "dam_h",
	"pmsa_dam_d": "dam_d",
	"pmsa_tec": "tec",
}

# Asset paths
const TEXTURE_PATH := "res://assets/player/pc_000/textures/pc_000_000.png"

# Node references
@onready var model: Node3D = $PlayerModel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

# Floor detection (raycast-based)
const FLOOR_CHECK_DISTANCE: float = 1.0  # How far ahead to check for floor
const FLOOR_CHECK_SIDE: float = 0.5  # Side offset for corner checks
const FLOOR_RAY_LENGTH: float = 5.0  # How far down to raycast

# Animation references (found at runtime)
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var weapon_node: Node3D  # Attached weapon model

# Weapon attachment config
const WEAPON_BONE_NAME: String = "070_RArm02"  # Right arm segment 2 (hand)
var weapon_scene: PackedScene = preload("res://assets/weapons/saber/saber.glb")

# State tracking
var current_state: PlayerState = PlayerState.IDLE
var player_rotation: float = 0.0

# Combo system
var combo_state: int = 0  # 0 = not attacking, 1-3 = combo step
var combo_window_open: bool = false
var combo_timer: float = 0.0
const COMBO_WINDOW_DURATION: float = 0.5

# Dodge tracking
var dodge_direction: float = 0.0
var dodge_timer: float = 0.0
const DODGE_DURATION: float = 0.8
const DODGE_SPEED: float = 5.0

# Interaction system
var interaction_area: Area3D
var nearby_elements: Array = []  # Array of GameElement nodes
var nearest_interactable: Node3D = null  # GameElement or null
const INTERACTION_RADIUS: float = 2.0

# Combat system
var attack_hitbox: Hitbox
const ATTACK_HITBOX_SIZE := Vector3(1.5, 1.0, 2.0)  # Width, height, depth
const ATTACK_HITBOX_OFFSET := 1.5  # Forward offset from player

# Signals
signal state_changed(new_state: PlayerState)
signal interacted_with(element: Node3D)


func _ready() -> void:
	# Set up interaction detection area
	_setup_interaction_area()
	# Set up attack hitbox
	_setup_attack_hitbox()
	# Store spawn position for respawn
	spawn_position = global_position

	# Apply texture to player model
	_apply_player_texture()

	# Set up animations
	_setup_animations()

	# Set up weapon attachment
	_setup_weapon()

	# Initialize animation player if we have one
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)

	# Start in idle state
	transition_to(PlayerState.IDLE)


func _setup_animations() -> void:
	# Find the skeleton in the model
	var model_node := $PlayerModel/Model
	skeleton = _find_node_of_type(model_node, "Skeleton3D") as Skeleton3D

	# Find the AnimationPlayer in the Animations node
	var anims_node := $PlayerModel/Animations
	var source_anim_player: AnimationPlayer
	if anims_node:
		source_anim_player = _find_node_of_type(anims_node, "AnimationPlayer") as AnimationPlayer

	if not source_anim_player or not skeleton:
		push_warning("Could not set up animations - skeleton: %s, anim_player: %s" % [skeleton != null, source_anim_player != null])
		return

	# Add AnimationPlayer as sibling to skeleton (under skeleton's parent)
	var skeleton_parent := skeleton.get_parent()
	animation_player = AnimationPlayer.new()
	animation_player.name = "PlayerAnimationPlayer"
	skeleton_parent.add_child(animation_player)

	# Animations that should loop
	var looping_anims := ["pmsa_wait", "pmsa_run", "pmsa_stp_fb", "pmsa_stp_lr"]

	# Copy and remap each animation - skeleton is now a sibling
	var lib := AnimationLibrary.new()
	for anim_name in source_anim_player.get_animation_list():
		var source_anim := source_anim_player.get_animation(anim_name)
		var new_anim := _remap_animation(source_anim, skeleton.name)

		# Set loop mode for looping animations
		if anim_name in looping_anims or anim_name.ends_with("_lp"):
			new_anim.loop_mode = Animation.LOOP_LINEAR

		lib.add_animation(anim_name, new_anim)

	animation_player.add_animation_library("", lib)


func _setup_weapon() -> void:
	if not skeleton:
		push_warning("[Player] No skeleton found, cannot attach weapon")
		return

	# Find the weapon bone
	var bone_idx := skeleton.find_bone(WEAPON_BONE_NAME)
	if bone_idx == -1:
		# Try alternative bone names
		for alt_name in ["R_Hand", "RightHand", "hand_R", "Wrist_R"]:
			bone_idx = skeleton.find_bone(alt_name)
			if bone_idx != -1:
				break

	if bone_idx == -1:
		push_warning("[Player] Could not find weapon bone. Available bones: %s" % _get_bone_names())
		return

	# Create BoneAttachment3D
	var bone_attachment := BoneAttachment3D.new()
	bone_attachment.name = "WeaponAttachment"
	bone_attachment.bone_name = skeleton.get_bone_name(bone_idx)
	skeleton.add_child(bone_attachment)

	# Instance and attach weapon
	if weapon_scene:
		weapon_node = weapon_scene.instantiate() as Node3D
		bone_attachment.add_child(weapon_node)
		# Adjust weapon position/rotation as needed
		weapon_node.rotation_degrees = Vector3(0, 90, 0)  # Rotate to align with hand
		weapon_node.scale = Vector3(1.5, 1.5, 1.5)  # Scale up if needed
		print("[Player] Weapon attached to bone: ", bone_attachment.bone_name)


func _get_bone_names() -> Array[String]:
	var names: Array[String] = []
	if skeleton:
		for i in range(skeleton.get_bone_count()):
			names.append(skeleton.get_bone_name(i))
	return names


func _remap_animation(source: Animation, skeleton_name: String) -> Animation:
	var anim := source.duplicate() as Animation

	# Remap each track to point to the correct skeleton
	for i in range(anim.get_track_count()):
		var track_path := anim.track_get_path(i)
		var path_str := String(track_path)

		# Original path format: "pc_000_000/Skeleton3D:BoneName" or "pc_000_000/Skeleton3D::blend_shapes/shape"
		# We need: "{skeleton_name}:BoneName" (relative to animation player)
		if "Skeleton3D" in path_str:
			# Extract the property part after Skeleton3D
			var skel_idx := path_str.find("Skeleton3D")
			if skel_idx >= 0:
				var prop_part := path_str.substr(skel_idx + 10)  # After "Skeleton3D"
				var new_path := skeleton_name + prop_part
				anim.track_set_path(i, NodePath(new_path))

	return anim


func _find_node_of_type(root: Node, type_name: String) -> Node:
	if root.get_class() == type_name:
		return root

	for child in root.get_children():
		var found := _find_node_of_type(child, type_name)
		if found:
			return found

	return null


func _apply_player_texture() -> void:
	# Load texture
	var texture := load(TEXTURE_PATH) as Texture2D
	if not texture:
		push_warning("Failed to load player texture: " + TEXTURE_PATH)
		return

	# Apply texture to existing materials (preserves normals and mesh properties)
	_apply_texture_to_materials(model, texture)


func _apply_texture_to_materials(node: Node, texture: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh:
			for surface_idx in range(mesh.get_surface_count()):
				var mat := mesh_instance.get_active_material(surface_idx)
				if mat is StandardMaterial3D:
					# Duplicate to avoid modifying shared resource
					var new_mat := mat.duplicate() as StandardMaterial3D
					new_mat.albedo_texture = texture
					new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mesh_instance.set_surface_override_material(surface_idx, new_mat)
				elif mat == null:
					# No material, create one
					var new_mat := StandardMaterial3D.new()
					new_mat.albedo_texture = texture
					new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					mesh_instance.set_surface_override_material(surface_idx, new_mat)

	for child in node.get_children():
		_apply_texture_to_materials(child, texture)


func _physics_process(delta: float) -> void:
	# Check for fall and respawn
	if global_position.y < FALL_RESPAWN_Y:
		_respawn()
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Handle state-specific logic
	match current_state:
		PlayerState.IDLE, PlayerState.RUNNING:
			_handle_movement(delta)
		PlayerState.DODGING:
			_handle_dodge(delta)
		PlayerState.ATTACKING:
			_handle_attack_state(delta)
		PlayerState.DAMAGED:
			_handle_damaged(delta)

	# Apply movement
	move_and_slide()

	# Update model rotation
	if model:
		model.rotation.y = player_rotation


func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	player_rotation = 0.0
	if model:
		model.rotation.y = 0.0
	transition_to(PlayerState.IDLE)


func _unhandled_input(event: InputEvent) -> void:
	# Handle dodge input
	if event.is_action_pressed("dodge"):
		if current_state != PlayerState.DODGING and current_state != PlayerState.ATTACKING:
			_start_dodge()

	# Handle attack input
	if event.is_action_pressed("attack"):
		_start_attack()

	# Handle interact input
	if event.is_action_pressed("interact"):
		_try_interact()


func _handle_movement(delta: float) -> void:
	# Get input direction
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		input_dir.y -= 1
	if Input.is_action_pressed("move_backward"):
		input_dir.y += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1

	var is_moving := input_dir.length_squared() > 0

	if is_moving:
		# Normalize input
		input_dir = input_dir.normalized()

		# Calculate target rotation from input
		var target_rotation := atan2(input_dir.x, input_dir.y)

		# Smoothly rotate toward target
		var rot_diff := target_rotation - player_rotation
		# Normalize angle difference to -PI to PI
		while rot_diff > PI:
			rot_diff -= TAU
		while rot_diff < -PI:
			rot_diff += TAU
		player_rotation += rot_diff * ROTATE_SPEED * delta

		# Calculate desired movement
		var move_dir := Vector3(sin(player_rotation), 0, cos(player_rotation))
		var desired_velocity := move_dir * MOVE_SPEED

		# Check if movement would stay on floor using raycasts
		# Check three points: center, left, and right of movement direction
		if _can_move_to(move_dir):
			velocity.x = desired_velocity.x
			velocity.z = desired_velocity.z
		else:
			# No floor ahead, stop at edge
			velocity.x = 0
			velocity.z = 0

		# Switch to running state if idle
		if current_state == PlayerState.IDLE:
			transition_to(PlayerState.RUNNING)
	else:
		# Stop horizontal movement
		velocity.x = 0
		velocity.z = 0

		# Switch to idle if running
		if current_state == PlayerState.RUNNING:
			transition_to(PlayerState.IDLE)


func _can_move_to(move_dir: Vector3) -> bool:
	# Check multiple points to prevent walking off edges at any angle
	# This ensures consistent edge detection regardless of approach angle
	var center := global_position + move_dir * FLOOR_CHECK_DISTANCE

	# Calculate perpendicular direction for side checks
	var side_dir := Vector3(-move_dir.z, 0, move_dir.x)  # 90 degree rotation
	var left := center + side_dir * FLOOR_CHECK_SIDE
	var right := center - side_dir * FLOOR_CHECK_SIDE

	# All three points must have floor
	return _has_floor_at(center) and _has_floor_at(left) and _has_floor_at(right)


func _has_floor_at(check_pos: Vector3) -> bool:
	# Cast a ray downward from check_pos to see if there's floor
	var space_state := get_world_3d().direct_space_state
	var ray_origin := Vector3(check_pos.x, global_position.y + 1.0, check_pos.z)
	var ray_end := Vector3(check_pos.x, global_position.y - FLOOR_RAY_LENGTH, check_pos.z)

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1  # Environment layer
	query.exclude = [self]

	var result := space_state.intersect_ray(query)
	return not result.is_empty()


func _start_dodge() -> void:
	# Store facing direction for dodge movement
	dodge_direction = player_rotation
	dodge_timer = 0.0
	transition_to(PlayerState.DODGING)


func _handle_dodge(delta: float) -> void:
	dodge_timer += delta

	if dodge_timer >= DODGE_DURATION:
		transition_to(PlayerState.IDLE)
		return

	# Move in the direction player was facing when dodge started
	var dodge_dir := Vector3(sin(dodge_direction), 0, cos(dodge_direction))

	# Check floor ahead - stop at edges to prevent dodging off
	if _can_move_to(dodge_dir):
		velocity.x = dodge_dir.x * DODGE_SPEED
		velocity.z = dodge_dir.z * DODGE_SPEED
	else:
		velocity.x = 0
		velocity.z = 0


func _start_attack() -> void:
	if current_state == PlayerState.ATTACKING:
		# Check if we're in combo window
		if combo_window_open and combo_state < 3:
			combo_state += 1
			combo_window_open = false
			_play_attack_animation(combo_state)
		return

	# Start fresh attack combo
	combo_state = 1
	combo_window_open = false
	transition_to(PlayerState.ATTACKING)
	_play_attack_animation(combo_state)


func _handle_attack_state(delta: float) -> void:
	# Handle combo window timeout
	if combo_window_open:
		combo_timer += delta
		if combo_timer >= COMBO_WINDOW_DURATION:
			# Combo window closed, return to idle
			combo_window_open = false
			combo_state = 0
			_deactivate_attack_hitbox()
			transition_to(PlayerState.IDLE)

	# Stop horizontal movement during attacks
	velocity.x = 0
	velocity.z = 0


func _handle_damaged(_delta: float) -> void:
	# Check floor during knockback - stop at edges to prevent falling off
	if velocity.length_squared() > 0.1:
		var move_dir := velocity.normalized()
		move_dir.y = 0
		if move_dir.length() > 0.1 and not _can_move_to(move_dir):
			velocity.x = 0
			velocity.z = 0


func _play_attack_animation(attack_num: int) -> void:
	var anim_name := "pmsa_atk" + str(attack_num)
	play_animation(anim_name, false)
	_activate_attack_hitbox()


func transition_to(new_state: PlayerState) -> void:
	current_state = new_state
	state_changed.emit(new_state)

	match new_state:
		PlayerState.IDLE:
			play_animation("pmsa_wait", true)
		PlayerState.RUNNING:
			play_animation("pmsa_run", true)
		PlayerState.DODGING:
			play_animation("pmsa_esc_f", false)
		PlayerState.DAMAGED:
			play_animation("pmsa_dam_n", false)


func play_animation(anim_name: String, _loop: bool = true) -> void:
	if animation_player and animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
		# Note: Animation looping is typically set in the animation resource itself


func _on_animation_finished(_anim_name: String) -> void:
	match current_state:
		PlayerState.DODGING:
			transition_to(PlayerState.IDLE)
		PlayerState.ATTACKING:
			_deactivate_attack_hitbox()
			if combo_state >= 3:
				# Combo finished, return to idle
				combo_state = 0
				transition_to(PlayerState.IDLE)
			else:
				# Open combo window
				combo_window_open = true
				combo_timer = 0.0
		PlayerState.DAMAGED:
			transition_to(PlayerState.IDLE)


# Public API for external systems
func take_damage(damage: int, knockback: Vector3 = Vector3.ZERO) -> void:
	GameState.set_hp(GameState.hp - damage)

	# Apply knockback
	if knockback.length() > 0:
		velocity = knockback

	# Play damage animation (heavy if damage > 20)
	if damage > 20:
		play_animation("pmsa_dam_h", false)
	else:
		play_animation("pmsa_dam_n", false)
	transition_to(PlayerState.DAMAGED)


func get_state() -> PlayerState:
	return current_state


func get_combo_state() -> int:
	return combo_state


# Combat System
func _setup_attack_hitbox() -> void:
	attack_hitbox = Hitbox.new()
	attack_hitbox.name = "AttackHitbox"
	attack_hitbox.owner_node = self
	attack_hitbox.damage = _get_attack_damage()

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = ATTACK_HITBOX_SIZE
	shape.shape = box
	shape.position = Vector3(0, ATTACK_HITBOX_SIZE.y / 2, ATTACK_HITBOX_OFFSET)
	attack_hitbox.add_child(shape)

	# Hitbox follows player rotation via model
	model.add_child(attack_hitbox)


func _get_attack_damage() -> int:
	# TODO: Implement proper damage calculation when combat is ready
	# For now, use fixed damage while working on timing/animations
	return 10


func _activate_attack_hitbox() -> void:
	if attack_hitbox:
		attack_hitbox.damage = _get_attack_damage()
		attack_hitbox.activate()


func _deactivate_attack_hitbox() -> void:
	if attack_hitbox:
		attack_hitbox.deactivate()


# Interaction System
func _setup_interaction_area() -> void:
	interaction_area = Area3D.new()
	interaction_area.name = "InteractionArea"
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 4  # Triggers layer (layer 3)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = INTERACTION_RADIUS
	shape.shape = sphere
	interaction_area.add_child(shape)

	interaction_area.area_entered.connect(_on_interaction_area_entered)
	interaction_area.area_exited.connect(_on_interaction_area_exited)

	add_child(interaction_area)


func _on_interaction_area_entered(area: Area3D) -> void:
	var element := _get_element_from_area(area)
	if element and element not in nearby_elements:
		nearby_elements.append(element)
		_update_nearest_interactable()


func _on_interaction_area_exited(area: Area3D) -> void:
	var element := _get_element_from_area(area)
	if element:
		nearby_elements.erase(element)
		_update_nearest_interactable()


func _get_element_from_area(area: Area3D) -> Node3D:
	# Check if the area's parent is a GameElement (has interact method)
	var parent := area.get_parent()
	if parent and parent.has_method("interact"):
		return parent as Node3D
	return null


func _update_nearest_interactable() -> void:
	nearest_interactable = null
	var closest_dist := INF

	for element in nearby_elements:
		if not is_instance_valid(element):
			continue
		if not element.get("interactable"):
			continue

		var dist := global_position.distance_to(element.global_position)
		if dist < closest_dist:
			closest_dist = dist
			nearest_interactable = element


func _try_interact() -> void:
	if nearest_interactable and is_instance_valid(nearest_interactable):
		nearest_interactable.interact(self)
		interacted_with.emit(nearest_interactable)
		print("[Player] Interacted with: ", nearest_interactable.name)


func get_nearest_interactable() -> Node3D:
	return nearest_interactable

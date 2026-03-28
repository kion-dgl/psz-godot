extends CharacterBody3D
## Player controller - handles movement, rotation, and animation states
## Ported from psz-sketch PlayerMovementDemo.tsx

# Movement settings
const MOVE_SPEED: float = 6.0
const SPRINT_SPEED: float = 8.0
const WALK_SPEED: float = 2.5
const WALK_TO_RUN_DELAY: float = 1.2
const ROTATE_SPEED: float = 5.0
const GRAVITY: float = 20.0
const FALL_RESPAWN_Y: float = -10.0  # Respawn if player falls below this

# Spawn tracking
var spawn_position: Vector3 = Vector3.ZERO

# Player state machine
enum PlayerState {
	IDLE,
	WALKING,
	RUNNING,
	SPRINTING,
	ATTACKING,
	DODGING,
	DAMAGED,
	DOWN,
	STUNNED,
	CUTSCENE
}

# Weapon type → animation GLB path and prefix (male / female)
const WEAPON_ANIM_DATA: Dictionary = {
	WeaponData.WeaponType.SABER: {"glb_m": "res://assets/player/animations/saver_m.glb", "glb_w": "res://assets/player/animations/saver_w.glb", "prefix_m": "pmsa", "prefix_w": "pwsa"},
	WeaponData.WeaponType.SWORD: {"glb_m": "res://assets/player/animations/sword_m.glb", "glb_w": "res://assets/player/animations/sword_w.glb", "prefix_m": "pmsw", "prefix_w": "pwsw"},
	WeaponData.WeaponType.DAGGERS: {"glb_m": "res://assets/player/animations/dagger_m.glb", "glb_w": "res://assets/player/animations/dagger_w.glb", "prefix_m": "pmda", "prefix_w": "pwda"},
	WeaponData.WeaponType.SPEAR: {"glb_m": "res://assets/player/animations/spear_m.glb", "glb_w": "res://assets/player/animations/spear_w.glb", "prefix_m": "pmsp", "prefix_w": "pwsp"},
	WeaponData.WeaponType.SLICER: {"glb_m": "res://assets/player/animations/saver_m.glb", "glb_w": "res://assets/player/animations/saver_w.glb", "prefix_m": "pmsa", "prefix_w": "pwsa"},
	WeaponData.WeaponType.GUN_BLADE: {"glb_m": "res://assets/player/animations/shotgun_m.glb", "glb_w": "res://assets/player/animations/shotgun_w.glb", "prefix_m": "pmgb", "prefix_w": "pwgbs"},
	WeaponData.WeaponType.HANDGUN: {"glb_m": "res://assets/player/animations/handgun_m.glb", "glb_w": "res://assets/player/animations/handgun_w.glb", "prefix_m": "pmhg", "prefix_w": "pwhg"},
	WeaponData.WeaponType.MECH_GUN: {"glb_m": "res://assets/player/animations/machinegun_m.glb", "glb_w": "res://assets/player/animations/machinegun_w.glb", "prefix_m": "pmmg", "prefix_w": "pwmgs"},
	WeaponData.WeaponType.RIFLE: {"glb_m": "res://assets/player/animations/shotgun_m.glb", "glb_w": "res://assets/player/animations/shotgun_w.glb", "prefix_m": "pmri", "prefix_w": "pwri"},
	WeaponData.WeaponType.BAZOOKA: {"glb_m": "res://assets/player/animations/shotgun_m.glb", "glb_w": "res://assets/player/animations/shotgun_w.glb", "prefix_m": "pmri", "prefix_w": "pwri"},
	WeaponData.WeaponType.ROD: {"glb_m": "res://assets/player/animations/rod_m.glb", "glb_w": "res://assets/player/animations/rod_w.glb", "prefix_m": "pmro", "prefix_w": "pwro"},
	WeaponData.WeaponType.WAND: {"glb_m": "res://assets/player/animations/wand_m.glb", "glb_w": "res://assets/player/animations/wand_w.glb", "prefix_m": "pmwa", "prefix_w": "pwwa"},
}
const DEFAULT_ANIM_GLB_M := "res://assets/player/animations/saver_m.glb"
const DEFAULT_ANIM_GLB_W := "res://assets/player/animations/saver_w.glb"
const DEFAULT_ANIM_PREFIX_M := "pmsa"
const DEFAULT_ANIM_PREFIX_W := "pwsa"

# Current weapon animation prefix (changes when weapon changes)
var _anim_prefix: String = DEFAULT_ANIM_PREFIX_M

# Gender-aware walk/run/sprint animation names
var _walk_anim: String = "pmsa_walk"
var _run_anim: String = "pmsa_run_pso"
var _sprint_anim: String = ""  # Set in _load_weapon_animations; empty = use _anim_prefix + "_run"
var _is_female: bool = false

# Default asset paths (fallback when no character data)
const DEFAULT_TEXTURE_PATH := "res://assets/player/pc_000/textures/pc_000_000.png"

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
const WEAPON_BONE_NAME: String = "070_RArm02"  # Right hand
const LEFT_WEAPON_BONE_NAME: String = "040_LArm02"  # Left hand (dual-wield)

# Per-weapon-type hold orientation: idle (walking/standing) vs attack (during combo)
const WEAPON_HOLD_DEFAULT := {
	"idle": {"pos": Vector3(0.31, 0, 0), "rot": Vector3(0, 90, 0)},
	"attack": {"pos": Vector3(0.31, 0, 0), "rot": Vector3(0, 90, 0)},
}
const WEAPON_HOLD := {
	# WeaponData.WeaponType enum values as keys
	9: {  # HANDGUN
		"idle": {"pos": Vector3(0.31, 0.015, 0), "rot": Vector3(16, -8, 78)},
		"attack": {"pos": Vector3(0.31, 0.015, 0), "rot": Vector3(16, -8, 78)},
	},
	10: {  # MECH_GUN
		"idle": {"pos": Vector3(0.31, 0, 0), "rot": Vector3(8, -5, 98)},
		"attack": {"pos": Vector3(0.31, 0, 0), "rot": Vector3(8, -5, 98)},
	},
	14: {  # ROD
		"idle": {"pos": Vector3(0.31, 0, 0), "rot": Vector3(43, 90, -30)},
		"attack": {"pos": Vector3(0.31, 0, 0), "rot": Vector3(43, 90, -30)},
	},
	15: {  # WAND
		"idle": {"pos": Vector3(0.31, 0, 0), "rot": Vector3(-53, 90, 0)},
		"attack": {"pos": Vector3(0.31, 0, 0), "rot": Vector3(-53, 90, 0)},
	},
	11: {  # RIFLE
		"idle": {"pos": Vector3(0.31, 0, 0), "rot": Vector3(4, 12, 98)},
		"attack": {"pos": Vector3(0.2, 0.19, 0.1), "rot": Vector3(106, 12, 99)},
	},
	12: {  # BAZOOKA
		"idle": {"pos": Vector3(0.31, 0, 0), "rot": Vector3(4, 12, 98)},
		"attack": {"pos": Vector3(0.2, 0.19, 0.1), "rot": Vector3(106, 12, 99)},
	},
}
var weapon_node_left: Node3D  # Left-hand weapon for dual-wield

# Mag attachment config
const MAG_OFFSET := Vector3(0.0, 1.2, -0.4)  # Behind character at shoulder height
const MAG_BOB_SPEED := 0.6   # Cycles per second
const MAG_BOB_HEIGHT := 0.06  # Vertical bob amplitude
const MAG_SWAY_SPEED := 0.4  # Horizontal sway speed (slightly offset from bob)
const MAG_SWAY_AMOUNT := 0.03
var mag_node: Node3D
var _mag_time: float = 0.0

# State tracking
var current_state: PlayerState = PlayerState.IDLE
var player_rotation: float = 0.0
var walk_timer: float = 0.0

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
var _targeted_enemies: Array = []
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

	# Load character model/texture based on active character appearance
	_load_character_model()

	# Set up animations
	_setup_animations()

	# Set up weapon attachment (skip in city — no combat there)
	var in_city := _is_in_city()
	print("[Player] _ready: in_city=%s, skeleton=%s" % [in_city, skeleton != null])
	if not in_city:
		_setup_weapon()
	_setup_mag()

	# Initialize animation player if we have one
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)

	# Start in idle state
	transition_to(PlayerState.IDLE)


func _setup_animations() -> void:
	# Find the skeleton in the model
	var model_node := $PlayerModel/Model
	skeleton = _find_node_of_type(model_node, "Skeleton3D") as Skeleton3D

	# Find the AnimationPlayer in the Animations node (scene-baked saber anims)
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

	# Load animations — weapon-specific in field, default unarmed in city
	_load_weapon_animations()


func _load_weapon_animations() -> void:
	if not animation_player or not skeleton:
		return

	# Detect character gender
	_is_female = false
	var character = CharacterManager.get_active_character()
	if character:
		var class_id: String = character.get("class_id", "humar")
		var class_data = ClassRegistry.get_class_data(class_id)
		if class_data and class_data.gender == "Female":
			_is_female = true

	var gender_key := "w" if _is_female else "m"

	# In city, always use default unarmed animations
	var anim_glb := DEFAULT_ANIM_GLB_W if _is_female else DEFAULT_ANIM_GLB_M
	_anim_prefix = DEFAULT_ANIM_PREFIX_W if _is_female else DEFAULT_ANIM_PREFIX_M

	if not _is_in_city():
		var weapon_data := _get_equipped_weapon_data()
		if weapon_data and WEAPON_ANIM_DATA.has(weapon_data.weapon_type):
			var data: Dictionary = WEAPON_ANIM_DATA[weapon_data.weapon_type]
			anim_glb = str(data.get("glb_" + gender_key, anim_glb))
			_anim_prefix = str(data.get("prefix_" + gender_key, _anim_prefix))

	print("[Player] Loading animations: glb=%s, prefix=%s, female=%s" % [anim_glb, _anim_prefix, _is_female])

	# Load animation GLB (fall back to male if female GLB missing)
	if not ResourceLoader.exists(anim_glb):
		push_warning("[Player] Animation GLB not found: %s, falling back to male" % anim_glb)
		anim_glb = DEFAULT_ANIM_GLB_M
		_anim_prefix = DEFAULT_ANIM_PREFIX_M
		_is_female = false

	var packed: PackedScene = load(anim_glb) as PackedScene
	if packed == null:
		push_warning("[Player] Failed to load animation GLB: %s" % anim_glb)
		return

	var anim_scene := packed.instantiate()
	var source_player: AnimationPlayer = _find_node_of_type(anim_scene, "AnimationPlayer") as AnimationPlayer
	if not source_player:
		push_warning("[Player] No AnimationPlayer found in animation GLB: %s" % anim_glb)
		anim_scene.queue_free()
		return

	# Looping animations: weapon-specific idle/wait + shared locomotion
	var looping_suffixes := ["_wait", "_run", "_run_pso", "_walk", "_stp_fb", "_stp_lr"]

	# Build new library from the weapon animation GLB
	var lib := AnimationLibrary.new()
	for anim_name in source_player.get_animation_list():
		var source_anim := source_player.get_animation(anim_name)
		var new_anim := _remap_animation(source_anim, skeleton.name)

		# Set loop mode
		var should_loop := anim_name.ends_with("_lp")
		if not should_loop:
			for suffix in looping_suffixes:
				if anim_name.ends_with(suffix):
					should_loop = true
					break
		if should_loop:
			new_anim.loop_mode = Animation.LOOP_LINEAR

		lib.add_animation(anim_name, new_anim)

	# Also load shared PSO locomotion from the scene-baked Animations node
	var scene_anims_node := $PlayerModel/Animations
	if scene_anims_node:
		var scene_player: AnimationPlayer = _find_node_of_type(scene_anims_node, "AnimationPlayer") as AnimationPlayer
		if scene_player:
			for anim_name in ["pmsa_walk", "pmsa_run_pso"]:
				if scene_player.has_animation(anim_name) and not lib.has_animation(anim_name):
					var source_anim := scene_player.get_animation(anim_name)
					var new_anim := _remap_animation(source_anim, skeleton.name)
					new_anim.loop_mode = Animation.LOOP_LINEAR
					lib.add_animation(anim_name, new_anim)

	# Set gender-aware walk/run/sprint animation names
	if _is_female:
		_walk_anim = "pwsa_walk" if lib.has_animation("pwsa_walk") else "pmsa_walk"
		_run_anim = "pwsa_run_pso" if lib.has_animation("pwsa_run_pso") else "pmsa_run_pso"
		# Sprint uses weapon-specific run; search for best pw*_run in library
		var female_sprint := _anim_prefix + "_run"
		if not lib.has_animation(female_sprint):
			for anim_name in lib.get_animation_list():
				if anim_name.begins_with("pw") and anim_name.ends_with("_run") and not anim_name.ends_with("_run_pso"):
					female_sprint = anim_name
					break
		_sprint_anim = female_sprint
	else:
		_walk_anim = "pmsa_walk"
		_run_anim = "pmsa_run_pso"
		_sprint_anim = _anim_prefix + "_run"
	print("[Player] Walk=%s, Run=%s, Sprint=%s" % [_walk_anim, _run_anim, _sprint_anim])

	# Replace existing library
	if animation_player.has_animation_library(""):
		animation_player.remove_animation_library("")
	animation_player.add_animation_library("", lib)

	var anim_list := animation_player.get_animation_list()
	print("[Player] Loaded %d animations: %s" % [anim_list.size(), anim_list])

	anim_scene.queue_free()


## Call this after equipment changes to update the 3D weapon model.
func refresh_weapon() -> void:
	if _is_in_city():
		return
	_clear_weapon()
	_setup_weapon()
	_load_weapon_animations()
	transition_to(current_state)  # Replay current animation with new set


## Call this after mag equipment changes to update the 3D mag orb.
func refresh_mag() -> void:
	_clear_mag()
	_setup_mag()


func _clear_weapon() -> void:
	if weapon_node and is_instance_valid(weapon_node):
		var parent := weapon_node.get_parent()
		if parent:
			parent.get_parent().remove_child(parent)
			parent.queue_free()
		weapon_node = null
	if weapon_node_left and is_instance_valid(weapon_node_left):
		var parent := weapon_node_left.get_parent()
		if parent:
			parent.get_parent().remove_child(parent)
			parent.queue_free()
		weapon_node_left = null


func _setup_mag() -> void:
	if not model:
		return

	var character = CharacterManager.get_active_character()
	if character == null:
		return
	var mag_id: String = str(character.get("equipment", {}).get("mag", ""))
	if mag_id.is_empty():
		return

	# Determine mag form and model path
	var form_id := "mag"
	var mag_state: Dictionary = MagManager.get_mag_state(character, mag_id)
	if not mag_state.is_empty():
		form_id = str(mag_state.get("form_id", "mag"))

	var glb_path: String = MagManager.get_model_path(form_id)
	if glb_path.is_empty() or not ResourceLoader.exists(glb_path):
		print("[Player] Mag GLB not found: %s" % glb_path)
		return

	var packed: PackedScene = load(glb_path) as PackedScene
	if packed == null:
		return

	# Attach as child of PlayerModel so it follows character rotation
	var node := packed.instantiate() as Node3D
	node.name = "MagModel"
	node.position = MAG_OFFSET
	model.add_child(node)
	mag_node = node
	print("[Player] Mag '%s' attached to model (%s)" % [form_id, glb_path])


func _clear_mag() -> void:
	if mag_node and is_instance_valid(mag_node):
		mag_node.get_parent().remove_child(mag_node)
		mag_node.queue_free()
		mag_node = null


func _setup_weapon() -> void:
	print("[Player] _setup_weapon called, skeleton=%s" % [skeleton != null])
	if not skeleton:
		push_warning("[Player] ABORT: No skeleton found, cannot attach weapon")
		print("[Player] Available bones: (none — skeleton is null)")
		return

	print("[Player] Skeleton bone count: %d, bones: %s" % [skeleton.get_bone_count(), _get_bone_names()])

	# Get equipped weapon from character data
	var weapon_data: WeaponData = _get_equipped_weapon_data()
	if weapon_data == null:
		print("[Player] ABORT: No weapon data returned")
		return

	print("[Player] Weapon data: id=%s, name=%s, type=%d, glb=%s, scale=%f, tint=%s" % [
		weapon_data.id, weapon_data.name, weapon_data.weapon_type,
		weapon_data.glb_path, weapon_data.glb_scale, weapon_data.tint_color])

	# Attach to right hand
	weapon_node = _attach_weapon_to_bone(WEAPON_BONE_NAME, weapon_data)

	# Dual-wield: daggers and mechguns go in both hands
	var is_dual_wield := weapon_data.weapon_type in [
		WeaponData.WeaponType.DAGGERS,
		WeaponData.WeaponType.MECH_GUN,
	]
	if is_dual_wield:
		print("[Player] Dual-wield weapon, attaching to left hand")
		weapon_node_left = _attach_weapon_to_bone(LEFT_WEAPON_BONE_NAME, weapon_data, true)


func _get_equipped_weapon_data() -> WeaponData:
	var character = CharacterManager.get_active_character()
	if character == null:
		print("[Player] _get_equipped_weapon_data: No active character")
		return null
	var equipment: Dictionary = character.get("equipment", {})
	var weapon_id: String = str(equipment.get("weapon", ""))
	print("[Player] _get_equipped_weapon_data: equipment=%s, weapon_id='%s'" % [equipment, weapon_id])
	if weapon_id.is_empty():
		print("[Player] ABORT: weapon_id is empty")
		return null
	var all_ids = WeaponRegistry.get_all_weapon_ids()
	print("[Player] WeaponRegistry has %d weapons: %s" % [all_ids.size(), all_ids])
	var w = WeaponRegistry.get_weapon(Inventory.get_base_id(weapon_id))
	if w == null:
		push_warning("[Player] ABORT: weapon '%s' not found in registry" % weapon_id)
	return w


func _attach_weapon_to_bone(bone_name: String, weapon_data: WeaponData, mirror: bool = false) -> Node3D:
	var bone_idx := skeleton.find_bone(bone_name)
	if bone_idx == -1:
		push_warning("[Player] ABORT: Could not find bone '%s' in skeleton" % bone_name)
		return null

	# Load the weapon GLB
	var glb_path: String = weapon_data.glb_path
	if glb_path.is_empty():
		push_warning("[Player] ABORT: No glb_path set for weapon: %s" % weapon_data.id)
		return null
	var exists := ResourceLoader.exists(glb_path)
	print("[Player] Loading GLB: %s (exists=%s)" % [glb_path, exists])
	if not exists:
		push_warning("[Player] ABORT: Weapon GLB not found: %s" % glb_path)
		return null

	var packed: PackedScene = load(glb_path) as PackedScene
	if packed == null:
		push_warning("[Player] ABORT: Failed to load GLB as PackedScene: %s" % glb_path)
		return null

	# Create bone attachment
	var bone_attachment := BoneAttachment3D.new()
	bone_attachment.name = "WeaponAttachment_R" if not mirror else "WeaponAttachment_L"
	bone_attachment.bone_name = skeleton.get_bone_name(bone_idx)
	skeleton.add_child(bone_attachment)

	# Instance weapon
	var node := packed.instantiate() as Node3D
	bone_attachment.add_child(node)

	# Position and scale — use idle hold by default
	var hold: Dictionary = WEAPON_HOLD.get(weapon_data.weapon_type, WEAPON_HOLD_DEFAULT)
	var idle_hold: Dictionary = hold.get("idle", {})

	var s: float = weapon_data.glb_scale
	node.position = idle_hold.get("pos", Vector3(0.31, 0, 0))
	node.rotation_degrees = idle_hold.get("rot", Vector3(0, 90, 0))
	node.scale = Vector3(s, s, s)

	# Mirror left-hand weapon on X axis
	if mirror:
		node.scale.x = -s

	# Apply tint and additive blending to blade materials
	_apply_weapon_materials(node, weapon_data)

	print("[Player] SUCCESS: Weapon '%s' attached to bone '%s' (mirror=%s, scale=%f)" % [
		weapon_data.name, bone_attachment.bone_name, mirror, s])
	return node


# Weapon type → global material indices that get additive blending (blade/energy surfaces)
# Indices count across all mesh children in order (matching web preview)
const WEAPON_ADDITIVE_MATERIALS: Dictionary = {
	WeaponData.WeaponType.SABER: [1, 2],
	WeaponData.WeaponType.SWORD: [1, 3],
	WeaponData.WeaponType.DAGGERS: [1],
	WeaponData.WeaponType.SPEAR: [2, 3],
}


func _apply_weapon_materials(node: Node3D, weapon_data: WeaponData) -> void:
	var tint: Color = weapon_data.tint_color
	var has_tint: bool = tint != Color.WHITE and tint != Color(1, 1, 1, 1)

	var surfaces: Array = []  # Array of [MeshInstance3D, surface_index]
	_collect_surfaces(node, surfaces)

	if has_tint:
		# Basic weapons: additive blending on blade/energy surfaces
		var additive_indices: Array = WEAPON_ADDITIVE_MATERIALS.get(weapon_data.weapon_type, [])
		for global_idx in additive_indices:
			if global_idx >= surfaces.size():
				continue
			var entry: Array = surfaces[global_idx]
			var mesh_inst: MeshInstance3D = entry[0]
			var surf_idx: int = entry[1]
			var mat := mesh_inst.get_active_material(surf_idx)
			if mat is StandardMaterial3D:
				var new_mat := mat.duplicate() as StandardMaterial3D
				new_mat.albedo_color = tint
				new_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				new_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				new_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				mesh_inst.set_surface_override_material(surf_idx, new_mat)
	else:
		# Unique weapons: normal textures, double-sided faces
		for entry in surfaces:
			var mesh_inst: MeshInstance3D = entry[0]
			var surf_idx: int = entry[1]
			var mat := mesh_inst.get_active_material(surf_idx)
			if mat is StandardMaterial3D:
				var new_mat := mat.duplicate() as StandardMaterial3D
				new_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				mesh_inst.set_surface_override_material(surf_idx, new_mat)


func _collect_surfaces(node: Node3D, surfaces: Array) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		var mesh := mesh_inst.mesh
		if mesh:
			for i in range(mesh.get_surface_count()):
				surfaces.append([mesh_inst, i])
	for child in node.get_children():
		if child is Node3D:
			_collect_surfaces(child as Node3D, surfaces)


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


func _is_in_city() -> bool:
	var parent := get_parent()
	return parent is CityAreaBase


func _find_node_of_type(root: Node, type_name: String) -> Node:
	if root.get_class() == type_name:
		return root

	for child in root.get_children():
		var found := _find_node_of_type(child, type_name)
		if found:
			return found

	return null


func _load_character_model() -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		# No active character — use default texture on existing model
		_apply_player_texture_from_path(DEFAULT_TEXTURE_PATH)
		return

	var paths: Dictionary = PlayerConfig.get_paths_for_character(character)
	var model_path: String = paths["model_path"]
	var texture_path: String = paths["texture_path"]

	# Swap model if different from default pc_000
	if ResourceLoader.exists(model_path):
		_swap_model(model_path)
	else:
		push_warning("[Player] Model not found: %s, using default" % model_path)

	# Apply texture
	if ResourceLoader.exists(texture_path):
		_apply_player_texture_from_path(texture_path)
	else:
		# Fallback: try default texture for this variation
		var variation: String = PlayerConfig.get_variation(
			character.get("class_id", "humar"),
			int(character.get("appearance", {}).get("variation_index", 0)))
		var fallback := "res://assets/player/%s/textures/%s_000.png" % [variation, variation]
		if ResourceLoader.exists(fallback):
			_apply_player_texture_from_path(fallback)
		else:
			_apply_player_texture_from_path(DEFAULT_TEXTURE_PATH)


func _swap_model(model_path: String) -> void:
	var model_node := $PlayerModel/Model
	if model_node:
		model_node.get_parent().remove_child(model_node)
		model_node.free()

	var packed: PackedScene = load(model_path) as PackedScene
	if packed == null:
		push_warning("[Player] Failed to load model: " + model_path)
		return

	var new_model := packed.instantiate() as Node3D
	new_model.name = "Model"
	$PlayerModel.add_child(new_model)
	# Move Model before Animations to maintain child order
	$PlayerModel.move_child(new_model, 0)
	print("[Player] Loaded model: %s" % model_path)


func _apply_player_texture_from_path(texture_path: String) -> void:
	var texture := load(texture_path) as Texture2D
	if not texture:
		push_warning("[Player] Failed to load texture: " + texture_path)
		return
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
		PlayerState.IDLE, PlayerState.WALKING, PlayerState.RUNNING, PlayerState.SPRINTING:
			_handle_movement(delta)
		PlayerState.DODGING:
			_handle_dodge(delta)
		PlayerState.ATTACKING:
			_handle_attack_state(delta)
		PlayerState.DAMAGED, PlayerState.DOWN:
			_handle_damaged(delta)
		PlayerState.CUTSCENE:
			velocity.x = 0
			velocity.z = 0

	# Apply movement
	move_and_slide()

	# Update model rotation
	if model:
		model.rotation.y = player_rotation

	# Update combat targeting reticles
	_update_combat_targets()

	# Mag bob and sway
	if mag_node and is_instance_valid(mag_node):
		_mag_time += delta
		mag_node.position = MAG_OFFSET + Vector3(
			sin(_mag_time * MAG_SWAY_SPEED * TAU) * MAG_SWAY_AMOUNT,
			sin(_mag_time * MAG_BOB_SPEED * TAU) * MAG_BOB_HEIGHT,
			0.0
		)


func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	player_rotation = 0.0
	if model:
		model.rotation.y = 0.0
	transition_to(PlayerState.IDLE)


func _unhandled_input(event: InputEvent) -> void:
	if current_state == PlayerState.CUTSCENE:
		return

	# Palette swap
	if event.is_action_pressed("palette_swap"):
		ActionPalette.swap_page()

	# Action palette inputs — dispatch through ActionPalette
	if event.is_action_pressed("action_1"):
		_execute_palette_action(0)
	if event.is_action_pressed("action_2"):
		_execute_palette_action(1)
	if event.is_action_pressed("action_3"):
		_execute_palette_action(2)

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

		# Camera-relative movement: transform input by camera orientation
		# so W always moves "into the screen" regardless of camera angle.
		var target_rotation: float
		var cam := get_viewport().get_camera_3d()
		if cam:
			var cam_basis := cam.get_global_transform().basis
			var move_3d := cam_basis * Vector3(input_dir.x, 0, input_dir.y)
			move_3d.y = 0
			move_3d = move_3d.normalized()
			target_rotation = atan2(move_3d.x, move_3d.z)
		else:
			target_rotation = atan2(input_dir.x, input_dir.y)

		# Smoothly rotate toward target
		var rot_diff := target_rotation - player_rotation
		# Normalize angle difference to -PI to PI
		while rot_diff > PI:
			rot_diff -= TAU
		while rot_diff < -PI:
			rot_diff += TAU
		player_rotation += rot_diff * ROTATE_SPEED * delta

		# State transitions: IDLE → WALKING → RUNNING
		if current_state == PlayerState.SPRINTING:
			transition_to(PlayerState.RUNNING)
		elif current_state == PlayerState.IDLE:
			walk_timer = 0.0
			transition_to(PlayerState.WALKING)
		elif current_state == PlayerState.WALKING:
			walk_timer += delta
			if walk_timer >= WALK_TO_RUN_DELAY:
				transition_to(PlayerState.RUNNING)

		# Speed based on current state
		var speed: float = MOVE_SPEED
		if current_state == PlayerState.WALKING:
			speed = WALK_SPEED
		elif current_state == PlayerState.SPRINTING:
			speed = SPRINT_SPEED

		# Calculate desired movement
		var move_dir := Vector3(sin(player_rotation), 0, cos(player_rotation))
		var desired_velocity := move_dir * speed

		# Check if movement would stay on floor using raycasts
		# Check three points: center, left, and right of movement direction
		if _can_move_to(move_dir):
			velocity.x = desired_velocity.x
			velocity.z = desired_velocity.z
		else:
			# No floor ahead, stop at edge
			velocity.x = 0
			velocity.z = 0
	else:
		# Stop horizontal movement
		velocity.x = 0
		velocity.z = 0

		# Switch to idle if walking, running, or sprinting
		if current_state in [PlayerState.WALKING, PlayerState.RUNNING, PlayerState.SPRINTING]:
			walk_timer = 0.0
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
		var max_combo: int = int(CombatManager.get_weapon_type_config(_get_equipped_weapon_type()).get("combo_steps", 3))
		if combo_window_open and combo_state < max_combo:
			combo_state += 1
			combo_window_open = false
			_play_attack_animation(combo_state)
		return

	# Start fresh attack combo
	combo_state = 1
	combo_window_open = false
	transition_to(PlayerState.ATTACKING)
	_play_attack_animation(combo_state)


func _execute_palette_action(slot: int) -> void:
	# Block actions during hit reactions and knockdown
	if current_state == PlayerState.DAMAGED or current_state == PlayerState.DOWN:
		return
	var action_id: String = ActionPalette.get_action_for_slot(slot)
	match action_id:
		"attack":
			_start_attack()
		"strong_attack":
			_start_strong_attack()
		"dodge":
			_start_dodge()
		"monomate", "dimate", "trimate", "monofluid", "difluid", "trifluid":
			_use_consumable(action_id)
		"kill_all":
			_debug_kill_all()
		_:
			if TechniqueManager.TECHNIQUES.has(action_id):
				_cast_technique(action_id)


func _cast_technique(technique_id: String) -> void:
	if current_state == PlayerState.ATTACKING or current_state == PlayerState.DODGING:
		return

	var character = CharacterManager.get_active_character()
	if character == null:
		return
	if TechniqueManager.get_technique_level(character, technique_id) <= 0:
		print("[Player] Technique %s not learned" % technique_id)
		return

	var tech_data: Dictionary = CombatManager.calculate_technique_damage(technique_id)
	var pp_cost: int = int(tech_data.get("pp_cost", 5))

	if GameState.mp < pp_cost:
		print("[Player] Not enough PP for %s (need %d, have %d)" % [technique_id, pp_cost, GameState.mp])
		return

	GameState.set_mp(GameState.mp - pp_cost)

	# Play cast animation — no combo for techniques
	transition_to(PlayerState.ATTACKING)
	combo_state = 0
	combo_window_open = false
	play_animation(_anim_prefix + "_tec", false)

	_spawn_technique_effect(technique_id, tech_data)


func _spawn_technique_effect(technique_id: String, tech_data: Dictionary) -> void:
	var forward := Vector3(sin(player_rotation), 0, cos(player_rotation))
	var spawn_pos := global_position + Vector3(0, 1.0, 0) + forward * 0.5
	var damage: int = int(tech_data.get("damage", 10))
	var kb: float = float(tech_data.get("knockback", 3.0))

	match technique_id:
		"foie":
			_spawn_foie(spawn_pos, forward, damage, kb)
		"barta":
			_spawn_barta(spawn_pos, forward, damage, kb)
		"zonde":
			_spawn_zonde(damage, kb)
		_:
			# Fallback: fire a basic projectile for unimplemented techniques
			_spawn_foie(spawn_pos, forward, damage, kb)


func _spawn_foie(spawn_pos: Vector3, forward: Vector3, damage: int, kb: float) -> void:
	var proj := Projectile.new()
	proj.damage = damage
	proj.knockback = kb
	proj.accuracy = 100
	proj.direction = forward
	proj.max_range = 15.0
	proj.owner_node = self
	proj.speed = 20.0
	proj.color = Color(1.0, 0.3, 0.05)
	get_tree().current_scene.add_child(proj)
	proj.global_position = spawn_pos


func _spawn_barta(spawn_pos: Vector3, forward: Vector3, damage: int, kb: float) -> void:
	var proj := Projectile.new()
	proj.damage = damage
	proj.knockback = kb
	proj.accuracy = 100
	proj.direction = forward
	proj.max_range = 12.0
	proj.owner_node = self
	proj.speed = 15.0
	proj.pierce = true
	proj.color = Color(0.3, 0.7, 1.0)
	var ground_pos := Vector3(spawn_pos.x, global_position.y + 0.3, spawn_pos.z)
	get_tree().current_scene.add_child(proj)
	proj.global_position = ground_pos


func _spawn_zonde(damage: int, kb: float) -> void:
	if _targeted_enemies.is_empty():
		print("[Player] Zonde: no target")
		return
	var target_enemy = _targeted_enemies[0]
	if not is_instance_valid(target_enemy):
		return
	if target_enemy.hurtbox:
		var forward := Vector3(sin(player_rotation), 0, cos(player_rotation))
		target_enemy.hurtbox.take_hit(damage, forward * kb, 100)
	_spawn_zonde_visual(target_enemy.global_position)


func _spawn_zonde_visual(target_pos: Vector3) -> void:
	var bolt := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.08
	cylinder.bottom_radius = 0.08
	cylinder.height = 10.0
	bolt.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.8, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bolt.material_override = mat
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = target_pos + Vector3(0, 5.0, 0)
	var tween := bolt.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tween.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.4)
	tween.tween_callback(bolt.queue_free)


func _debug_kill_all() -> void:
	var kill_count: int = 0
	# Kill all enemies directly (bypass damage formula)
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyBase and node.is_alive:
			node.current_hp = 0
			node._die()
			kill_count += 1
		elif node is EnemySpawn and node.get("element_state") != "dead":
			node.take_damage(99999)
			kill_count += 1
	print("[DEBUG] Kill All from action palette (%d killed)" % kill_count)
	# Reset player state in case we were mid-attack
	if current_state == PlayerState.ATTACKING:
		combo_state = 0
		combo_window_open = false
		_deactivate_attack_hitbox()
		transition_to(PlayerState.IDLE)


func _start_strong_attack() -> void:
	if current_state == PlayerState.ATTACKING or current_state == PlayerState.DODGING:
		return
	# Strong attack uses combo step 3 animation directly
	combo_state = 3
	combo_window_open = false
	transition_to(PlayerState.ATTACKING)
	_play_attack_animation(combo_state)


func _use_consumable(item_id: String) -> void:
	if current_state == PlayerState.ATTACKING or current_state == PlayerState.DODGING:
		return
	if Inventory.use_item(item_id):
		print("[Player] Used %s from action palette" % item_id)
	else:
		print("[Player] No %s in inventory" % item_id)


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
	# No physics movement during hit reactions — animation-driven only
	velocity.x = 0
	velocity.z = 0


func _set_weapon_hold(mode: String) -> void:
	if not weapon_node or not is_instance_valid(weapon_node):
		return
	var wtype: int = _get_equipped_weapon_type()
	var hold: Dictionary = WEAPON_HOLD.get(wtype, WEAPON_HOLD_DEFAULT)
	var h: Dictionary = hold.get(mode, hold.get("idle", {}))
	weapon_node.position = h.get("pos", Vector3(0.31, 0, 0))
	weapon_node.rotation_degrees = h.get("rot", Vector3(0, 90, 0))


func _play_attack_animation(attack_num: int) -> void:
	var anim_name := _anim_prefix + "_atk" + str(attack_num)
	play_animation(anim_name, false)
	_activate_attack_hitbox()


func transition_to(new_state: PlayerState) -> void:
	var was_attacking: bool = current_state == PlayerState.ATTACKING
	current_state = new_state
	state_changed.emit(new_state)

	# Swap weapon hold orientation between attack and idle
	if new_state == PlayerState.ATTACKING and not was_attacking:
		_set_weapon_hold("attack")
	elif was_attacking and new_state != PlayerState.ATTACKING:
		_set_weapon_hold("idle")

	match new_state:
		PlayerState.IDLE:
			play_animation(_anim_prefix + "_wait", true)
		PlayerState.WALKING:
			play_animation(_walk_anim, true)
		PlayerState.RUNNING:
			play_animation(_run_anim, true)
		PlayerState.SPRINTING:
			play_animation(_sprint_anim, true)
		PlayerState.DODGING:
			play_animation(_anim_prefix + "_esc_f", false)
		PlayerState.DAMAGED, PlayerState.DOWN:
			pass  # Animation already set by take_damage / _on_animation_finished
		PlayerState.CUTSCENE:
			play_animation(_anim_prefix + "_wait", true)


func play_animation(anim_name: String, _loop: bool = true) -> void:
	if not animation_player:
		return
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
		return
	# Try with 's' suffix variant (e.g. pwros_wait for pwro prefix)
	var parts := anim_name.rsplit("_", true, 1)
	if parts.size() == 2:
		var alt := parts[0] + "s_" + parts[1]
		if animation_player.has_animation(alt):
			animation_player.play(alt)
			return
	# Search for any animation ending with a matching suffix, trying longest first
	# e.g. for "pmsa_dam_d_lp" try "_dam_d_lp", then "_d_lp", then "_lp"
	var underscores: PackedInt32Array = []
	for i in range(anim_name.length()):
		if anim_name[i] == "_":
			underscores.append(i)
	for idx in range(1, underscores.size()):
		var suffix := anim_name.substr(underscores[idx])
		for anim in animation_player.get_animation_list():
			if anim.ends_with(suffix):
				animation_player.play(anim)
				return


func _on_animation_finished(_anim_name: String) -> void:
	match current_state:
		PlayerState.DODGING:
			transition_to(PlayerState.IDLE)
		PlayerState.ATTACKING:
			_deactivate_attack_hitbox()
			if combo_state == 0:
				# Technique cast finished (no combo)
				transition_to(PlayerState.IDLE)
				return
			var config: Dictionary = CombatManager.get_weapon_type_config(_get_equipped_weapon_type())
			var max_combo: int = int(config.get("combo_steps", 3))
			if combo_state >= max_combo:
				# Combo finished, return to idle
				combo_state = 0
				transition_to(PlayerState.IDLE)
			else:
				# Open combo window
				combo_window_open = true
				combo_timer = 0.0
		PlayerState.DAMAGED:
			transition_to(PlayerState.IDLE)
		PlayerState.DOWN:
			if GameState.hp <= 0:
				# Dead — stay lying down
				play_animation(_anim_prefix + "_dam_d_lp", true)
			else:
				# Get back up
				play_animation(_anim_prefix + "_dam_d_wa", false)
				transition_to(PlayerState.DAMAGED)  # DAMAGED → IDLE when wake-up finishes


# Public API for external systems
func take_damage(damage: int, _knockback: Vector3 = Vector3.ZERO) -> void:
	# Already dead — ignore further hits
	if current_state == PlayerState.DOWN and GameState.hp <= 0:
		return

	GameState.set_hp(GameState.hp - damage)

	# No physics knockback — animation-driven hit reactions only
	velocity = Vector3.ZERO

	if GameState.hp <= 0:
		# Death: knockdown into lying-down loop
		play_animation(_anim_prefix + "_dam_d", false)
		transition_to(PlayerState.DOWN)
	elif damage > 20:
		# Heavy hit: knockdown then get back up
		play_animation(_anim_prefix + "_dam_d", false)
		transition_to(PlayerState.DOWN)
	elif damage > 10:
		# Medium hit: knockdown + immediate recovery (single animation)
		play_animation(_anim_prefix + "_dam_h", false)
		transition_to(PlayerState.DAMAGED)
	else:
		# Light hit: stagger
		play_animation(_anim_prefix + "_dam_n", false)
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
	attack_hitbox.damage = 10  # Will be set properly on each attack activation

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Use weapon-specific hitbox size from config
	var weapon_type: int = _get_equipped_weapon_type()
	var config: Dictionary = CombatManager.get_weapon_type_config(weapon_type)
	box.size = config.get("hitbox_size", ATTACK_HITBOX_SIZE)
	shape.shape = box
	var offset: float = float(config.get("hitbox_offset", ATTACK_HITBOX_OFFSET))
	shape.position = Vector3(0, box.size.y * 0.5 + 0.5, offset + box.size.z * 0.5)
	attack_hitbox.add_child(shape)

	# Hitbox follows player rotation via model
	model.add_child(attack_hitbox)


func _get_attack_damage() -> Dictionary:
	return CombatManager.calculate_attack_damage(combo_state)


func _get_equipped_weapon_type() -> int:
	var character = CharacterManager.get_active_character()
	if character == null:
		return 0
	var weapon_id: String = str(character.get("equipment", {}).get("weapon", ""))
	if weapon_id.is_empty():
		return 0
	var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(weapon_id))
	if weapon:
		return weapon.weapon_type
	return 0


const RANGED_WEAPON_TYPES := [9, 10, 11, 12]  # HANDGUN, MECH_GUN, RIFLE, BAZOOKA


func _activate_attack_hitbox() -> void:
	var atk: Dictionary = _get_attack_damage()
	var weapon_type: int = int(atk.get("weapon_type", 0))

	if weapon_type in RANGED_WEAPON_TYPES:
		_fire_projectile(atk)
		return

	if attack_hitbox:
		attack_hitbox.damage = int(atk.get("damage", 10))
		attack_hitbox.knockback = float(atk.get("knockback", 5.0))
		attack_hitbox.accuracy = int(atk.get("accuracy", 100))
		attack_hitbox.max_targets = int(atk.get("max_targets", 1))
		attack_hitbox.hits_per_target = int(atk.get("hits", 1))
		attack_hitbox.activate()


func _fire_projectile(atk: Dictionary) -> void:
	var config: Dictionary = CombatManager.get_weapon_type_config(int(atk.get("weapon_type", 0)))
	var forward := Vector3(sin(player_rotation), 0, cos(player_rotation))
	var spawn_pos := global_position + Vector3(0, 1.0, 0) + forward * 0.5
	var max_range: float = float(config.get("hitbox_offset", 8.0)) + float(config.get("hitbox_size", Vector3(1, 1, 1)).z)
	var hits: int = int(atk.get("hits", 1))

	for i in range(hits):
		var proj := Projectile.new()
		proj.damage = int(atk.get("damage", 10))
		proj.knockback = float(atk.get("knockback", 3.0))
		proj.accuracy = int(atk.get("accuracy", 100))
		proj.direction = forward
		proj.max_range = max_range
		proj.owner_node = self
		proj.speed = 25.0

		# Slight spread for multi-shot (mechgun)
		if hits > 1:
			var spread := randf_range(-0.05, 0.05)
			proj.direction = Vector3(forward.x + spread, 0, forward.z + spread).normalized()

		get_tree().current_scene.add_child(proj)
		proj.global_position = spawn_pos

		# Stagger multi-shot slightly
		if hits > 1 and i < hits - 1:
			spawn_pos += forward * 0.1


func _deactivate_attack_hitbox() -> void:
	if attack_hitbox:
		attack_hitbox.deactivate()


var _debug_range_mesh: MeshInstance3D


func _update_combat_targets() -> void:
	# Clear old reticles
	for enemy in _targeted_enemies:
		if is_instance_valid(enemy) and enemy.has_method("hide_reticle"):
			enemy.hide_reticle()
	_targeted_enemies.clear()

	var weapon_type: int = _get_equipped_weapon_type()
	var config: Dictionary = CombatManager.get_weapon_type_config(weapon_type)
	var max_targets: int = int(config.get("max_targets", 1))
	var hitbox_size: Vector3 = config.get("hitbox_size", ATTACK_HITBOX_SIZE)
	var hitbox_offset: float = float(config.get("hitbox_offset", ATTACK_HITBOX_OFFSET))
	var attack_range: float = hitbox_offset + hitbox_size.z * 0.5

	# Player's forward direction (model rotation)
	var forward := Vector3(sin(player_rotation), 0, cos(player_rotation))
	var half_width: float = hitbox_size.x * 0.5 + 0.5  # Slight padding

	# Debug: show targeting box attached to model
	if DebugConfig.show_hitboxes:
		if not _debug_range_mesh:
			_debug_range_mesh = MeshInstance3D.new()
			var box_mesh := BoxMesh.new()
			box_mesh.size = Vector3(1, 1, 1)
			_debug_range_mesh.mesh = box_mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.2, 1.0, 0.2, 0.15)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.no_depth_test = true
			_debug_range_mesh.material_override = mat
			model.add_child(_debug_range_mesh)
		var box_depth: float = hitbox_offset + hitbox_size.z * 0.5
		_debug_range_mesh.scale = Vector3(hitbox_size.x + 1.0, hitbox_size.y, box_depth)
		_debug_range_mesh.position = Vector3(0, hitbox_size.y * 0.5 + 0.5, box_depth * 0.5)
		_debug_range_mesh.visible = true
	elif _debug_range_mesh:
		_debug_range_mesh.visible = false

	# Find enemies in front of the player within weapon range
	var candidates: Array = []
	var enemy_group := get_tree().get_nodes_in_group("enemies")
	for enemy in enemy_group:
		if not is_instance_valid(enemy):
			continue
		if not enemy.get("is_alive"):
			continue
		var to_enemy: Vector3 = enemy.global_position - global_position
		to_enemy.y = 0

		# Check distance along forward axis
		var forward_dist: float = to_enemy.dot(forward)
		if forward_dist < -0.5 or forward_dist > attack_range:
			continue

		# Check lateral distance (perpendicular to forward)
		var right := Vector3(-forward.z, 0, forward.x)
		var lateral_dist: float = absf(to_enemy.dot(right))
		if lateral_dist > half_width:
			continue

		candidates.append({"enemy": enemy, "dist": forward_dist})

	# Sort by distance
	candidates.sort_custom(func(a, b): return a.dist < b.dist)

	# Show reticle on closest N enemies
	for i in range(mini(max_targets, candidates.size())):
		var enemy = candidates[i].enemy
		if enemy.has_method("show_reticle"):
			enemy.show_reticle()
		_targeted_enemies.append(enemy)

	# Debug: color box based on targets found
	if _debug_range_mesh and _debug_range_mesh.visible:
		var mat: StandardMaterial3D = _debug_range_mesh.material_override
		if _targeted_enemies.size() > 0:
			mat.albedo_color = Color(1.0, 0.2, 0.2, 0.15)
		else:
			mat.albedo_color = Color(0.2, 1.0, 0.2, 0.15)

	# Debug log every 2 seconds
	if DebugConfig.show_hitboxes and Engine.get_process_frames() % 120 == 0:
		print("[Target] enemies_in_group=%d fwd=(%.1f,%.1f) range=%.1f width=%.1f candidates=%d targets=%d" % [
			enemy_group.size(), forward.x, forward.z, attack_range, half_width,
			candidates.size(), _targeted_enemies.size()])


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
		var target := nearest_interactable
		target.interact(self)
		interacted_with.emit(target)
		if is_instance_valid(target):
			print("[Player] Interacted with: ", target.name)


func get_nearest_interactable() -> Node3D:
	return nearest_interactable

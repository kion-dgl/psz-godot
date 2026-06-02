extends CharacterBody3D
## Player controller - handles movement, rotation, and animation states
## Ported from psz-sketch PlayerMovementDemo.tsx

# Movement settings
const MOVE_SPEED: float = 6.0
const SPRINT_SPEED: float = 8.0
const WALK_SPEED: float = 2.5
const WALK_TO_RUN_DELAY: float = 1.2
const ROTATE_SPEED: float = 10.0
## Minimum speed multiplier while rotating — at facing-error PI (180°), speed scales
## to this value, at 0° it's 1.0. Stops the "skate forward during a 180° flick" feel
## by slowing the character when their facing is far from input direction.
const TURN_SPEED_FLOOR: float = 0.3
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
	WeaponData.WeaponType.CLAW: {"glb_m": "res://assets/player/animations/claw_m.glb", "glb_w": "res://assets/player/animations/claw_w.glb", "prefix_m": "pmcl", "prefix_w": "pwcl"},
	WeaponData.WeaponType.SPEAR: {"glb_m": "res://assets/player/animations/spear_m.glb", "glb_w": "res://assets/player/animations/spear_w.glb", "prefix_m": "pmsp", "prefix_w": "pwsp"},
	WeaponData.WeaponType.SLICER: {"glb_m": "res://assets/player/animations/slicer_m.glb", "glb_w": "res://assets/player/animations/slicer_w.glb", "prefix_m": "pmsl", "prefix_w": "pwsls"},
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
	3: {  # CLAW
		"idle": {"pos": Vector3(0.31, 0, 0), "rot": Vector3(0, -4, 0)},
		"attack": {"pos": Vector3(0.31, 0, 0), "rot": Vector3(0, -4, 0)},
	},
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
var _is_special_attack: bool = false  # True when current attack carries weapon element
var combo_window_open: bool = false
var combo_timer: float = 0.0
var _attack_anim_length: float = 0.0  # Current attack animation duration
var _attack_anim_elapsed: float = 0.0  # Time since attack animation started
var _combo_window_opened: bool = false  # Has the window opened this step yet
const COMBO_WINDOW_OPEN_PCT: float = 0.55  # Open combo window at 55% of animation
const COMBO_WINDOW_DURATION: float = 0.35  # Window stays open for 0.35s

# Combo timing visual
var _combo_ring: MeshInstance3D = null
var _combo_ring_mat: StandardMaterial3D = null

# Special attack charge visual
var _charge_ring: MeshInstance3D = null
var _charge_ring_mat: StandardMaterial3D = null
var _charge_particles: GPUParticles3D = null
var _charge_timer: float = 0.0
var _charge_active: bool = false
var _charge_color: Color = Color.WHITE
var _glow_light: OmniLight3D  # Lantern glow, toggled by time of day
var _cached_materials: Array = []  # Array of StandardMaterial3D for charge/glow effects

# Technique charge (hold-to-charge)
var _charging_slot: int = -1
var _charging_tech_id: String = ""
var _tech_charge_timer: float = 0.0
var _tech_charge_ready: bool = false
const TECH_CHARGE_THRESHOLD := 0.6
signal tech_charge_started(slot: int)
signal tech_charge_ready(slot: int)
signal tech_charge_released(slot: int)

# Footstep SFX
var _footstep_timer: float = 0.0
const FOOTSTEP_WALK_INTERVAL := 0.55
const FOOTSTEP_RUN_INTERVAL := 0.40
const FOOTSTEP_SPRINT_INTERVAL := 0.30

# Footstep samples keyed by (terrain, race). PSO uses a single sample per combo
# (no step1/step2 alternation). Terrain is resolved from the current area id;
# race is derived from class_id. Missing race entries fall back to "human".
const FOOTSTEP_CLIPS := {
	"forest":   {"human": "res://assets/sfx/common/common_000.wav"},
	"caves":    {"human": "res://assets/sfx/common/common_002.wav"},
	"city":     {
		"human": "res://assets/sfx/common/common_004.wav",
		"cast": "res://assets/sfx/common/common_009.wav",
		"racast": "res://assets/sfx/common/common_008.wav",
	},
	"jungle":   {"human": "res://assets/sfx/common/common_007.wav"},
	"sand":     {"human": "res://assets/sfx/common/common_023.wav"},
	"water":    {"human": "res://assets/sfx/common/common_025.wav"},
	"snow":     {"human": "res://assets/sfx/common/common_026.wav"},
	"generic":  {"human": "res://assets/sfx/common/common_026.wav"},
}

# Area id (SessionManager.get_current_area_id) → terrain key above.
const AREA_TO_TERRAIN := {
	"gurhacia": "forest",
	"ozette":   "snow",
	"rioh":     "jungle",
	"makara":   "sand",
	"paru":     "caves",
	"arca":     "city",
	"dark":     "caves",
	"tower":    "city",
}

const CAST_CLASSES := ["hucast", "hucaseal"]
const RACAST_CLASSES := ["racast", "racaseal"]

# Dodge tracking
var dodge_direction: float = 0.0
var dodge_timer: float = 0.0
# Per-dodge cache of the active animation's length and the timestamp the
# move phase ends (= length × DODGE_MOVE_FRACTION). Recomputed at every
# _start_dodge so each weapon's own _esc_f duration is respected.
var dodge_anim_duration: float = 0.0
var dodge_move_end: float = 0.0
const DODGE_DURATION: float = 0.8
const DODGE_SPEED: float = 7.0
# Fraction of the dodge animation during which we apply velocity. The
# remaining (1 - fraction) is the recovery — the character lands in a
# crouch and stands up. Sliding through that recovery looked wrong, so
# we cut velocity at this boundary while staying in DODGING so the
# animation finishes naturally.
const DODGE_MOVE_FRACTION: float = 0.7

# Interaction system
var interaction_area: Area3D
var nearby_elements: Array = []  # Array of GameElement nodes
var nearest_interactable: Node3D = null  # GameElement or null
const INTERACTION_RADIUS: float = 2.0

# Combat system
var attack_hitbox: Hitbox
var _targeted_enemies: Array = []
var _current_attack_element: String = ""
var _current_attack_element_level: int = 0
var _cached_tech_targeting: Dictionary = {}
var _tech_targeting_dirty: bool = true
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
	_cache_model_materials()

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

	# Lantern-style warm light — only in field areas, toggled by time of day
	if not in_city:
		_glow_light = OmniLight3D.new()
		_glow_light.name = "PlayerGlow"
		_glow_light.light_color = Color(1.0, 0.8, 0.5)
		_glow_light.light_energy = 1.2 * TimeManager.get_darkness_factor()
		_glow_light.omni_range = 8.0
		_glow_light.omni_attenuation = 1.2
		_glow_light.shadow_enabled = false
		_glow_light.position = Vector3(0, 1.2, 0)
		add_child(_glow_light)

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

	# In city, always use default unarmed animations (saber-prefix; visual choice)
	var anim_glb := DEFAULT_ANIM_GLB_W if _is_female else DEFAULT_ANIM_GLB_M
	_anim_prefix = DEFAULT_ANIM_PREFIX_W if _is_female else DEFAULT_ANIM_PREFIX_M

	if not _is_in_city():
		var weapon_data := _get_equipped_weapon_data()
		if weapon_data and WEAPON_ANIM_DATA.has(weapon_data.weapon_type):
			var data: Dictionary = WEAPON_ANIM_DATA[weapon_data.weapon_type]
			anim_glb = str(data.get("glb_" + gender_key, anim_glb))
			_anim_prefix = str(data.get("prefix_" + gender_key, _anim_prefix))
		else:
			# No weapon equipped in field: use truly barehanded animations
			# (common_m/w.glb, pmbn/pwbn = "bare hands" prefix). Falling back
			# to the city default (saber) here meant unarmed players still
			# played saber attack animations and swing sounds with empty hands.
			anim_glb = "res://assets/player/animations/common_w.glb" if _is_female else "res://assets/player/animations/common_m.glb"
			_anim_prefix = "pwbn" if _is_female else "pmbn"

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

		# Strip baked-in root translation from dodge clips — see
		# _strip_root_translation_track for rationale.
		if anim_name.ends_with("_esc_f"):
			_strip_root_translation_track(new_anim, skeleton.name)

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
		# Sprint fallback (mirrors female logic above): some prefix sets don't
		# ship a `<prefix>_run` (e.g. pmbn/unarmed reuses pmsa_run from
		# common_m.glb). Fall back to any pm*_run that's actually in the lib.
		if not lib.has_animation(_sprint_anim):
			for anim_name in lib.get_animation_list():
				if anim_name.begins_with("pm") and anim_name.ends_with("_run") and not anim_name.ends_with("_run_pso"):
					_sprint_anim = anim_name
					break
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
	if _is_in_city():
		return
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
	print("[Player] WeaponRegistry has %d weapons" % all_ids.size())
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


func _resolve_footstep_clip() -> String:
	var terrain: String
	if _is_in_city() or SessionManager.get_location() == "city":
		terrain = "city"
	else:
		var area_id: String = SessionManager.get_current_area_id()
		terrain = AREA_TO_TERRAIN.get(area_id, "generic")
	var clips: Dictionary = FOOTSTEP_CLIPS.get(terrain, {})
	if clips.is_empty():
		return ""

	var class_id: String = ""
	var session: Dictionary = SessionManager.get_session()
	var character: Variant = session.get("character", {})
	if character is Dictionary:
		class_id = str(character.get("class_id", ""))
	var race: String = "human"
	if class_id in CAST_CLASSES:
		race = "cast"
	elif class_id in RACAST_CLASSES:
		race = "racast"
	# Fall back to human if the specific race isn't labeled for this terrain yet.
	return clips.get(race, clips.get("human", ""))


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


func _cache_model_materials() -> void:
	## Pre-cache StandardMaterial3D references from the player model so charge
	## visual and glow updates don't need nested get_children() loops every frame.
	_cached_materials.clear()
	if not model:
		return
	for child in model.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			for i in range(mi.get_surface_override_material_count()):
				var mat := mi.get_active_material(i)
				if mat is StandardMaterial3D:
					_cached_materials.append(mat)


func _physics_process(delta: float) -> void:
	FrameProfiler.mark("player_start")
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

	FrameProfiler.mark("player_move_slide")
	# Apply movement
	move_and_slide()

	# Update model rotation
	if model:
		model.rotation.y = player_rotation

	# Footstep sounds
	if is_on_floor() and current_state in [PlayerState.WALKING, PlayerState.RUNNING, PlayerState.SPRINTING]:
		var interval: float = FOOTSTEP_WALK_INTERVAL
		if current_state == PlayerState.RUNNING:
			interval = FOOTSTEP_RUN_INTERVAL
		elif current_state == PlayerState.SPRINTING:
			interval = FOOTSTEP_SPRINT_INTERVAL
		_footstep_timer -= delta
		if _footstep_timer <= 0:
			_footstep_timer = interval
			var sfx: String = _resolve_footstep_clip()
			if sfx != "":
				SfxManager.play_at(sfx, global_position, -8.0)
	else:
		_footstep_timer = 0.0

	# Smoothly fade lantern glow based on time of day (check every ~0.5s)
	if _glow_light and Engine.get_physics_frames() % 30 == 0:
		var darkness: float = TimeManager.get_darkness_factor()
		_glow_light.light_energy = 1.2 * darkness

	# Technique charge timer
	if _charging_slot >= 0:
		_tech_charge_timer += delta
		if not _tech_charge_ready and _tech_charge_timer >= TECH_CHARGE_THRESHOLD:
			_tech_charge_ready = true
			tech_charge_ready.emit(_charging_slot)
			_current_attack_element = str(TechniqueManager.TECHNIQUES.get(_charging_tech_id, {}).get("element", ""))
			_start_charge_visual()

	# Update combat targeting reticles (every 3rd frame to reduce CPU)
	FrameProfiler.mark("player_targeting")
	if not _is_in_city() and Engine.get_physics_frames() % 3 == 0:
		_update_combat_targets()
	FrameProfiler.mark("player_done")

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

	# Don't process gameplay input while any menu/dialog/overlay is active.
	# Menu face-button bindings overlap with palette actions (ui_accept shares
	# button 1/east with action_3 under switch scheme, etc.), so relying on
	# set_input_as_handled() alone is fragile — an explicit gate is safer.
	if GameState.is_gameplay_blocked():
		return

	# Combat input gate — palette HUD is hidden in city via field_hud, but the
	# input bindings still fire without an explicit gate, so action_1/2/3
	# would play attack anims and spawn projectiles in town with a weapon
	# equipped. Interact stays available for NPC conversations.
	if not _is_in_city():
		# Palette swap
		if event.is_action_pressed("palette_swap"):
			ActionPalette.swap_page()
			_tech_targeting_dirty = true

		# Action palette inputs — press starts charge for techniques, release casts
		for slot_idx in range(3):
			var action_name: String = "action_%d" % (slot_idx + 1)
			if event.is_action_pressed(action_name):
				_on_palette_pressed(slot_idx)
			elif event.is_action_released(action_name):
				_on_palette_released(slot_idx)

		# Dodge has its own dedicated button (L1 on controller) — no longer on palette
		if event.is_action_pressed("dodge"):
			if current_state != PlayerState.DAMAGED and current_state != PlayerState.DOWN:
				_start_dodge()

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

		# Scale speed by facing-error so sharp turns tighten instead of skating
		# forward in the old direction while rotation catches up.
		var turn_factor: float = lerpf(TURN_SPEED_FLOOR, 1.0, (cos(rot_diff) + 1.0) * 0.5)
		speed *= turn_factor

		# Calculate desired movement
		var move_dir := Vector3(sin(player_rotation), 0, cos(player_rotation))
		var desired_velocity := move_dir * speed

		# Check if movement would stay on floor using raycasts
		# Check three points: center, left, and right of movement direction
		if _can_move_to(move_dir):
			velocity.x = desired_velocity.x
			velocity.z = desired_velocity.z
		else:
			# Edge/wall ahead in the desired direction. Instead of stopping
			# dead (the old behaviour, which made the autopilot stick on
			# stage geometry seams and floor-mesh joins), try the axis
			# components separately and walk whichever one keeps us on
			# floor — effectively slide along the obstruction. Worst case
			# both axes are blocked and we still stop.
			var x_only := Vector3(sign(move_dir.x), 0, 0)
			var z_only := Vector3(0, 0, sign(move_dir.z))
			if move_dir.x != 0.0 and _can_move_to(x_only):
				velocity.x = desired_velocity.x
				velocity.z = 0
			elif move_dir.z != 0.0 and _can_move_to(z_only):
				velocity.x = 0
				velocity.z = desired_velocity.z
			else:
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

	# Require at least 2 of 3 sample points to find floor. The previous
	# all-3 rule wedged the player on hairline gaps in the floor mesh
	# triangulation (one of the three downward rays drops cleanly into
	# the crack and the other two land on solid floor, so the all-3
	# check returns false and the player can't advance in any direction).
	# 2-of-3 tolerates that single-point miss while still preventing the
	# cliff-walk case (no floor at all = all 3 miss = stop).
	var hits: int = 0
	if _has_floor_at(center):
		hits += 1
	if _has_floor_at(left):
		hits += 1
	if _has_floor_at(right):
		hits += 1
	return hits >= 2


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
	# Look up the active weapon's _esc_f length so the move phase scales
	# to the actual clip (saber is 0.667s, others vary). Fall back to
	# DODGE_DURATION if the animation isn't loaded for some reason —
	# better to dodge a short distance than not at all.
	var anim_name := _anim_prefix + "_esc_f"
	if animation_player and animation_player.has_animation(anim_name):
		dodge_anim_duration = animation_player.get_animation(anim_name).length
	else:
		dodge_anim_duration = DODGE_DURATION
	dodge_move_end = dodge_anim_duration * DODGE_MOVE_FRACTION
	transition_to(PlayerState.DODGING)


func _handle_dodge(delta: float) -> void:
	dodge_timer += delta

	if dodge_timer >= DODGE_DURATION:
		velocity.x = 0
		velocity.z = 0
		transition_to(PlayerState.IDLE)
		return

	# Recovery phase (last 1 - DODGE_MOVE_FRACTION of the clip): the
	# character lands in a crouch and stands up. Stay in DODGING so the
	# animation keeps playing, but stop applying velocity — sliding
	# through the crouch+rise while no foot motion is visible looked
	# bad. animation_finished will transition us to IDLE when the clip
	# actually completes.
	if dodge_timer >= dodge_move_end:
		velocity.x = 0
		velocity.z = 0
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


# The PSO dodge animations (e.g. pmsa_esc_f) have ~4m of root-bone Z
# translation baked in that does NOT return to zero by the final frame
# (z≈4.36 at end of pmsa_esc_f). The game already drives the CharacterBody3D
# forward via gameplay velocity (DODGE_SPEED × DODGE_DURATION = ~4m), so the
# animation root motion compounded with that. Worse, the wait animation has
# no root translation track, so when the AnimationPlayer transitions from
# _esc_f → _wait the root bone snapped from z=4.36 back to rest pose at 0,
# producing a large visible slide at the end of the roll. Stripping the
# 000_Root translation track at load time leaves the rest of the animation
# (limb poses, hip drop, body curl) intact, while letting velocity be the
# sole source of horizontal motion.
func _strip_root_translation_track(anim: Animation, skeleton_name: String) -> void:
	var target_path := "%s:000_Root" % skeleton_name
	for i in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		if String(anim.track_get_path(i)) == target_path:
			anim.remove_track(i)
			return


func _start_attack() -> void:
	if current_state == PlayerState.ATTACKING:
		# Check if we're in combo window
		var max_combo: int = int(CombatManager.get_weapon_type_config(_get_equipped_weapon_type()).get("combo_steps", 3))
		if combo_window_open and combo_state < max_combo:
			combo_state += 1
			combo_window_open = false
			_is_special_attack = false
			_combo_ring_flash(Color(0.2, 1.0, 0.4))  # Green flash on chain
			_play_attack_animation(combo_state)
		return

	# Start fresh attack combo
	combo_state = 1
	combo_window_open = false
	_is_special_attack = false
	transition_to(PlayerState.ATTACKING)
	_play_attack_animation(combo_state)


func _on_palette_pressed(slot: int) -> void:
	if current_state == PlayerState.DAMAGED or current_state == PlayerState.DOWN:
		return
	var action_id: String = ActionPalette.get_action_for_slot(slot)
	if TechniqueManager.TECHNIQUES.has(action_id):
		_charging_slot = slot
		_charging_tech_id = action_id
		_tech_charge_timer = 0.0
		_tech_charge_ready = false
		tech_charge_started.emit(slot)
	else:
		_execute_palette_action(slot)


func _on_palette_released(slot: int) -> void:
	if _charging_slot != slot:
		return
	var tech_id: String = _charging_tech_id
	var charged: bool = _tech_charge_ready
	_charging_slot = -1
	_charging_tech_id = ""
	_tech_charge_timer = 0.0
	_tech_charge_ready = false
	_end_charge_visual()
	tech_charge_released.emit(slot)
	if charged:
		var charged_id: String = TechniqueManager.get_charged_technique(tech_id)
		_cast_technique(charged_id)
	else:
		_cast_technique(tech_id)


func _execute_palette_action(slot: int) -> void:
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
		"monomate", "dimate", "trimate", "monofluid", "difluid", "trifluid", \
		"sol_atomizer", "star_atomizer", "moon_atomizer", "telepipe":
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
	print("[Player] Cast %s: damage=%d pp_cost=%d" % [technique_id, int(tech_data.get("damage", 0)), pp_cost])

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

	# Set element for status effect procs
	_current_attack_element = str(tech_data.get("element", ""))
	var character = CharacterManager.get_active_character()
	_current_attack_element_level = 0
	if character:
		_current_attack_element_level = TechniqueManager.get_technique_level(character, technique_id)

	match technique_id:
		"foie":
			_spawn_foie(spawn_pos, forward, damage, kb)
		"gifoie":
			_spawn_gifoie(damage, kb)
		"rafoie":
			_spawn_rafoie(spawn_pos, forward, damage, kb)
		"barta":
			_spawn_barta(spawn_pos, forward, damage, kb)
		"gibarta":
			_spawn_gibarta(spawn_pos, forward, damage, kb)
		"rabarta":
			_spawn_rabarta(damage, kb)
		"zonde":
			_spawn_zonde(damage, kb)
		"gizonde":
			_spawn_gizonde(damage, kb)
		"razonde":
			_spawn_razonde(damage, kb)
		_:
			# Fallback: fire a basic projectile for unimplemented techniques
			_spawn_foie(spawn_pos, forward, damage, kb)


func _apply_element_to_proj(proj: Projectile) -> void:
	proj.element = _current_attack_element
	proj.element_level = _current_attack_element_level


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
	_apply_element_to_proj(proj)
	get_tree().current_scene.add_child(proj)
	proj.global_position = spawn_pos


func _spawn_barta(spawn_pos: Vector3, forward: Vector3, damage: int, kb: float) -> void:
	var proj := Projectile.new()
	proj.damage = damage
	proj.knockback = kb
	proj.accuracy = 100
	proj.direction = forward
	proj.max_range = 15.0
	proj.owner_node = self
	proj.speed = 20.0
	proj.pierce = true
	proj.max_hits = 0  # Unlimited — Barta runs the full length of the cone
	proj.color = Color(0.3, 0.7, 1.0)
	var ground_pos := Vector3(spawn_pos.x, global_position.y + 0.3, spawn_pos.z)
	_apply_element_to_proj(proj)
	get_tree().current_scene.add_child(proj)
	proj.global_position = ground_pos


func _spawn_gifoie(damage: int, kb: float) -> void:
	# Single fireball that spirals outward from the caster — orbits 2-3 times
	# with increasing radius, hitting everything in its path, then fizzles
	var spiral := _GifoieSpiral.new()
	spiral.caster = self
	spiral.damage = damage
	spiral.knockback = kb
	spiral.accuracy = 100
	spiral.element = _current_attack_element
	spiral.element_level = _current_attack_element_level
	spiral.start_angle = player_rotation
	get_tree().current_scene.add_child(spiral)
	spiral.global_position = global_position + Vector3(0, 1.0, 0)


class _GifoieSpiral extends Area3D:
	var caster: Node3D
	var damage: int = 10
	var knockback: float = 3.0
	var accuracy: int = 100
	var element: String = ""
	var element_level: int = 0
	var start_angle: float = 0.0

	const ROTATION_SPEED := 12.0   # Radians/sec — how fast it orbits
	const EXPAND_SPEED := 2.0      # Units/sec — how fast radius grows
	const MAX_RADIUS := 5.0        # Fizzle distance
	const FIZZLE_START := 4.0      # Start shrinking at this radius

	var _angle: float = 0.0
	var _radius: float = 0.3
	var _mesh: MeshInstance3D
	var _mat: StandardMaterial3D
	var _hit_targets: Array = []

	func _ready() -> void:
		_angle = start_angle
		collision_layer = 0
		collision_mask = 32  # Hurtboxes
		monitoring = true
		monitorable = false
		area_entered.connect(_on_area_entered)

		# Visual
		_mesh = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.2
		sphere.height = 0.4
		sphere.radial_segments = 8
		sphere.rings = 4
		_mesh.mesh = sphere
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(1.0, 0.4, 0.05)
		_mat.emission_enabled = true
		_mat.emission = Color(1.0, 0.3, 0.0)
		_mat.emission_energy_multiplier = 3.0
		_mesh.material_override = _mat
		add_child(_mesh)

		# Collision
		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.3
		col.shape = shape
		add_child(col)

	func _physics_process(delta: float) -> void:
		if not is_instance_valid(caster):
			queue_free()
			return

		# Orbit: increase angle and radius each frame
		_angle += ROTATION_SPEED * delta
		_radius += EXPAND_SPEED * delta

		# Position relative to caster
		var offset := Vector3(sin(_angle), 0, cos(_angle)) * _radius
		global_position = caster.global_position + Vector3(0, 1.0, 0) + offset

		# Fizzle: shrink and fade near max radius
		if _radius > FIZZLE_START:
			var fizzle_t: float = (_radius - FIZZLE_START) / (MAX_RADIUS - FIZZLE_START)
			var scale_val: float = maxf(1.0 - fizzle_t, 0.05)
			_mesh.scale = Vector3(scale_val, scale_val, scale_val)
			_mat.albedo_color.a = scale_val

		if _radius >= MAX_RADIUS:
			queue_free()

	func _on_area_entered(area: Area3D) -> void:
		if area is Hurtbox:
			var hurtbox := area as Hurtbox
			if hurtbox.owner_node == caster:
				return
			if hurtbox.owner_node in _hit_targets:
				return
			_hit_targets.append(hurtbox.owner_node)
			var hit_dir: Vector3 = (hurtbox.owner_node.global_position - caster.global_position).normalized()
			hurtbox.take_hit(damage, hit_dir * knockback, accuracy, element, element_level)


func _spawn_rafoie(_spawn_pos: Vector3, _forward: Vector3, damage: int, kb: float) -> void:
	# Explosion on targeted enemy — damages target + nearby enemies in radius
	if _targeted_enemies.is_empty():
		print("[Player] Rafoie: no target")
		return
	var target_enemy = _targeted_enemies[0]
	if not is_instance_valid(target_enemy):
		return
	var explosion_pos: Vector3 = target_enemy.global_position
	var explosion_radius := 5.0

	# Full damage to primary target
	if target_enemy.hurtbox:
		var hit_dir: Vector3 = (target_enemy.global_position - global_position).normalized()
		target_enemy.hurtbox.take_hit(damage, hit_dir * kb, 100, _current_attack_element, _current_attack_element_level)

	# Reduced damage to nearby enemies
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy == target_enemy:
			continue
		if not enemy.get("is_alive"):
			continue
		var dist: float = enemy.global_position.distance_to(explosion_pos)
		if dist <= explosion_radius and enemy.hurtbox:
			var splash_dir: Vector3 = (enemy.global_position - explosion_pos).normalized()
			enemy.hurtbox.take_hit(int(damage * 0.6), splash_dir * kb, 100, _current_attack_element, _current_attack_element_level)

	_spawn_aoe_visual(explosion_pos, Color(1.0, 0.3, 0.05), explosion_radius)


func _spawn_gibarta(spawn_pos: Vector3, _forward: Vector3, damage: int, kb: float) -> void:
	# Ice flamethrower — 3 waves of 3 fan projectiles (pierce)
	_spawn_gibarta_wave(spawn_pos, damage, kb)
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_callback(_spawn_gibarta_wave.bind(spawn_pos, damage, kb))
	tw.tween_interval(0.15)
	tw.tween_callback(_spawn_gibarta_wave.bind(spawn_pos, damage, kb))


func _spawn_gibarta_wave(spawn_pos: Vector3, damage: int, kb: float) -> void:
	for i in range(3):
		var angle_offset: float = (i - 1) * 0.12
		var rot := player_rotation + angle_offset
		var dir := Vector3(sin(rot), 0, cos(rot))
		var proj := Projectile.new()
		proj.damage = damage
		proj.knockback = kb
		proj.accuracy = 100
		proj.direction = dir
		proj.max_range = 10.0
		proj.owner_node = self
		proj.speed = 18.0
		proj.pierce = true
		proj.max_hits = 0  # Unlimited — Gibarta wave traverses the full cone
		proj.color = Color(0.3, 0.7, 1.0)
		var ground_pos := Vector3(spawn_pos.x, global_position.y + 0.3, spawn_pos.z)
		_apply_element_to_proj(proj)
		get_tree().current_scene.add_child(proj)
		proj.global_position = ground_pos


func _spawn_rabarta(damage: int, kb: float) -> void:
	# Ice shards in a circle around the user — pierce, largest ice AoE
	var num_shards := 10
	for i in range(num_shards):
		var angle: float = i * TAU / float(num_shards)
		var dir := Vector3(sin(angle), 0, cos(angle))
		var proj := Projectile.new()
		proj.damage = damage
		proj.knockback = kb
		proj.accuracy = 100
		proj.direction = dir
		proj.max_range = 8.0
		proj.owner_node = self
		proj.speed = 12.0
		proj.pierce = true
		proj.max_hits = 0  # Unlimited — Rabarta shards traverse outward
		proj.color = Color(0.5, 0.8, 1.0)
		_apply_element_to_proj(proj)
		get_tree().current_scene.add_child(proj)
		proj.global_position = global_position + Vector3(0, 0.3, 0)


func _spawn_zonde(damage: int, kb: float) -> void:
	if _targeted_enemies.is_empty():
		print("[Player] Zonde: no target")
		return
	var target_enemy = _targeted_enemies[0]
	if not is_instance_valid(target_enemy):
		return
	if target_enemy.hurtbox:
		var forward := Vector3(sin(player_rotation), 0, cos(player_rotation))
		target_enemy.hurtbox.take_hit(damage, forward * kb, 100, _current_attack_element, _current_attack_element_level)
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


func _spawn_gizonde(damage: int, kb: float) -> void:
	# Chain lightning — chains from enemy to enemy in front of the user (up to 10)
	if _targeted_enemies.is_empty():
		print("[Player] Gizonde: no target")
		return
	var primary = _targeted_enemies[0]
	if not is_instance_valid(primary):
		return

	# Hit primary target
	if primary.hurtbox:
		var fwd := Vector3(sin(player_rotation), 0, cos(player_rotation))
		primary.hurtbox.take_hit(damage, fwd * kb, 100, _current_attack_element, _current_attack_element_level)
	_spawn_zonde_visual(primary.global_position)

	# Chain from the last hit enemy to the nearest unhit enemy
	var hit_enemies: Array = [primary]
	var last_hit = primary
	var best_enemy = null
	var best_dist := 0.0
	for _chain in range(9):
		best_enemy = null
		best_dist = 8.0  # Max chain distance
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy) or enemy in hit_enemies:
				continue
			if not enemy.get("is_alive"):
				continue
			var d: float = enemy.global_position.distance_to(last_hit.global_position)
			if d < best_dist and enemy.hurtbox:
				best_dist = d
				best_enemy = enemy
		if best_enemy == null:
			break
		var chain_dir: Vector3 = (best_enemy.global_position - last_hit.global_position).normalized()
		best_enemy.hurtbox.take_hit(damage, chain_dir * kb, 100, _current_attack_element, _current_attack_element_level)
		_spawn_zonde_visual(best_enemy.global_position)
		hit_enemies.append(best_enemy)
		last_hit = best_enemy


func _spawn_razonde(damage: int, kb: float) -> void:
	# Lightning spiral around user — largest range, no target required
	var nearby := _get_enemies_in_radius(12.0)
	for enemy in nearby:
		if enemy.hurtbox:
			var hit_dir: Vector3 = (enemy.global_position - global_position).normalized()
			enemy.hurtbox.take_hit(damage, hit_dir * kb, 100, _current_attack_element, _current_attack_element_level)
		_spawn_zonde_visual(enemy.global_position)
	_spawn_aoe_visual(global_position, Color(0.8, 0.8, 1.0), 12.0)


func _get_enemies_in_radius(radius: float) -> Array:
	var result: Array = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if not enemy.get("is_alive"):
			continue
		var dist: float = enemy.global_position.distance_to(global_position)
		if dist <= radius:
			result.append(enemy)
	return result


func _spawn_aoe_visual(center: Vector3, aoe_color: Color, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := CylinderMesh.new()
	torus.top_radius = radius
	torus.bottom_radius = radius
	torus.height = 0.3
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(aoe_color.r, aoe_color.g, aoe_color.b, 0.4)
	mat.emission_enabled = true
	mat.emission = aoe_color
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	get_tree().current_scene.add_child(ring)
	ring.global_position = center + Vector3(0, 0.2, 0)
	var tween := ring.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tween.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 0.5)
	tween.tween_callback(ring.queue_free)


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
	if current_state == PlayerState.DODGING:
		return

	# Set weapon element for the special attack
	var character = CharacterManager.get_active_character()
	if character:
		var weapon_id: String = str(character.get("equipment", {}).get("weapon", ""))
		var ws: Dictionary = character.get("weapon_stats", {}).get(weapon_id, {})
		_current_attack_element = str(ws.get("element", ""))
		_current_attack_element_level = int(ws.get("element_level", 0))

	if current_state == PlayerState.ATTACKING:
		# Chain into combo like normal attack, but flagged as special
		var max_combo: int = int(CombatManager.get_weapon_type_config(_get_equipped_weapon_type()).get("combo_steps", 3))
		if combo_window_open and combo_state < max_combo:
			combo_state += 1
			combo_window_open = false
			_is_special_attack = true
			_combo_ring_flash(Color(1.0, 0.8, 0.2))  # Yellow flash for special chain
			_play_attack_animation(combo_state)
		return

	# Start fresh combo step 1 as special
	combo_state = 1
	combo_window_open = false
	_is_special_attack = true
	transition_to(PlayerState.ATTACKING)
	_play_attack_animation(combo_state)


func _use_consumable(item_id: String) -> void:
	if current_state == PlayerState.ATTACKING or current_state == PlayerState.DODGING:
		return
	if Inventory.use_item(item_id):
		var info: Dictionary = Inventory.get_last_use_info()
		var use_type: String = str(info.get("type", ""))
		var amount: int = int(info.get("amount", 0))
		_spawn_heal_number(use_type, amount)
	else:
		print("[Player] Cannot use %s" % item_id)


func _spawn_heal_number(heal_type: String, amount: int) -> void:
	var label := Label3D.new()
	if heal_type == "hp":
		label.text = "+%d HP" % amount
		label.modulate = Color(0.3, 1.0, 0.3)
	else:
		label.text = "+%d PP" % amount
		label.modulate = Color(0.3, 0.6, 1.0)
	label.font_size = 48
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 6
	label.outline_modulate = Color(0, 0, 0)
	label.position = Vector3(0, 2.5, 0)
	add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", 3.5, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


func _handle_attack_state(delta: float) -> void:
	# Track animation elapsed for mid-animation combo window
	_attack_anim_elapsed += delta

	# Open combo window at the rhythm point (% of animation)
	if not _combo_window_opened and _attack_anim_length > 0:
		var max_combo: int = int(CombatManager.get_weapon_type_config(_get_equipped_weapon_type()).get("combo_steps", 3))
		if combo_state > 0 and combo_state < max_combo:
			var open_at: float = _attack_anim_length * COMBO_WINDOW_OPEN_PCT
			if _attack_anim_elapsed >= open_at:
				combo_window_open = true
				combo_timer = 0.0
				_combo_window_opened = true

	# Handle combo window timeout
	if combo_window_open:
		combo_timer += delta
		if combo_timer >= COMBO_WINDOW_DURATION:
			# Missed the rhythm window — combo resets
			combo_window_open = false
			combo_state = 0
			_deactivate_attack_hitbox()
			_combo_ring_flash(Color(1.0, 0.2, 0.2))  # Red flash on miss
			transition_to(PlayerState.IDLE)

	# Update visuals
	_update_combo_ring(delta)
	_update_charge_visual(delta)

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


const SPECIAL_ATTACK_DELAY := 0.4  # Seconds of pause before special attack animation

func _play_attack_animation(attack_num: int) -> void:
	var anim_name := _anim_prefix + "_atk" + str(attack_num)
	_combo_window_opened = false
	_attack_anim_elapsed = 0.0
	_attack_anim_length = 0.0

	if _is_special_attack:
		# Pause before attack — player is exposed during wind-up
		play_animation(_anim_prefix + "_wait", true)
		_start_charge_visual()
		var tw := create_tween()
		tw.tween_interval(SPECIAL_ATTACK_DELAY)
		tw.tween_callback(_end_charge_visual)
		tw.tween_callback(_play_and_track_attack.bind(anim_name))
	else:
		_play_and_track_attack(anim_name)


## Weapon type → SFX glob pattern
const WEAPON_SFX := {
	WeaponData.WeaponType.SABER: "res://assets/sfx/weapons/saber_swing_*.wav",
	WeaponData.WeaponType.SWORD: "res://assets/sfx/weapons/sword_swing_*.wav",
	WeaponData.WeaponType.DAGGERS: "res://assets/sfx/weapons/dagger_swing_*.wav",
	WeaponData.WeaponType.CLAW: "res://assets/sfx/weapons/dagger_swing_*.wav",
	WeaponData.WeaponType.DOUBLE_SABER: "res://assets/sfx/weapons/saber_swing_*.wav",
	WeaponData.WeaponType.SPEAR: "res://assets/sfx/weapons/spear_swing_*.wav",
	WeaponData.WeaponType.SLICER: "res://assets/sfx/weapons/slicer_swing_*.wav",
	WeaponData.WeaponType.GUN_BLADE: "res://assets/sfx/weapons/saber_swing_*.wav",
	WeaponData.WeaponType.SHIELD: "res://assets/sfx/weapons/saber_swing_*.wav",
	WeaponData.WeaponType.HANDGUN: "res://assets/sfx/weapons/handgun_shot_*.wav",
	WeaponData.WeaponType.RIFLE: "res://assets/sfx/weapons/rifle_shot_*.wav",
	WeaponData.WeaponType.MECH_GUN: "res://assets/sfx/weapons/mechgun_shot_*.wav",
	WeaponData.WeaponType.ROD: "res://assets/sfx/weapons/rod_swing_*.wav",
	WeaponData.WeaponType.WAND: "res://assets/sfx/weapons/rod_swing_*.wav",
}

func _play_and_track_attack(anim_name: String) -> void:
	play_animation(anim_name, false)
	_attack_anim_elapsed = 0.0
	_combo_window_opened = false
	# Get animation length for rhythm window timing
	if animation_player and animation_player.has_animation(anim_name):
		_attack_anim_length = animation_player.get_animation(anim_name).length
	else:
		_attack_anim_length = 0.5  # Fallback
	_activate_attack_hitbox()
	# Play weapon SFX
	var wtype: int = _get_equipped_weapon_type()
	var sfx_pattern: String = WEAPON_SFX.get(wtype, "")
	if not sfx_pattern.is_empty():
		SfxManager.play_random_at(sfx_pattern, global_position)


func _ensure_combo_ring() -> void:
	if _combo_ring:
		return
	_combo_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	torus.rings = 16
	torus.ring_segments = 24
	_combo_ring.mesh = torus
	_combo_ring_mat = StandardMaterial3D.new()
	_combo_ring_mat.albedo_color = Color(0.2, 1.0, 0.4, 0.7)
	_combo_ring_mat.emission_enabled = true
	_combo_ring_mat.emission = Color(0.2, 1.0, 0.4)
	_combo_ring_mat.emission_energy_multiplier = 1.5
	_combo_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_combo_ring_mat.no_depth_test = true
	_combo_ring.material_override = _combo_ring_mat
	_combo_ring.visible = false
	add_child(_combo_ring)


func _update_combo_ring(_delta: float) -> void:
	if not DebugConfig.show_combo_timing:
		if _combo_ring:
			_combo_ring.visible = false
		return

	_ensure_combo_ring()

	if combo_window_open:
		_combo_ring.visible = true
		_combo_ring.global_position = global_position + Vector3(0, 0.05, 0)
		# Shrink as the window closes
		var pct: float = 1.0 - (combo_timer / COMBO_WINDOW_DURATION)
		var ring_scale: float = 0.5 + pct * 0.5  # 1.0 → 0.5
		_combo_ring.scale = Vector3(ring_scale, 0.3, ring_scale)
		_combo_ring_mat.albedo_color = Color(0.2, 1.0, 0.4, 0.5 + pct * 0.3)
		_combo_ring_mat.emission = Color(0.2, 1.0, 0.4)
	else:
		if _combo_ring and _combo_ring.visible:
			_combo_ring.visible = false


func _combo_ring_flash(flash_color: Color) -> void:
	if not DebugConfig.show_combo_timing:
		return
	_ensure_combo_ring()
	_combo_ring.visible = true
	_combo_ring.global_position = global_position + Vector3(0, 0.05, 0)
	_combo_ring.scale = Vector3(0.8, 0.3, 0.8)
	_combo_ring_mat.albedo_color = Color(flash_color.r, flash_color.g, flash_color.b, 0.8)
	_combo_ring_mat.emission = flash_color
	var tw := create_tween()
	tw.tween_property(_combo_ring_mat, "albedo_color:a", 0.0, 0.3)
	tw.tween_callback(func(): _combo_ring.visible = false)


## Element → charge color mapping
const ELEMENT_CHARGE_COLORS := {
	"fire": Color(1.0, 0.4, 0.1),
	"ice": Color(0.3, 0.6, 1.0),
	"lightning": Color(1.0, 1.0, 0.3),
	"dark": Color(0.6, 0.1, 0.8),
	"light": Color(1.0, 1.0, 0.8),
	"none": Color(0.8, 0.8, 0.8),
}


func _start_charge_visual() -> void:
	_charge_color = ELEMENT_CHARGE_COLORS.get(_current_attack_element, Color(0.8, 0.8, 0.8))
	_charge_active = true
	_charge_timer = 0.0

	# 1. Expanding ring at feet
	if not _charge_ring:
		_charge_ring = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.6
		torus.outer_radius = 0.8
		torus.rings = 16
		torus.ring_segments = 24
		_charge_ring.mesh = torus
		_charge_ring_mat = StandardMaterial3D.new()
		_charge_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_charge_ring_mat.no_depth_test = true
		_charge_ring.material_override = _charge_ring_mat
		add_child(_charge_ring)
	_charge_ring_mat.albedo_color = Color(_charge_color.r, _charge_color.g, _charge_color.b, 0.6)
	_charge_ring_mat.emission_enabled = true
	_charge_ring_mat.emission = _charge_color
	_charge_ring_mat.emission_energy_multiplier = 2.0
	_charge_ring.scale = Vector3(0.2, 0.3, 0.2)
	_charge_ring.global_position = global_position + Vector3(0, 0.05, 0)
	_charge_ring.visible = true

	# 2. Glow on player model (uses cached material references)
	for mat in _cached_materials:
		mat.emission_enabled = true
		mat.emission = _charge_color
		mat.emission_energy_multiplier = 0.5

	# 3. Particles
	if not _charge_particles:
		_charge_particles = GPUParticles3D.new()
		var particle_mat := ParticleProcessMaterial.new()
		particle_mat.direction = Vector3(0, 1, 0)
		particle_mat.spread = 180.0
		particle_mat.initial_velocity_min = 1.0
		particle_mat.initial_velocity_max = 2.5
		particle_mat.gravity = Vector3(0, 1, 0)
		particle_mat.scale_min = 0.05
		particle_mat.scale_max = 0.12
		_charge_particles.process_material = particle_mat
		var sphere := SphereMesh.new()
		sphere.radius = 0.04
		sphere.height = 0.08
		_charge_particles.draw_pass_1 = sphere
		_charge_particles.amount = 20
		_charge_particles.lifetime = 0.4
		_charge_particles.explosiveness = 0.3
		add_child(_charge_particles)

	# Set particle color
	var p_mat: ParticleProcessMaterial = _charge_particles.process_material as ParticleProcessMaterial
	p_mat.color = _charge_color
	_charge_particles.global_position = global_position + Vector3(0, 0.8, 0)
	_charge_particles.visible = true
	_charge_particles.emitting = true


func _end_charge_visual() -> void:
	_charge_active = false

	# Fade out ring
	if _charge_ring:
		var tw := create_tween()
		tw.tween_property(_charge_ring_mat, "albedo_color:a", 0.0, 0.15)
		tw.tween_callback(func(): _charge_ring.visible = false)

	# Remove model glow (uses cached material references)
	for mat in _cached_materials:
		mat.emission_enabled = false
		mat.emission_energy_multiplier = 0.0

	# Stop particles
	if _charge_particles:
		_charge_particles.emitting = false


func _update_charge_visual(delta: float) -> void:
	if not _charge_active:
		return
	_charge_timer += delta
	var pct: float = _charge_timer / SPECIAL_ATTACK_DELAY

	# Expand ring during charge
	if _charge_ring and _charge_ring.visible:
		var ring_scale: float = 0.2 + pct * 0.8  # 0.2 → 1.0
		_charge_ring.scale = Vector3(ring_scale, 0.3, ring_scale)
		_charge_ring.global_position = global_position + Vector3(0, 0.05, 0)

	# Intensify model glow (uses cached material references)
	for mat in _cached_materials:
		if mat.emission_enabled:
			mat.emission_energy_multiplier = 0.5 + pct * 1.5

	# Update particle position
	if _charge_particles:
		_charge_particles.global_position = global_position + Vector3(0, 0.8, 0)


func transition_to(new_state: PlayerState) -> void:
	if _charging_slot >= 0 and new_state in [PlayerState.DAMAGED, PlayerState.DOWN]:
		var slot := _charging_slot
		_charging_slot = -1
		_charging_tech_id = ""
		_tech_charge_timer = 0.0
		_tech_charge_ready = false
		_end_charge_visual()
		tech_charge_released.emit(slot)
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
			# Zero horizontal velocity so dodge/attack carry-over doesn't
			# slide the character into the wait pose. Y is preserved so
			# gravity / falling continues to read correctly.
			velocity.x = 0
			velocity.z = 0
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
				# Final combo step finished
				combo_state = 0
				transition_to(PlayerState.IDLE)
			elif combo_window_open:
				# Window is still open — let the timer in _handle_attack_state close it
				pass
			else:
				# Window was missed or never opened — combo resets
				combo_state = 0
				transition_to(PlayerState.IDLE)
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

	# Player hit SFX
	if damage > 10:
		SfxManager.play_at("res://assets/sfx/player/take_hard_hit.wav", global_position)
	else:
		SfxManager.play_at("res://assets/sfx/player/take_hit.wav", global_position)

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


const RANGED_WEAPON_TYPES := [6, 9, 10, 11, 12]  # SLICER, HANDGUN, MECH_GUN, RIFLE, BAZOOKA


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
		# Special attacks carry weapon element for status procs
		if _is_special_attack:
			attack_hitbox.element = _current_attack_element
			attack_hitbox.element_level = _current_attack_element_level
		else:
			attack_hitbox.element = ""
			attack_hitbox.element_level = 0
		attack_hitbox.activate()


func _fire_projectile(atk: Dictionary) -> void:
	var config: Dictionary = CombatManager.get_weapon_type_config(int(atk.get("weapon_type", 0)))
	var forward := Vector3(sin(player_rotation), 0, cos(player_rotation))
	var spawn_pos := global_position + Vector3(0, 1.0, 0) + forward * 0.5
	var max_range: float = float(config.get("hitbox_offset", 8.0)) + float(config.get("hitbox_size", Vector3(1, 1, 1)).z)
	var hits: int = int(atk.get("hits", 1))

	var weapon_type: int = int(atk.get("weapon_type", 0))

	for i in range(hits):
		var proj := Projectile.new()
		proj.damage = int(atk.get("damage", 10))
		proj.knockback = float(atk.get("knockback", 3.0))
		proj.accuracy = int(atk.get("accuracy", 100))
		proj.direction = forward
		proj.max_range = max_range
		proj.owner_node = self
		proj.speed = 25.0
		proj.max_hits = int(config.get("max_targets", 1))

		# Slicer: throwing blade aimed at target, bounces to nearby enemies
		if weapon_type == WeaponData.WeaponType.SLICER:
			proj.pierce = true
			proj.bounce_radius = 3.0
			proj.max_hits = 4
			proj.speed = 20.0
			proj.color = Color(0.7, 0.9, 1.0)
			# Semi-homing: aim at the targeted enemy instead of straight forward
			if not _targeted_enemies.is_empty() and is_instance_valid(_targeted_enemies[0]):
				var to_target: Vector3 = _targeted_enemies[0].global_position - spawn_pos
				to_target.y = 0  # Keep horizontal
				if to_target.length() > 0.5:
					proj.direction = to_target.normalized()
			# Spawn at enemy height so it doesn't fly over short targets
			spawn_pos.y = global_position.y + 0.6

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


func _get_technique_targeting() -> Dictionary:
	## Check current palette slots for techniques and return extended targeting params.
	if not _tech_targeting_dirty and not _cached_tech_targeting.is_empty():
		return _cached_tech_targeting
	_tech_targeting_dirty = false
	var slots: Array = ActionPalette.get_current_slots()
	var best_range := 0.0
	var best_width := 0.0
	var has_zonde := false
	for action_id in slots:
		if not TechniqueManager.TECHNIQUES.has(action_id):
			continue
		var character = CharacterManager.get_active_character()
		if character and TechniqueManager.get_technique_level(character, action_id) <= 0:
			continue
		match action_id:
			"foie", "gifoie", "rafoie":
				best_range = maxf(best_range, 15.0)
				best_width = maxf(best_width, 1.0)
			"barta", "gibarta", "rabarta":
				best_range = maxf(best_range, 15.0)
				best_width = maxf(best_width, 1.0)
			"zonde", "gizonde", "razonde":
				has_zonde = true
				best_range = maxf(best_range, 12.0)
				best_width = maxf(best_width, 4.0)
			_:
				best_range = maxf(best_range, 10.0)
				best_width = maxf(best_width, 2.0)
	_cached_tech_targeting = {"range": best_range, "half_width": best_width * 0.5, "has_zonde": has_zonde}
	return _cached_tech_targeting


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
	var weapon_range: float = hitbox_offset + hitbox_size.z * 0.5
	var weapon_half_width: float = hitbox_size.x * 0.5 + 0.5

	# Extend targeting to cover equipped techniques
	var tech_targeting: Dictionary = _get_technique_targeting()
	var attack_range: float = maxf(weapon_range, float(tech_targeting.get("range", 0.0)))
	var half_width: float = maxf(weapon_half_width, float(tech_targeting.get("half_width", 0.0)))
	var has_zonde: bool = tech_targeting.get("has_zonde", false)

	# Player's forward direction (model rotation)
	var forward := Vector3(sin(player_rotation), 0, cos(player_rotation))

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
		var box_depth: float = attack_range
		_debug_range_mesh.scale = Vector3(half_width * 2.0, hitbox_size.y, box_depth)
		_debug_range_mesh.position = Vector3(0, hitbox_size.y * 0.5 + 0.5, box_depth * 0.5)
		_debug_range_mesh.visible = true
	elif _debug_range_mesh:
		_debug_range_mesh.visible = false

	# Find enemies in front of the player within range
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

		# For Zonde: cone widens with distance
		var effective_width: float = half_width
		if has_zonde and forward_dist > 0:
			effective_width = maxf(half_width, forward_dist * 0.4)

		if lateral_dist > effective_width:
			continue

		candidates.append({"enemy": enemy, "dist": forward_dist})

	# Sort by distance
	candidates.sort_custom(func(a, b): return a.dist < b.dist)

	# Techniques can target more enemies than the weapon allows
	var effective_max: int = max_targets
	if float(tech_targeting.get("range", 0.0)) > 0:
		effective_max = maxi(max_targets, 3)

	# Show reticle on closest N enemies
	for i in range(mini(effective_max, candidates.size())):
		var enemy = candidates[i].enemy
		if enemy.has_method("show_reticle"):
			enemy.show_reticle()
		_targeted_enemies.append(enemy)

	# Slicer: show secondary reticles for bounce targets near the primary
	if weapon_type == WeaponData.WeaponType.SLICER and not _targeted_enemies.is_empty():
		var primary = _targeted_enemies[0]
		var bounce_count := 0
		for c in candidates:
			if bounce_count >= 3:
				break
			if c.enemy == primary or c.enemy in _targeted_enemies:
				continue
			var dist_to_primary: float = c.enemy.global_position.distance_to(primary.global_position)
			if dist_to_primary <= 3.0 and c.enemy.has_method("show_reticle"):
				c.enemy.show_reticle()
				_targeted_enemies.append(c.enemy)
				bounce_count += 1

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

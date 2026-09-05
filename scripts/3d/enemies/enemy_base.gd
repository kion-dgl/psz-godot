class_name EnemyBase extends CharacterBody3D
## Base class for all enemies. Uses EnemyData resource for stats.

## Enemy data resource (set in inspector or via spawn)
@export var enemy_data: Resource  # EnemyData

## Current HP
var current_hp: int = 100

## Defense stat (from EnemyData)
var current_defense: int = 5

## Evasion stat (from EnemyData)
var current_evasion: int = 30

## Is enemy alive?
var is_alive: bool = true

## Dormant spawn (free-field parity): in the original, a room's enemies
## materialise when the player walks in — they are not standing there waiting.
## A dormant enemy is hidden, runs no AI, and cannot be hit; `reveal()` brings
## it in with a spawn effect and start animation. Set BEFORE the node enters
## the tree (the spawner does), so _ready() can hide it during setup.
var dormant := false

## Seconds after reveal the enemy holds still while the start animation plays.
var _spawn_lock := 0.0
const SPAWN_LOCK_SEC := 0.8

## Target to chase (usually the player)
var target: Node3D

## State machine
enum EnemyState {
	IDLE,
	CHASING,
	ATTACKING,
	LOAFING,  # Backing off after attack
	HURT,
	DEAD,
}
var current_state: EnemyState = EnemyState.IDLE

## Components
var hurtbox: Hurtbox
var model: Node3D
var nav_agent: NavigationAgent3D
var animation_player: AnimationPlayer

## Attack tracking
var attack_cooldown_timer: float = 0.0
var hurt_timer: float = 0.0
const HURT_DURATION: float = 0.3

## Animation state tracking
var is_attacking: bool = false
var current_anim: String = ""
## Resolved (full) name of the attack animation in flight — attack end is
## detected against this, never by parsing a suffix out of the finished
## signal (big rigs name the clip atk1/atckwat and used to wedge ATTACKING
## until a hit forced HURT — #477, spec /states/enemies).
var _attack_anim: String = ""
## Ticks down when no attack animation resolved at all (armadillo has none).
var _attack_fallback_timer: float = 0.0
const ATTACK_FALLBACK_DURATION: float = 0.8

## Frame-tied attack model (#509, spec /mechanics/enemy-attacks). The instant
## hardcoded-10 hit is replaced by: select an attack from data/enemy_attacks.json by
## range band, lock facing at start, then during the clip's damage window run an arc
## test and deal attack_base × damage_mult once.
var _attacks: Array = []                    # resolved attack defs for this enemy (cached)
var _attack_def: Dictionary = {}            # the attack chosen for the swing in flight
var _attack_facing: Vector3 = Vector3.FORWARD  # facing locked at attack start
var _attack_hit_resolved: bool = false      # one resolution (hit or dodge) per attack
var _attack_clip_len: float = ATTACK_FALLBACK_DURATION  # resolved clip length (or fallback)
var _attack_pos: float = 0.0                # position within the attack clip (seconds)
var _rng := RandomNumberGenerator.new()

## Pre-strike telegraph (#491, spec /mechanics/enemy-attacks). ATTACKING opens with a
## readable attack-ready pose held long enough to react — no "walk up, freeze, cheap
## hit". Stance risers rise via stt into a wat2 hold; other rigs hold their idle (wat).
## Damage NEVER lands during telegraph. The hold is TELEGRAPH_HOLD × difficulty reaction
## (Normal generous, higher tiers shorter). Telegraph is a sub-phase of ATTACKING, so the
## 6-state FSM (spec /states/enemies) is unchanged and _start_attack stays the strike.
## ponytail: one hold knob — tune the beat by play-test.
const TELEGRAPH_HOLD: float = 0.7
var _telegraphing: bool = false
var _telegraph_rising: bool = false
var _telegraph_timer: float = 0.0

## Per-archetype locomotion (#494, spec /states/enemies). `_archetype` selects the chase
## behavior (quadruped arc-circle, quad_machine/shooter/roller standoff-hold, else the
## baseline straight chase); `_fsm` carries standoff_range etc. `_arc_side` (±1) is the
## circling/strafe side, re-picked on `_arc_timer`; `_chase_mode` is the quadruped
## arc↔dash sub-mode. Movement math is ported in EnemyLocomotionLogic (fsm.ts).
var _archetype: String = "simple_melee"
var _fsm: Dictionary = {}
var _arc_side: float = 1.0
var _arc_timer: float = 0.0
var _chase_mode: String = "arc"
## Player collision radius used by the arc test (the target's radius). Real value isn't
## exposed cheaply; melee reach dwarfs it, so a constant is fine.
## ponytail: constant player radius, read the real shape if arc precision ever matters.
const PLAYER_HIT_RADIUS: float = 0.5

## Delivery kinds + authored telegraphs (#629, spec /mechanics/enemy-attacks "kind" /
## "windup_clips"). Port of fsm.ts startAttack/processAttackCharge: projectile/lob are
## released once at window open and resolve at impact/landing; charge runs its own
## st → lp → ed segment machine (the segments ARE the timeline); leap travels the enemy
## itself to the target's window-open position and lands for area damage at window
## close. windup_clips play sequentially as pure telegraph before the attack clip, with
## the timeline fractions offset past them. Until now every kind collapsed to the
## instant melee arc (#494 interim) — these are the travel mechanics proper.
const CHARGE_SEGMENT_FALLBACK: float = 0.4  # fsm.ts stDur/edDur fallback; windup clip fallback
const CHARGE_MAX_LP_TIME: float = 8.0       # fsm.ts charge loop watchdog
var _attack_kind := "melee_arc"
var _window_opened := false                 # damaging window opened (ranged release point)
var _window_closed := false                 # damaging window closed (leap landing point)
var _windup_clips: Array = []               # [{token, end}] sequential telegraph preludes
var _windup_total := 0.0                    # their resolved total duration
var _windup_elapsed := 0.0
var _windup_idx := -1                       # prelude clip currently playing
var _windup_done := true                    # false only while the prelude plays
var _leap_from := Vector3.ZERO              # kind leap: enemy travels during the window
var _leap_to := Vector3.ZERO
var _charge: Dictionary = {}                # kind charge: phase machine (see _start_charge)
var _vulnerable_mult := 1.0                 # recovery punish window (recovery_vulnerable_mult)

## Berserk kamikaze (spec /states/enemies §shooter): `apply_berserk()` (leader loss —
## wired in _die) plays the atk_an confusion display once, then CHASING loops the
## berserk_only attack's clip straight at the player and self-destructs on contact.
var _berserk := false
var _kamikaze_def: Dictionary = {}

## Aggro display hold (fsm.ts threatTimer): bigrig chest-beat / flyer takeoff / roller
## activate / ape-gunner stand — each its rig's stt, held for the clip before pursuit.
const THREAT_DISPLAY_ARCHETYPES := ["bigrig_combo", "flyer_combo", "roller", "ape_gunner"]
var _threat_timer := 0.0
var _threat_total := 0.0

## Box mimic (spec /states/enemies §box-mimic): dormant disguise ignoring
## detection_range entirely; only fsm.reveal_range breaks it. Holds stt's first frame,
## occasionally sways (wlk2 tell); reveal-cancel retreats into the box (tk2).
var _dormant_timer := 0.0
var _dormant_swaying := false
var _disguise_held := false

## Flyer combo (spec /states/enemies §flyer): shoulder-height hover is the anti-melee
## design — MUST NOT ground while engaged. `_flying` gates the altitude hold; the
## takeoff rises through the aggro display.
var _flying := false
var _ground_y := 0.0

## Entry-level engaged-idle clip for rooted enemies (idle_clip — the lily's waito).
## Entry-level, NOT inside fsm, so it comes through its own registry getter.
var _idle_clip := ""


func _rooted_idle_clip() -> String:
	return _idle_clip if not _idle_clip.is_empty() else "wat"

## Difficulty scaling of aggression + timing (#522, spec /mechanics/enemy-attacks).
## Normal = identity (current passive baseline); higher tiers widen aggro and tighten
## cadence/telegraph. cadence/reaction < 1 = faster attacks / shorter windup.
## ponytail: starting calibration table — tune the three rows by play-test.
const AGGRO_SCALING := {
	"normal":     {"detection": 1.0,  "cadence": 1.0,  "reaction": 1.0},
	"hard":       {"detection": 1.25, "cadence": 0.80, "reaction": 0.85},
	"super-hard": {"detection": 1.5,  "cadence": 0.65, "reaction": 0.70},
}
var _aggro_cadence: float = 1.0
var _aggro_reaction: float = 1.0
var _detection_range: float = 15.0

## Stuck detection — try perpendicular direction when blocked
var _stuck_time: float = 0.0
var _stuck_side: float = 1.0  # 1.0 or -1.0 to try left/right
const STUCK_THRESHOLD := 0.2  # Seconds blocked before trying alternate direction

## Status effects
var _status_effects: Array = []  # [{type: String, timer: float, dot_timer: float, phase: String}]
var _is_immobilized: bool = false  # frozen/stunned(phase1)/sleeping
var _stun_no_attack: bool = false  # stun phase 2: can move, can't attack
const DOT_TICK_INTERVAL := 1.0
## Model tint per timed status — every CombatManager.STATUS_EFFECTS key
## MUST have an entry (test_element_status pins it). Devil is instant and
## tints nothing; its damage number uses its own purple.
const STATUS_COLORS := {
	"freeze": Color(0.5, 0.7, 1.0),
	"burn": Color(1.0, 0.6, 0.3),
	"stun": Color(1.0, 1.0, 0.5),
	"sleep": Color(0.7, 0.5, 0.9),
	"poison": Color(0.5, 0.9, 0.3),
	"slow": Color(0.6, 0.6, 0.8),
	"paralysis": Color(0.95, 0.82, 0.15),
}

## Target reticle (shown when player is targeting this enemy)
var _reticle: Node3D
var _cached_materials: Array = []  # Cached StandardMaterial3D refs for tint updates

## Walk variant cycling — for enemies with wlk_l/wlk_r instead of plain wlk.
## _uses_walk_variants is set to true the first time the fallback fires, so
## the timer only ticks (and forces re-plays) for enemies that actually need it.
var _walk_variant_timer: float = 0.0
var _walk_use_left: bool = false
var _uses_walk_variants: bool = false
const WALK_VARIANT_INTERVAL: float = 1.5  # Switch every 1.5s for circling effect

## Wandering behavior (idle state)
var wander_timer: float = 0.0
var wander_direction: Vector3 = Vector3.ZERO
var is_wandering: bool = false
const WANDER_INTERVAL_MIN: float = 2.0  # Min time before changing direction
const WANDER_INTERVAL_MAX: float = 5.0  # Max time before changing direction
const WANDER_PAUSE_CHANCE: float = 0.3  # Chance to pause instead of walk
const WANDER_SPEED_MULT: float = 0.5  # Wander at half chase speed

## Loafing behavior (semi-circle walk after attack)
var loaf_timer: float = 0.0
var loaf_direction: Vector3 = Vector3.ZERO
var loaf_curve_rate: float = 0.0  # How fast to curve (positive = right, negative = left)
const LOAF_DURATION_MIN: float = 2.5  # Min time to loaf
const LOAF_DURATION_MAX: float = 4.0  # Max time to loaf
const LOAF_SPEED_MULT: float = 0.5  # Loaf at half speed
const LOAF_CURVE_RATE: float = 0.8  # Radians per second to curve path

## Charge behavior (short burst before attack)
const CHARGE_RANGE_MULT: float = 2.0  # Start charging at 2x attack range
const CHARGE_SPEED_MULT: float = 1.5  # Run faster during charge
const WALK_SPEED_MULT: float = 0.5  # Walk at half speed during normal approach

## Movement
const GRAVITY: float = 20.0

## Floor detection (raycast-based) - same as player
const FLOOR_CHECK_DISTANCE: float = 1.0  # How far ahead to check
const FLOOR_CHECK_SIDE: float = 0.5  # Side offset for corner checks
const FLOOR_RAY_LENGTH: float = 5.0  # How far down to raycast

## Enemy SFX keyed by model_id → {damage, death, attack, idle}
const ENEMY_SFX := {
	"wolf": {
		"damage": "res://assets/sfx/forest/forest_020.wav",
		"death": "res://assets/sfx/forest/forest_021.wav",
		"attack": "res://assets/sfx/forest/forest_023.wav",
		"idle": "res://assets/sfx/forest/forest_018.wav",
	},
}

## Signals
signal died(enemy: EnemyBase)
signal damaged(enemy: EnemyBase, amount: int)


var _sfx: Dictionary = {}

func _ready() -> void:
	add_to_group("enemies")
	set_collision_mask_value(2, true)  # Enable player layer collision (preserve other mask bits)
	_setup_from_data()
	_setup_model()
	_setup_hurtbox()
	_setup_navigation()
	_find_target()

	if enemy_data:
		_sfx = ENEMY_SFX.get(enemy_data.model_id, {})
		_attacks = EnemyAttackRegistry.get_attacks(enemy_data.id, enemy_data.attack_range)
		_archetype = EnemyAttackRegistry.get_archetype(enemy_data.id)
		_fsm = EnemyAttackRegistry.get_fsm(enemy_data.id)
		_idle_clip = EnemyAttackRegistry.get_idle_clip(enemy_data.id)
		for a in _attacks:
			if a.get("berserk_only", false):
				_kamikaze_def = a
				break

	_rng.randomize()
	_apply_difficulty()
	_ground_y = global_position.y

	# Randomize initial wander timer so enemies don't sync up
	wander_timer = randf_range(0.0, WANDER_INTERVAL_MAX)
	_setup_reticle()

	if dormant:
		visible = false
		if hurtbox:
			hurtbox.set_deferred("monitorable", false)


func _setup_from_data() -> void:
	if enemy_data:
		current_hp = enemy_data.hp_base
		current_defense = enemy_data.defense_base
		current_evasion = enemy_data.evasion_base
	else:
		push_warning("[Enemy] No enemy_data set!")


func _setup_model() -> void:
	# Find existing Model node (from scene), or load from enemy_data
	model = get_node_or_null("Model")
	if not model and enemy_data and not str(enemy_data.model_id).is_empty():
		var glb_path := "res://assets/enemies/%s/%s.glb" % [enemy_data.model_id, enemy_data.model_id]
		if ResourceLoader.exists(glb_path):
			var packed := load(glb_path) as PackedScene
			if packed:
				model = packed.instantiate()
				model.name = "Model"
				add_child(model)
	if not model:
		return

	# Apply texture if PNG exists alongside GLB
	if enemy_data and not str(enemy_data.model_id).is_empty():
		var tex_path := "res://assets/enemies/%s/%s.png" % [enemy_data.model_id, enemy_data.model_id]
		if ResourceLoader.exists(tex_path):
			var texture := load(tex_path) as Texture2D
			if texture:
				MeshUtils.apply_texture(model, texture)

	# Find AnimationPlayer in the model hierarchy
	animation_player = NodeUtils.first_of_type(model, "AnimationPlayer") as AnimationPlayer

	# Entry-level render scale for oversized source GLBs (spec /mechanics/
	# enemy-attacks: model_scale — poison_lily is 0.09; the runtime applies the
	# same factor the web tool renders with).
	if enemy_data:
		var ms := EnemyAttackRegistry.get_model_scale(enemy_data.id)
		if not is_equal_approx(ms, 1.0):
			model.scale = Vector3.ONE * ms

	# If no animations in the model, load from animation_model_id source
	if animation_player:
		var anim_count: int = animation_player.get_animation_list().size()
		if anim_count == 0:
			animation_player = null  # Discard empty player
		else:
			print("[Enemy] %s has %d animations in model" % [enemy_data.name if enemy_data else "?", anim_count])
	if not animation_player and enemy_data and not str(enemy_data.animation_model_id).is_empty():
		print("[Enemy] %s: loading animations from %s" % [enemy_data.name if enemy_data else "?", enemy_data.animation_model_id])
		var anim_glb_path := "res://assets/enemies/%s/%s.glb" % [enemy_data.animation_model_id, enemy_data.animation_model_id]
		if ResourceLoader.exists(anim_glb_path):
			var anim_scene: PackedScene = load(anim_glb_path)
			if anim_scene:
				var anim_model := anim_scene.instantiate()
				var source_player := NodeUtils.first_of_type(anim_model, "AnimationPlayer") as AnimationPlayer
				if source_player:
					# Find the skeleton parents on both models so we can remap
					# track paths from source mesh root → destination mesh root.
					# Guard get_parent() in case the Skeleton3D ends up at the
					# scene root with no parent (shouldn't happen for these GLBs
					# but is cheap to handle).
					var dst_skel := NodeUtils.first_of_type(model, "Skeleton3D") as Skeleton3D
					var src_skel := NodeUtils.first_of_type(anim_model, "Skeleton3D") as Skeleton3D
					var src_root_name: String = ""
					var dst_root_name: String = ""
					if src_skel and src_skel.get_parent():
						src_root_name = src_skel.get_parent().name
					if dst_skel and dst_skel.get_parent():
						dst_root_name = dst_skel.get_parent().name

					# `model` is the instantiated GLB scene root. Godot's GLB
					# importer puts the AnimationPlayer at this same level as a
					# sibling of the mesh node, so the remapped track paths
					# (which start with the mesh root name) resolve correctly.
					animation_player = AnimationPlayer.new()
					animation_player.name = "AnimPlayer"
					model.add_child(animation_player)
					var lib := AnimationLibrary.new()
					for anim_name in source_player.get_animation_list():
						var anim := source_player.get_animation(anim_name).duplicate() as Animation
						# Remap "src_root/Skeleton3D:bone" → "dst_root/Skeleton3D:bone"
						if not src_root_name.is_empty() and src_root_name != dst_root_name:
							for i in range(anim.get_track_count()):
								var tp := String(anim.track_get_path(i))
								if tp.begins_with(src_root_name + "/"):
									tp = dst_root_name + tp.substr(src_root_name.length())
									anim.track_set_path(i, NodePath(tp))
						lib.add_animation(anim_name, anim)
					animation_player.add_animation_library("", lib)
				anim_model.queue_free()

	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
	else:
		push_warning("[Enemy] No AnimationPlayer found in model")

	# Cache material references for status effect tinting
	_cache_model_materials()


func _cache_model_materials() -> void:
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


func _setup_hurtbox() -> void:
	hurtbox = Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.owner_node = self
	# Don't connect hit_received signal — hurtbox.take_hit() calls _on_hit_received directly

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()

	if enemy_data:
		capsule.radius = enemy_data.collision_radius
		# Ensure hurtbox extends high enough for projectiles (min 2.0 height)
		capsule.height = maxf(enemy_data.collision_height, 2.0)
	else:
		capsule.radius = 0.5
		capsule.height = 2.0

	shape.shape = capsule
	shape.position.y = capsule.height / 2
	hurtbox.add_child(shape)

	add_child(hurtbox)


func _setup_navigation() -> void:
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 1.5
	add_child(nav_agent)


func _find_target() -> void:
	# Find the player in the scene
	target = _find_player()


## The player node, or null if none is in the scene. Shared by subclasses that
## drive their own movement (PoisonLily, ReyburnBoss) and need to re-acquire the
## target each frame.
func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Node3D if players.size() > 0 else null


## The pre-AI gate: dead, dormant (waiting for the room-entry reveal), or
## fresh off a reveal (hold still while the start animation plays). Each case
## handles its own velocity/motion and the caller returns when one fires.
func _early_process_returns(delta: float) -> bool:
	if not is_alive:
		return true

	# Dormant: waiting for the player to walk into the room. No AI, no
	# gravity — the spawner already placed the body on the floor.
	if dormant:
		velocity = Vector3.ZERO
		return true

	# Fresh reveal: hold position (gravity still settles) while the start
	# animation plays, so the spawn reads as an entrance and not a pop-in.
	if _spawn_lock > 0.0:
		_spawn_lock -= delta
		velocity.x = 0
		velocity.z = 0
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		return true

	# Kill enemy if it falls off the stage
	if global_position.y < -10.0:
		_die()
		return true

	return false


func _physics_process(delta: float) -> void:
	if _early_process_returns(delta):
		return

	# Process status effects
	FrameProfiler.mark("enemy_status")
	_process_status_effects(delta)

	# Tick walk variant timer only for enemies that use the wlk_l/wlk_r fallback
	if _uses_walk_variants:
		_walk_variant_timer += delta
		if _walk_variant_timer >= WALK_VARIANT_INTERVAL:
			_walk_variant_timer = 0.0
			_walk_use_left = not _walk_use_left
			# If currently walking, force a re-play to switch variant
			if current_anim == "wlk":
				current_anim = ""

	# Flyers hold their hover altitude while engaged (spec /states/enemies §flyer —
	# the anti-melee design; they MUST NOT ground mid-combat): gravity is bypassed
	# and y lerps to the hover plane. Everything else falls normally.
	if _archetype == "flyer_combo" and _flying and is_alive:
		velocity.y = 0.0
		global_position.y = lerpf(global_position.y,
			_ground_y + float(_fsm.get("hover_height", 1.3)), 2.0 * delta)
	elif not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Immobilized by status effect — skip AI
	if _is_immobilized:
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	# Update state
	FrameProfiler.mark("enemy_ai")
	match current_state:
		EnemyState.IDLE:
			_process_idle(delta)
		EnemyState.CHASING:
			_process_chasing(delta)
		EnemyState.ATTACKING:
			_process_attacking(delta)
		EnemyState.LOAFING:
			_process_loafing(delta)
		EnemyState.HURT:
			_process_hurt(delta)

	# Update cooldowns
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta

	FrameProfiler.mark("enemy_move_slide")
	var pos_before := global_position
	move_and_slide()

	# Stuck detection: if we tried to move but barely displaced, try going around
	if current_state == EnemyState.CHASING:
		_detect_stuck_movement(pos_before, delta)

	# Safety: if enemy ends up over empty space, stop horizontal movement
	if (velocity.x * velocity.x + velocity.z * velocity.z) > 0.001:
		if not _has_floor_at(global_position):
			velocity.x = 0
			velocity.z = 0


func _process_idle(delta: float) -> void:
	# Try to find target if we don't have one
	if not target or not is_instance_valid(target):
		_find_target()

	if target and is_instance_valid(target):
		var dist := global_position.distance_to(target.global_position)

		# Box mimic (spec /states/enemies §box-mimic): the dormant disguise overrides
		# normal detection entirely — stationary, holding stt's boxed-up first frame,
		# aggroing ONLY inside fsm.reveal_range. Occasional wlk2 sway = the live tell.
		if _archetype == "box_mimic":
			_idle_mimic(dist, delta)
			return

		# Rooted enemies (fsm.stationary): no wander out of combat either — stand at
		# the authored idle clip and let detection promote to CHASING.
		if _fsm.get("stationary", false):
			_idle_stationary(dist)
			return

		# Check if target is in detection range - become alert!
		if enemy_data and dist <= _detection_range:
			current_state = EnemyState.CHASING
			is_wandering = false
			if _archetype in THREAT_DISPLAY_ARCHETYPES:
				# Per-archetype aggro display, held for its clip before pursuit:
				# gorilla chest-beat / roc takeoff / roller activation / ape stands.
				_begin_threat_display("stt")
			else:
				_play_animation("tht", true)  # Threat/war cry when becoming active
			return

	# Wandering behavior
	wander_timer -= delta
	if wander_timer <= 0:
		_pick_new_wander_behavior()

	if is_wandering and wander_direction.length() > 0.1:
		# Walking in wander direction
		_play_animation("wlk")

		var speed := 3.0
		if enemy_data:
			speed = enemy_data.move_speed * WANDER_SPEED_MULT

		# Apply movement if floor ahead
		if _can_move_to(wander_direction):
			velocity.x = wander_direction.x * speed
			velocity.z = wander_direction.z * speed
			# Face movement direction
			_face_direction(wander_direction)
		else:
			# Hit an edge, pick new direction
			_pick_new_wander_behavior()
	else:
		# Standing idle
		velocity.x = 0
		velocity.z = 0
		# Roller rigs idle on wat1/wat2 (no plain wat — the wat→stt alias would
		# mis-read as "become active").
		if _archetype == "roller":
			_play_animation("wat1")
		else:
			_play_animation("wat")


## The dormant disguise hold: frozen on stt's first frame (the boxed-up pose), with a
## rare one-shot wlk2 sway (fsm.ts box-mimic idle). Port of fsm.ts box_mimic idle branch.
## `_idle_mimic` is the IDLE-state branch: hold the disguise, or pop out on reveal.
func _idle_mimic(dist: float, delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	if dist <= _fsm.get("reveal_range", 3.5):
		current_state = EnemyState.CHASING
		is_wandering = false
		_disguise_held = false
		_dormant_swaying = false
		_begin_threat_display("stt")  # pokes its head out of the box
		return
	_process_disguise(delta)


## Rooted IDLE branch (fsm.stationary): stand at the authored idle clip; detection
## still promotes to CHASING (rooted enemies fight — they never wander).
func _idle_stationary(dist: float) -> void:
	velocity.x = 0
	velocity.z = 0
	_play_animation(_rooted_idle_clip())
	if enemy_data and dist <= _detection_range:
		current_state = EnemyState.CHASING
		is_wandering = false


## The dormant disguise hold: frozen on stt's first frame (the boxed-up pose), with a
## rare one-shot wlk2 sway (fsm.ts box-mimic idle). Port of fsm.ts box_mimic idle branch.
func _process_disguise(delta: float) -> void:
	_dormant_timer -= delta
	if _dormant_swaying:
		# Playing out a one-shot (the sway tell, or a tk2 reveal-cancel retreat) —
		# let it finish, then re-hold the disguise.
		_disguise_held = false
		if _dormant_timer <= 0:
			_dormant_swaying = false
		return
	if not _disguise_held:
		var full := _play_animation("stt", true)
		if not full.is_empty() and animation_player:
			animation_player.seek(0.05)
			animation_player.pause()
			_disguise_held = true
	if _dormant_timer <= 0:
		_dormant_timer = 3.0 + _rng.randf() * 4.0
		if _rng.randf() < 0.35:
			_dormant_swaying = true
			_dormant_timer = _clip_duration("wlk2")
			if _dormant_timer < 0.0:
				_dormant_timer = 1.0
			_play_animation("wlk2", true)


## Hold an aggro/reveal display clip for its duration before pursuit (fsm.ts
## threatTimer). Flyers start flying (the takeoff rise runs through the hold).
func _begin_threat_display(token: String) -> void:
	var dur := _clip_duration(token)
	_threat_timer = dur if dur > 0.0 else 1.0
	_threat_total = _threat_timer
	_play_animation(token, true)
	if _archetype == "flyer_combo":
		_flying = true


func _pick_new_wander_behavior() -> void:
	wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)

	# Chance to just stand still
	if randf() < WANDER_PAUSE_CHANCE:
		is_wandering = false
		wander_direction = Vector3.ZERO
	else:
		# Pick random direction
		is_wandering = true
		var angle := randf() * TAU
		wander_direction = Vector3(sin(angle), 0, cos(angle))


func _process_chasing(delta: float) -> void:
	if not target or not is_instance_valid(target):
		current_state = EnemyState.IDLE
		return

	var dist := global_position.distance_to(target.global_position)

	# Aggro display hold (fsm.ts threatTimer): stand and display (chest-beat /
	# takeoff / pop-out) before pursuit. The flyer rises during the hold.
	if _threat_timer > 0.0:
		_threat_timer -= delta
		velocity.x = 0
		velocity.z = 0
		var d := target.global_position - global_position
		d.y = 0
		if d.length() > 0.1:
			_face_direction(d.normalized())
		# Reveal-cancel (spec §box-mimic): the target backed off mid-reveal —
		# tk2 retreats into the box and the disguise resumes.
		if _archetype == "box_mimic" and dist > float(_fsm.get("reveal_range", 3.5)) * 1.5:
			_threat_timer = 0.0
			current_state = EnemyState.IDLE
			_dormant_swaying = true
			_dormant_timer = _clip_duration("tk2")
			if _dormant_timer < 0.0:
				_dormant_timer = 1.0
			_play_animation("tk2", true)
		return

	# Berserk kamikaze (spec §shooter): loop the berserk_only clip straight at the
	# player and self-destruct on contact — regardless of i-frames (the blast
	# happens; i-frames dodge the damage, not the explosion).
	if _berserk and not _kamikaze_def.is_empty():
		var radial_k := _radial_to_target()
		var speed_k := _base_move_speed() * float(_fsm.get("charge_speed_mult", CHARGE_SPEED_MULT)) * 1.2
		velocity.x = radial_k.x * speed_k
		velocity.z = radial_k.z * speed_k
		_face_direction(radial_k)
		_play_animation(String(_kamikaze_def.get("clip", "atk_ji")))
		if dist <= float(_kamikaze_def.get("hit_reach", 1.5)) + PLAYER_HIT_RADIUS:
			_explode_kamikaze()
		return

	var attack_range := 2.0
	if enemy_data:
		attack_range = enemy_data.attack_range

	# Gate FIRST (every archetype): cooldown ready AND some non-berserk attack band
	# contains the distance (spec /mechanics/enemy-attacks "Selection"). Keeps kiters
	# firing from their bands. Falls back to the flat attack_range with no attack table.
	if attack_cooldown_timer <= 0 and not _stun_no_attack and _has_attack_in_band(dist, attack_range):
		current_state = EnemyState.ATTACKING
		_begin_telegraph()
		return

	# Rooted enemies (poison lily): never move — face the target and let the band
	# gate above fire the attacks (fsm.ts stationary chasing).
	if _fsm.get("stationary", false):
		velocity.x = 0
		velocity.z = 0
		var df := target.global_position - global_position
		df.y = 0
		if df.length() > 0.1:
			_face_direction(df.normalized())
		_play_animation(_rooted_idle_clip())
		return

	# Per-archetype locomotion (#494, spec /states/enemies). Distinct ground movers circle
	# or hold a standoff; every baseline archetype chases straight. Math: EnemyLocomotionLogic.
	var radial := _radial_to_target()
	match _archetype:
		"quadruped":
			_chase_quadruped(dist, radial, attack_range)
		"quad_machine", "shooter", "roller":
			_chase_standoff(_archetype, dist, radial)
		"flyer_combo":
			_chase_flyer(dist, radial)
		_:
			_chase_baseline(dist, attack_range)


## Flyer combo chase (spec /states/enemies §flyer, fsm.ts processChasingFlyer):
## airborne at fsm.hover_height (never grounds while engaged); `fly` to close
## distance, `tk` to hover-orbit at fsm.standoff_range, watching the target.
func _chase_flyer(dist: float, radial: Vector3) -> void:
	_flying = true
	var m := EnemyLocomotionLogic.flyer_move(dist, float(_fsm.get("standoff_range", 6.0)), radial, _arc_side)
	if m["mode"] == "approach":
		_tick_arc_side(1.5, 2.5, 0.4)
		_apply_move(m["dir"], _base_move_speed() * float(_fsm.get("charge_speed_mult", CHARGE_SPEED_MULT)),
			radial, "fly")
	else:
		_apply_move(m["dir"], _base_move_speed() * float(_fsm.get("walk_speed_mult", WALK_SPEED_MULT)),
			radial, "tk")


## Baseline straight-line chase (simple_melee and every non-distinct archetype): walk
## beyond the charge ring, run inside it, nav-pathing around obstacles. The revealed
## box mimic shares this but walks wlk1 (its rig has no plain wlk/run).
func _chase_baseline(dist: float, attack_range: float) -> void:
	var is_charging := dist <= attack_range * CHARGE_RANGE_MULT
	var clip := "run" if is_charging else "wlk"
	if _archetype == "box_mimic":
		clip = "wlk1"
	_play_animation(clip)

	var to_target := target.global_position - global_position
	var horizontal_dir := Vector3(to_target.x, 0, to_target.z)
	var direction := horizontal_dir.normalized() if horizontal_dir.length() > 0.1 else Vector3.ZERO

	# Nav pathing (refresh every 10th frame, staggered per instance)
	if Engine.get_physics_frames() % 10 == (get_index() % 10):
		nav_agent.target_position = target.global_position
	if not nav_agent.is_navigation_finished():
		var next_pos := nav_agent.get_next_path_position()
		var nav_dir := next_pos - global_position
		nav_dir.y = 0
		if nav_dir.length() > 0.5:
			direction = nav_dir.normalized()

	var speed := _base_move_speed() * (CHARGE_SPEED_MULT if is_charging else WALK_SPEED_MULT)
	if direction.length() > 0.1 and _can_move_to(direction):
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		_face_direction(direction)


## Quadruped arc-circler (fsm.ts:689-725): circles on an arc (wlk_l/wlk_r by side) and
## only dashes straight (stt) to close inside the charge ring when armed.
func _chase_quadruped(dist: float, radial: Vector3, attack_range: float) -> void:
	var charge_range := attack_range * CHARGE_RANGE_MULT
	if _chase_mode != "dash" and dist <= charge_range and attack_cooldown_timer <= 0.0:
		_chase_mode = "dash"
	if _chase_mode == "dash" and dist > charge_range * 1.5:
		_chase_mode = "arc"
	var dashing := _chase_mode == "dash"
	if not dashing:
		_tick_arc_side(2.0, 3.0, 0.35)
	var m := EnemyLocomotionLogic.quadruped_move(radial, _arc_side, dashing)
	if m["dash"]:
		_apply_move(m["dir"], _base_move_speed() * CHARGE_SPEED_MULT, m["dir"], "stt")
	else:
		_apply_move(m["dir"], _base_move_speed() * WALK_SPEED_MULT, m["dir"],
			"wlk_l" if m["side_left"] else "wlk_r")


## Standoff holder (fsm.ts:736-767/894-915/924-948): quad_machine kites & strafes facing
## the target, shooter holds radial-only and stops to fire, roller sidles facing its
## movement. All hold fsm.standoff_range.
func _chase_standoff(kind: String, dist: float, radial: Vector3) -> void:
	var standoff := float(_fsm.get("standoff_range", 6.0))
	var near_mult := 0.85
	var far_mult := 1.25
	var strafe := true
	var faces_target := true
	if kind == "shooter":
		near_mult = 0.8
		far_mult = 1.2
		strafe = false
	elif kind == "roller":
		near_mult = 0.75
		far_mult = 1.3
		faces_target = false
	if strafe:
		_tick_arc_side(1.5, 2.5, 0.4)
	var m := EnemyLocomotionLogic.standoff_move(dist, standoff, radial, _arc_side, near_mult, far_mult, strafe)
	var mode := String(m["mode"])
	# Retreat is fast (charge mult) for the kiters; the roller walks everywhere.
	var speed := _base_move_speed() * WALK_SPEED_MULT
	if mode == "retreat" and kind != "roller":
		speed = _base_move_speed() * CHARGE_SPEED_MULT
	var face: Vector3 = radial if faces_target else m["dir"]
	_apply_move(m["dir"], speed, face, _standoff_clip(kind, mode, bool(m["side_left"])))


func _standoff_clip(kind: String, mode: String, side_left: bool) -> String:
	if kind == "shooter":
		return "wat" if mode == "hold" else "run"
	if kind == "roller":
		return "wlk"
	# quad_machine: clip matches movement relative to the target-facing body.
	if mode == "retreat":
		return "wlk_b"
	if mode == "close":
		return "wlk_f"
	return "wlk_l" if side_left else "wlk_r"


## Resolve a movement intent to velocity: move along `dir` at `speed` when the floor
## ahead holds (else stop), face `face_dir`, play `clip`. Shared by the archetype chases.
func _apply_move(dir: Vector3, speed: float, face_dir: Vector3, clip: String) -> void:
	if dir.length() > 0.1 and _can_move_to(dir):
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if face_dir.length() > 0.1:
		_face_direction(face_dir)
	if not clip.is_empty():
		_play_animation(clip)


func _radial_to_target() -> Vector3:
	var to := target.global_position - global_position
	to.y = 0.0
	return to.normalized() if to.length() > 0.001 else Vector3.FORWARD


func _base_move_speed() -> float:
	return float(enemy_data.move_speed) if enemy_data else 3.0


## Tick the circling/strafe-side timer; re-pick the side after a random interval.
func _tick_arc_side(base: float, span: float, flip_chance: float) -> void:
	_arc_timer -= get_physics_process_delta_time()
	if _arc_timer <= 0.0:
		_arc_timer = base + _rng.randf() * span
		if _rng.randf() < flip_chance:
			_arc_side = -_arc_side


func _process_attacking(delta: float) -> void:
	# Telegraph sub-phase: hold the attack-ready pose (facing the player) before the
	# strike so the wind-up is readable and dodgeable. No damage here.
	if _telegraphing:
		velocity.x = 0
		velocity.z = 0
		if target and is_instance_valid(target):
			var d := target.global_position - global_position
			d.y = 0
			if d.length() > 0.1:
				_face_direction(d.normalized())
		_process_telegraph(delta)
		return

	# Segmented charge (kind charge): its own phase machine — the st/lp/ed segments
	# ARE the timeline (spec §big-rig). It moves during lp, so it owns its velocity.
	if not _charge.is_empty():
		_process_charge(delta)
		if not is_attacking:
			_start_loafing()
		return

	velocity.x = 0
	velocity.z = 0

	# windup_clips prelude (fsm.ts windup): sequential pure-telegraph clips before
	# the attack clip; the swing's window cannot start until the prelude finishes.
	# No damage during it.
	if not _windup_done:
		_process_windup(delta)
		return

	# Advance the position within the attack clip. Prefer the real animation
	# position; fall back to an accumulating timer for no-clip rigs (and tests).
	if _attack_anim != "" and animation_player and animation_player.current_animation == _attack_anim:
		_attack_pos = animation_player.current_animation_position
	else:
		_attack_pos += delta

	if is_attacking and not _attack_def.is_empty():
		_process_attack_window()

	# Attack end: the resolved animation finished (signal path or the
	# watchdog below), or the fallback duration elapsed when no attack
	# animation resolved. Never wait on a damage event to recover (#477).
	if is_attacking:
		if _attack_anim.is_empty():
			_attack_fallback_timer -= delta
			if _attack_fallback_timer <= 0.0:
				is_attacking = false
		elif animation_player and not animation_player.is_playing():
			is_attacking = false
			_attack_anim = ""

	if not is_attacking:
		_start_loafing()


## The damaging-window step, post-prelude: window open releases the ranged kinds /
## captures the leap, the leap travels the window, melee runs the per-frame arc
## test, and window close is the leap's landing. One resolution per attack.
func _process_attack_window() -> void:
	# The fractions apply to the attack clip's own timeline (`_attack_pos`, reset
	# when the clip starts); the windup_clips prelude delays the whole window via
	# the _windup_done gate above — no extra offset, or it would count twice.
	var window_start: float = float(_attack_def.get("windup_frac", 0.35)) * _attack_clip_len * _aggro_reaction
	var window_end: float = float(_attack_def.get("damage_end_frac", 0.6)) * _attack_clip_len

	# Ranged kinds release exactly once, at window open (spec: kind) — resolution
	# then happens at impact/landing, not via the arc test. The leap captures its
	# flight endpoints at the same instant.
	if not _window_opened and _attack_pos >= window_start:
		_window_opened = true
		if _attack_kind == "projectile":
			_attack_hit_resolved = true
			_fire_projectile()
		elif _attack_kind == "lob":
			_attack_hit_resolved = true
			_fire_lob()
		elif _attack_kind == "leap":
			_leap_from = global_position
			var tp := target.global_position if target and is_instance_valid(target) else global_position
			_leap_to = Vector3(tp.x, global_position.y, tp.z)

	# Leap flight: the enemy itself travels from → target during the window.
	if _attack_kind == "leap" and _window_opened and not _window_closed and window_end > window_start:
		var f := clampf((_attack_pos - window_start) / (window_end - window_start), 0.0, 1.0)
		global_position.x = lerpf(_leap_from.x, _leap_to.x, f)
		global_position.z = lerpf(_leap_from.z, _leap_to.z, f)

	# Frame-tied damage window, melee only: the arc test runs each frame; the
	# first frame the target passes resolves the hit. One resolution (hit or
	# dodge) per attack (#509). Ranged/leap kinds resolve at impact/landing.
	if _attack_kind == "melee_arc" and not _attack_hit_resolved \
			and _attack_pos >= window_start and _attack_pos <= window_end:
		_try_attack_hit()

	# Window close = the leap's landing: snap to the landing point, AoE with
	# hit_reach as the radius, i-frames tested at landing (spec §big-rig).
	if not _window_closed and _attack_pos > window_end:
		_window_closed = true
		if _attack_kind == "leap" and not _attack_hit_resolved:
			_leap_land()


## windup_clips prelude ticker (fsm.ts windup): advance through the telegraph clips
## on their resolved cumulative end-times, then hand off to the attack clip.
func _process_windup(delta: float) -> void:
	_windup_elapsed += delta
	if _windup_elapsed < _windup_total:
		for i in _windup_clips.size():
			if _windup_elapsed < float(_windup_clips[i]["end"]):
				if i != _windup_idx:
					_windup_idx = i
					_play_animation(String(_windup_clips[i]["token"]), true)
				break
		return
	_windup_done = true
	_begin_main_clip()


## Segmented charge phases (fsm.ts processAttackCharge): st stationary windup →
## lp charging forward along the locked facing, hitting on first contact (a dodge
## lets it pass and keep going), capped at the travel target → ed recovery, whose
## duration is the recovery_vulnerable_mult punish window (spec §roller).
func _process_charge(delta: float) -> void:
	var c: Dictionary = _charge
	c["phase_t"] = float(c["phase_t"]) + delta
	var tokens: Dictionary = c["tokens"]
	match String(c["phase"]):
		"st":
			velocity.x = 0
			velocity.z = 0
			if float(c["phase_t"]) >= float(c["st_dur"]):
				c["phase"] = "lp"
				c["phase_t"] = 0.0
				_play_charge_segment(tokens, "lp")
		"lp":
			var speed := _base_move_speed() * float(_fsm.get("charge_speed_mult", CHARGE_SPEED_MULT))
			velocity.x = _attack_facing.x * speed
			velocity.z = _attack_facing.z * speed
			c["traveled"] = float(c["traveled"]) + speed * delta
			# Engine-rolled loop clips (the roller's curled wat3) carry no motion of
			# their own — the model must rotate while it travels (spec §roller).
			if c.get("rotate_model", false) and model:
				model.rotate_x(-deg_to_rad(720.0) * delta)
			var end_charge := false
			if not _attack_hit_resolved and target and is_instance_valid(target):
				var reach := float(_attack_def.get("hit_reach", 2.0))
				var half := float(_attack_def.get("hit_half_angle_deg", 45.0))
				if EnemyAttackLogic.arc_hit_test(global_position, _attack_facing,
						target.global_position, PLAYER_HIT_RADIUS, half, reach):
					_attack_hit_resolved = true
					var dodged: bool = target.has_method("is_dodge_iframed") and target.is_dodge_iframed()
					if not dodged:
						_deal_damage_for(_attack_def)
						# stop_on_hit: false (roller) bowls the player over and keeps
						# rolling — same animation whether it hits player or wall.
						if _attack_def.get("stop_on_hit", true) != false:
							end_charge = true
			if float(c["traveled"]) >= float(c["travel_target"]) or float(c["phase_t"]) > CHARGE_MAX_LP_TIME:
				end_charge = true
			if end_charge:
				c["phase"] = "ed"
				c["phase_t"] = 0.0
				velocity.x = 0
				velocity.z = 0
				_play_charge_segment(tokens, "ed")
				# The fall-over punish window (spec §roller): recovery takes mult damage.
				var vm = _attack_def.get("recovery_vulnerable_mult", null)
				if vm != null:
					_vulnerable_mult = float(vm)
		"ed":
			velocity.x = 0
			velocity.z = 0
			if float(c["phase_t"]) >= float(c["ed_dur"]):
				is_attacking = false
				_charge = {}
				_vulnerable_mult = 1.0


func _process_loafing(delta: float) -> void:
	loaf_timer -= delta

	# When loaf time is up, go back to chasing
	if loaf_timer <= 0:
		current_state = EnemyState.CHASING
		return

	# Rooted enemies never move — stand at the idle clip through the loaf.
	if _fsm.get("stationary", false):
		velocity.x = 0
		velocity.z = 0
		_play_animation(_rooted_idle_clip())
		return

	# Curve the direction over time (creates semi-circle path)
	var angle_change := loaf_curve_rate * delta
	loaf_direction = loaf_direction.rotated(Vector3.UP, angle_change)

	# Move in loaf direction
	var speed := 3.0
	if enemy_data:
		speed = enemy_data.move_speed * LOAF_SPEED_MULT

	# Check if we can move in loaf direction
	if loaf_direction.length() > 0.1 and _can_move_to(loaf_direction):
		velocity.x = loaf_direction.x * speed
		velocity.z = loaf_direction.z * speed
		_face_direction(loaf_direction)  # Face movement direction (away from player)
		_play_animation("wlk1" if _archetype == "box_mimic" else "wlk")
	else:
		# Can't move that way, try reversing curve direction
		loaf_curve_rate = -loaf_curve_rate
		velocity.x = 0
		velocity.z = 0
		_play_animation("wat")


func _start_loafing() -> void:
	current_state = EnemyState.LOAFING
	_telegraphing = false
	_vulnerable_mult = 1.0  # the recovery (and its punish window) is over
	# Stance risers lower back down (wt2w) as they peel off; other rigs just loaf.
	_play_animation("wt2w", true)
	loaf_timer = randf_range(LOAF_DURATION_MIN, LOAF_DURATION_MAX)

	# Start moving perpendicular to player (left or right randomly)
	if target and is_instance_valid(target):
		var away_from_target := global_position - target.global_position
		var away_dir := Vector3(away_from_target.x, 0, away_from_target.z).normalized()

		# Rotate 90 degrees left or right to get perpendicular direction
		var side := 1.0 if randf() > 0.5 else -1.0
		loaf_direction = away_dir.rotated(Vector3.UP, side * PI * 0.5)

		# Curve back toward the "away" direction over time (creates arc)
		loaf_curve_rate = -side * LOAF_CURVE_RATE
	else:
		# No target, pick random direction
		var angle := randf() * TAU
		loaf_direction = Vector3(sin(angle), 0, cos(angle))
		loaf_curve_rate = LOAF_CURVE_RATE if randf() > 0.5 else -LOAF_CURVE_RATE


func _process_hurt(delta: float) -> void:
	hurt_timer -= delta
	velocity.x = 0
	velocity.z = 0

	if hurt_timer <= 0:
		current_state = EnemyState.CHASING


## Enter the pre-strike telegraph. Stance risers rise (stt) then hold wat2; other rigs
## hold their idle (wat). The strike (_start_attack) begins only when the hold elapses.
## Attacks carrying their OWN authored telegraph — windup_clips preludes, charge st
## segments — skip the generic hold: their clips are the readable beat (spec
## /mechanics/enemy-attacks "windup_clips" / "kind").
func _begin_telegraph() -> void:
	if not target or not is_instance_valid(target):
		return
	is_attacking = true
	var dist := global_position.distance_to(target.global_position)
	_attack_def = _select_attack_for(dist)
	_attack_kind = String(_attack_def.get("kind", "melee_arc"))
	var windup: Array = _attack_def.get("windup_clips", [])
	if _attack_kind == "charge" or not windup.is_empty():
		_telegraphing = false
		_start_attack()
		return
	_telegraphing = true
	var rise := _play_animation("stt", true)
	if not rise.is_empty():
		_telegraph_rising = true
		var a := animation_player.get_animation(rise)
		_telegraph_timer = a.length if a else 0.3
	else:
		_telegraph_rising = false
		_telegraph_timer = TELEGRAPH_HOLD * _aggro_reaction
		_play_telegraph_hold()


func _process_telegraph(delta: float) -> void:
	_telegraph_timer -= delta
	if _telegraph_timer > 0.0:
		return
	if _telegraph_rising:
		# Rise finished — hold the raised attack-ready pose for the readable beat.
		_telegraph_rising = false
		_telegraph_timer = TELEGRAPH_HOLD * _aggro_reaction
		_play_telegraph_hold()
	else:
		# Hold done — commit to the strike (the player dodges it, not prevents it).
		_telegraphing = false
		_start_attack()


## Play the held attack-ready pose: the raised stance (wat2) if the rig has one, else
## its idle (wat). Looped so it holds through the telegraph beat.
func _play_telegraph_hold() -> void:
	var held := _play_animation("wat2", true)
	if held.is_empty():
		held = _play_animation("wat", true)
	if not held.is_empty():
		var a := animation_player.get_animation(held)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR


func _start_attack() -> void:
	if not target or not is_instance_valid(target):
		return

	is_attacking = true

	# Select the attack by range band + weight. Already selected at telegraph start
	# for authored-telegraph kinds; keep the fallback for direct entries (tests,
	# PoisonLily's delegated swings).
	var dist := global_position.distance_to(target.global_position)
	if _attack_def.is_empty():
		_attack_def = _select_attack_for(dist)
	_attack_kind = String(_attack_def.get("kind", "melee_arc"))
	_attack_hit_resolved = false
	_window_opened = false
	_window_closed = false
	_windup_done = true
	_windup_total = 0.0
	_windup_elapsed = 0.0
	_windup_idx = -1
	_charge = {}
	_vulnerable_mult = 1.0

	# Per-kind machinery: the charge's segments ARE its timeline; windup_clips play
	# before the attack clip and gate its window; everything else resolves the main clip.
	var windup: Array = _attack_def.get("windup_clips", [])
	if _attack_kind == "charge":
		_start_charge(dist)
	elif windup.size() > 0:
		_setup_windup()
	else:
		_begin_main_clip()
	_play_sfx("attack")

	# Lock facing at attack start — the arc does not track during the swing.
	var dir_to_target := target.global_position - global_position
	dir_to_target.y = 0
	if dir_to_target.length() > 0.1:
		_attack_facing = dir_to_target.normalized()
		_face_direction(_attack_facing)

	# Set cooldown (difficulty tightens cadence).
	var cooldown := 1.5
	if enemy_data:
		cooldown = enemy_data.attack_cooldown
	attack_cooldown_timer = cooldown * _aggro_cadence


## Resolve + play the attack clip proper and arm its timeline/fallback end.
func _begin_main_clip() -> void:
	_attack_anim = _play_animation(String(_attack_def.get("clip", "atk")), true)
	if _attack_anim.is_empty():
		# Rig has no resolvable attack clip — timeline fractions apply to the
		# fixed fallback duration; end the attack on that same timer.
		_attack_fallback_timer = ATTACK_FALLBACK_DURATION
		_attack_clip_len = ATTACK_FALLBACK_DURATION
	else:
		var anim := animation_player.get_animation(_attack_anim)
		_attack_clip_len = anim.length if anim else ATTACK_FALLBACK_DURATION
	_attack_pos = 0.0


## Build the windup_clips prelude (fsm.ts startAttack windup): resolved clip lengths
## (fallback CHARGE_SEGMENT_FALLBACK per missing clip), cumulative end-times, then
## play the first prelude clip. The main clip starts when the prelude elapses.
func _setup_windup() -> void:
	_windup_clips = []
	var acc := 0.0
	for token in _attack_def.get("windup_clips", []):
		var dur := _clip_duration(str(token))
		if dur < 0.0:
			dur = CHARGE_SEGMENT_FALLBACK
		acc += dur
		_windup_clips.append({"token": token, "end": acc})
	_windup_total = acc
	_windup_elapsed = 0.0
	_windup_idx = -1
	_windup_done = _windup_clips.is_empty()
	_attack_anim = ""
	_attack_clip_len = ATTACK_FALLBACK_DURATION
	if not _windup_done:
		_windup_idx = 0
		_play_animation(String(_windup_clips[0]["token"]), true)


## Arm the segmented charge (fsm.ts startAttack charge branch). Tokens come from
## charge_segments (the roller's trf1/wat3/trf2) or the clip's _st/_lp/_ed suffixes.
## The travel target rolls overshoot meters PAST where the target stood at start
## (spec §roller), capped by max_range.
func _start_charge(dist: float) -> void:
	var clip := String(_attack_def.get("clip", "atk"))
	var tokens: Dictionary = _attack_def.get("charge_segments", {})
	if tokens.is_empty():
		tokens = {"st": clip + "_st", "lp": clip + "_lp", "ed": clip + "_ed"}
	var st_dur := _clip_duration(str(tokens["st"]))
	var ed_dur := _clip_duration(str(tokens["ed"]))
	var max_range := maxf(float(_attack_def.get("max_range", 1.0)), 1.0)
	var overshoot = _attack_def.get("overshoot", null)
	var travel_target := max_range
	if overshoot != null:
		travel_target = clampf(dist + float(overshoot), 0.0, max_range)
	_charge = {
		"phase": "st",
		"phase_t": 0.0,
		"st_dur": st_dur if st_dur > 0.0 else CHARGE_SEGMENT_FALLBACK,
		"ed_dur": ed_dur if ed_dur > 0.0 else CHARGE_SEGMENT_FALLBACK,
		"tokens": tokens,
		"traveled": 0.0,
		"travel_target": travel_target,
		# Explicit segments (roller) mean transform clips — the loop piece is a
		# motionless ball the engine must roll.
		"rotate_model": not (_attack_def.get("charge_segments", {}) as Dictionary).is_empty(),
	}
	_attack_anim = ""          # the phase machine ends the attack, never the clip
	_attack_fallback_timer = 1.0e9
	_play_animation(str(tokens["st"]), true)


func _play_charge_segment(tokens: Dictionary, key: String) -> void:
	var full := _play_animation(str(tokens[key]), true)
	# The lp loop may repeat (travel outlasts one loop) — loop it; st/ed are timed
	# by their durations anyway.
	if key == "lp" and not full.is_empty() and animation_player:
		var a := animation_player.get_animation(full)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR


## A clip token's resolved duration on this rig, or -1 when it doesn't resolve.
func _clip_duration(token: String) -> float:
	if not animation_player:
		return -1.0
	var full := _find_animation(token)
	if full.is_empty():
		return -1.0
	var a := animation_player.get_animation(full)
	return a.length if a else -1.0


## True when a non-berserk attack's band contains `dist`. Falls back to the flat
## attack_range when this enemy has no attack table.
func _has_attack_in_band(dist: float, attack_range: float) -> bool:
	if _attacks.is_empty():
		return dist <= attack_range
	for a in _attacks:
		if a.get("berserk_only", false):
			continue
		if dist >= float(a.get("min_range", 0.0)) and dist <= float(a.get("max_range", 999.0)):
			return true
	return false


## Pick the attack for this swing (berserk excluded — not implemented in this slice).
func _select_attack_for(dist: float) -> Dictionary:
	var pool: Array = []
	for a in _attacks:
		if not a.get("berserk_only", false):
			pool.append(a)
	var chosen := EnemyAttackLogic.select_attack(pool, dist, _rng)
	if chosen.is_empty():
		# No table at all — a basic melee swing (mirrors the registry default).
		chosen = {"clip": "atk", "windup_frac": 0.35, "damage_end_frac": 0.6,
			"hit_half_angle_deg": 45.0, "hit_reach": 2.0, "damage_mult": 1.0, "kind": "melee_arc"}
	return chosen


## Run the arc test against the target during the damage window and, on a pass, deal
## attack_base × damage_mult once. A pass consumes the attack's one resolution even if
## the player dodges (take_damage no-ops during i-frames — player.gd), matching the spec.
func _try_attack_hit() -> void:
	if not target or not is_instance_valid(target):
		return
	var reach := float(_attack_def.get("hit_reach", 2.0))
	var half := float(_attack_def.get("hit_half_angle_deg", 45.0))
	if not EnemyAttackLogic.arc_hit_test(global_position, _attack_facing,
			target.global_position, PLAYER_HIT_RADIUS, half, reach):
		return
	_attack_hit_resolved = true
	_deal_damage_for(_attack_def)


## Damage the target per an attack def: attack_base × damage_mult, plus the def's
## knockdown flag (the player maps it to its knock-down reaction — spec
## /mechanics/enemy-attacks "knockdown").
func _deal_damage_for(def: Dictionary) -> void:
	if not target or not is_instance_valid(target):
		return
	if target.has_method("take_damage"):
		target.take_damage(_attack_damage(def), Vector3.ZERO, bool(def.get("knockdown", false)))


func _attack_damage(def: Dictionary) -> int:
	var base_attack: int = enemy_data.attack_base if enemy_data else 10
	return int(round(float(base_attack) * float(def.get("damage_mult", 1.0))))


## Release a straight projectile (kind projectile) at window open — Godot port of the
## fsm.ts delivery. Travel is along the facing locked at attack start; hit_reach is the
## flight range. Tech casts fire recolored for now; routing through the real technique
## system (element, status procs, tech visuals) stays owed to the `tech` contract.
func _fire_projectile() -> void:
	if not is_inside_tree():
		return
	var p := EnemyProjectile.new()
	p.dir = _attack_facing
	p.speed = EnemyProjectile.PROJECTILE_SPEED
	p.max_range = maxf(float(_attack_def.get("hit_reach", 2.0)), 1.0)
	p.damage = _attack_damage(_attack_def)
	p.knockdown = bool(_attack_def.get("knockdown", false))
	p.target = target
	p.on_hit = _projectile_on_hit()
	if str(_attack_def.get("tech", "")) != "":
		p.color = Color(0.5, 0.8, 1.0)
	get_parent().add_child(p)
	p.global_position = global_position + _attack_facing * 0.8 + Vector3(0, 1.2, 0)


## Subclass hook: an extra on-hit effect for projectiles (the lily's poison DoT).
func _projectile_on_hit() -> Callable:
	return Callable()


## Release a grenade (kind lob) at window open, toward the target's position at
## release. Lands after LOB_FLIGHT_TIME for area damage (hit_reach = blast radius).
func _fire_lob() -> void:
	if not is_inside_tree():
		return
	var l := EnemyLob.new()
	l.from = global_position + Vector3(0, 1.2, 0)
	var tp := target.global_position if target and is_instance_valid(target) else global_position
	l.to = tp
	l.blast_radius = float(_attack_def.get("hit_reach", 1.6))
	l.damage = _attack_damage(_attack_def)
	l.knockdown = bool(_attack_def.get("knockdown", false))
	l.target = target
	get_parent().add_child(l)
	l.global_position = l.from


## Leap landing (kind leap): snap to the landing point and resolve the area hit —
## hit_reach is the radius, i-frames are tested here, one resolution regardless.
func _leap_land() -> void:
	_attack_hit_resolved = true
	global_position.x = _leap_to.x
	global_position.z = _leap_to.z
	var radius := float(_attack_def.get("hit_reach", 2.0))
	EnemyLob.spawn_ring(get_parent(), global_position, radius)
	if target and is_instance_valid(target):
		var to := target.global_position - _leap_to
		to.y = 0.0
		if to.length() <= radius + PLAYER_HIT_RADIUS:
			_deal_damage_for(_attack_def)


## Leader-loss berserk (spec /states/enemies §shooter): the atk_an confusion display
## plays once as a threat hold, then CHASING's kamikaze branch dives at the player.
## No-op unless the table carries a berserk_only attack.
func apply_berserk() -> void:
	if _berserk or not is_alive or _kamikaze_def.is_empty():
		return
	_berserk = true
	is_attacking = false
	_telegraphing = false
	_attack_anim = ""
	_charge = {}
	_vulnerable_mult = 1.0
	current_state = EnemyState.CHASING
	var dur := _clip_duration("atk_an")
	_threat_timer = dur if dur > 0.0 else 1.0
	_threat_total = _threat_timer
	_play_animation("atk_an", true)


## Contact self-destruct: one AoE hit at the kamikaze def's hit_reach, then die.
## The explosion triggers regardless of i-frames — i-frames dodge the damage, not
## the blast (fsm.ts exploded branch).
func _explode_kamikaze() -> void:
	if not is_alive:
		return
	var radius := float(_kamikaze_def.get("hit_reach", 1.5))
	EnemyLob.spawn_ring(get_parent(), global_position, radius)
	if target and is_instance_valid(target):
		var to := target.global_position - global_position
		to.y = 0.0
		if to.length() <= radius + PLAYER_HIT_RADIUS:
			_deal_damage_for(_kamikaze_def)
	_die()


## Shooter leader-loss wiring (spec §shooter): when a *_leader model dies (Akorse is
## the Canane analog), its pack — same model minus the suffix (Korse) — goes berserk.
## Full pack wiring is #495; this radius trigger is the runtime half (#629).
func _notify_leader_loss() -> void:
	if not enemy_data or not str(enemy_data.model_id).ends_with("_leader"):
		return
	var follower_model := str(enemy_data.model_id).trim_suffix("_leader")
	for n in get_tree().get_nodes_in_group("enemies"):
		var eb := n as EnemyBase
		if eb == null or eb == self or not eb.is_alive:
			continue
		if not eb.enemy_data or str(eb.enemy_data.model_id) != follower_model:
			continue
		if eb._kamikaze_def.is_empty():
			continue
		if eb.global_position.distance_to(global_position) <= 30.0:
			eb.apply_berserk()


## Difficulty-scaled aggression + timing (#522). Reads the session difficulty (default
## "normal" when no session — keeps tests isolated) and sets the aggro/cadence/reaction
## multipliers + the scaled detection range.
func _apply_difficulty() -> void:
	var diff := "normal"
	if SessionManager and SessionManager.has_method("get_session"):
		diff = str(SessionManager.get_session().get("difficulty", "normal"))
	var s: Dictionary = AGGRO_SCALING.get(diff, AGGRO_SCALING["normal"])
	_aggro_cadence = float(s["cadence"])
	_aggro_reaction = float(s["reaction"])
	var base_det: float = enemy_data.detection_range if enemy_data else 15.0
	_detection_range = base_det * float(s["detection"])


func _on_hit_received(raw_damage: int, _knockback: Vector3, accuracy: int = 100, hit_element: String = "", hit_element_level: int = 0) -> void:
	if not is_alive:
		return

	# Break freeze/sleep on any hit
	_break_on_hit_effects()

	# Apply damage multiplier from freeze
	var damage_mult := 1.0
	for fx in _status_effects:
		var fx_def: Dictionary = CombatManager.STATUS_EFFECTS.get(fx.type, {})
		if fx_def.has("damage_taken_mult"):
			damage_mult *= float(fx_def.damage_taken_mult)

	var result: Dictionary = CombatManager.apply_damage_to_enemy(raw_damage, current_defense, current_evasion, accuracy)
	if not result.get("hit", true):
		_spawn_damage_number("MISS", Color(0.7, 0.7, 0.7))
		return

	# Apply damage multiplier from freeze, then the recovery punish window if the
	# hit lands inside one (recovery_vulnerable_mult — spec §roller).
	var final_damage: int = int(int(result.get("damage", raw_damage)) * damage_mult * _vulnerable_mult)
	var is_crit: bool = result.get("is_critical", false)
	current_hp -= final_damage
	damaged.emit(self, final_damage)

	# Spawn floating damage number
	var dmg_color := Color(1.0, 1.0, 0.2) if is_crit else Color.WHITE
	var dmg_text := str(final_damage) + ("!" if is_crit else "")
	_spawn_damage_number(dmg_text, dmg_color)

	if current_hp <= 0:
		_die()
	else:
		# Try status effect from element
		if not hit_element.is_empty() and hit_element_level > 0:
			_try_apply_status(hit_element, hit_element_level)

		# Enter hurt state — play stagger animation, no physics knockback
		is_attacking = false  # Cancel any attack
		_telegraphing = false  # a hit during the wind-up cancels the telegraph too
		_attack_anim = ""
		_charge = {}            # a stagger interrupts a charge mid-phase
		_vulnerable_mult = 1.0  # ...and closes any punish window
		current_state = EnemyState.HURT
		hurt_timer = HURT_DURATION
		velocity = Vector3.ZERO  # Stop movement during stagger

		_play_animation("dmg", true)  # Force play damage animation
		_play_sfx("damage")


func _die() -> void:
	is_alive = false
	is_attacking = false
	_vulnerable_mult = 1.0
	current_state = EnemyState.DEAD
	died.emit(self)
	_notify_leader_loss()

	print("[Enemy] ", enemy_data.name if enemy_data else "Enemy", " died!")

	# Play death animation
	_play_animation("ded", true)
	_play_sfx("death")

	# Drops are handled by the field controller via the died signal

	# Remove after death animation (or delay if no animation)
	var delay := 1.5  # Default delay
	if animation_player and animation_player.has_animation("ded"):
		delay = animation_player.get_animation("ded").length + 0.3
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(queue_free)


## Face a direction (model faces -Z, so we look opposite way)
func _face_direction(dir: Vector3) -> void:
	if dir.length() < 0.1:
		return
	# Look at the opposite direction since model faces -Z
	look_at(global_position - dir, Vector3.UP)


## Check if enemy can move in direction (floor detection)
func _can_move_to(move_dir: Vector3) -> bool:
	# Check multiple points to prevent walking off edges
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


## Play an animation by name (short name like "atk" will match "s_001_atk").
## Returns the resolved full animation name, or "" if nothing played.
func _play_animation(anim_name: String, force: bool = false) -> String:
	if not animation_player:
		return ""

	# Don't interrupt same animation unless forced
	if not force and current_anim == anim_name:
		return ""

	# Try to find the animation - GLB animations are named like "s_001_atk"
	var full_name := _find_animation(anim_name)

	# Walk fallback: some enemies (e.g. hyena) only have wlk_l/wlk_r variants
	# instead of a plain wlk. Alternate between them for a circling effect.
	if full_name.is_empty() and anim_name == "wlk":
		var variant := "wlk_l" if _walk_use_left else "wlk_r"
		full_name = _find_animation(variant)
		if not full_name.is_empty():
			_uses_walk_variants = true

	if full_name.is_empty():
		return ""

	# Ensure looping animations actually loop
	var anim := animation_player.get_animation(full_name)
	if anim and anim_name in ["run", "wlk", "wat"]:
		anim.loop_mode = Animation.LOOP_LINEAR

	animation_player.play(full_name)
	current_anim = anim_name
	return full_name


## Find animation by short name (e.g., "atk" matches "s_001_atk")
## Animation name aliases — some enemies use different suffixes for the same action
const ANIM_ALIASES := {
	"wat": ["stt"],       # wait/idle → standing
	"wlk": ["fly"],       # walk → fly (for airborne enemies)
	"run": ["fly"],       # run → fly
	"atk": ["atk1", "atckwat"],  # attack → variant 1, or orangutan's misspelled attack-from-wait
	"dmg": ["dam"],       # five rigs name the damage clip dam (booma/swordman/tank/orangutan/shrimp)
	"spawn": ["app", "appearance", "stt"],  # spawn-in → appearance clip; stt is a stand-from-wait that reads as one
}

func _find_animation(short_name: String) -> String:
	# Direct match first
	if animation_player.has_animation(short_name):
		return short_name

	# Search all animations for one ending with the short name
	var anim_list: PackedStringArray = animation_player.get_animation_list()
	for i in range(anim_list.size()):
		var anim_name: String = anim_list[i]
		if anim_name.ends_with("_" + short_name):
			return anim_name

	# Search in libraries
	var lib_list: Array[StringName] = animation_player.get_animation_library_list()
	for j in range(lib_list.size()):
		var lib_name: StringName = lib_list[j]
		var lib: AnimationLibrary = animation_player.get_animation_library(lib_name)
		var lib_anim_list: PackedStringArray = lib.get_animation_list()
		for k in range(lib_anim_list.size()):
			var anim_name: String = lib_anim_list[k]
			if anim_name.ends_with("_" + short_name):
				var full: String = str(lib_name) + "/" + anim_name if lib_name else anim_name
				return full

	# Try aliases
	if short_name in ANIM_ALIASES:
		for alias in ANIM_ALIASES[short_name]:
			var result := _find_animation(alias)
			if not result.is_empty():
				return result

	# Last-resort ATTACK scan — suffix-variant rigs (b062_atk_pu,
	# b052_atk_sh, m061_atk_a, b072_atk_sa_a…) must still swing. Normative
	# order in spec /states/enemies "Attack recovery".
	if short_name == "atk":
		return _find_attack_clip_fallback()

	return ""


## Any clip with an exact "atk" underscore-segment qualifies, EXCEPT
## segmented charge/loop/end pieces (…_st/_lp/_ed — playing one alone shows
## a partial attack). Alphabetically first for deterministic resolution.
func _find_attack_clip_fallback() -> String:
	var best := ""
	for anim_name in animation_player.get_animation_list():
		var n := String(anim_name)
		var parts := n.split("_")
		if not ("atk" in parts):
			continue
		if parts[parts.size() - 1] in ["st", "lp", "ed"]:
			continue
		if best.is_empty() or n < best:
			best = n
	return best


## Called when animation finishes
func _on_animation_finished(anim_name: String) -> void:
	# Attack end is matched against the resolved name that _start_attack
	# actually played — suffix parsing wedged atk1/atckwat rigs (#477).
	if anim_name == _attack_anim:
		is_attacking = false
		_attack_anim = ""
		return

	# Extract short name (e.g., "s_001_tht" -> "tht")
	var short_name := anim_name
	if "_" in anim_name:
		var parts := anim_name.split("_")
		short_name = parts[parts.size() - 1]  # Get last part after underscore

	match short_name:
		"tht":
			# After threat animation, start chasing
			if current_state == EnemyState.CHASING:
				_play_animation("wlk")


func _play_sfx(key: String) -> void:
	var path: String = _sfx.get(key, "")
	if not path.is_empty():
		SfxManager.play_at(path, global_position)


## Bring a dormant enemy in: show it, play the spawn effect and a start
## animation, and hold it still for SPAWN_LOCK_SEC so the entrance reads.
## `delay` staggers multi-enemy reveals so a wave arrives as a ripple rather
## than one simultaneous pop.
func reveal(delay: float = 0.0) -> void:
	if not dormant:
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if not dormant or not is_inside_tree():
			return
	dormant = false
	visible = true
	if hurtbox:
		hurtbox.set_deferred("monitorable", true)
	_spawn_lock = SPAWN_LOCK_SEC
	_play_spawn_effect()
	# Start animation if the rig has one, else settle into idle. Short names
	# the rigs use for it: "app"/"appearance"/"spawn"; none is guaranteed.
	if _play_animation("spawn", true).is_empty():
		_play_animation("wat", true)


## The spawn-in burst: a one-shot puff of additive glow dots, in the shape the
## weather controller uses for its particles. Self-frees when finished.
func _play_spawn_effect() -> void:
	var burst := GPUParticles3D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.lifetime = 0.6
	burst.amount = 24
	burst.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 35.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, -6, 0)
	mat.scale_min = 0.35
	mat.scale_max = 0.9
	burst.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	var qm := StandardMaterial3D.new()
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.albedo_texture = _glow_dot()
	qm.albedo_color = Color(0.55, 0.8, 1.0)
	quad.material = qm
	burst.draw_pass_1 = quad
	add_child(burst)
	burst.position = Vector3(0, 0.8, 0)
	burst.finished.connect(burst.queue_free)


## Shared radial-gradient dot texture for the spawn burst (same construction as
## WeatherController's, kept local so the enemy has no dependency on the field).
static var _dot_tex: ImageTexture = null

static func _glow_dot() -> ImageTexture:
	if _dot_tex:
		return _dot_tex
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	for y in range(size):
		for x in range(size):
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(center) / (size / 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


func _spawn_damage_number(text: String, color: Color = Color.WHITE) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	label.outline_size = 6
	label.outline_modulate = Color(0, 0, 0)
	# Position above the enemy with slight random offset
	label.position = Vector3(randf_range(-0.3, 0.3), 2.0 + randf_range(0, 0.3), 0)
	add_child(label)

	# Animate: float up and fade out
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.0, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


func _setup_reticle() -> void:
	# Centre of the body, not above the head — the three triangles mark the
	# thing they lock, and with a crowd the above-head reticles smear into a
	# band instead of reading one-per-enemy.
	var height := 1.5
	if enemy_data:
		height = enemy_data.collision_height
	_reticle = TargetReticle.build(height * 0.5)
	add_child(_reticle)


func show_reticle() -> void:
	if _reticle:
		_reticle.visible = true


func hide_reticle() -> void:
	if _reticle:
		_reticle.visible = false


## Stuck-avoidance (CHASING only, after move_and_slide): displacement stalling below
## the attempted speed steers perpendicular around the obstacle, flipping the side if
## still stuck after three thresholds.
func _detect_stuck_movement(pos_before: Vector3, delta: float) -> void:
	var attempted_speed := Vector2(velocity.x, velocity.z).length()
	var actual_disp := Vector2(global_position.x - pos_before.x, global_position.z - pos_before.z).length()
	if attempted_speed <= 0.5 or actual_disp >= delta * 0.5:
		_stuck_time = 0.0
		return
	_stuck_time += delta
	if _stuck_time > STUCK_THRESHOLD and target and is_instance_valid(target):
		var to_target := (target.global_position - global_position)
		var dir := Vector3(to_target.x, 0, to_target.z).normalized()
		var perp := Vector3(-dir.z, 0, dir.x) * _stuck_side
		velocity.x = perp.x * attempted_speed * 0.7
		velocity.z = perp.z * attempted_speed * 0.7
		if _stuck_time > STUCK_THRESHOLD * 3:
			_stuck_side *= -1.0
			_stuck_time = STUCK_THRESHOLD


# ── Status Effects ──────────────────────────────────────────────────────────

func _try_apply_status(hit_element: String, level: int) -> void:
	var status_type: String = CombatManager.roll_element_status(hit_element)
	if status_type.is_empty():
		return

	# Trigger chance: 10% + 10% per level
	var chance := 0.10 + 0.10 * float(level)
	if randf() > chance:
		return

	# Devil is instant — reduce to 1/4 HP
	if status_type == "devil":
		var old_hp := current_hp
		current_hp = maxi(current_hp / 4, 1)
		var devil_dmg := old_hp - current_hp
		_spawn_damage_number(str(devil_dmg), Color(0.6, 0.0, 0.8))
		if current_hp <= 0:
			_die()
		return

	apply_status_effect(status_type)


func apply_status_effect(status_type: String) -> void:
	# Don't stack same status
	for fx in _status_effects:
		if fx.type == status_type:
			return

	var fx_def: Dictionary = CombatManager.STATUS_EFFECTS.get(status_type, {})
	if fx_def.is_empty():
		return

	var duration: float = float(fx_def.get("duration", 2))
	var phase: String = "immobilize" if status_type == "stun" else ""
	_status_effects.append({"type": status_type, "timer": duration, "dot_timer": 0.0, "phase": phase})
	_spawn_damage_number(status_type.capitalize() + "!", STATUS_COLORS.get(status_type, Color.WHITE))
	_update_status_visuals()
	_update_immobilized()


func _process_status_effects(delta: float) -> void:
	if _status_effects.is_empty():
		return

	var expired: Array = []

	for fx in _status_effects:
		fx.timer -= delta

		# Stun phase transition: immobilize → no_attack
		if fx.type == "stun" and fx.phase == "immobilize":
			var fx_def_stun: Dictionary = CombatManager.STATUS_EFFECTS.get("stun", {})
			var immob_dur: float = float(fx_def_stun.get("immobilize_duration", 1))
			var total_dur: float = float(fx_def_stun.get("duration", 3))
			var elapsed: float = total_dur - fx.timer
			if elapsed >= immob_dur:
				fx.phase = "no_attack"

		# DoT (burn, poison)
		var fx_def: Dictionary = CombatManager.STATUS_EFFECTS.get(fx.type, {})
		var dot_pct: float = float(fx_def.get("dot_percent", 0.0))
		if dot_pct > 0.0:
			fx.dot_timer += delta
			if fx.dot_timer >= DOT_TICK_INTERVAL:
				fx.dot_timer -= DOT_TICK_INTERVAL
				var max_hp := 100
				if enemy_data:
					max_hp = enemy_data.hp_base
				var dot_damage: int = maxi(int(float(max_hp) * dot_pct), 1)
				current_hp -= dot_damage
				_spawn_damage_number(str(dot_damage), STATUS_COLORS.get(fx.type, Color.RED))

		if fx.timer <= 0:
			expired.append(fx)

	for fx in expired:
		_status_effects.erase(fx)

	if current_hp <= 0 and is_alive:
		_die()

	# Update immobilized/no-attack state every frame (stun phase transitions)
	_update_immobilized()

	if not expired.is_empty():
		_update_status_visuals()


func _break_on_hit_effects() -> void:
	var broke: Array = []
	for fx in _status_effects:
		var fx_def: Dictionary = CombatManager.STATUS_EFFECTS.get(fx.type, {})
		if fx_def.get("breaks_on_hit", false):
			broke.append(fx)
	for fx in broke:
		_status_effects.erase(fx)
	if not broke.is_empty():
		_update_status_visuals()
		_update_immobilized()


func _update_immobilized() -> void:
	_is_immobilized = false
	_stun_no_attack = false
	for fx in _status_effects:
		if fx.type == "stun":
			if fx.phase == "immobilize":
				_is_immobilized = true
			else:
				_stun_no_attack = true
		else:
			var fx_def: Dictionary = CombatManager.STATUS_EFFECTS.get(fx.type, {})
			if float(fx_def.get("skip_chance", 0.0)) >= 1.0:
				_is_immobilized = true


func _update_status_visuals() -> void:
	if not model:
		return
	if _status_effects.is_empty():
		_set_model_tint(Color.WHITE)
		return
	# Use the color of the most recent status
	var latest: Dictionary = _status_effects[_status_effects.size() - 1]
	var tint: Color = STATUS_COLORS.get(latest.type, Color.WHITE)
	_set_model_tint(tint)


func _set_model_tint(tint: Color) -> void:
	for mat in _cached_materials:
		mat.albedo_color = tint

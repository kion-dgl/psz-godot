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
## Player collision radius used by the arc test (the target's radius). Real value isn't
## exposed cheaply; melee reach dwarfs it, so a constant is fine.
## ponytail: constant player radius, read the real shape if arc precision ever matters.
const PLAYER_HIT_RADIUS: float = 0.5

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
var _reticle: Sprite3D
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

	_rng.randomize()
	_apply_difficulty()

	# Randomize initial wander timer so enemies don't sync up
	wander_timer = randf_range(0.0, WANDER_INTERVAL_MAX)
	_setup_reticle()


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
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target = players[0]


func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	# Kill enemy if it falls off the stage
	if global_position.y < -10.0:
		_die()
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

	# Apply gravity
	if not is_on_floor():
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
		var attempted_speed := Vector2(velocity.x, velocity.z).length()
		var actual_disp := Vector2(global_position.x - pos_before.x, global_position.z - pos_before.z).length()
		if attempted_speed > 0.5 and actual_disp < delta * 0.5:
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
		else:
			_stuck_time = 0.0

	# Safety: if enemy ends up over empty space, stop horizontal movement
	if (velocity.x * velocity.x + velocity.z * velocity.z) > 0.001:
		if not _has_floor_at(global_position):
			velocity.x = 0
			velocity.z = 0


func _process_idle(delta: float) -> void:
	# Try to find target if we don't have one
	if not target or not is_instance_valid(target):
		_find_target()

	# Check if target is in detection range - become alert!
	if target and is_instance_valid(target):
		var dist := global_position.distance_to(target.global_position)
		if enemy_data and dist <= _detection_range:
			current_state = EnemyState.CHASING
			is_wandering = false
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
		_play_animation("wat")


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


func _process_chasing(_delta: float) -> void:
	if not target or not is_instance_valid(target):
		current_state = EnemyState.IDLE
		return

	var dist := global_position.distance_to(target.global_position)

	# Check if in attack range
	var attack_range := 2.0
	if enemy_data:
		attack_range = enemy_data.attack_range

	# Gate: cooldown ready AND some non-berserk attack band contains the distance
	# (spec /mechanics/enemy-attacks "Selection"). Falls back to the flat attack_range
	# only when this enemy has no attack table.
	if attack_cooldown_timer <= 0 and not _stun_no_attack and _has_attack_in_band(dist, attack_range):
		current_state = EnemyState.ATTACKING
		_start_attack()
		return

	# Determine if charging (close to target) or walking (far from target)
	var charge_range := attack_range * CHARGE_RANGE_MULT
	var is_charging := dist <= charge_range

	# Use appropriate animation and speed
	if is_charging:
		_play_animation("run")
	else:
		_play_animation("wlk")

	# Calculate direction to target (horizontal only, properly normalized)
	var to_target := target.global_position - global_position
	var horizontal_dir := Vector3(to_target.x, 0, to_target.z)
	var direction := horizontal_dir.normalized() if horizontal_dir.length() > 0.1 else Vector3.ZERO

	# Try navigation if available (update path every 10th frame to save CPU)
	if Engine.get_physics_frames() % 10 == (get_index() % 10):
		nav_agent.target_position = target.global_position
	if not nav_agent.is_navigation_finished():
		var next_pos := nav_agent.get_next_path_position()
		var nav_dir := (next_pos - global_position)
		nav_dir.y = 0
		# Only use nav direction if it's valid (not pointing at ourselves)
		if nav_dir.length() > 0.5:
			direction = nav_dir.normalized()

	# Apply movement - walk normally, run when charging
	var base_speed := 3.0
	if enemy_data:
		base_speed = enemy_data.move_speed

	var speed := base_speed * WALK_SPEED_MULT
	if is_charging:
		speed = base_speed * CHARGE_SPEED_MULT

	# Apply movement toward target
	if direction.length() > 0.1 and _can_move_to(direction):
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		_face_direction(direction)


func _process_attacking(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0

	# Advance the position within the attack clip. Prefer the real animation
	# position; fall back to an accumulating timer for no-clip rigs (and tests).
	if _attack_anim != "" and animation_player and animation_player.current_animation == _attack_anim:
		_attack_pos = animation_player.current_animation_position
	else:
		_attack_pos += delta

	# Frame-tied damage window: [windup_frac, damage_end_frac] of the clip length.
	# Difficulty shortens the windup (reaction). Damage lands on the first frame the
	# target passes the arc test; one resolution (hit or dodge) per attack (#509).
	if is_attacking and not _attack_hit_resolved and not _attack_def.is_empty():
		var window_start: float = float(_attack_def.get("windup_frac", 0.35)) * _attack_clip_len * _aggro_reaction
		var window_end: float = float(_attack_def.get("damage_end_frac", 0.6)) * _attack_clip_len
		if _attack_pos >= window_start and _attack_pos <= window_end:
			_try_attack_hit()

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


func _process_loafing(delta: float) -> void:
	loaf_timer -= delta

	# When loaf time is up, go back to chasing
	if loaf_timer <= 0:
		current_state = EnemyState.CHASING
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
		_play_animation("wlk")
	else:
		# Can't move that way, try reversing curve direction
		loaf_curve_rate = -loaf_curve_rate
		velocity.x = 0
		velocity.z = 0
		_play_animation("wat")


func _start_loafing() -> void:
	current_state = EnemyState.LOAFING
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


func _start_attack() -> void:
	if not target or not is_instance_valid(target):
		return

	is_attacking = true

	# Select the attack by range band + weight, then resolve its clip.
	var dist := global_position.distance_to(target.global_position)
	_attack_def = _select_attack_for(dist)
	_attack_hit_resolved = false
	_attack_pos = 0.0

	_attack_anim = _play_animation(String(_attack_def.get("clip", "atk")), true)
	if _attack_anim.is_empty():
		# Rig has no resolvable attack clip — timeline fractions apply to the
		# fixed fallback duration; end the attack on that same timer.
		_attack_fallback_timer = ATTACK_FALLBACK_DURATION
		_attack_clip_len = ATTACK_FALLBACK_DURATION
	else:
		var anim := animation_player.get_animation(_attack_anim)
		_attack_clip_len = anim.length if anim else ATTACK_FALLBACK_DURATION
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
## ponytail: projectile/lob/charge/leap resolve through this same arc as an interim —
## their travel mechanics are deferred (#494); no enemy is left on instant damage.
func _try_attack_hit() -> void:
	if not target or not is_instance_valid(target):
		return
	var reach := float(_attack_def.get("hit_reach", 2.0))
	var half := float(_attack_def.get("hit_half_angle_deg", 45.0))
	if not EnemyAttackLogic.arc_hit_test(global_position, _attack_facing,
			target.global_position, PLAYER_HIT_RADIUS, half, reach):
		return
	_attack_hit_resolved = true
	var base_attack: int = enemy_data.attack_base if enemy_data else 10
	var dmg := int(round(float(base_attack) * float(_attack_def.get("damage_mult", 1.0))))
	if target.has_method("take_damage"):
		target.take_damage(dmg)


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

	var final_damage: int = int(int(result.get("damage", raw_damage)) * damage_mult)
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
		_attack_anim = ""
		current_state = EnemyState.HURT
		hurt_timer = HURT_DURATION
		velocity = Vector3.ZERO  # Stop movement during stagger

		_play_animation("dmg", true)  # Force play damage animation
		_play_sfx("damage")


func _die() -> void:
	is_alive = false
	is_attacking = false
	current_state = EnemyState.DEAD
	died.emit(self)

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
	var height := 1.5
	if enemy_data:
		height = enemy_data.collision_height
	_reticle = TargetReticle.build(height + 0.5)
	add_child(_reticle)


func show_reticle() -> void:
	if _reticle:
		_reticle.visible = true


func hide_reticle() -> void:
	if _reticle:
		_reticle.visible = false


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

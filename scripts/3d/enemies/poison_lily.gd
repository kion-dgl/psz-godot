class_name PoisonLily extends EnemyBase
## Poison Lily — stationary plant enemy that wakes when the player approaches.
## The sleep/wake cycle (spec /states/enemies §poison-lily) stays bespoke in this
## script; the ATTACKS themselves now run through the base frame-tied machinery and
## the authored table in data/enemy_attacks.json (#629) — `bite` (melee_arc, band
## 0-3) and `poison_spit` (projectile, band 3-12) select by range band like every
## other enemy, instead of this script's old hardcoded midpoint/MELEE_RANGE split.
## The spit's on-hit poison DoT (3 dmg/s for 5s) rides the _projectile_on_hit hook.

const POISON_DURATION := 5.0
const POISON_TICK_DAMAGE := 3

enum LilyState { SLEEPING, WAKING, IDLE_AWAKE, HURT, DYING }
var _lily_state: LilyState = LilyState.SLEEPING

const ANIM := {
	"sleep": "waitc_re2_b_root",
	"wake": "wake_re2_b_root",
	"idle": "waito_re2_b_root",
	"attack": "attack_re2_b_root",
	"damage": "damege_re2_b_root",
	"die": "die_re2_b_root",
}


func _ready() -> void:
	super._ready()
	if model:
		print("[PoisonLily] Model loaded and scaled at %s" % global_position)
	else:
		print("[PoisonLily] WARNING: No model loaded at %s (model_id=%s)" % [global_position, enemy_data.model_id if enemy_data else "?"])


func _play_lily_anim(key: String, looping: bool = false) -> void:
	var anim_name: String = ANIM.get(key, "")
	if anim_name.is_empty() or not animation_player:
		return
	if animation_player.has_animation(anim_name):
		var anim := animation_player.get_animation(anim_name)
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
		animation_player.play(anim_name)


func _physics_process(delta: float) -> void:
	if not is_alive or current_state == EnemyState.DEAD:
		return

	# Override EnemyBase locomotion — Poison Lily never moves.
	velocity = Vector3.ZERO

	if not target or not is_instance_valid(target):
		target = _find_player()
		if not target:
			return

	# Attacks delegate to the base frame-tied machinery (selection by band, window
	# timeline, projectile release at window open, arc test for the bite).
	if current_state == EnemyState.ATTACKING:
		_process_attacking(delta)
		if current_state == EnemyState.LOAFING:
			# The lily doesn't loaf — straight back to awake idle (override below).
			current_state = EnemyState.IDLE
			_lily_state = LilyState.IDLE_AWAKE
			_play_lily_anim("idle", true)
		return

	var dist: float = global_position.distance_to(target.global_position)
	var det_range: float = enemy_data.detection_range if enemy_data else 12.0

	match _lily_state:
		LilyState.SLEEPING:
			_play_lily_anim("sleep", true)
			if dist <= det_range:
				_wake()

		LilyState.WAKING:
			_face_target()

		LilyState.IDLE_AWAKE:
			_face_target()
			if dist > det_range:
				_lily_state = LilyState.SLEEPING
				_play_lily_anim("sleep", true)
			elif attack_cooldown_timer <= 0 and _has_attack_in_band(dist, enemy_data.attack_range):
				# Commit to a swing from the authored table: bite up close, spit at
				# range. Waking was the telegraph — no generic hold.
				_lily_state = LilyState.IDLE_AWAKE  # stays; base states drive the swing
				current_state = EnemyState.ATTACKING
				is_attacking = true
				_attack_def = _select_attack_for(dist)
				_start_attack()

		LilyState.HURT:
			pass


func _wake() -> void:
	_lily_state = LilyState.WAKING
	_play_lily_anim("wake")
	_face_target()
	if animation_player and not animation_player.animation_finished.is_connected(_on_wake_finished):
		animation_player.animation_finished.connect(_on_wake_finished, CONNECT_ONE_SHOT)


func _on_wake_finished(_anim_name: String) -> void:
	if _lily_state == LilyState.WAKING:
		_lily_state = LilyState.IDLE_AWAKE
		_play_lily_anim("idle", true)


## Rooted: the base loaf would walk a semicircle — stand at the awake idle instead.
func _start_loafing() -> void:
	current_state = EnemyState.LOAFING  # caller (this script) immediately re-routes to idle
	_telegraphing = false
	_vulnerable_mult = 1.0


## The spit's extra effect: poison DoT on the player (3 dmg/s for 5s).
func _projectile_on_hit() -> Callable:
	return func(body: Node3D) -> void: _apply_poison_to(body)


func _apply_poison_to(body: Node3D) -> void:
	# Simple poison DoT — attach a timer to the player
	var poison_node := Node.new()
	poison_node.name = "PoisonDoT"
	body.add_child(poison_node)

	var ticks_remaining: int = int(POISON_DURATION)
	var tick_dmg: int = POISON_TICK_DAMAGE
	var target_body := body

	var tick_fn: Callable
	tick_fn = func() -> void:
		if ticks_remaining <= 0 or not is_instance_valid(target_body):
			if is_instance_valid(poison_node):
				poison_node.queue_free()
			return
		ticks_remaining -= 1
		if target_body.has_method("take_damage"):
			target_body.take_damage(tick_dmg)
		if ticks_remaining > 0:
			get_tree().create_timer(1.0).timeout.connect(tick_fn)

	get_tree().create_timer(1.0).timeout.connect(tick_fn)
	print("[PoisonLily] Applied poison to %s for %ds" % [body.name, ticks_remaining])


func _face_target() -> void:
	if not target or not is_instance_valid(target):
		return
	var dir := target.global_position - global_position
	dir.y = 0
	if dir.length() > 0.01:
		rotation.y = atan2(dir.x, dir.z)
		if model:
			model.rotation.y = 0


func _die() -> void:
	_lily_state = LilyState.DYING
	_play_lily_anim("die")
	super._die()


func _on_hit_received(raw_damage: int, knockback: Vector3, accuracy: int = 100, hit_element: String = "", hit_element_level: int = 0) -> void:
	# Being hit wakes a sleeping lily (spec §poison-lily).
	if _lily_state == LilyState.SLEEPING:
		_wake()

	# Play the damage animation briefly but don't override death
	if _lily_state != LilyState.DYING:
		_lily_state = LilyState.HURT
		_play_lily_anim("damage")
		if animation_player:
			animation_player.animation_finished.connect(func(_n: String) -> void:
				if _lily_state == LilyState.HURT:
					_lily_state = LilyState.IDLE_AWAKE
					# super set the BASE state to HURT and this script never runs the
					# base hurt handler — clear it or the ATTACKING branch below would
					# never fire again.
					current_state = EnemyState.IDLE
					_play_lily_anim("idle", true)
			, CONNECT_ONE_SHOT)

	super._on_hit_received(raw_damage, knockback, accuracy, hit_element, hit_element_level)

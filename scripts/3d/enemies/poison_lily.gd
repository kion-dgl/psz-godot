class_name PoisonLily extends EnemyBase
## Poison Lily — stationary plant enemy that wakes when player approaches.
## Melee attacks at close range, fires poison projectiles at distance.

const PSO_SCALE := Vector3(0.09, 0.09, 0.09)
const MELEE_RANGE := 3.0
const PROJECTILE_SPEED := 12.0
const POISON_DURATION := 5.0
const POISON_TICK_DAMAGE := 3

enum LilyState { SLEEPING, WAKING, IDLE_AWAKE, ATTACKING, HURT, DYING }
var _lily_state: LilyState = LilyState.SLEEPING
var _attack_timer: float = 0.0
var _attack_fired: bool = false

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
		model.scale = PSO_SCALE
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

	# Process active projectiles
	var i := _active_projectiles.size() - 1
	while i >= 0:
		var proj: Area3D = _active_projectiles[i]
		if is_instance_valid(proj):
			_process_projectile(proj, delta)
		else:
			_active_projectiles.remove_at(i)
		i -= 1

	_attack_timer -= delta

	# Override EnemyBase movement — Poison Lily never moves
	velocity = Vector3.ZERO

	if not target or not is_instance_valid(target):
		target = _find_player()
		if not target:
			return

	var dist: float = global_position.distance_to(target.global_position)
	var det_range: float = enemy_data.detection_range if enemy_data else 12.0

	match _lily_state:
		LilyState.SLEEPING:
			if dist <= det_range:
				_lily_state = LilyState.WAKING
				_play_lily_anim("wake")
				_face_target()
				if animation_player and not animation_player.animation_finished.is_connected(_on_wake_finished):
					animation_player.animation_finished.connect(_on_wake_finished, CONNECT_ONE_SHOT)

		LilyState.WAKING:
			_face_target()

		LilyState.IDLE_AWAKE:
			_face_target()
			if dist > det_range:
				_lily_state = LilyState.SLEEPING
				_play_lily_anim("sleep", true)
			elif _attack_timer <= 0:
				_start_attack(dist)

		LilyState.ATTACKING:
			pass

		LilyState.HURT:
			pass


func _on_wake_finished(_anim_name: String) -> void:
	if _lily_state == LilyState.WAKING:
		_lily_state = LilyState.IDLE_AWAKE
		_play_lily_anim("idle", true)


func _start_attack(dist: float) -> void:
	_lily_state = LilyState.ATTACKING
	_attack_fired = false
	_play_lily_anim("attack")
	var cooldown: float = enemy_data.attack_cooldown if enemy_data else 3.0
	_attack_timer = cooldown

	# Fire damage/projectile at mid-animation via timer
	var attack_delay: float = 0.4
	if animation_player and animation_player.has_animation(ANIM["attack"]):
		attack_delay = animation_player.get_animation(ANIM["attack"]).length * 0.5

	var is_melee: bool = dist <= MELEE_RANGE
	get_tree().create_timer(attack_delay).timeout.connect(func() -> void:
		if not is_alive or _lily_state != LilyState.ATTACKING:
			return
		_attack_fired = true
		if is_melee:
			_do_melee_attack()
		else:
			_fire_projectile()
	)

	if animation_player:
		animation_player.animation_finished.connect(_on_attack_finished, CONNECT_ONE_SHOT)


func _on_attack_finished(_anim_name: String) -> void:
	if _lily_state == LilyState.ATTACKING:
		_lily_state = LilyState.IDLE_AWAKE
		_play_lily_anim("idle", true)


func _do_melee_attack() -> void:
	if not target or not is_instance_valid(target):
		return
	var dist: float = global_position.distance_to(target.global_position)
	if dist <= MELEE_RANGE + 1.0 and target.has_method("take_damage"):
		var dmg: int = enemy_data.attack_base if enemy_data else 15
		target.take_damage(dmg)


func _fire_projectile() -> void:
	if not target or not is_instance_valid(target):
		return
	var proj := _create_poison_projectile()
	get_parent().add_child(proj)
	proj.global_position = global_position + Vector3(0, 1.0, 0)
	_active_projectiles.append(proj)
	print("[PoisonLily] Fired projectile toward %s" % target.name)


func _create_poison_projectile() -> Node3D:
	var proj := Area3D.new()
	proj.name = "PoisonProjectile"
	proj.collision_layer = 0
	proj.collision_mask = 2  # Player layer

	# Collision shape
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	col.shape = sphere
	proj.add_child(col)

	# Visual — green glowing sphere
	var mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.15
	sphere_mesh.height = 0.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.8, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 0.1)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere_mesh.material = mat
	mesh.mesh = sphere_mesh
	proj.add_child(mesh)

	# Direction toward player
	var direction: Vector3 = Vector3.ZERO
	if target and is_instance_valid(target):
		direction = (target.global_position + Vector3(0, 1, 0) - proj.global_position).normalized()

	var speed: float = PROJECTILE_SPEED
	var dmg: int = enemy_data.attack_base if enemy_data else 15
	var max_dist: float = enemy_data.detection_range * 1.5 if enemy_data else 18.0
	var start_pos := global_position

	# Attach script behavior via _process
	var elapsed: float = 0.0
	proj.set_meta("direction", direction)
	proj.set_meta("speed", speed)
	proj.set_meta("damage", dmg)
	proj.set_meta("max_dist", max_dist)
	proj.set_meta("start_pos", start_pos)
	proj.set_meta("hit", false)

	proj.body_entered.connect(func(body: Node3D) -> void:
		if proj.get_meta("hit"):
			return
		if body.is_in_group("player") and body.has_method("take_damage"):
			proj.set_meta("hit", true)
			body.take_damage(proj.get_meta("damage"))
			_apply_poison_to(body)
			proj.queue_free()
	)

	return proj


func _process_projectile(proj: Area3D, delta: float) -> void:
	var dir: Vector3 = proj.get_meta("direction", Vector3.ZERO)
	var spd: float = proj.get_meta("speed", 10.0)
	var max_d: float = proj.get_meta("max_dist", 20.0)
	var start: Vector3 = proj.get_meta("start_pos", Vector3.ZERO)
	proj.global_position += dir * spd * delta
	if proj.global_position.distance_to(start) > max_d:
		proj.queue_free()


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
			print("[PoisonLily] Poison tick: %d damage (%d ticks left)" % [tick_dmg, ticks_remaining])
		if ticks_remaining > 0:
			get_tree().create_timer(1.0).timeout.connect(tick_fn)

	get_tree().create_timer(1.0).timeout.connect(tick_fn)
	print("[PoisonLily] Applied poison to %s for %ds" % [body.name, ticks_remaining])


var _active_projectiles: Array[Area3D] = []


func _face_target() -> void:
	if not target or not is_instance_valid(target):
		return
	var dir := target.global_position - global_position
	dir.y = 0
	if dir.length() > 0.01:
		rotation.y = atan2(dir.x, dir.z)
		if model:
			model.rotation.y = 0


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0] as Node3D
	return null


func _die() -> void:
	_lily_state = LilyState.DYING
	_play_lily_anim("die")
	super._die()


func take_damage(amount: int, knockback: Vector3 = Vector3.ZERO, accuracy: int = 100) -> void:
	if _lily_state == LilyState.SLEEPING:
		_lily_state = LilyState.WAKING
		_play_lily_anim("wake")
		if animation_player:
			animation_player.animation_finished.connect(_on_wake_finished, CONNECT_ONE_SHOT)

	# Play damage animation briefly but don't override death
	if _lily_state != LilyState.DYING:
		var prev_state := _lily_state
		_lily_state = LilyState.HURT
		_play_lily_anim("damage")
		if animation_player:
			animation_player.animation_finished.connect(func(_n: String) -> void:
				if _lily_state == LilyState.HURT:
					_lily_state = LilyState.IDLE_AWAKE
					_play_lily_anim("idle", true)
			, CONNECT_ONE_SHOT)

	# Apply damage using parent logic
	super.take_damage(amount, knockback, accuracy)

class_name ReyburnBoss extends EnemyBase
## Reyburn — the Gurhacia Valley dragon boss (psz-re boss_dragon / s01z).
##
## A phase-driven boss that replaces the plain "walk up and melee" behaviour a
## generic EnemyBase would give it. Behaviour is data-driven from
## data/boss_arenas.json (the authored kit, clips verified against the z_001
## animation set in data/re_reference/boss_reyburn.json):
##
##   * ground phase — walks the arena (wlk1) with the full melee + breath kit:
##     bite / rush-bite charge / tail swipes / wing-flap knockback / war-cry AoE
##     / a three-shot fireball volley. Opens with the tht roar.
##   * flight phase — periodically takes off, repositions, and drops a land-slam
##     AoE where it comes down.
##   * enrage — below 35% HP it speeds up, its cooldowns shorten, it growls, and
##     a red glow marks the shift (a modifier overlay, not a separate moveset).
##
## HP (1650), the arena and the model come from data/enemies/reyburn.tres. This
## reuses EnemyBase for HP/damage/death/animation resolution; the phase + attack
## logic lives here (the sanctioned bespoke-subclass pattern — see poison_lily.gd).

const KIT_PATH := "res://data/boss_arenas.json"
const ENRAGE_FRAC := 0.35

enum S { INTRO, GROUND, TELEGRAPH, ATTACK, LOAF, FLIGHT_OUT, FLIGHT_HOVER, FLIGHT_SLAM, DEAD }

var _s: S = S.INTRO
var _t: float = 0.0                 # generic per-state timer
var _cooldown: float = 0.0
var _flight_clock: float = 0.0
var _enraged := false
var _max_hp: int = 1650

# tuning pulled from boss_arenas.json (defaults are the reyburn values)
var _move_speed := 4.0
var _turn_speed := deg_to_rad(120.0)
var _attack_base := 12
var _atk_cooldown := 2.5
var _flight_interval := 22.0
var _hover_height := 8.0
var _fly_speed_mult := 2.5
var _loaf_min := 2.5
var _loaf_max := 4.5
var _enrage_speed_mult := 1.3
var _enrage_cd_mult := 0.6

var _ground_attacks: Array = []
var _flight_attacks: Array = []
var _cur: Dictionary = {}           # attack currently telegraphing/executing
var _attack_done := false           # damage already applied this swing
var _ground_y: float = 0.0
var _fly_target: Vector3 = Vector3.ZERO
var _glow: OmniLight3D = null


func _ready() -> void:
	super._ready()
	_max_hp = enemy_data.hp_base if enemy_data else 1650
	_ground_y = global_position.y
	_load_kit()
	if model:
		model.scale = Vector3.ONE * 1.0
	_s = S.INTRO
	_t = 1.2
	_play("tht")                    # war-cry opener


func _load_kit() -> void:
	if not ResourceLoader.exists(KIT_PATH) and not FileAccess.file_exists(KIT_PATH):
		return
	var f := FileAccess.open(KIT_PATH, FileAccess.READ)
	if not f: return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY: return
	var bosses: Dictionary = data.get("bosses", data)
	var b: Dictionary = bosses.get("reyburn", {})
	if b.is_empty(): return
	var st: Dictionary = b.get("stats", {})
	_move_speed = float(st.get("move_speed", _move_speed))
	_turn_speed = deg_to_rad(float(st.get("turn_speed_deg", 120.0)))
	_attack_base = int(st.get("attack_base", _attack_base))
	_atk_cooldown = float(st.get("attack_cooldown", _atk_cooldown))
	var fsm: Dictionary = b.get("fsm", {})
	_flight_interval = float(fsm.get("flight_interval", _flight_interval))
	_hover_height = float(fsm.get("hover_height", _hover_height))
	_fly_speed_mult = float(fsm.get("fly_speed_mult", _fly_speed_mult))
	_loaf_min = float(fsm.get("loaf_duration_min", _loaf_min))
	_loaf_max = float(fsm.get("loaf_duration_max", _loaf_max))
	for ph in b.get("phases", []):
		if ph.get("id") == "enrage":
			_enrage_speed_mult = float(ph.get("speed_mult", _enrage_speed_mult))
			_enrage_cd_mult = float(ph.get("cooldown_mult", _enrage_cd_mult))
	for a in b.get("attacks", []):
		var phases: Array = a.get("phases", ["ground"])
		if "flight" in phases: _flight_attacks.append(a)
		else: _ground_attacks.append(a)


# ---- main loop --------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not is_alive or _s == S.DEAD:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_flight_clock += delta
	if not _enraged and current_hp <= int(_max_hp * ENRAGE_FRAC):
		_enter_enrage()

	if not target or not is_instance_valid(target):
		target = _find_player()
		if not target:
			return
	var dist: float = _planar_dist(target.global_position)

	match _s:
		S.INTRO: _tick_intro(delta)
		S.GROUND: _tick_ground(delta, dist)
		S.TELEGRAPH: _tick_telegraph(delta)
		S.ATTACK: _tick_attack(delta)
		S.LOAF: _tick_loaf(delta)
		S.FLIGHT_OUT: _tick_flight_out(delta)
		S.FLIGHT_HOVER: _tick_flight_hover(delta)
		S.FLIGHT_SLAM: _tick_flight_slam(delta)


func _tick_intro(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()
	_t -= delta
	if _t <= 0.0:
		_s = S.GROUND


func _tick_ground(delta: float, dist: float) -> void:
	_face(target.global_position, delta)
	_apply_gravity(delta)
	if _flight_attacks.size() > 0 and _flight_clock >= _flight_interval and _cooldown <= 0.0:
		_begin_flight()
	elif _cooldown <= 0.0 and _pick_ground_attack(dist):
		pass                                       # _pick_ground_attack sets _s = TELEGRAPH
	else:
		_walk_toward(target.global_position, delta)
	move_and_slide()


func _tick_telegraph(delta: float) -> void:
	_face(target.global_position, delta)
	velocity = Vector3.ZERO
	_apply_gravity(delta)
	move_and_slide()
	_t -= delta
	if _t <= 0.0:
		_execute_attack()


func _tick_attack(delta: float) -> void:
	_apply_gravity(delta)
	# charge attacks keep lunging forward during the swing
	if _cur.get("kind") == "charge" and not _attack_done:
		velocity.x = -sin(rotation.y) * _move_speed * _speed_mult() * 1.8
		velocity.z = -cos(rotation.y) * _move_speed * _speed_mult() * 1.8
	else:
		velocity.x = 0; velocity.z = 0
	move_and_slide()
	_t -= delta
	if not _attack_done and _t <= _cur.get("_hit_at", 0.0):
		_apply_attack_effect()
	if _t <= 0.0:
		_enter_loaf()


func _tick_loaf(delta: float) -> void:
	_face(target.global_position, delta)
	velocity = Vector3.ZERO
	_apply_gravity(delta)
	move_and_slide()
	_t -= delta
	if _t <= 0.0:
		_s = S.GROUND


func _tick_flight_out(delta: float) -> void:
	# rise to hover height and move to the reposition point
	global_position.y = lerpf(global_position.y, _ground_y + _hover_height, delta * 2.0)
	var to := (_fly_target - global_position)
	to.y = 0
	if to.length() > 1.0:
		var v := to.normalized() * _move_speed * _fly_speed_mult
		global_position.x += v.x * delta
		global_position.z += v.z * delta
	_t -= delta
	if _t <= 0.0:
		_s = S.FLIGHT_HOVER
		_t = 1.0
		_play("fly")


func _tick_flight_hover(delta: float) -> void:
	_face(target.global_position, delta)
	_t -= delta
	if _t <= 0.0:
		# come down onto the player's position for the slam
		_fly_target = target.global_position
		_s = S.FLIGHT_SLAM
		_t = 0.8
		_attack_done = false
		_play("gld2claw")


func _tick_flight_slam(delta: float) -> void:
	var tp := _fly_target; tp.y = _ground_y
	global_position = global_position.lerp(tp, delta * 6.0)
	_t -= delta
	if not _attack_done and global_position.y <= _ground_y + 0.6:
		_attack_done = true
		global_position.y = _ground_y
		_aoe_burst(6.0, 180.0, int(_attack_base * 1.5))
	if _t <= 0.0:
		global_position.y = _ground_y
		_flight_clock = 0.0
		_play("claw2wat")
		_enter_loaf()


# ---- attack selection & execution ------------------------------------------
func _pick_ground_attack(dist: float) -> bool:
	var choices: Array = []
	for a in _ground_attacks:
		var lo := float(a.get("min_range", 0.0))
		var hi := float(a.get("max_range", 6.0))
		if dist >= lo and dist <= hi:
			var w := float(a.get("weight", 1.0))
			choices.append([a, w])
	if choices.is_empty():
		return false
	var total := 0.0
	for c in choices: total += c[1]
	var roll := randf() * total
	var chosen: Dictionary = choices[0][0]
	for c in choices:
		roll -= c[1]
		if roll < 0.0:
			chosen = c[0]; break
	_begin_attack(chosen)
	return true


func _begin_attack(a: Dictionary) -> void:
	_cur = a.duplicate(true)
	_s = S.TELEGRAPH
	# telegraph is a short wind-up before the clip's damage frame
	_t = 0.35
	_attack_done = false
	# play the first clip of the chain (or the attack clip)
	var chain: Array = a.get("chain", [])
	_play(chain[0] if chain.size() > 0 else a.get("clip", "atkh1"))


func _execute_attack() -> void:
	# start the swing proper: play the striking clip and set its length
	var clip: String = _cur.get("clip", "atkh1")
	_play(clip, true)
	var length := 0.8
	if animation_player:
		var full := _find_animation(clip)
		if full != "" and animation_player.has_animation(full):
			length = maxf(0.4, animation_player.get_animation(full).length)
	_s = S.ATTACK
	_t = length
	_cur["_hit_at"] = length * 0.45         # apply damage ~55% through the clip
	_attack_done = false


func _apply_attack_effect() -> void:
	_attack_done = true
	var kind: String = _cur.get("kind", "melee_arc")
	var dmg := int(_attack_base * float(_cur.get("damage_mult", 1.0)))
	match kind:
		"projectile", "lob":
			var n := int(_cur.get("split", _cur.get("lp_loops", 1)))
			for i in maxi(1, n):
				_spawn_fireball(dmg)
		"aoe_burst":
			_aoe_burst(float(_cur.get("hit_reach", 6.0)), float(_cur.get("hit_half_angle_deg", 180.0)), dmg)
		_:  # melee_arc, charge
			var reach := float(_cur.get("max_range", 4.0))
			var half := float(_cur.get("hit_half_angle_deg", 60.0))
			if _arc_hit(reach, half, dmg) and _cur.has("knockback"):
				_knockback_player(float(_cur.get("knockback", 0.0)))


func _enter_loaf() -> void:
	_s = S.LOAF
	_t = randf_range(_loaf_min, _loaf_max)
	_cooldown = _atk_cooldown * (_enrage_cd_mult if _enraged else 1.0)
	_play("wat")


func _begin_flight() -> void:
	_s = S.FLIGHT_OUT
	_t = 1.0
	# pick a reposition point on the far side of the arena from the player
	var away := (global_position - target.global_position)
	away.y = 0
	if away.length() < 1.0:
		away = Vector3(1, 0, 0)
	_fly_target = target.global_position + away.normalized() * 10.0
	_play("flst")                               # takeoff


# ---- damage helpers ---------------------------------------------------------
func _arc_hit(reach: float, half_angle_deg: float, dmg: int) -> bool:
	if not target or not is_instance_valid(target): return false
	var to := target.global_position - global_position
	to.y = 0
	if to.length() > reach: return false
	var facing := Vector3(-sin(rotation.y), 0, -cos(rotation.y))
	if to.length() > 0.01 and rad_to_deg(facing.angle_to(to.normalized())) > half_angle_deg:
		return false
	if target.has_method("take_damage"):
		target.take_damage(dmg)
	return true


func _aoe_burst(radius: float, half_angle_deg: float, dmg: int) -> void:
	# radial burst around the dragon; half_angle 180 = full circle
	if not target or not is_instance_valid(target): return
	var to := target.global_position - global_position
	to.y = 0
	if to.length() <= radius:
		if half_angle_deg >= 179.0:
			if target.has_method("take_damage"): target.take_damage(dmg)
		else:
			_arc_hit(radius, half_angle_deg, dmg)
	_spawn_shockwave(radius)


func _knockback_player(strength: float) -> void:
	if not target or not is_instance_valid(target): return
	var dir := Vector3(-sin(rotation.y), 0, -cos(rotation.y))
	if target.has_method("apply_knockback"):
		target.apply_knockback(dir * strength)
	elif "velocity" in target:
		target.velocity += dir * strength


func _spawn_fireball(dmg: int) -> void:
	if not target or not is_instance_valid(target): return
	var proj := Area3D.new()
	proj.collision_layer = 0
	proj.collision_mask = 2
	proj.monitoring = true
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new(); sph.radius = 0.5
	col.shape = sph
	proj.add_child(col)
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.35; sm.height = 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.05)
	mat.emission_energy_multiplier = 3.0
	sm.material = mat
	mesh.mesh = sm
	proj.add_child(mesh)
	proj.set_meta("hit", false)
	proj.body_entered.connect(func(body: Node3D) -> void:
		if proj.get_meta("hit"): return
		if body.is_in_group("player") and body.has_method("take_damage"):
			proj.set_meta("hit", true)
			body.take_damage(dmg)
			proj.queue_free())
	get_parent().add_child(proj)
	var start := global_position + Vector3(0, 1.6, 0)
	proj.global_position = start
	# slight spread per shot so a volley fans out
	var aim := (target.global_position + Vector3(0, 1, 0) - start).normalized()
	aim = aim.rotated(Vector3.UP, randf_range(-0.18, 0.18))
	var end := start + aim * 20.0
	var tw := proj.create_tween()
	tw.tween_property(proj, "global_position", end, 20.0 / 12.0)
	tw.tween_callback(proj.queue_free)


func _spawn_shockwave(radius: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.6
	tm.outer_radius = radius * 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.2, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.material = mat
	ring.mesh = tm
	get_parent().add_child(ring)
	ring.global_position = Vector3(global_position.x, _ground_y + 0.2, global_position.z)
	var tw := ring.create_tween()
	tw.parallel().tween_property(ring, "scale", Vector3.ONE * 1.4, 0.4)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.tween_callback(ring.queue_free)


# ---- phase / movement helpers ----------------------------------------------
func _enter_enrage() -> void:
	_enraged = true
	_play("tht")                                # growl
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.2, 0.1)
	_glow.light_energy = 2.5
	_glow.omni_range = 8.0
	_glow.position = Vector3(0, 2.0, 0)
	add_child(_glow)


func _speed_mult() -> float:
	return _enrage_speed_mult if _enraged else 1.0


func _walk_toward(pos: Vector3, _delta: float) -> void:
	var to := pos - global_position
	to.y = 0
	if to.length() <= 3.5:
		velocity.x = 0; velocity.z = 0
		return
	var v := to.normalized() * _move_speed * _speed_mult()
	velocity.x = v.x
	velocity.z = v.z
	_play("wlk1")


func _face(pos: Vector3, delta: float) -> void:
	var to := pos - global_position
	to.y = 0
	if to.length() < 0.01: return
	var want := atan2(to.x, to.z)
	rotation.y = rotate_toward(rotation.y, want, _turn_speed * delta)
	if model: model.rotation.y = 0


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0


func _planar_dist(pos: Vector3) -> float:
	var a := global_position; a.y = 0
	var b := pos; b.y = 0
	return a.distance_to(b)


func _play(short: String, force: bool = true) -> void:
	_play_animation(short, force)


# ---- base overrides ---------------------------------------------------------
func _on_hit_received(raw_damage: int, knockback: Vector3, accuracy: int = 100, hit_element: String = "", hit_element_level: int = 0) -> void:
	# Take damage/HP via the base, but never let it drop us into the base HURT
	# state machine — the boss drives its own states. Re-assert our state after.
	var prev := _s
	super._on_hit_received(raw_damage, knockback, accuracy, hit_element, hit_element_level)
	if is_alive and _s != S.DEAD:
		# base may have set current_state = HURT; ignore it, keep the boss FSM
		if prev in [S.INTRO]:
			_s = S.GROUND
		else:
			_s = prev


func _die() -> void:
	_s = S.DEAD
	if _glow and is_instance_valid(_glow):
		_glow.queue_free()
	super._die()

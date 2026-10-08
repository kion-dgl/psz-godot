extends RefCounted
class Rig extends EnemyBase:
	var allow_travel := true
	func _ready(): pass
	func _can_move_to(_dir: Vector3) -> bool: return allow_travel
	func _spawn_damage_number(_text: String, _color: Color = Color.WHITE): pass
class Target extends Node3D:
	var hits := 0
	var dodging := false
	func take_damage(_d: int, _v: Vector3 = Vector3.ZERO, _k: bool = false):
		if not dodging: hits += 1

static func run(r: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7007
	for id in ["helion", "blaze_helion"]:
		var attacks := EnemyAttackRegistry.get_attacks(id, 2.0)
		r.assert_eq(EnemyAttackLogic.select_attack(attacks, 1.5, rng).id, "claws", id + " claws selected close")
		r.assert_eq(EnemyAttackLogic.select_attack(attacks, 5.0, rng).id, "spin_lunge", id + " distant lunge selected")
	_test_motion(r, false)
	_test_motion(r, true)
	_test_interrupt(r)
	_test_clip(r)

static func _test_motion(r: Node, dodge: bool) -> void:
	var e := Rig.new()
	e.enemy_data = EnemyData.new()
	r.add_child(e)
	e.set_physics_process(false)
	var target := Target.new()
	r.add_child(target)
	target.position.z = 4.0
	target.dodging = dodge
	e.target = target
	e._attack_def = {"kind":"lunge", "max_range":7.0, "hit_reach":0.9, "windup_frac":0.15, "damage_end_frac":0.7}
	e._attack_kind = "lunge"
	e._attack_clip_len = 1.0
	e._attack_facing = Vector3.BACK
	e._lunge.begin(e, 4.0)
	e._attack_pos = 0.1
	e._process_attack_window()
	r.assert_eq(e.position.z, 0.0, "lunge preparation stationary")
	r.assert_eq(target.hits, 0, "lunge preparation harmless")
	# A large step must sweep through contact, not tunnel past the target.
	e._attack_pos = 0.7
	e._process_attack_window()
	r.assert_almost_eq(e.position.z, 4.5, 0.001, "lunge has bounded committed travel")
	r.assert_eq(target.hits, 0 if dodge else 1, "swept lunge contact respects dodge")
	target.dodging = false
	e._attack_pos = 0.9
	e._process_attack_window()
	r.assert_eq(target.hits, 0 if dodge else 1, "lunge cannot rehit in recovery")
	r.assert_almost_eq(e.position.z, 4.5, 0.001, "recovery does not snap model/body back")
	e._lunge.begin(e, 4.0)
	e.allow_travel = false
	e._lunge.step(e, 1.0)
	r.assert_almost_eq(e.position.z, 4.5, 0.001, "floor gate stops lunge travel")
	e.free()
	target.free()

static func _test_clip(r: Node) -> void:
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	var source := Animation.new()
	var track := source.add_track(Animation.TYPE_POSITION_3D)
	source.track_set_path(track, "Skeleton3D:Point_Spine01")
	source.position_track_insert_key(track, 0, Vector3(0,1,0))
	source.position_track_insert_key(track, 0.5, Vector3(2,3,8))
	library.add_animation("atkb", source)
	player.add_animation_library("", library)
	preload("res://scripts/3d/enemies/enemy_lunge.gd").prepare_clip(player, "atkb", "Point_Spine01")
	var fixed := player.get_animation("atkb")
	r.assert_eq(fixed.track_get_key_value(track, 1), Vector3(0,3,0), "in-place lunge preserves vertical pose")
	r.assert_eq(source.track_get_key_value(track, 1), Vector3(2,3,8), "lunge does not mutate shared source animation")
	player.free()

static func _test_interrupt(r: Node) -> void:
	var e := Rig.new()
	e.enemy_data = EnemyData.new()
	e.current_hp = 100
	r.add_child(e)
	e.set_physics_process(false)
	e._attack_def = {"kind":"lunge", "max_range":7.0}
	e._attack_facing = Vector3.BACK
	e.current_state = EnemyBase.EnemyState.ATTACKING
	e.is_attacking = true
	e._lunge.begin(e, 4.0)
	e._lunge.step(e, 0.25)
	var interrupted := e.position
	e._on_hit_received(1, Vector3.ZERO, 10000)
	r.assert_eq(e.current_state, EnemyBase.EnemyState.HURT, "hit interrupts lunge state")
	r.assert_true(not e.is_attacking, "hurt cancels lunge attack")
	e._physics_process(0.05)
	r.assert_almost_eq(e.position.z, interrupted.z, 0.001, "hurt cannot continue planar lunge travel")
	e._die()
	e._physics_process(0.05)
	r.assert_almost_eq(e.position.z, interrupted.z, 0.001, "dead enemy cannot continue lunge travel")
	e.free()

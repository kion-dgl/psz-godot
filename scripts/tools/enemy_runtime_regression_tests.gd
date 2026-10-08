extends RefCounted

class Dummy extends Node3D:
	var hits := 0
	var dodging := false
	func take_damage(_n: int, _v: Vector3 = Vector3.ZERO, _k: bool = false): hits += 1
	func is_dodge_iframed() -> bool: return dodging

class Lily extends PoisonLily:
	func _ready(): pass

class PlayerTarget extends "res://scripts/3d/player/player.gd":
	func _ready(): pass

static func run(r: Node) -> void:
	_test_idle_and_lowering(r)
	_test_lily(r)
	_test_roller(r)
	_test_ice(r)
	_test_freeze(r)

static func _test_idle_and_lowering(r: Node) -> void:
	for kind in ["stance_riser", "roller", "box_mimic", "flyer_combo"]:
		var e: EnemyBase = r._make_rig_enemy({"stt":1.0,"wat1":0.5,"tk1":0.5,"tk":0.5,"wt2w":0.8})
		e._archetype = kind
		e._flying = true
		var expected: String = {"stance_riser":"wat1","roller":"wat1","box_mimic":"tk1","flyer_combo":"tk"}[kind]
		r.assert_eq(e._play_animation("wat",true), expected, kind + " idle never selects transition")
		r.assert_eq(e._find_animation("wat"), "", "resolver has no generic stt idle alias")
		if kind == "stance_riser":
			e._start_loafing()
			for i in range(30): e._process_loafing(1.0 / 60.0)
			r.assert_eq(e.current_anim,"wt2w","snake holds lowering through recovery")
			r.assert_eq(e.velocity.x,0.0,"snake cannot move while lowering")
			r.assert_true(e._lower_timer > 0.0,"lowering is not consumed in one tick")
			e._process_loafing(0.5)
			r.assert_eq(e._lower_timer,0.0,"lowering releases after full duration")
		e.free()

static func _test_lily(r: Node) -> void:
	var l := Lily.new()
	l.enemy_data = EnemyData.new()
	l.current_hp = 100
	r.add_child(l)
	l.set_physics_process(false)
	var t := Dummy.new()
	r.add_child(t)
	t.position.z = 1.0
	l.target = t
	l._attacks = [{"clip":"missing","min_range":0,"max_range":3,"kind":"melee_arc"}]
	l._lily_state = PoisonLily.LilyState.IDLE_AWAKE
	for i in range(600): l._physics_process(1.0 / 60.0)
	r.assert_true(t.hits >= 3,"lily keeps attacking after first cooldown")
	l._status_effects = [{"type":"freeze","timer":0.2,"dot_timer":0.0,"phase":""}]
	l._update_immobilized()
	l.current_state = EnemyBase.EnemyState.IDLE
	l.attack_cooldown_timer = 0
	var hits := t.hits
	l._physics_process(0.1)
	r.assert_eq(t.hits,hits,"frozen lily cannot attack")
	l._physics_process(0.15)
	r.assert_true(not l._is_immobilized,"lily freeze expires via shared tick")
	l.dormant = true
	l.attack_cooldown_timer = 1.0
	l._physics_process(0.5)
	r.assert_eq(l.attack_cooldown_timer,1.0,"dormant lily cannot run active AI")
	l.free()
	t.free()

static func _test_roller(r: Node) -> void:
	var e: EnemyBase = r._make_rig_enemy({"trf1":0.1,"wat3":0.2,"trf2":1.0,"dmg":0.2})
	e._archetype = "roller"
	e.model = Node3D.new()
	e.add_child(e.model)
	e.model.rotation.y = 0.3
	var original := e.model.basis
	e._attack_def = {"clip":"wat3","kind":"charge","max_range":1.7,"charge_segments":{"st":"trf1","lp":"wat3","ed":"trf2"},"recovery_vulnerable_mult":2.0}
	e.is_attacking = true
	e.current_hp = 10000
	e.current_state = EnemyBase.EnemyState.ATTACKING
	e._start_charge(3.0)
	for i in range(90):
		e._process_charge(1.0 / 60.0)
		if e._charge.get("phase") == "ed": break
	r.assert_true(e.model.basis.is_equal_approx(original),"roller restores its authored basis before recovery")
	var remaining: float = e._charge.ed_dur - e._charge.phase_t
	e._on_hit_received(1,Vector3.ZERO,10000)
	r.assert_eq(e._vulnerable_mult,2.0,"punish hit preserves vulnerability")
	r.assert_almost_eq(e._charge.ed_dur - e._charge.phase_t,remaining,0.001,"punish hit preserves recovery time")
	e._process_charge(remaining + 0.01)
	r.assert_eq(e._vulnerable_mult,1.0,"vulnerability closes at authored recovery end")
	e._start_charge(3.0)
	e._process_charge(0.2)
	e._process_charge(0.1)
	e._on_hit_received(1,Vector3.ZERO,10000)
	r.assert_true(e.model.basis.is_equal_approx(original),"interrupted roller restores authored basis")
	e.free()

static func _test_ice(r: Node) -> void:
	var t := Dummy.new()
	r.add_child(t)
	var cast = preload("res://scripts/3d/combat/ice_technique.gd").new()
	cast.technique_id = "gibarta"
	cast.target = t
	r.add_child(cast)
	cast.set_physics_process(false)
	var before := r.get_child_count()
	cast._physics_process(0.01)
	r.assert_eq(r.get_child_count() - before,3,"Gibarta releases first fan of three ice bolts")
	cast._physics_process(0.3)
	var bolts: Array = []
	for child in r.get_children():
		if child is EnemyProjectile and child.technique_id == "gibarta": bolts.append(child)
	r.assert_eq(bolts.size(),9,"Gibarta emits three timed fan waves")
	for bolt in bolts:
		bolt._resolve_contact()
		bolt.free()
	r.assert_eq(t.hits,1,"fan shares one resolution per target")
	var bolt := EnemyProjectile.new()
	bolt.target = t
	t.dodging = true
	bolt._resolve_contact()
	t.dodging = false
	bolt._resolve_contact()
	r.assert_eq(t.hits,1,"dodged contact cannot hit later in the same cast")
	bolt.free()
	t.free()

static func _test_freeze(r: Node) -> void:
	var p := PlayerTarget.new()
	r.add_child(p)
	p.set_physics_process(false)
	p.set_process(false)
	var saved_hp: int = GameState.hp
	GameState.set_hp(80)
	p.take_technique_hit(1,"barta",0.0)
	r.assert_true(p._freeze.remaining > 0,"ice contact can apply freeze")
	p._start_dodge()
	r.assert_true(p.current_state != p.PlayerState.DODGING,"freeze blocks dodge")
	p._freeze.tick(p,2.1)
	r.assert_eq(p._freeze.remaining,0.0,"freeze expires")
	p.take_technique_hit(1,"gibarta",0.0)
	p.take_damage(1)
	r.assert_eq(p._freeze.remaining,0.0,"later damage breaks freeze")
	p.current_state = p.PlayerState.DODGING
	p.dodge_timer = 0.0
	var hp: int = GameState.hp
	p.take_technique_hit(1,"barta",0.0)
	r.assert_eq(GameState.hp,hp,"dodge blocks ice damage")
	r.assert_eq(p._freeze.remaining,0.0,"dodge blocks freeze")
	p.free()
	GameState.set_hp(saved_hp)

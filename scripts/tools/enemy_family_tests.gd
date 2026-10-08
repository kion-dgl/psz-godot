extends RefCounted
class Target extends Node3D:
	var hits := 0
	func take_damage(_d: int, _v: Vector3 = Vector3.ZERO, _k: bool = false): hits += 1

static func run(r: Node) -> void:
	_recovery(r)
	_groups(r)

static func _recovery(r: Node) -> void:
	var enemy: EnemyBase = r._make_rig_enemy({"wat":0.5, "atk":1.0, "end":0.5, "dmg":0.3})
	enemy.set_physics_process(false)
	var player := Target.new()
	r.add_child(player)
	player.position.z = 1.0
	enemy.target = player
	enemy._attack_def = {"id":"test", "clip":"atk", "recovery_clip":"end", "kind":"melee_arc", "windup_frac":0.3, "damage_end_frac":0.6, "hit_reach":2.0}
	enemy.current_state = EnemyBase.EnemyState.ATTACKING
	enemy._start_attack()
	enemy._attack_pos = 0.5
	enemy._process_attack_window()
	r.assert_eq(player.hits, 1, "main clip hits once")
	enemy._on_animation_finished(enemy._attack_anim)
	r.assert_true(enemy.is_attacking and enemy._recovery_started, "main end starts recovery, does not free the AI")
	r.assert_eq(enemy.current_anim, "end", "explicit recovery clip plays")
	enemy.velocity = Vector3(5,0,5)
	enemy._process_attacking(0.1)
	r.assert_eq(enemy.velocity, Vector3.ZERO, "recovery cannot move")
	r.assert_eq(player.hits, 1, "recovery cannot hit again")
	enemy._process_attacking(0.5)
	r.assert_eq(enemy.current_state, EnemyBase.EnemyState.LOAFING, "recovery releases into loafing")
	r.assert_true(not enemy.is_attacking, "recovery cannot wedge the next attack")
	enemy._start_attack()
	enemy._on_animation_finished(enemy._attack_anim)
	enemy.current_hp = 100
	enemy._on_hit_received(1, Vector3.ZERO, 10000)
	r.assert_true(not enemy.is_attacking, "hurt cancels recovery")
	enemy._fsm.move_clip = "wat"
	enemy._play_animation("wlk", true)
	r.assert_eq(enemy.current_anim, "wat", "authored movement token replaces missing walk")
	enemy.free()
	player.free()

static func _groups(r: Node) -> void:
	for id in ColiseumRoster.MIXED_GROUPS:
		var cells: Array = ColiseumRoster.make_sections(id)[0].cells
		var objects: Array = cells[0].objects
		var ids: Array = ColiseumRoster.MIXED_GROUPS[id].enemies
		r.assert_eq(objects.size(), ids.size()+1, id + " has all enemies and one exit")
		for i in ids.size():
			r.assert_true(EnemyRegistry.get_enemy(objects[i].enemy_id) != null, id + " member exists")
			for j in range(i):
				var a: Array = objects[i].position
				var b: Array = objects[j].position
				r.assert_true(Vector2(a[0],a[2]).distance_to(Vector2(b[0],b[2])) >= 4.0, id + " members spawn apart")
		r.assert_eq(objects.back().spawn_condition, "room_clear", id + " exit waits for all members")

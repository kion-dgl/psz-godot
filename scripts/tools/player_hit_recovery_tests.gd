extends RefCounted

class Player extends "res://scripts/3d/player/player.gd":
	func _ready() -> void: pass

static func run(r: Node) -> void:
	var p := Player.new()
	for child_name in ["PlayerModel", "CollisionShape3D", "NavigationAgent3D"]:
		var child: Node = CollisionShape3D.new() if child_name == "CollisionShape3D" else NavigationAgent3D.new() if child_name == "NavigationAgent3D" else Node3D.new()
		child.name = child_name
		p.add_child(child)
	r.add_child(p)
	p.set_physics_process(false)
	p.set_process(false)
	var old_hp: int = GameState.hp
	GameState.set_hp(GameState.max_hp)
	var full: int = GameState.hp
	for i in range(4): p.take_damage(1)
	r.assert_eq(GameState.hp, full - 1, "four simultaneous lizard hits deal damage once")
	p._tick_hit_invulnerability(0.49)
	p.take_damage(1)
	r.assert_eq(GameState.hp, full - 1, "post-hit protection lasts through 0.49 seconds")
	p.take_technique_hit(1, "barta", 0.0)
	r.assert_eq(p._freeze.remaining, 0.0, "blocked ice hit cannot apply freeze")
	p.take_damage(1, Vector3.ZERO, false, true)
	r.assert_eq(GameState.hp, full - 2, "existing poison or burn still ticks during impact protection")
	p._tick_hit_invulnerability(0.02)
	p.take_damage(1)
	r.assert_eq(GameState.hp, full - 3, "damage resumes after expiry; blocked hits and DoT do not refresh immunity")
	p._tick_hit_invulnerability(0.5)
	p.current_state = p.PlayerState.DODGING
	p.take_damage(1)
	r.assert_eq(GameState.hp, full - 4, "dodge alone does not grant damage immunity")
	p.free()
	GameState.set_hp(old_hp)

	var data: EnemyData = EnemyRegistry.get_enemy("ghowl")
	var attack: Dictionary = EnemyAttackRegistry.get_attacks("ghowl", data.attack_range)[0]
	var reach := float(attack.hit_reach)
	var half := float(attack.hit_half_angle_deg)
	r.assert_true(EnemyAttackLogic.arc_hit_test(Vector3.ZERO, Vector3.BACK, Vector3(0, 0, 1.5), EnemyBase.PLAYER_HIT_RADIUS, half, reach), "lizard swing connects at its attack-start distance")
	r.assert_true(not EnemyAttackLogic.arc_hit_test(Vector3.ZERO, Vector3.BACK, Vector3(0, 0, 1.8), EnemyBase.PLAYER_HIT_RADIUS, half, reach), "backing out to 1.8 units avoids the lizard swing")
	r.assert_true(not EnemyAttackLogic.arc_hit_test(Vector3.ZERO, Vector3.BACK, Vector3(0, 0, -1), EnemyBase.PLAYER_HIT_RADIUS, half, reach), "lizard cannot hit behind its locked facing")

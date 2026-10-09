extends RefCounted
## #554: real player timing and cone scan, with deterministic damage receivers.

class SwingPlayer extends "res://scripts/3d/player/player.gd":
	var weapon_type := 0
	var volleys := 0
	var damage_rolls := 0
	func _ready() -> void:
		set_physics_process(false)
		set_process(false)
	func _get_equipped_weapon_type() -> int:
		return weapon_type
	func _get_attack_damage() -> Dictionary:
		damage_rolls += 1
		var cfg: Dictionary = CombatManager.get_weapon_type_config(weapon_type)
		return {"weapon_type": weapon_type, "max_targets": cfg.get("max_targets_per_step", [cfg.max_targets, cfg.max_targets, cfg.max_targets])[combo_state - 1],
			"hits": cfg.hits_per_step[combo_state - 1], "damage": 10}
	func _fire_projectile(_atk: Dictionary) -> void:
		volleys += 1
	func _update_combo_ring(_delta: float) -> void:
		pass

class Receiver extends Node:
	var contacts := 0
	var elements: Array[String] = []
	func take_hit(_damage: int, _knockback: Vector3, _accuracy: int, element: String, _level: int) -> void:
		contacts += 1
		elements.append(element)

class Target extends Node3D:
	var is_alive := true
	var hurtbox: Receiver

static func run(t: Node) -> void:
	seed(554)
	_check_weapons(t)
	_check_boundaries(t)
	_check_target_budget(t)
	_check_cancellation_and_ranged(t)

static func _check_weapons(t: Node) -> void:
	for weapon_type in [0, 1, 2, 3, 4, 5, 7, 8, 13, 14, 15]:
		var cfg: Dictionary = CombatManager.get_weapon_type_config(weapon_type)
		var ends: Array = cfg.get("damage_end_frac", [])
		t.assert_eq(ends.size(), cfg.combo_steps, "melee has a close fraction for every step")
		for step in range(1, int(cfg.combo_steps) + 1):
			if ends.size() == int(cfg.combo_steps):
				t.assert_true(float(ends[step - 1]) > float(cfg.damaging_frac[step - 1]) and float(ends[step - 1]) < 1.0, "window closes after opening and before recovery ends")
			var pl := _player(t, weapon_type, step)
			var target := _target(t, 20.0)
			var opening := float(cfg.damaging_frac[step - 1])
			var closing := opening + 0.15
			pl._handle_attack_state(opening)
			target.position.z = 1.0
			pl._handle_attack_state(randf_range(0.01, 0.04))
			var expected := int(cfg.hits_per_step[step - 1])
			t.assert_eq(target.hurtbox.contacts, expected, "late arrival gets one configured bundle wt=%s step=%s" % [weapon_type, step])
			pl._handle_attack_state(0.01)
			t.assert_eq(target.hurtbox.contacts, expected, "remaining in cone cannot repeat a bundle")
			pl._handle_attack_state(closing - pl._attack_anim_elapsed)
			t.assert_true(pl._attack_hit_done, "window closes at exclusive end")
			t.assert_eq(pl.damage_rolls, 1, "scan rate cannot re-roll swing damage")
			pl.free()
			target.free()

static func _check_boundaries(t: Node) -> void:
	# No early damage, no post-window arrivals, and a slow tick crossing the window.
	for elapsed in [0.39, 0.55, 0.8]:
		var pl := _player(t, 0)
		var target := _target(t, 20.0)
		pl._handle_attack_state(elapsed)
		target.position.z = 1.0
		pl._handle_attack_state(0.001)
		t.assert_eq(target.hurtbox.contacts, 0, "outside active window cannot damage at %s" % elapsed)
		pl.free()
		target.free()
	var pl := _player(t, 0)
	var target := _target(t, 1.0)
	pl._handle_attack_state(0.8)
	t.assert_eq(target.hurtbox.contacts, 1, "slow tick crossing full window samples once")
	pl._handle_attack_state(0.01)
	t.assert_eq(target.hurtbox.contacts, 1, "slow tick closes the window after sampling")
	pl.free()
	target.free()

static func _check_target_budget(t: Node) -> void:
	# Sword's three slots span frames; already-hit nearest target must not block others.
	var pl := _player(t, 1)
	var targets: Array[Target] = []
	for i in range(4):
		targets.append(_target(t, 20.0))
	for i in range(4):
		targets[i].position.z = 1.0 + i * 0.2
		pl._handle_attack_state(0.4 if i == 0 else 0.02)
		t.assert_eq(targets[i].hurtbox.contacts, 1 if i < 3 else 0, "sword lifetime cap slot %s" % i)
	t.assert_eq(targets[0].hurtbox.contacts, 1, "nearest sword contact stays deduplicated")
	# A new strong swing resets the consumed budget, and retains its element.
	pl._play_and_track_attack("")
	pl._attack_anim_length = 1.0
	pl._is_special_attack = true
	pl._current_attack_element = "fire"
	pl._current_attack_element_level = 2
	pl._handle_attack_state(0.4)
	t.assert_eq(targets[0].hurtbox.contacts, 2, "new swing resets consumed targets")
	t.assert_eq(targets[0].hurtbox.elements, ["", "fire"], "strong swing carries element once")
	pl.free()
	for item in targets:
		item.free()

static func _check_cancellation_and_ranged(t: Node) -> void:
	var pl: SwingPlayer
	var target: Target
	for exit_state in [SwingPlayer.PlayerState.DAMAGED, SwingPlayer.PlayerState.DOWN, SwingPlayer.PlayerState.IDLE]:
		pl = _player(t, 0)
		target = _target(t, 1.0)
		pl._handle_attack_state(0.2)
		pl.transition_to(exit_state)
		pl._handle_attack_state(0.25)
		t.assert_eq(target.hurtbox.contacts, 0, "state exit cancels pending contact")
		pl.free()
		target.free()

	for weapon_type in [6, 9, 10, 11, 12]:
		pl = _player(t, weapon_type)
		pl._handle_attack_state(0.5)
		pl._handle_attack_state(0.02)
		t.assert_eq(pl.volleys, 1, "ranged volley stays single-release wt=%s" % weapon_type)
		pl.free()
	pl = _player(t, 0)
	target = _target(t, 1.0)
	pl.combo_state = 0
	pl._handle_attack_state(0.5)
	t.assert_eq(target.hurtbox.contacts, 0, "technique does not scan weapon contact")
	pl.free()
	target.free()

static func _player(t: Node, weapon_type: int, step: int = 1) -> SwingPlayer:
	var pl := SwingPlayer.new()
	pl.weapon_type = weapon_type
	pl.current_state = SwingPlayer.PlayerState.ATTACKING
	pl.combo_state = step
	pl._attack_anim_length = 1.0
	t.add_child(pl)
	return pl

static func _target(t: Node, distance: float) -> Target:
	var target := Target.new()
	target.hurtbox = Receiver.new()
	target.add_child(target.hurtbox)
	t.add_child(target)
	target.position.z = distance
	target.add_to_group("enemies")
	return target

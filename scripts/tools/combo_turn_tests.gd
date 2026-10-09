extends RefCounted
## #560: press-time steering, committed swings, and per-weapon turn limits.

static func run(t) -> void:
	const PlayerScript = preload("res://scripts/3d/player/player.gd")
	print("── Inter-swing turning (#560) ──")
	var limits := {0: 90.0, 1: 60.0, 2: 120.0, 3: 120.0, 4: 180.0,
		5: 75.0, 6: 90.0, 9: 180.0, 10: 180.0, 11: 45.0, 14: 90.0, 15: 90.0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 560
	for weapon in limits:
		for step in [2, 3]:
			for sample in range(12):
				var facing := rng.randf_range(-PI, PI)
				var requested := rng.randf_range(-PI, PI)
				var delta := wrapf(requested - facing, -PI, PI)
				var expected := facing + clampf(delta, -deg_to_rad(limits[weapon]), deg_to_rad(limits[weapon]))
				var actual: float = CombatManager.get_combo_turn_yaw(weapon, step, facing, requested)
				t.assert_true(absf(wrapf(actual - expected, -PI, PI)) < 0.00001,
					"weapon %d step %d sample %d respects shortest turn and limit" % [weapon, step, sample])
			t.assert_true(is_equal_approx(CombatManager.get_combo_turn_yaw(weapon, step, 0.7, null), 0.7),
				"weapon %d step %d no input preserves facing" % [weapon, step])
		t.assert_true(is_equal_approx(CombatManager.get_combo_turn_yaw(weapon, 1, 0.0, PI), PI),
			"first swing freely aims for weapon %d" % weapon)
	var pl = t._combo_swing_player(PlayerScript, 1, 0.8)
	Input.action_press("move_right")
	pl._try_queue_combo(false)
	t.assert_true(is_zero_approx(pl.player_rotation), "accepted press does not rotate outgoing swing")
	Input.action_release("move_right")
	Input.action_press("move_left")
	pl._try_queue_combo(false)
	Input.action_release("move_left")
	t._combo_step_end(pl)
	t.assert_true(is_equal_approx(pl.player_rotation, PI / 2), "step 2 uses first accepted direction despite changed input")
	pl._attack_anim_elapsed = 0.4
	pl._try_queue_combo(false) # no movement held at press
	Input.action_press("move_left")
	t._combo_step_end(pl)
	Input.action_release("move_left")
	t.assert_true(is_equal_approx(pl.player_rotation, PI / 2), "no-input chain does not acquire later input")
	pl.free()
	pl = t._combo_swing_player(PlayerScript, 1, 0.1)
	Input.action_press("move_right")
	pl._try_queue_combo(false)
	pl._attack_anim_elapsed = 0.8
	pl._try_queue_combo(false)
	t._combo_step_end(pl)
	t.assert_true(is_zero_approx(pl.player_rotation), "fumbled swing cannot steer")
	pl.free()
	pl = t._combo_swing_player(PlayerScript, 1, 0.0)
	pl._attack_anim_length = 0.0 # strong windup, before clip starts
	pl._try_queue_combo(false)
	t.assert_true(not pl._combo_fumbled and pl._queued_combo == PlayerScript.ComboQueue.NONE,
		"windup ignores input without fumbling")
	pl._attack_anim_length = 1.0
	pl._attack_anim_elapsed = 0.8
	pl._try_queue_combo(true)
	t.assert_true(pl._queued_combo_special and pl._queued_combo_yaw != null, "strong chain captures steering")
	pl.transition_to(PlayerScript.PlayerState.DAMAGED)
	t.assert_true(pl._queued_combo_yaw == null, "damage discards queued steering")
	Input.action_release("move_right")
	pl.free()

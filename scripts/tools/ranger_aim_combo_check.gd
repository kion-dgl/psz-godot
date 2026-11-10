extends RefCounted
## Drive real mouse presses on actual clip clocks; never advance an attack timer by hand.
static func click(p) -> void:
	var event := InputEventMouseButton.new()
	event.position = p.get_viewport().get_visible_rect().size * 0.5
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	var release := event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)

static func run(probe, p) -> void:
	Input.action_release("combat_aim")
	await probe.ticks(3)
	Input.action_press("combat_aim")
	await probe.ticks(15)
	p.transition_to(p.PlayerState.IDLE)
	var releases: Array[int] = []
	var on_shot := func(node):
		if node is Projectile and node.owner_node == p: releases.append(p.combo_state)
	p.get_tree().current_scene.child_entered_tree.connect(on_shot)
	click(p)
	await probe.ticks(2)
	for step in [1, 2, 3]:
		probe._check(p.combo_state == step and p.animation_player.current_animation.ends_with("_atk%d" % step), "aim combo plays real attack clip %d" % step)
		if step == 3:
			click(p)
			await probe.ticks(1)
			probe._check(p._queued_combo == p.ComboQueue.NONE, "finisher cannot queue a fourth aimed attack")
			break
		var timing: Dictionary = CombatManager.get_combo_timing(p._get_equipped_weapon_type(), step)
		var window: Array = p._chain_window(timing)
		var accept_at: float = (window[0] + window[1]) * 0.5
		for frame in range(180):
			if p._attack_frac() >= accept_at or p.combo_state != step: break
			await probe.ticks(1)
		probe._check(p.combat_aim.combo_feedback().state == "CLICK", "crosshair advertises actual chain window")
		click(p)
		await probe.ticks(1)
		probe._check(p.combat_aim.combo_feedback().state == "QUEUED", "crosshair confirms queued follow-up")
		probe._check(p._queued_combo != p.ComboQueue.NONE, "mouse queues aimed step %d in its timing window" % (step + 1))
		for frame in range(180):
			if p.combo_state != step: break
			await probe.ticks(1)
	for frame in range(180):
		if p.current_state != p.PlayerState.ATTACKING: break
		await probe.ticks(1)
	probe._check(p.combo_state == 0 and p.combat_aim.active, "finisher returns to aim without releasing the aim button")
	for step in [1, 2, 3]:
		probe._check(releases.has(step), "aim combo releases real projectiles on step %d" % step)
	p.get_tree().current_scene.child_entered_tree.disconnect(on_shot)
	Input.action_release("combat_aim")

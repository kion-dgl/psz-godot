extends RefCounted
## 3D delivery for the existing project trap payloads. Values are remake tuning,
## not a complete original status specification; see /states/gameplay-recovery-traps.
var effects: Dictionary = {}
var _label: Label3D

func apply(player: Node3D, kind: String) -> void:
	if not player.can_take_hit():
		return
	if kind == "freeze":
		player._freeze.apply(player, float(CombatManager.STATUS_EFFECTS.freeze.duration))
	elif kind in ["burn", "stun"] and not effects.has(kind):
		effects[kind] = {"remaining": float(CombatManager.STATUS_EFFECTS[kind].duration), "elapsed": 0.0}
		player._drop_charge()
	_update_label(player)

func clear(player: Node3D) -> void:
	effects.clear()
	player._freeze.clear(player)
	_update_label(player)

func blocks_attack() -> bool:
	return effects.has("stun")

func blocks_movement() -> bool:
	return effects.has("stun") and float(effects.stun.elapsed) < float(CombatManager.STATUS_EFFECTS.stun.immobilize_duration)

func tick(player: Node3D, delta: float) -> bool:
	if player._is_defeated or GameState.hp <= 0:
		clear(player)
		return false
	var held := false
	for kind in effects.keys():
		if not effects.has(kind):
			continue
		var fx: Dictionary = effects[kind]
		var active_delta := minf(delta, float(fx.remaining))
		var old_elapsed := float(fx.elapsed)
		fx.elapsed = old_elapsed + active_delta
		fx.remaining = maxf(0.0, float(fx.remaining) - delta)
		if kind == "burn":
			var ticks := int(fx.elapsed) - int(old_elapsed)
			for _tick in ticks:
				player.take_damage(maxi(1, int(GameState.max_hp * float(CombatManager.STATUS_EFFECTS.burn.dot_percent))), Vector3.ZERO, false, true)
				if not effects.has(kind):
					break # Lethal damage/recovery cleared the collection.
		elif kind == "stun":
			held = float(fx.elapsed) < float(CombatManager.STATUS_EFFECTS.stun.immobilize_duration)
		if float(fx.remaining) <= 0.0:
			effects.erase(kind)
	_update_label(player)
	return held


func _update_label(player: Node3D) -> void:
	if not player.is_inside_tree():
		return
	if effects.is_empty():
		if is_instance_valid(_label): _label.hide()
		return
	if not is_instance_valid(_label):
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.position.y = 2.1
		_label.font_size = 32
		_label.modulate = Color(1.0, 0.65, 0.2)
		player.add_child(_label)
	_label.text = " / ".join(effects.keys().map(func(kind): return "%s %ds" % [str(kind).capitalize(), ceili(effects[kind].remaining)]))
	_label.visible = not effects.is_empty()


func feedback(player: Node3D, message: String) -> void:
	if not player.is_inside_tree():
		return
	var label := Label3D.new()
	label.text = message
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.5
	label.font_size = 32
	player.add_child(label)
	var tween := player.create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

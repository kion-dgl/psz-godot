extends RefCounted
## 3D delivery for the existing project trap payloads. Values are remake tuning,
## not a complete original status specification; see /states/gameplay-recovery-traps.
var effects: Dictionary = {}
var _label: Label3D
var _poison_effect: Node3D

func apply(player: Node3D, kind: String) -> void:
	if not player.can_take_hit():
		return
	if kind == "freeze":
		player._freeze.apply(player, float(CombatManager.STATUS_EFFECTS.freeze.duration))
	elif kind in ["burn", "stun", "poison"] and not effects.has(kind):
		effects[kind] = {"remaining": 20.0 if kind == "poison" else float(CombatManager.STATUS_EFFECTS[kind].duration), "elapsed": 0.0}
		player._drop_charge()
	_update_label(player)

## Combat record 6: level 3/4/5, default 1230/1380/1530 updates and
## 150-update interval. DoT amount remains the remake's generic poison tuning.
func apply_octo_poison(player: Node3D, tier: int) -> void:
	if not player.can_take_hit(): return
	var level := clampi(tier,0,2)
	effects["poison"] = {"remaining": float([1230,1380,1530][level])/30.0, "elapsed":0.0}
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
		if kind in ["burn","poison"]:
			var interval := 5.0 if kind == "poison" else 1.0
			var ticks := int(float(fx.elapsed)/interval) - int(old_elapsed/interval)
			for _tick in ticks:
				player.take_damage(maxi(1, int(GameState.max_hp * float(CombatManager.STATUS_EFFECTS[kind].dot_percent))), Vector3.ZERO, false, true)
				if not effects.has(kind):
					break # Lethal damage/recovery cleared the collection.
		elif kind == "stun":
			held = float(fx.elapsed) < float(CombatManager.STATUS_EFFECTS.stun.immobilize_duration)
		if float(fx.remaining) <= 0.0:
			effects.erase(kind)
	_update_label(player)
	return held


func _sync_poison_effect(player: Node3D) -> void:
	if not effects.has("poison"):
		if is_instance_valid(_poison_effect):
			_poison_effect.stop_sound()
			_poison_effect.hide()
			_poison_effect.queue_free()
		_poison_effect = null
	elif not is_instance_valid(_poison_effect) and player.is_inside_tree():
		_poison_effect = preload("res://scripts/3d/player/player_poison_effect.gd").new()
		player.add_child(_poison_effect)

func _update_label(player: Node3D) -> void:
	_sync_poison_effect(player)
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

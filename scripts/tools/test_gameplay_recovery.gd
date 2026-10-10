extends RefCounted
## Unit layer for /states/gameplay-recovery-traps; live layer is the batch probe.

static func run(t: Node) -> void:
	_inventory_roundtrip(t)
	_recovery(t)
	_trap_guards(t)
	_status_boundaries(t)
	_character_order(t)
	_dialog_ownership(t)
	_death_once(t)
	_vision_lifecycle(t)
	_cure_items(t)

static func _inventory_roundtrip(t: Node) -> void:
	var saved: Dictionary = Inventory._items.duplicate()
	Inventory._items = {"trimate": 2, "monomate": 4, "telepipe": 1}
	var payload := {"inventory": Inventory._items, "order": Inventory._items.keys()}
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(payload))
	Inventory.restore_items(decoded.inventory, decoded.order)
	t.assert_eq(Inventory._items.keys(), ["trimate", "monomate", "telepipe"], "hard JSON round-trip preserves manual inventory order")
	Inventory.restore_items(decoded.inventory, ["missing", "telepipe", "telepipe"])
	t.assert_eq(Inventory._items.size(), 3, "stale/duplicate order entries cannot lose items")
	t.assert_eq(Inventory._items.keys()[0], "telepipe", "valid saved order takes priority")
	Inventory.restore_items({"trimate": 2, "monomate": 4}, [])
	t.assert_eq(Inventory._items.keys(), ["trimate", "monomate"], "legacy saves retain available order")
	Inventory._items = saved

static func _recovery(t: Node) -> void:
	var saved: Dictionary = Inventory._items.duplicate()
	var hp: int = GameState.hp
	var player = preload("res://scripts/3d/player/player.gd").new()
	Inventory._items = {"scape_doll": 2}
	GameState.set_hp(0)
	t.assert_true(player._try_auto_revive(), "held doll intercepts lethal damage")
	t.assert_eq(Inventory.get_item_count("scape_doll"), 1, "revive consumes exactly one doll")
	t.assert_eq(GameState.hp, GameState.max_hp, "revive restores full HP")
	t.assert_true(not player._is_defeated, "revive does not latch defeat")
	player.take_damage(9999)
	t.assert_eq(GameState.hp, GameState.max_hp, "recovery window rejects subsequent hits")
	Inventory._items.clear()
	t.assert_true(not player._try_auto_revive(), "no doll falls through to defeat")
	player.free()
	Inventory._items = saved
	GameState.set_hp(hp)

static func _trap_guards(t: Node) -> void:
	var trap := TrapBall.build_field("ice_trap")
	trap.disarmed = true
	t.assert_true(not trap._should_arm(), "disarmed trap cannot arm")
	trap._spent = true
	trap._trigger()
	t.assert_true(not trap._triggered, "spent trap cannot restart its fuse")
	trap.free()


static func _status_boundaries(t: Node) -> void:
	var hp := GameState.hp
	var player = preload("res://scripts/3d/player/player.gd").new()
	GameState.set_hp(GameState.max_hp)
	player.current_state = player.PlayerState.DODGING
	player.apply_status_effect("burn")
	t.assert_true(player._ailments.effects.is_empty(), "dodge rejects incoming status")
	player.current_state = player.PlayerState.IDLE
	player.apply_status_effect("stun")
	player._ailments.tick(player, 0.5)
	player.apply_status_effect("stun")
	t.assert_eq(player._ailments.effects.stun.remaining, 2.5, "duplicate status does not refresh")
	player._start_attack()
	t.assert_eq(player.current_state, player.PlayerState.IDLE, "stun forbids normal attack")
	player._start_strong_attack()
	t.assert_eq(player.current_state, player.PlayerState.IDLE, "stun forbids strong attack")
	t.assert_true(not player._ailments.tick(player, 0.6), "stun movement hold ends before attack lock")
	t.assert_true(player._ailments.blocks_attack(), "stun still denies attacks after hold")
	player._ailments.tick(player, 2.0)
	t.assert_true(not player._ailments.blocks_attack(), "stun expires on elapsed time")
	player.apply_status_effect("burn")
	player.current_state = player.PlayerState.DODGING
	player._ailments.tick(player, 1.1)
	t.assert_eq(GameState.hp, GameState.max_hp - maxi(1, int(GameState.max_hp * 0.03)), "existing burn ticks through dodge")
	t.assert_eq(player.current_state, player.PlayerState.DODGING, "burn does not interrupt movement")
	player.clear_status_effects()
	var cured_hp := GameState.hp
	player._ailments.tick(player, 5.0)
	t.assert_eq(GameState.hp, cured_hp, "cured burn has no late ticks")
	player.free()
	GameState.set_hp(hp)


static func _character_order(t: Node) -> void:
	var characters := CharacterManager.get_save_data()
	var slot := CharacterManager._active_slot
	var inventory: Dictionary = Inventory._items.duplicate()
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "OrderTest")
	CharacterManager.set_active_slot(0)
	Inventory._items = {"trimate": 2, "monomate": 3, "telepipe": 1}
	CharacterManager.sync_inventory_to_active()
	var serialized: Array = JSON.parse_string(JSON.stringify(CharacterManager.get_save_data()))
	CharacterManager._active_slot = -1
	CharacterManager.load_from_save(serialized)
	Inventory._items.clear()
	CharacterManager.set_active_slot(0)
	t.assert_eq(Inventory._items.keys(), ["trimate", "monomate", "telepipe"], "character save/load restores explicit inventory order")
	CharacterManager._characters = characters
	CharacterManager._active_slot = slot
	if slot >= 0:
		CharacterManager._sync_to_game_state()
	Inventory._items = inventory


static func _dialog_ownership(t: Node) -> void:
	var pages := [{"speaker": "Test", "text": "One page"}]
	pages.make_read_only()
	var dialog = preload("res://scripts/3d/ui/dialog_box.gd").new()
	t.add_child(dialog)
	dialog.show_dialog(pages)
	dialog._close()
	t.assert_eq(pages.size(), 1, "closing dialog cannot mutate caller's read-only pages")
	t.assert_true(not dialog.is_active(), "read-only dialog closes normally")
	dialog.queue_free()


static func _death_once(t: Node) -> void:
	var enemy: EnemyBase = t._make_rig_enemy({"ded": 0.2})
	var deaths: Array[int] = []
	enemy.died.connect(func(_e): deaths.append(1))
	enemy._die()
	enemy._die()
	t.assert_eq(deaths.size(), 1, "multiple death callbacks emit rewards/clear once")
	enemy.queue_free()
	var boss := ReyburnBoss.new()
	boss.is_alive = false
	boss._attack_done = false
	boss._apply_attack_effect()
	boss._spawn_fireball(10)
	t.assert_true(not boss._attack_done and boss._projectiles.is_empty(), "dead boss cannot resolve or release queued attack")
	boss.free()


static func _vision_lifecycle(t: Node) -> void:
	var expiry := TrapBall.vision_until_msec
	var characters := CharacterManager.get_save_data()
	var slot := CharacterManager._active_slot
	var inventory: Dictionary = Inventory._items.duplicate()
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "VisionTest")
	CharacterManager.set_active_slot(0)
	var trap := TrapBall.build_field("heat_trap")
	t.assert_true(not trap.can_be_targeted(), "human cannot target dormant unseen trap")
	TrapBall.grant_vision()
	t.assert_true(trap.can_be_targeted(), "vision enables dormant trap targeting")
	var next_room := TrapBall.build_field("ice_trap")
	t.assert_true(next_room.can_be_targeted(), "vision carries into newly built room traps")
	TrapBall.vision_until_msec = Time.get_ticks_msec() - 1
	t.assert_true(not trap.can_be_targeted(), "expired vision removes dormant targeting")
	trap._armed = true
	t.assert_true(trap.can_be_targeted(), "armed trap stays targetable after vision expiry")
	TrapBall.grant_vision()
	CharacterManager.set_active_slot(0)
	t.assert_true(not TrapBall.vision_active(), "character selection resets vision")
	TrapBall.grant_vision()
	SessionManager.enter_field("gurhacia", "normal")
	t.assert_true(not TrapBall.vision_active(), "fresh field resets vision")
	TrapBall.grant_vision()
	SessionManager.enter_quest("debug_boss_reyburn", "normal")
	t.assert_true(not TrapBall.vision_active(), "fresh quest resets vision")
	TrapBall.grant_vision()
	SessionManager.return_to_city()
	t.assert_true(not TrapBall.vision_active(), "ending session resets vision")
	trap.free()
	next_room.free()
	CharacterManager._characters = characters
	CharacterManager._active_slot = slot
	if slot >= 0: CharacterManager._sync_to_game_state()
	Inventory._items = inventory
	TrapBall.vision_until_msec = expiry


static func _cure_items(t: Node) -> void:
	var saved: Dictionary = Inventory._items.duplicate()
	var hp := GameState.hp
	Inventory._items = {"sol_atomizer": 1, "moon_atomizer": 1}
	GameState.set_hp(1)
	t.assert_true(not Inventory.use_item("sol_atomizer"), "Sol without field recipient is rejected")
	t.assert_true(not Inventory.use_item("moon_atomizer"), "Moon without teammate is rejected")
	t.assert_eq(GameState.hp, 1, "status/revival items cannot self-heal")
	t.assert_eq(Inventory.get_item_count("sol_atomizer"), 1, "invalid Sol preserves inventory")
	Inventory._items = saved
	GameState.set_hp(hp)

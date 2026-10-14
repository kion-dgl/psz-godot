extends "res://scripts/tools/systems_progression_probe.gd"
## Extends the established fresh-Hunter real-kill route with menu/bank/restart/recovery.
const Sets := preload("res://scripts/utils/equipment_sets.gd")

func _run() -> void:
	if OS.get_environment("PSZ_COMPLETION_RESTART") == "1":
		probe_label = "systems"
		SaveManager.load_game()
		CharacterManager.set_active_slot(0)
		var ch = CharacterManager.get_active_character()
		_verify(ch != null and ch.level == 2 and Sets.list_sets().size() == 1, "separate process restores earned level and saved set")
		_verify(Sets.recall(0).success and ch.equipment.weapon == "saber", "separate process recalls exact upgraded weapon")
		_verify(ch.weapon_grinds.saber == 5 and Inventory.get_item_count("scape_doll") == 0, "upgrades and consumed doll persist across process restart")
		get_tree().quit(0 if _failures.is_empty() else 1)
		return
	await super._run()

func _combat(player: Node3D, enemy: EnemyBase, ch: Dictionary) -> void:
	await super._combat(player, enemy, ch)
	var active: Dictionary = CharacterManager.get_active_character()
	await _loadout_menu(player, active)
	await _levels(player)
	await _death_paths(player, active)

func _choose(index: int) -> void:
	var modal = PsoStartMenu._active_modal
	_verify(index < modal._buttons.size() and modal._enabled[index], "live modal exposes requested enabled action")
	modal._focused_idx = index
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	modal._input(event)
	await get_tree().process_frame

func _loadout_menu(player: Node3D, ch: Dictionary) -> void:
	PsoStartMenu.open()
	PsoStartMenu._mode = PsoStartMenu.Mode.EQUIP
	PsoStartMenu._sub_idx = PsoStartMenu._get_equip_slots().size() - 1
	PsoStartMenu._sub_accept()
	_verify(PsoStartMenu._active_modal != null, "Equip → Sets opens live modal")
	await _choose(0)
	var naming = PsoStartMenu._active_modal
	naming.get_node("SetName").text = "Field kit"
	naming.confirmed.emit()
	await get_tree().process_frame
	_verify(Sets.list_sets().size() == 1 and Sets.list_sets()[0].name == "Field kit", "live name dialog saves set")
	ch.equipment.weapon = ""
	var storage = load("res://scenes/2d/storage.tscn").instantiate()
	get_tree().root.add_child(storage)
	await get_tree().process_frame
	storage._tab = 0
	storage._load_items()
	storage._selected_index = storage._inventory_items.find(storage._inventory_items.filter(func(item): return item.id == "saber")[0])
	storage._do_item_move(1)
	_verify(not Inventory.has_item("saber") and GameState.shared_storage.size() > 0, "real storage screen deposits referenced weapon")
	var new_id := Inventory.add_weapon("saber")
	_verify(new_id != "saber", "buying a duplicate cannot alias banked gear")
	PsoStartMenu._sub_accept()
	await _choose(1)
	await _choose(0)
	_verify(ch.equipment.weapon == "saber" and ch.weapon_grinds.saber == 5, "live recall restores exact weapon and current grind")
	_verify(player.weapon_node != null and Inventory._items.keys()[0] == "saber", "recall refreshes rig and inventory ordering")
	_manual_bank_withdrawal(storage, ch)
	storage.queue_free()
	await get_tree().process_frame
	await _snapshot("equipment-sets")
	PsoStartMenu._sub_accept()
	await _snapshot("equipment-set-list")
	PsoStartMenu._active_modal._emit_cancelled()
	await get_tree().process_frame
	await _menu_limits()
	PsoStartMenu.close()

func _levels(player: Node3D) -> void:
	var session: Dictionary = SessionManager.get_session()
	var saved := session.duplicate(true)
	var field = get_tree().current_scene
	for sample in [["gurhacia", "normal", 1], ["rioh", "hard", 35], ["dark", "super-hard", 90]]:
		session.erase("coliseum_enemy_level")
		session.erase("enemy_level")
		session.area_id = "gurhacia" # Starting area must not mask current-section area.
		var prefix: String = {"gurhacia": "s01", "rioh": "s03", "dark": "s07"}[sample[0]]
		SessionManager.set_field_sections([{"cells": [{"stage_id": prefix + "a_sa1"}]}])
		session.difficulty = sample[1]
		field._cell_spawner._spawn_enemy(Vector3(0, 0, 6), "ghowl")
		var enemies = get_tree().get_nodes_in_group("enemies").filter(func(n): return n is EnemyBase and n.is_alive)
		var spawned = enemies.back()
		spawned.set_physics_process(false)
		_verify(spawned.enemy_level == sample[2], "live spawn follows fixed %s/%s level %d" % sample)
		var hp: int = spawned.current_hp
		var level: int = spawned.enemy_level
		spawned.queue_free()
		await get_tree().process_frame
		var active = CharacterManager.get_active_character()
		var old_level: int = active.level
		active.level = 80
		field._cell_spawner._spawn_enemy(Vector3(0, 0, 6), "ghowl")
		enemies = get_tree().get_nodes_in_group("enemies").filter(func(n): return n is EnemyBase and n.is_alive)
		spawned = enemies.back()
		spawned.set_physics_process(false)
		_verify(spawned.enemy_level == level and spawned.current_hp == hp, "revisit spawn ignores player level")
		active.level = old_level
		spawned.queue_free()
		await get_tree().process_frame
	session.clear()
	session.merge(saved)
	player.set_physics_process(false)

func _death_paths(player: Node3D, ch: Dictionary) -> void:
	PsoStartMenu.close()
	for target in get_tree().get_nodes_in_group("enemies"):
		target.set_physics_process(false)
	Inventory._items["scape_doll"] = 1
	GameState.set_hp(GameState.max_hp)
	player._recovery_left = 0.0
	player.transition_to(player.PlayerState.IDLE)
	player.take_damage(99999)
	_verify(Inventory.get_item_count("scape_doll") == 0 and GameState.hp == 0, "lethal hit consumes last doll once")
	_verify(get_tree().get_nodes_in_group("defeat_screen").is_empty(), "doll prevents defeat prompt")
	_verify(await preload("res://scripts/tools/gameplay_recovery_check.gd")._revival_presentation(player), "live doll stand-up and immunity expire")
	GameState.meseta = 101
	ch.meseta = 101
	GameState.stored_meseta = 500
	player.take_damage(99999)
	for frame in 300:
		await get_tree().physics_frame
		if not get_tree().get_nodes_in_group("defeat_screen").is_empty(): break
	var screen = get_tree().get_first_node_in_group("defeat_screen")
	_verify(screen != null, "no doll raises defeat prompt")
	if screen:
		screen._decline()
		_verify(GameState.hp == 0 and SessionManager.get_location() == "field", "No keeps player defeated in field")
		screen.confirm_return()
		for frame in 600:
			await get_tree().physics_frame
			if not SceneManager._transitioning and SessionManager.get_location() == "city": break
		_verify(GameState.hp == GameState.max_hp and GameState.meseta == 51 and GameState.stored_meseta == 500, "Yes restores HP and deducts only half carried meseta")
		_verify(SessionManager.get_session().is_empty(), "defeat ends session")
	SaveManager.save_game()

func _menu_limits() -> void:
	for index in 7: Sets.save_set("Kit %d" % (index + 2))
	PsoStartMenu._sub_accept()
	_verify(not PsoStartMenu._active_modal._enabled[0], "full list disables ninth save")
	await _choose(4)
	_verify(PsoStartMenu._active_modal._buttons.size() == 6, "middle page stays bounded")
	await _choose(5)
	await _snapshot("equipment-set-pages")
	_verify(PsoStartMenu._active_modal._buttons.size() == 4, "last page exposes final two sets and back navigation")
	PsoStartMenu._active_modal._emit_cancelled()
	await get_tree().process_frame
	for index in range(7, 0, -1): Sets.delete_set(index)
	_verify(Sets.list_sets()[0].name == "Field kit", "navigation cancellation preserves saved set")

func _manual_bank_withdrawal(storage: Control, ch: Dictionary) -> void:
	ch.equipment.weapon = ""
	storage._tab = 0
	storage._load_items()
	storage._selected_index = storage._inventory_items.find(storage._inventory_items.filter(func(item): return item.id == "saber")[0])
	storage._do_item_move(1)
	storage._tab = 1
	storage._load_items()
	storage._selected_index = storage._storage_items.find(storage._storage_items.filter(func(item): return item.id == "saber")[0])
	storage._do_item_move(1)
	_verify(Inventory.has_item("saber") and ch.weapon_grinds.saber == 5, "ordinary bank withdrawal retains identity and upgraded stats")
	_verify(Sets.recall(0).success, "set still recalls after manual bank round trip")

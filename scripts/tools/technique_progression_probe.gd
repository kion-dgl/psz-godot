extends Node
## Fresh-save progression integration. Run in an isolated XDG_DATA_HOME.
var _ok := true

func _ready() -> void:
	var pack := OS.get_environment("PSZ_PROBE_PACK")
	if not pack.is_empty() and not ProjectSettings.load_resource_pack(pack, false):
		get_tree().quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	get_tree().current_scene = null
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "fomar", "ForceProbe")
	CharacterManager.set_active_slot(0)
	Inventory.add_item("disk_barta_1", 1)
	_check(Inventory.use_item("disk_barta_1"), "fresh FOmar learns Barta")
	Inventory.add_item("disk_barta_5", 1)
	_check(not Inventory.use_item("disk_barta_5") and Inventory.has_item("disk_barta_5"), "level gate retains disk")
	SessionManager.enter_quest("debug_coliseum", "normal")
	SessionManager.set_field_sections(ColiseumRoster.make_sections("hildegigas"))
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", ColiseumRoster.warp_data())
	var player: Node3D
	for frame in 600:
		await get_tree().physics_frame
		player = get_tree().get_first_node_in_group("player")
		if player: break
	if not player:
		_check(false, "live player spawned")
	else:
		await get_tree().create_timer(0.2).timeout
		player.set_physics_process(false)
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.set_physics_process(false)
		await _exercise(player)
	print("[technique-progression] DONE " + ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _exercise(player: Node3D) -> void:
	var early := _cast(player, 1)
	# Exercise actual EXP/level-up API with the existing table, not a new curve.
	var table = load("res://data/experience_table.tres")
	var growth := CharacterManager.add_experience(table.get_exp_for_level(5))
	_check(growth.leveled_up and growth.new_level == 5, "EXP reaches disk gate through existing growth table")
	_check(Inventory.use_item("disk_barta_5") and not Inventory.has_item("disk_barta_5"), "upgrade consumes selected disk exactly once")
	var character = CharacterManager.get_active_character()
	character.techniques.rabarta = 1 # old save compatibility: must not shadow new base
	seed(747)
	var upgraded := CombatManager.calculate_technique_damage("barta")
	_check(int(upgraded.damage) > int(early.damage), "upgraded technique plus character growth increases damage")
	_check(int(upgraded.pp_cost) < int(early.pp_cost), "upgrade reaches existing PP reduction boundary")
	_check(TechniqueManager.get_technique_level(character, "rabarta") == 5, "charged upgrade ignores stale lower variant")
	_cast(player, 5)
	var before := GameState.mp
	player.current_state = player.PlayerState.DAMAGED
	player._cast_technique("barta")
	_check(GameState.mp == before, "stagger prevents cast/cost")
	player.current_state = player.PlayerState.IDLE
	GameState.set_mp(0)
	player._cast_technique("barta")
	_check(GameState.mp == 0 and player.current_state == player.PlayerState.IDLE, "insufficient PP leaves idle")
	character.class_id = "racast"
	GameState.set_mp(GameState.max_mp)
	before = GameState.mp
	player._cast_technique("barta")
	_check(GameState.mp == before and player.current_state == player.PlayerState.IDLE, "CAST stale learned entry cannot cast")
	character.class_id = "fomar"
	SaveManager.save_game()
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	Inventory.clear_inventory()
	SaveManager.load_game()
	CharacterManager.set_active_slot(0)
	character = CharacterManager.get_active_character()
	_check(character.level == 5 and TechniqueManager.get_technique_level(character, "barta") == 5, "growth and technique survive disk reload")
	_check(not Inventory.has_item("disk_barta_5"), "consumed upgrade stays consumed after reload")
	await get_tree().physics_frame

func _cast(player: Node3D, expected_level: int) -> Dictionary:
	player.current_state = player.PlayerState.IDLE
	GameState.set_mp(GameState.max_mp)
	seed(747)
	var expected := CombatManager.calculate_technique_damage("barta")
	seed(747)
	var before := GameState.mp
	player._cast_technique("barta")
	_check(GameState.mp == before - int(expected.pp_cost), "live Barta spends resolved PP once")
	var candidates := get_tree().current_scene.get_children().filter(func(n): return n is Projectile)
	_check(not candidates.is_empty(), "Barta emits real projectile")
	if not candidates.is_empty():
		var projectile = candidates.back()
		_check(projectile.element_level == expected_level and projectile.damage == int(expected.damage), "projectile receives resolved level and damage")
	player._cast_technique("barta")
	_check(GameState.mp == before - int(expected.pp_cost), "repeat cast during attack spends no extra PP")
	player._handle_attack_state(2.0)
	_check(player.current_state == player.PlayerState.IDLE, "cast recovers to idle")
	return expected

func _check(condition: bool, message: String) -> void:
	_ok = condition and _ok
	print("[technique-progression] %s: %s" % ["PASS" if condition else "FAIL", message])

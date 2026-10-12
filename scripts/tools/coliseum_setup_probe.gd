extends "res://scripts/tools/probe_checks.gd"
## Live NPC framing, level dialogs, spawn scaling and damage debug controls.
func _run() -> void:
	probe_label = "coliseum-setup"
	var picker = await _open_picker()
	var row: Dictionary = await _configure_picker(picker)
	var preview_hp := ColiseumRoster.row_hp(row)
	var boss: MotherTrinityBoss = await _launch(picker)
	if not boss:
		get_tree().quit(1)
		return
	_check_combat(boss, preview_hp)
	_check_health_display()
	_check_floor_texture(boss)
	await _snapshot("coliseum_boss_level")
	await _check_debug_menu()
	print("[coliseum-setup] DONE " + ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _open_picker():
	await SceneManager.goto_scene("res://scenes/3d/city/city_counter.tscn")
	var city := get_tree().current_scene
	await city.open_shop_view(city.get_node("ColiseumMasterNPC"), "res://scenes/2d/shops/coliseum_pick.tscn")
	var picker = SceneManager._overlay_stack.back().scene
	await get_tree().process_frame
	_check(city._shop_open and city.player.current_state == city.player.PlayerState.CUTSCENE, "Coliseum uses live NPC shop camera and ghosts player")
	_check(picker.get_node("Panel").get_global_rect().end.x <= 800, "Coliseum menu leaves right side for NPC")
	return picker

func _configure_picker(picker) -> Dictionary:
	picker._load_tab(1)
	for index in picker._rows.size():
		if picker._rows[index].id == "mother_trinity": picker._selected_index = index
	picker._refresh_display()
	var row: Dictionary = picker._rows[picker._selected_index]
	_check(ColiseumRoster.row_level(row) == 30, "picker Auto shows real Shrine boss level")
	picker._edit_level(true)
	picker._active_modal._change(49)
	picker._active_modal._emit_cancelled()
	await get_tree().process_frame
	_check(CharacterManager.get_active_character().level == 1, "canceling level editor leaves character unchanged")
	picker._edit_level(true)
	picker._active_modal._change(49)
	picker._active_modal._emit_confirmed()
	await get_tree().process_frame
	_check(CharacterManager.get_active_character().level == 50 and GameState.hp == GameState.max_hp, "player editor sets Lv50 and refills HP")
	picker._edit_level(false)
	picker._active_modal._change(5)
	picker._active_modal._emit_confirmed()
	await get_tree().process_frame
	_check(ColiseumRoster.row_level(row) == 5, "enemy editor changes preview to Lv5")
	await _snapshot("coliseum_setup")
	return row

func _launch(picker) -> MotherTrinityBoss:
	picker._open_confirm()
	_check("Lv.5" in picker._active_modal._prompt_label.text and "Lv.50" in picker._active_modal._prompt_label.text, "battle confirmation shows both levels")
	picker._active_modal._emit_confirmed()
	var boss: MotherTrinityBoss
	for frame in 600:
		await get_tree().physics_frame
		for node in get_tree().get_nodes_in_group("bosses"):
			if node is MotherTrinityBoss: boss = node
		if boss and boss.pieces.size() == 3: break
	_check(is_instance_valid(boss), "picker launches selected boss arena")
	return boss

func _check_combat(boss: MotherTrinityBoss, preview_hp: int) -> void:
	boss.set_physics_process(false)
	for piece in boss.pieces: piece.set_physics_process(false)
	_check(boss.enemy_level == 5 and boss.current_hp == preview_hp, "spawned boss level and HP match picker preview")
	_check(boss.pieces.all(func(piece): return piece.enemy_level == 5), "level override also reaches all Trinity pieces")
	var field := get_tree().current_scene
	_check("Lv.5" in field._field_hud._boss_bar._name, "boss health bar displays actual level")
	var player = get_tree().get_first_node_in_group("player")
	player.set_physics_process(false)
	player.current_state = player.PlayerState.IDLE
	player._recovery_left = 0
	DebugConfig.invincible = true
	var hp := GameState.hp
	player.take_damage(999999)
	_check(GameState.hp == hp and not player._is_defeated, "debug invincibility prevents lethal boss damage")
	DebugConfig.invincible = false
	player.take_damage(10)
	_check(GameState.hp == hp - 10, "turning debug invincibility off restores damage")

func _check_debug_menu() -> void:
	SessionManager.enter_quest("debug_boss_dark_falz", "normal")
	_check(preload("res://scripts/utils/enemy_progression.gd").level_for(SessionManager.get_session()) == 30,
		"Coliseum override does not leak into next quest")
	SessionManager.return_to_city()
	ColiseumRoster.selected_enemy_level = 0
	await SceneManager.goto_scene("res://scenes/3d/city/city_counter.tscn")
	PsoStartMenu.open()
	PsoStartMenu._toggle_debug(14)
	PsoStartMenu._active_modal._change(-20)
	PsoStartMenu._active_modal._emit_confirmed()
	await get_tree().process_frame
	_check(CharacterManager.get_active_character().level == 30, "System Debug shares working level editor")
	PsoStartMenu._toggle_debug(15)
	_check(DebugConfig.invincible and "ON" in PsoStartMenu._get_debug_list()[15], "System Debug invincibility toggle reflects state")
	DebugConfig.invincible = false
	PsoStartMenu.close()

func _check_health_display() -> void:
	var hud = get_tree().current_scene._field_hud
	var info := {"kind":"enemy","name":"Test Lv.5","hp":10,"max_hp":20}
	hud._target_info.update_info(info)
	PsoStartMenu._toggle_debug(16)
	hud._boss_bar._process(0.0)
	hud._target_info.update_info(info)
	_check(not hud._boss_bar._show_health and not hud._target_info._show_health, "debug toggle hides boss and target HP without a target change")
	_check(hud._boss_bar.visible and hud._target_info.visible, "health toggle preserves target names and levels")
	hud._target_info.update_info({"kind":"item","name":"Monomate"})
	_check(hud._target_info.visible, "health toggle preserves item target labels")
	PsoStartMenu._toggle_debug(16)
	hud._boss_bar._process(0.0)
	hud._target_info.update_info(info)
	_check(hud._boss_bar._show_health and hud._target_info._show_health, "health bars restore immediately when enabled")

func _check_floor_texture(boss: MotherTrinityBoss) -> void:
	var material := boss.arena.cover.get_active_material(0) as ShaderMaterial
	_check(material != null and material.get_shader_parameter("uv_scale") == Vector3(2,2,1), "Trinity cover uses 2x2 texture repeat")
	_check(material != null and material.get_shader_parameter("wrap_s") == 1 and material.get_shader_parameter("wrap_t") == 1,
		"Trinity cover mirrors texture on both axes")

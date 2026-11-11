extends "res://scripts/tools/ranger_aim_probe.gd"
## Full-roster diagnostic. Legacy/advanced entries are test grants, not new disks.
const BANKS := [
	["foie", "barta", "zonde"], ["resta", "anti", "shifta"],
	["deband", "jellen", "zalure"], ["gifoie", "gibarta", "gizonde"],
	["rafoie", "rabarta", "razonde"], ["grants", "megid", "reverser"],
]
const BLOCKED := ["reverser", "shifta", "deband", "jellen", "zalure"]
var bank := 0
var roster_label: Label
var observations: Array = []

func _run() -> void:
	probe_label = "force-techniques"
	if ProjectSettings.get_setting("application/config/name") != "PSZ Aim Prototype":
		get_tree().quit(1)
		return
	get_tree().current_scene = null
	await launch_fixture()
	configure_panel()
	if OS.get_environment("PSZ_AIM_CHECK") == "1":
		await audit_roster()
		var output := OS.get_environment("PSZ_TECH_REPORT")
		if not output.is_empty():
			var file := FileAccess.open(output, FileAccess.WRITE)
			file.store_string(JSON.stringify({"loadout": Loadouts.label(), "observations": observations}, "\t") + "\n")
		print("[force-techniques] DONE ", "ok" if _ok else "FAIL")
		get_tree().quit(0 if _ok else 1)
	else:
		for enemy in enemies: enemy.set_physics_process(true)
		DisplayServer.window_set_title("Force Coliseum — F3 technique bank • F4 refill • T enemy AI • Z shoulder • Q lock")

func configure_panel() -> void:
	grant_roster()
	for child in get_tree().current_scene.get_children():
		if child is CanvasLayer:
			for item in child.get_children():
				if item is Label and item.text.begins_with(Loadouts.label()): item.hide()
	var layer := CanvasLayer.new()
	get_tree().current_scene.add_child(layer)
	roster_label = Label.new()
	roster_label.position = Vector2(20, 145)
	roster_label.add_theme_font_size_override("font_size", 16)
	layer.add_child(roster_label)
	set_bank()

func reload_fixture() -> void:
	await super.reload_fixture()
	configure_panel()
	for enemy in enemies: enemy.set_physics_process(true)

func grant_roster() -> void:
	var character: Dictionary = CharacterManager.get_active_character()
	for id in TechniqueManager.TECHNIQUES: character.techniques[id] = 1

func set_bank() -> void:
	player._drop_charge()
	ActionPalette.pages = [BANKS[bank].duplicate(), ["attack", "resta", "monofluid"]]
	ActionPalette.current_page = 0
	ActionPalette.config_changed.emit()
	roster_label.text = "FORCE COLISEUM — %d/6: %s\nF2 restart • F3 next spells • F4 refill • F5 poison • T enemies • R reset\nMouse buttons cast • Hold to charge • Shift: Attack / Resta / Fluid\nZ shoulder • Q lock • Tab target • Space dodge" % [bank + 1, " / ".join(BANKS[bank])]
	if bank in [1, 2, 5]: roster_label.text += "\nKnown gaps: support buffs/debuffs/revive unavailable; Grants/Megid use fallback."
	if bank >= 3: roster_label.text += "\nAdvanced spells granted for this test only."


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and is_instance_valid(player):
		match event.physical_keycode:
			KEY_F2:
				if not switching:
					switching = true
					reload_fixture.call_deferred()
				return
			KEY_F3:
				bank = (bank + 1) % BANKS.size()
				set_bank()
				return
			KEY_F4:
				GameState.set_hp(GameState.max_hp)
				GameState.set_mp(GameState.max_mp)
				return
			KEY_F5:
				player.apply_status_effect("poison")
				return
	# Avoid inherited loadout cycling replacing the diagnostic scene's controls.
		if event.physical_keycode in [KEY_F1, KEY_F2]: return
	super._unhandled_input(event)

func audit_roster() -> void:
	if OS.get_environment("PSZ_TECH_SIDE") == "1":
		var camera := Camera3D.new()
		get_tree().current_scene.add_child(camera)
		camera.global_position = origin + Vector3(5, 3, 4)
		camera.look_at(origin + Vector3(0, 0.5, 2))
		camera.current = true
	for id in TechniqueManager.TECHNIQUES:
		if not OS.get_environment("PSZ_TECH_ONLY").is_empty() and id != OS.get_environment("PSZ_TECH_ONLY"): continue
		await prepare_case()
		if id == "anti": player.apply_status_effect("poison")
		var before_status: bool = player.has_status_effects()
		var before_hp: int = GameState.hp
		var before_pp: int = GameState.mp
		var before_enemy: int = enemies[0].current_hp + enemies[1].current_hp
		player._cast_technique(id)
		var spent: int = before_pp - GameState.mp
		await ticks(8)
		await _snapshot("tech-" + id)
		await ticks(172)
		var note := "implemented delivery; visual/feel review pending"
		if id in BLOCKED: note = "blocked before cost: no 3D support recipient/resolver"
		if id in ["grants", "megid"]: note = "generic Foie fallback; spell-specific delivery absent"
		var row := {"id": id, "tier": TechniqueManager.TECHNIQUES[id].tier,
			"effective_level": TechniqueManager.get_technique_level(CharacterManager.get_active_character(), id),
			"pp_spent": spent, "hp_gain": GameState.hp - before_hp,
			"enemy_hp_loss": before_enemy - enemies[0].current_hp - enemies[1].current_hp,
			"status_before": before_status, "status_after": player.has_status_effects(), "note": note}
		observations.append(row)
		print("[force-techniques] OBS ", JSON.stringify(row))
		_check(spent == 0 if id in BLOCKED else spent > 0, id + " cost matches current delivery gate")
		if id == "resta": _check(GameState.hp > before_hp, "Resta increases actual HP")
		if id == "anti": _check(before_status and not player.has_status_effects(), "Anti removes actual poison")
		_check(get_tree().get_nodes_in_group("technique_visuals").is_empty(), id + " bounded new VFX cleanup")
	# Exercise real palette hold/release resolution for every learnable base.
	for id in TechniqueManager.SHOP_BASIC_TECHS:
		if not OS.get_environment("PSZ_TECH_ONLY").is_empty() and id != OS.get_environment("PSZ_TECH_ONLY"): continue
		await prepare_case()
		ActionPalette.pages = [[id, "resta", "anti"], ["attack", "resta", "monofluid"]]
		ActionPalette.current_page = 0
		var before: int = GameState.mp
		player._on_palette_pressed(0)
		await ticks(90)
		_check(player._tech_charge_ready, id + " reaches charged state")
		player._on_palette_released(0)
		observations.append({"base": id, "charged": TechniqueManager.get_charged_technique(id), "pp_spent": before - GameState.mp})
		await ticks(180)

	if OS.get_environment("PSZ_TECH_ONLY") in ["", "barta"]:
		await prepare_case()
		enemies[0].global_position = origin + Vector3(0, 0, 7)
		enemies[1].global_position = origin + Vector3(0, 0, 11)
		await ticks(3)
		player._cast_technique("barta")
		await ticks(90)
		_check(enemies[0].current_hp < 10000, "Barta reaches the near target at 7 units")
		_check(enemies[1].current_hp == 10000, "Barta cannot reach the far target at 11 units")

func prepare_case() -> void:
	player.clear_status_effects()
	player.transition_to(player.PlayerState.IDLE)
	player.global_position = origin
	player.player_rotation = 0.0
	GameState.set_hp(maxi(1, GameState.max_hp - 20))
	GameState.set_mp(GameState.max_mp)
	for i in range(enemies.size()):
		enemies[i].global_position = origin + Vector3(i * 0.6, 0, 2.0 + i)
		enemies[i].current_hp = 10000
	player._targeted_enemies.assign(enemies)
	await ticks(3)

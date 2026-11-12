extends "res://scripts/tools/ranger_aim_probe.gd"
## Full-roster diagnostic. Legacy/advanced entries are test grants, not new disks.
const BANKS := [
	["foie", "barta", "zonde"], ["resta", "anti", "shifta"],
	["deband", "jellen", "zalure"], ["gifoie", "gibarta", "gizonde"],
	["rafoie", "rabarta", "razonde"], ["grants", "megid", "reverser"],
]
const BLOCKED := []
var bank := 0
var roster_label: Label
var observations: Array = []
var support_members: Array = []

func _run() -> void:
	probe_label = "force-techniques"
	if ProjectSettings.get_setting("application/config/name") != "PSZ Aim Prototype":
		get_tree().quit(1)
		return
	if OS.get_environment("PSZ_TECH_SUPPORT") == "1": bank = 1
	if OS.get_environment("PSZ_TECH_FOCUS") == "buffs": bank = 2
	if OS.get_environment("PSZ_TECH_FOCUS") in ["light_dark", "revive"]: bank = 5
	get_tree().current_scene = null
	await launch_fixture()
	configure_panel()
	if OS.get_environment("PSZ_AIM_CHECK") == "1":
		if OS.get_environment("PSZ_TECH_ONLY") == "revive":
			await audit_revive()
		elif OS.get_environment("PSZ_TECH_ONLY") == "light_dark":
			await audit_light_dark()
		elif OS.get_environment("PSZ_TECH_ONLY") == "buffs":
			await audit_stat_buffs()
		elif OS.get_environment("PSZ_TECH_ONLY") == "shifta" and OS.get_environment("PSZ_TECH_SUPPORT") == "1":
			await audit_shifta()
		else:
			await audit_palette_availability()
			await audit_roster()
			if OS.get_environment("PSZ_TECH_SUPPORT") == "1": await audit_support_party()
		var output := OS.get_environment("PSZ_TECH_REPORT")
		if not output.is_empty():
			var file := FileAccess.open(output, FileAccess.WRITE)
			file.store_string(JSON.stringify({"loadout": Loadouts.label(), "observations": observations}, "\t") + "\n")
		print("[force-techniques] DONE ", "ok" if _ok else "FAIL")
		get_tree().quit(0 if _ok else 1)
	else:
		for enemy in enemies: enemy.set_physics_process(OS.get_environment("PSZ_TECH_SUPPORT") != "1" and OS.get_environment("PSZ_TECH_FOCUS").is_empty())
		DisplayServer.window_set_title("Force Coliseum — F3 technique bank • F4 refill • T enemy AI • Z shoulder • Q lock")

func configure_panel() -> void:
	if OS.get_environment("PSZ_TECH_FOCUS") in ["rafoie", "rabarta", "razonde", "light_dark"]:
		for enemy in enemies:
			enemy.enemy_data = enemy.enemy_data.duplicate(true)
			enemy.enemy_data.hp_base = 10000
			enemy.current_hp = 10000
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
	if OS.get_environment("PSZ_TECH_FOCUS") == "light_dark":
		for i in range(enemies.size()): enemies[i].global_position = origin + Vector3(0, 0, 4 + i * 3)
	if OS.get_environment("PSZ_TECH_FOCUS") == "buffs":
		for i in range(enemies.size()): enemies[i].global_position = origin + Vector3(-1.5 + i * 3, 0, 3)
	if OS.get_environment("PSZ_TECH_SUPPORT") == "1":
		GameState.set_hp(maxi(1, GameState.max_hp / 2))
		support_members.clear()
		support_members.append(make_support_member("sarisa", Vector3(-2, 0, 1)))
		support_members.append(make_support_member("kai", Vector3(8, 0, 0)))
		if OS.get_environment("PSZ_TECH_FOCUS") == "revive":
			for member in support_members: member.set_defeated_for_test()

func reload_fixture() -> void:
	await super.reload_fixture()
	configure_panel()
	for enemy in enemies: enemy.set_physics_process(OS.get_environment("PSZ_TECH_SUPPORT") != "1" and OS.get_environment("PSZ_TECH_FOCUS").is_empty())

func grant_roster() -> void:
	var character: Dictionary = CharacterManager.get_active_character()
	for id in TechniqueManager.TECHNIQUES: character.techniques[id] = 1

func set_bank() -> void:
	player._drop_charge()
	ActionPalette.pages = [BANKS[bank].duplicate(), ["attack", "resta", "monofluid"]]
	ActionPalette.current_page = 0
	ActionPalette.config_changed.emit()
	roster_label.text = "FORCE COLISEUM — %d/6: %s\nF2 restart • B spells • U refill • P refill PP • H lose HP • T enemies • R reset\nJ / K / L or mouse • Hold then release to cast • Shift: Attack / Resta / Fluid\nZ shoulder • Q lock • Tab target • Space dodge" % [bank + 1, " / ".join(BANKS[bank])]
	if OS.get_environment("PSZ_TECH_SUPPORT") == "1": roster_label.text += "\nF5 poison party • H injure party • F7 move Kai near/far"
	if OS.get_environment("PSZ_TECH_FOCUS") == "rafoie": roster_label.text += "\nRAFOIE: hold J until charged, release to blast • Q lock • R reset targets"
	if OS.get_environment("PSZ_TECH_FOCUS") == "rabarta": roster_label.text += "\nRABARTA: hold K until charged, release • P refill PP • R reset targets"
	if OS.get_environment("PSZ_TECH_FOCUS") == "razonde": roster_label.text += "\nRAZONDE: hold L until charged, release • P refill PP • R reset targets"
	if OS.get_environment("PSZ_TECH_FOCUS") == "buffs": roster_label.text += "\nJ Deband (blue party) • K Jellen (red enemies) • L Zalure (blue enemies) • P refill PP"
	if OS.get_environment("PSZ_TECH_FOCUS") == "revive": roster_label.text += "\nSarisa down beside you • Tap L to revive • Charge L for group/half HP • N down allies again • P refill PP"
	if bank == 1: roster_label.text += "\nMiddle-click Shifta: red wrist glow = ATK buff (60 seconds)."
	if bank in [2, 5]: roster_label.text += "\nTap J Grants • Tap K Megid • Tap L Reverser (hold: group)."
	if bank >= 3: roster_label.text += "\nAdvanced spells granted for this test only."


## Claim fixture shortcuts before the field's F3/F5/F6/F7 debug bindings.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if not is_instance_valid(player) or GameState.is_gameplay_blocked(): return
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code not in [KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_B, KEY_U, KEY_P, KEY_H, KEY_N]: return
	var shortcut := event.duplicate() as InputEventKey
	shortcut.physical_keycode = code
	_unhandled_input(shortcut)
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and is_instance_valid(player):
		match event.physical_keycode:
			KEY_F2:
				if not switching:
					switching = true
					reload_fixture.call_deferred()
				return
			KEY_F3, KEY_B:
				bank = (bank + 1) % BANKS.size()
				set_bank()
				return
			KEY_F4, KEY_U:
				GameState.set_hp(GameState.max_hp)
				GameState.set_mp(GameState.max_mp)
				return
			KEY_P:
				GameState.set_mp(GameState.max_mp)
				return
			KEY_F7:
				if support_members.size() > 1 and is_instance_valid(support_members[1]):
					var ally = support_members[1]
					ally.global_position = player.global_position + Vector3(2.5 if ally.global_position.distance_to(player.global_position) > 6 else 8, 0, 0)
				return
			KEY_N:
				for member in support_members:
					if is_instance_valid(member): member.set_defeated_for_test()
				return
			KEY_F6, KEY_H:
				if not player._is_defeated: GameState.set_hp(maxi(1, GameState.hp - 30))
				for member in support_members:
					if is_instance_valid(member): member.current_hp = maxi(1, member.current_hp - 30)
				return
			KEY_F5:
				print("[force-techniques] Poison shortcut received")
				player.apply_status_effect("poison")
				for member in support_members:
					if is_instance_valid(member): member.apply_status_effect("poison")
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
		if not OS.get_environment("PSZ_TECH_ONLY").is_empty() and id not in OS.get_environment("PSZ_TECH_ONLY").split(","): continue
		await prepare_case()
		if id == "anti": player.apply_status_effect("poison")
		var before_status: bool = player.has_status_effects()
		var before_hp: int = GameState.hp
		var before_pp: int = GameState.mp
		var before_enemy: int = enemies[0].current_hp + enemies[1].current_hp
		var no_revive_target: bool = id == "reverser" and preload("res://scripts/3d/combat/support_technique.gd").revive_target(player) == null
		player._cast_technique(id)
		var spent: int = before_pp - GameState.mp
		await ticks(8)
		await _snapshot("tech-" + id)
		await ticks(172)
		var note := "implemented delivery; visual/feel review pending"
		if id == "reverser" and spent == 0: note = "no defeated party recipient in range"

		var row := {"id": id, "tier": TechniqueManager.TECHNIQUES[id].tier,
			"effective_level": TechniqueManager.get_technique_level(CharacterManager.get_active_character(), id),
			"pp_spent": spent, "hp_gain": GameState.hp - before_hp,
			"enemy_hp_loss": before_enemy - enemies[0].current_hp - enemies[1].current_hp,
			"status_before": before_status, "status_after": player.has_status_effects(), "note": note}
		observations.append(row)
		print("[force-techniques] OBS ", JSON.stringify(row))
		_check(spent == 0 if id in BLOCKED or no_revive_target else spent > 0, id + " cost matches current delivery gate")
		if id == "resta": _check(GameState.hp > before_hp, "Resta increases actual HP")
		if id == "anti": _check(before_status and not player.has_status_effects(), "Anti removes actual poison")
		_check(get_tree().get_nodes_in_group("technique_visuals").is_empty(), id + " bounded new VFX cleanup")
	await audit_charge_and_range()

func audit_charge_and_range() -> void:
	# Exercise real palette hold/release resolution for every learnable base.
	for id in TechniqueManager.SHOP_BASIC_TECHS:
		if not OS.get_environment("PSZ_TECH_ONLY").is_empty() and id not in OS.get_environment("PSZ_TECH_ONLY").split(","): continue
		await prepare_case()
		ActionPalette.pages = [["resta", id, "anti"], ["attack", "resta", "monofluid"]]
		ActionPalette.current_page = 0
		var before: int = GameState.mp
		var tap := InputEventKey.new()
		tap.physical_keycode = KEY_K
		tap.pressed = true
		Input.parse_input_event(tap)
		await ticks(2)
		tap = tap.duplicate()
		tap.pressed = false
		Input.parse_input_event(tap)
		await ticks(2)
		_check(GameState.mp == before and player._charging_slot == -1, id + " early release cancels without casting")
		var press := InputEventKey.new()
		press.physical_keycode = KEY_K
		press.pressed = true
		Input.parse_input_event(press)
		await ticks(90)
		_check(player._tech_charge_ready, id + " reaches charged state")
		_check(GameState.mp == before, id + " holding K spends no PP before release")
		press = press.duplicate()
		press.pressed = false
		Input.parse_input_event(press)
		await ticks(1)
		_check(GameState.mp < before if id not in BLOCKED else GameState.mp == before, id + " K release resolves charged cost")
		observations.append({"base": id, "charged": TechniqueManager.get_charged_technique(id), "pp_spent": before - GameState.mp})
		await ticks(180)

	if OS.get_environment("PSZ_TECH_ONLY") in ["razonde", "zonde,razonde"]:
		await prepare_case()
		player._cast_technique("razonde")
		await ticks(3)
		_check(enemies[0].current_hp < 10000 and enemies[1].current_hp == 10000, "Razonde strikes first target before chaining")
		await ticks(12)
		_check(enemies[1].current_hp < 10000, "Razonde chains to second enemy")
		var hp_after: int = enemies[0].current_hp + enemies[1].current_hp
		await ticks(90)
		_check(enemies[0].current_hp + enemies[1].current_hp == hp_after, "Razonde never repeats a target")
		_check(get_tree().get_nodes_in_group("technique_visuals").is_empty(), "Razonde chain cleans up")
		await prepare_case()
		enemies[1].global_position = origin + Vector3(0, 0, 13)
		player._cast_technique("razonde")
		await ticks(100)
		_check(enemies[1].current_hp == 10000, "Razonde stays within cast area")

	if OS.get_environment("PSZ_TECH_ONLY") in ["rabarta", "barta,rabarta"]:
		await prepare_case()
		enemies[0].global_position = origin + Vector3(2.0, 0, 3.0)
		enemies[1].global_position = origin + Vector3(0, 0, 6.0)
		player._cast_technique("rabarta")
		await ticks(6)
		_check(enemies[0].current_hp == 10000, "Rabarta waits for expanding wave to reach target")
		await ticks(30)
		_check(enemies[0].current_hp < 10000, "Rabarta hits between former projectile spokes")
		var after_hit: int = enemies[0].current_hp
		await ticks(90)
		_check(enemies[0].current_hp == after_hit, "Rabarta hits each enemy once")
		_check(enemies[1].current_hp == 10000, "Rabarta excludes target beyond five-unit radius")
		_check(get_tree().get_nodes_in_group("technique_visuals").is_empty(), "Rabarta sheet and growth clean up")

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

func make_support_member(id: String, offset: Vector3):
	var member = preload("res://scripts/3d/elements/companion_npc.gd").new()
	member.companion_id = id
	get_tree().current_scene.add_child(member)
	member.global_position = origin + offset
	member.current_hp = maxi(1, member.max_hp / 2)
	member.set_physics_process(false) # Stationary recipients for range comparison.
	var label := Label3D.new()
	label.name = "SupportReadout"
	label.position.y = 2.5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 26
	member.add_child(label)
	return member

func _process(_delta: float) -> void:
	for member in support_members:
		if not is_instance_valid(member): continue
		member.get_node("SupportReadout").text = "%s: %d/%d HP%s" % [member.companion_id, member.current_hp, member.max_hp, " — Poison" if member.has_status_effects() else ""]

func audit_support_party() -> void:
	await prepare_case()
	var near = support_members[0]
	var far = support_members[1]
	near.current_hp = 1
	far.current_hp = 1
	var dead = make_support_member("dorn", Vector3(2, 0, 0))
	dead.current_hp = 0
	var enemy_hp: int = enemies[0].current_hp
	player._cast_technique("resta")
	await ticks(2)
	_check(near.current_hp > 1 and near.current_hp <= near.max_hp, "Resta heals nearby real companion with HP cap")
	_check(far.current_hp == 1, "Resta excludes out-of-range companion")
	_check(dead.current_hp == 0, "Resta does not revive defeated companion")
	_check(enemies[0].current_hp == enemy_hp, "Resta does not affect enemies")
	_check(near.get_node_or_null("SupportParticles") != null and far.get_node_or_null("SupportParticles") == null, "particles attach only to changed recipients")
	await _snapshot("party-resta")
	await ticks(120)
	_check(get_tree().get_nodes_in_group("support_particles").is_empty() and get_tree().get_nodes_in_group("support_areas").is_empty(), "recipient particles and radius ring expire")
	await prepare_case()
	near.apply_status_effect("poison")
	far.apply_status_effect("poison")
	player.apply_status_effect("poison")
	player._cast_technique("anti")
	await ticks(2)
	_check(not player.has_status_effects() and not near.has_status_effects(), "Anti cures caster and nearby companion")
	_check(far.has_status_effects(), "Anti leaves out-of-range companion poisoned")
	await _snapshot("party-anti")
	await ticks(120)
	player._cast_technique("anti")
	_check(get_tree().get_nodes_in_group("support_particles").is_empty(), "clean recipients do not show false cure particles")
	await ticks(120)
	GameState.set_mp(0)
	var sound_index: int = SfxManager._next_3d_idx
	player._cast_technique("resta")
	_check(sound_index == SfxManager._next_3d_idx and get_tree().get_nodes_in_group("support_areas").is_empty(), "insufficient PP produces no sound or area")
	for path in preload("res://scripts/3d/combat/support_technique.gd").SOUNDS.values():
		_check(SfxManager._load(path) != null, "PSO cue loads: " + path)
	player.clear_status_effects()
	GameState.set_hp(GameState.max_hp)
	player.apply_status_effect("poison")
	var tick_sound: int = SfxManager._next_3d_idx
	var hp_before: int = GameState.hp
	player._ailments.tick(player, 4.9)
	_check(GameState.hp == hp_before and SfxManager._next_3d_idx == tick_sound, "poison sound waits for actual HP tick")
	player._ailments.tick(player, 0.1)
	_check(GameState.hp < hp_before and SfxManager._next_3d_idx == (tick_sound + 1) % SfxManager.POOL_SIZE, "poison HP tick emits one cue")
	player.clear_status_effects()
	tick_sound = SfxManager._next_3d_idx
	player._ailments.tick(player, 10.0)
	_check(SfxManager._next_3d_idx == tick_sound, "cured poison emits no further ticking cue")
	player.apply_status_effect("stun")
	_check(SfxManager._next_3d_idx == (tick_sound + 1) % SfxManager.POOL_SIZE, "stun application emits paralysis cue")
	player.clear_status_effects()
	for path in player._ailments.STATUS_SOUNDS.values(): _check(SfxManager._load(path) != null, "status cue loads: " + path)
	dead.queue_free()


func audit_shifta() -> void:
	const Buff = preload("res://scripts/3d/combat/shifta_buff.gd")
	for buff in get_tree().get_nodes_in_group("shifta_buffs"): buff.queue_free()
	await ticks(2)
	await prepare_case()
	var near = support_members[0]
	var far = support_members[1]
	var character: Dictionary = CharacterManager.get_active_character()
	var baseline: int = CombatManager._get_player_stats(character).attack
	var ally_baseline: int = near._companion_stats().attack
	var pp: int = GameState.mp
	player._cast_technique("shifta")
	await ticks(12)
	_check(GameState.mp < pp, "Shifta spends PP once at release")
	_check(Buff.amount_for(player) > 0 and Buff.amount_for(near) > 0 and Buff.amount_for(far) == 0, "Shifta applies to caster and nearby ally only")
	_check(CombatManager._get_player_stats(character).attack > baseline and near._companion_stats().attack > ally_baseline, "Shifta boosts actual player and companion attack stats")
	var buff = player.get_node("ShiftaBuff")
	_check(buff._bones.size() == 2 and buff._bones[0] >= 0 and buff._bones[1] >= 0, "both player wrists resolve on the actual rig")
	var ally_buff = near.get_node("ShiftaBuff")
	_check(ally_buff._bones.size() == 2 and ally_buff._bones[0] >= 0 and ally_buff._bones[1] >= 0, "both ally wrists resolve on the actual rig")
	_check(SfxManager._load(preload("res://scripts/3d/combat/support_technique.gd").SOUNDS.shifta) != null, "Shifta PSO cue loads")
	await _snapshot("party-shifta")
	var boosted: int = CombatManager._get_player_stats(character).attack
	Buff.apply_to(player, 1)
	_check(CombatManager._get_player_stats(character).attack == boosted and is_equal_approx(buff.remaining, 60.0), "recast refreshes timer without multiplying attack again")
	near.current_hp = 0
	await get_tree().process_frame
	await get_tree().process_frame
	_check(Buff.amount_for(near) == 0 and near.get_node_or_null("ShiftaBuff") == null, "defeated ally loses Shifta and wrist glow")
	buff.remaining = 0.01
	await get_tree().create_timer(0.1).timeout
	await get_tree().process_frame
	_check(player.get_node_or_null("ShiftaBuff") == null and CombatManager._get_player_stats(character).attack == baseline, "expiry removes attack boost and wrist glow together")

func audit_palette_availability() -> void:
	await prepare_case()
	var cue = preload("res://scripts/3d/player/combat_palette_cue.gd")
	GameState.set_mp(29)
	_check(not cue.available(player, "foie"), "palette uses Rafoie cost rather than base Foie cost")
	GameState.set_mp(30)
	_check(cue.available(player, "foie"), "palette allows exact charged PP cost")
	GameState.set_mp(0)
	var hp_before: int = GameState.hp
	key(KEY_P)
	await ticks(1)
	_check(GameState.mp == GameState.max_mp and GameState.hp == hp_before, "P refills PP without changing HP")
	_check(not player.has_status_effects(), "P no longer poisons player")
	_check(cue.available(player, "foie"), "refill restores technique availability")
	_check(not cue.available(player, "reverser"), "unimplemented support is unavailable")

func audit_stat_buffs() -> void:
	await prepare_case()
	var buff_script = preload("res://scripts/3d/combat/shifta_buff.gd")
	var support = preload("res://scripts/3d/combat/support_technique.gd")
	var character: Dictionary = CharacterManager.get_active_character()
	var defense: int = CombatManager._get_player_stats(character).defense
	var recipients: Array = support.cast(player, "deband", 1)
	_check(player in recipients and support_members[0] in recipients and support_members[1] not in recipients, "Deband affects self and nearby party only")
	_check(CombatManager._get_player_stats(character).defense > defense, "Deband raises actual player defense")
	_check(buff_script.amount_for(enemies[0], "deband") == 0, "Deband excludes enemies")
	var enemy = enemies[0]
	enemy.enemy_data = enemy.enemy_data.duplicate(true)
	enemy.enemy_data.original_attack_stats = false
	enemy.enemy_data.attack_base = 100
	var attack: int = enemy._attack_damage({})
	recipients = support.cast(player, "jellen", 1)
	_check(enemy in recipients and player not in recipients, "Jellen affects enemies only")
	_check(enemy._attack_damage({}) < attack, "Jellen reduces actual outgoing enemy damage")
	support.cast(player, "zalure", 1)
	_check(buff_script.amount_for(enemy, "zalure") > 0 and buff_script.amount_for(player, "zalure") == 0, "Zalure affects enemy defense only")
	await ticks(3)
	var buff = enemy.get_node("JellenBuff")
	_check(buff._drips.size() == 2 and buff._drips[0].emitting and not buff._clouds[0].visible, "enemy debuffs drip instead of glowing")
	_check(enemy.get_node("ZalureBuff")._clouds[0].material_override.get_shader_parameter("defense"), "Zalure uses blue defense cloud")
	_check(not buff._clouds[0].material_override.get_shader_parameter("defense"), "Jellen uses red attack cloud")
	var baseline_defense: int = enemy.current_defense
	enemy.current_defense = 100
	var zalure = enemy.get_node("ZalureBuff")
	zalure.remaining = 0.0
	seed(42)
	var hp: int = enemy.current_hp
	enemy._on_hit_received(200, Vector3.ZERO, 10000)
	var normal_loss: int = hp - enemy.current_hp
	zalure.remaining = 60.0
	seed(42)
	hp = enemy.current_hp
	enemy._on_hit_received(200, Vector3.ZERO, 10000)
	_check(hp - enemy.current_hp > normal_loss, "Zalure increases damage through reduced enemy defense")
	enemy.current_defense = baseline_defense
	support.cast(player, "jellen", 1)
	_check(enemy._attack_damage({}) == int(attack * 0.9), "recast refreshes without stacking")
	buff.remaining = 0.0
	_check(enemy._attack_damage({}) == attack, "expired Jellen restores attack")
	player.get_node("DebandBuff").remaining = 0.0
	_check(CombatManager._get_player_stats(character).defense == defense, "expired Deband restores defense")
	for id in ["deband", "jellen", "zalure", "grants", "megid"]:
		_check(load(support.SOUNDS[id]) is AudioStream, id + " sound loads")

func audit_light_dark() -> void:
	await prepare_case()
	player._cast_technique("grants")
	await ticks(30)
	_check(enemies[0].current_hp == 10000, "Grants buildup deals no early damage")
	await ticks(40)
	_check(enemies[0].current_hp < 10000 and enemies[1].current_hp == 10000, "Grants pillar damages only selected target")
	await ticks(40)
	_check(get_tree().get_nodes_in_group("technique_visuals").is_empty(), "Grants visuals clean up")
	await prepare_case()
	var strike = preload("res://scripts/3d/combat/grants_strike.gd").new()
	strike.target = enemies[0]
	strike.caster = player
	strike.damage = 100
	get_tree().current_scene.add_child(strike)
	strike.target = null
	await ticks(2)
	_check(not is_instance_valid(strike), "Grants safely cancels when target disappears")
	var orb = preload("res://scripts/3d/combat/megid_projectile.gd").new()
	orb.owner_node = player
	orb.element_level = 1
	orb.element = "dark"
	orb.attack_kind = "technique"
	orb.damage = 100
	orb.accuracy = 10000
	orb.visual_kind = "megid"
	get_tree().current_scene.add_child(orb)
	orb.set_physics_process(false)
	var success_seed := 0
	var failure_seed := 0
	for candidate in range(100):
		seed(candidate)
		if randf() < 0.21: success_seed = candidate
		else: failure_seed = candidate
	var enemy = enemies[0]
	seed(failure_seed)
	orb._on_area_entered(enemy.hurtbox)
	_check(not orb._spent and not orb.is_queued_for_deletion(), "Megid continues after first contact")
	seed(failure_seed)
	orb._on_area_entered(enemies[1].hurtbox)
	_check(orb._hit_targets.size() == 2 and not orb._spent, "Megid contacts multiple distinct targets")
	orb._on_area_entered(enemy.hurtbox)
	_check(orb._hit_targets.size() == 2, "Megid never repeats a target")
	var before_damage: int = enemy.current_hp
	seed(failure_seed)
	orb._deliver(enemy.hurtbox, Vector3.ZERO)
	_check(enemy.is_alive and enemy.current_hp < before_damage, "Megid deals normal damage when instant defeat fails")
	enemy.enemy_data = enemy.enemy_data.duplicate(true)
	enemy.enemy_data.is_boss = true
	before_damage = enemy.current_hp
	seed(success_seed)
	orb._deliver(enemy.hurtbox, Vector3.ZERO)
	_check(enemy.is_alive and enemy.current_hp < before_damage, "boss resists instant defeat but takes Megid damage")
	enemy.enemy_data.is_boss = false
	seed(success_seed)
	orb._deliver(enemy.hurtbox, Vector3.ZERO)
	_check(not enemy.is_alive and enemy.current_hp == 0, "successful Megid uses enemy defeat lifecycle")
	orb.queue_free()

func audit_revive() -> void:
	await prepare_case()
	var near = support_members[0]
	var far = support_members[1]
	near.set_defeated_for_test()
	far.set_defeated_for_test()
	_check(near._anim_player.has_animation("down") and near._current_anim == "down", "Sarisa has a downed animation at zero HP")
	var before: int = GameState.mp
	ActionPalette.pages = [["grants", "megid", "reverser"], ["attack", "resta", "monofluid"]]
	ActionPalette.current_page = 0
	player._on_palette_pressed(2)
	player._on_palette_released(2)
	_check(near.current_hp > 0 and far.current_hp == 0, "Reverser restores nearby defeated ally only")
	_check(GameState.mp < before, "Reverser consumes PP on valid cast")
	_check(not get_tree().get_nodes_in_group("technique_visuals").is_empty(), "revived ally receives halo")
	await ticks(120)
	_check(get_tree().get_nodes_in_group("technique_visuals").is_empty(), "revive halo cleans up")
	before = GameState.mp
	player._cast_technique("reverser")
	_check(GameState.mp == before, "no defeated ally in range means no PP cost")
	await prepare_case()
	near.set_defeated_for_test()
	far.set_defeated_for_test()
	far.global_position = player.global_position + Vector3(3, 0, 0)
	player._on_palette_pressed(2)
	await ticks(90)
	_check(near.current_hp == 0 and far.current_hp == 0, "charging revive waits for release")
	player._on_palette_released(2)
	_check(near.current_hp >= ceili(near.max_hp * 0.5) and far.current_hp >= ceili(far.max_hp * 0.5), "charged revive restores nearby party to at least half HP")
	await ticks(120)
	await prepare_case()
	ActionPalette.pages = [["grants", "megid", "reverser"], ["attack", "resta", "monofluid"]]
	ActionPalette.current_page = 0
	before = GameState.mp
	player._on_palette_pressed(0)
	_check(GameState.mp < before and player._charging_slot == -1, "Grants casts immediately without charging")
	await ticks(120)
	await prepare_case()
	before = GameState.mp
	player._on_palette_pressed(1)
	_check(GameState.mp < before and player._charging_slot == -1, "Megid casts immediately without charging")

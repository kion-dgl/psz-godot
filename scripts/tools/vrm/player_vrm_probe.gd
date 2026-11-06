extends "res://scripts/tools/humar_vrm_probe.gd"
## All playable avatars through production loading and animation remapping.
var model_count := 0
var library_count := 0

func _setup() -> void:
	var libraries := DirAccess.get_files_at("res://assets/player/animations")
	for class_id in PlayerConfig.CLASS_PREFIX:
		for variation in range(PlayerConfig.HEAD_VARIATIONS):
			_create_pair(class_id, variation)
			if players.size() != 2 or players[1].skeleton == null:
				_check(false, "missing skeleton: %s/%d" % [class_id, variation])
				get_tree().quit(1)
				return
			_check(players[1].get_node("PlayerModel/Model").has_meta("psz_avatar_format"), "VRM used")
			_check(players[1].skeleton.get_bone_count() == 16, "16-bone compatible skeleton")
			_check(players[1].weapon_node != null, "starter weapon attached")
			_check(players[1].mag_node != null, "mag attached")
			_check_equipment()
			var gender := "_w.glb" if players[1]._is_female else "_m.glb"
			for file in libraries:
				if not file.ends_with(gender):
					continue
				for player in players:
					player.animation_player.stop()
					for key in player.animation_player.get_animation_library_list():
						player.animation_player.remove_animation_library(key)
					player.skeleton.reset_bone_poses()
					var lib: AnimationLibrary = player._build_animation_library("res://assets/player/animations/" + file)
					_check(lib != null, "library: " + file)
					player.animation_player.add_animation_library("", lib)
				_compare_animations()
				library_count += 1
			for player in players:
				player.free()
			players.clear()
			model_count += 1
			print("[player-vrm] %s/%d complete" % [class_id, variation])
			await get_tree().process_frame
	print("[player-vrm] DONE models=%d libraries=%d failures=%d" % [model_count, library_count, failures])
	get_tree().quit(1 if failures else 0)

func _create_pair(class_id: String, variation: int) -> void:
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, class_id, "VRM Test", {"variation_index": variation, "body_color_index": 4, "hair_color_index": 2, "skin_tone_index": 2})
	CharacterManager.set_active_slot(0)
	SessionManager.enter_field("gurhacia", "normal")
	for i in range(2):
		var player := PLAYER.instantiate() as CharacterBody3D
		if i == 0:
			player.set_script(preload("res://scripts/tools/vrm/legacy_player_fixture.gd"))
		add_child(player)
		player.set_physics_process(false)
		player.set_process(false)
		if player.animation_player:
			player.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		players.append(player)

func _process(_delta: float) -> void:
	pass

func _check_equipment() -> void:
	var seen: Dictionary = {}
	var character: Dictionary = CharacterManager.get_active_character()
	for weapon_id in WeaponRegistry.get_all_weapon_ids():
		var weapon: WeaponData = WeaponRegistry.get_weapon(weapon_id)
		if seen.has(weapon.weapon_type) or weapon.glb_path.is_empty():
			continue
		seen[weapon.weapon_type] = true
		character.equipment.weapon = weapon_id
		for player in players:
			player.transition_to(player.PlayerState.IDLE)
			player.refresh_weapon()
			_check(player.weapon_node != null, "weapon attachment: " + weapon_id)
			if weapon.weapon_type in [WeaponData.WeaponType.DAGGERS, WeaponData.WeaponType.MECH_GUN]:
				_check(player.weapon_node_left != null, "offhand attachment: " + weapon_id)
			player._start_attack()
			_check(player.current_state == player.PlayerState.ATTACKING, "attack starts: " + weapon_id)
			_check(player.animation_player.is_playing(), "attack animates: " + weapon_id)
			_check(player._attack_anim_length > 0, "attack timing: " + weapon_id)
		_check(players[0].animation_player.current_animation == players[1].animation_player.current_animation, "same attack clip: " + weapon_id)
		_check(players[0].weapon_node.transform.is_equal_approx(players[1].weapon_node.transform), "same weapon socket: " + weapon_id)
	for player in players:
		player.transition_to(player.PlayerState.IDLE)
	print("[player-vrm] weapon types exercised: ", seen.size())

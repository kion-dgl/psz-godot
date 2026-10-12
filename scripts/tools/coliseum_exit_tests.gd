extends "res://scripts/tools/probe_checks.gd"

func _run() -> void:
	probe_label = "coliseum-exit"
	SessionManager.reset_all_state()
	CharacterManager.create_character(0, "humar", "ExitProbe")
	CharacterManager.set_active_slot(0)
	for completed in [false, true]:
		SessionManager.enter_quest("debug_coliseum", "normal")
		if completed:
			SessionManager.mark_quest_complete()
		SessionManager.suspend_session()
		_check(not SessionManager.has_completed_quest(), "Coliseum return needs no guild report")
		_check(not SessionManager.has_suspended_session(), "Coliseum return leaves no suspended quest")
		var pad := WarpPad.new()
		_check(pad._is_pad_active(), "central warp remains active after Coliseum")
		pad.free()
		var guild = load("res://scenes/2d/guild_counter.tscn").instantiate()
		get_tree().root.add_child(guild)
		var available: Array = guild._entries.filter(func(e): return e.type == "quest" and e.available)
		_check(not available.is_empty(), "guild offers playable quests after Coliseum")
		guild.free()
		var warp = load("res://scenes/2d/warp_teleporter.tscn").instantiate()
		get_tree().root.add_child(warp)
		_check(warp._visible_areas.any(func(e): return e.id == "gurhacia"), "free-roam picker offers Valley")
		warp.free()
		SessionManager.reset_all_state()
	# Story completion still requires the normal guild report.
	SessionManager.enter_quest("search_and_rescue", "normal")
	SessionManager.mark_quest_complete()
	SessionManager.suspend_session()
	_check(SessionManager.has_completed_quest() and SessionManager.has_suspended_session(), "story quest keeps report and resume state")
	SessionManager.reset_all_state()
	print("[coliseum-exit] DONE %s" % ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

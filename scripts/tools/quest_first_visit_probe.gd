extends "res://scripts/tools/probe_checks.gd"
## Entry: godot --headless --path . res://scripts/tools/quest_first_visit_probe.tscn
## Actual DOE B traversal: collect Peparian before visiting the key room.
func _run() -> void:
	probe_label = "first-visit"
	get_tree().current_scene = null
	CharacterManager._characters.clear()
	CharacterManager._characters.resize(20)
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "RouteProbe")
	CharacterManager.set_active_slot(0)
	SessionManager.enter_quest("deep_ore_extraction", "normal")
	SessionManager.set_current_section(2)
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
		"current_cell_pos": "2,0", "spawn_edge": "", "keys_collected": {}})
	for frame in 36000:
		await get_tree().physics_frame
		if int(SessionManager.get_quest_item_count("peparian")) > 0:
			var visits: int = int(Autopilot._cell_visit_count.get("2:1,1", 0))
			_check(visits == 1, "Peparian collected on first actual visit to B 1,1")
			_check(Inventory.get_key_count("key_2_1") == 0, "pickup occurs before key detour, without opening gate early")
			print("[first-visit] DONE %s" % ("ok" if _ok else "FAIL"))
			get_tree().quit(0 if _ok else 1)
			return
	_check(false, "timed out before first-visit pickup")
	get_tree().quit(1)

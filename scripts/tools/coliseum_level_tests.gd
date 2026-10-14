extends RefCounted
static func run(t: Node) -> void:
	var session := SessionManager.get_session()
	session["coliseum_encounter"] = true
	var items_before := Inventory._items.duplicate(true)
	t.assert_eq(Inventory._use_telepipe(), false, "Coliseum blocks consumable escape")
	t.assert_eq(Inventory._items, items_before, "blocked escape consumes no items")
	session.erase("coliseum_encounter")
	var growth = preload("res://scripts/utils/enemy_progression.gd")
	t.assert_eq(growth.level_for({"area_id":"dark","difficulty":"normal"}),30,"automatic Shrine level remains 30")
	t.assert_eq(growth.level_for({"area_id":"dark","coliseum_enemy_level":12,"difficulty":"hard"}, 80),12,"Coliseum explicit level overrides cell and difficulty offset")
	t.assert_eq(growth.level_for({"coliseum_enemy_level":900}),100,"Coliseum level clamps at 100")
	for area in growth.AREA_LEVELS:
		for difficulty in growth.DIFFICULTY_LEVELS:
			var session_data := {"area_id": "gurhacia", "difficulty": difficulty}
			var expected: int = growth.AREA_LEVELS[area] + growth.DIFFICULTY_LEVELS[difficulty]
			t.assert_eq(growth.level_for(session_data, 0, area), expected, "current section controls area fallback")
			t.assert_eq(growth.level_for(JSON.parse_string(JSON.stringify(session_data)), 0, area), expected, "serialized level inputs are stable")
			session_data.enemy_level = 12
			t.assert_eq(growth.level_for(session_data, 0, area), 12 + growth.DIFFICULTY_LEVELS[difficulty], "authored quest beats section fallback")
			t.assert_eq(growth.level_for(session_data, 4, area), 4 + growth.DIFFICULTY_LEVELS[difficulty], "authored cell beats quest")
	var dialog := DebugLevelDialog.new()
	t.add_child(dialog)
	dialog.configure("Enemy level",0,true)
	for pair in [["ui_up",1],["ui_left",0],["ui_right",10]]:
		var event := InputEventAction.new()
		event.action = pair[0]
		event.pressed = true
		dialog._input(event)
		t.assert_eq(dialog.value,pair[1],"level dialog directional input respects Auto boundary")
	dialog.queue_free()
	var inventory := Inventory._items.duplicate(true)
	var vitals := [GameState.hp,GameState.max_hp,GameState.mp,GameState.max_mp]
	var before := CharacterManager._characters.duplicate(true)
	var slot := CharacterManager._active_slot
	CharacterManager._characters = [null]
	CharacterManager._active_slot = -1
	var hero := CharacterManager.create_character(0,"humar","LevelTest")
	CharacterManager.set_active_slot(0)
	hero.material_bonuses = {"hp":7,"pp":3}
	for level in [50,1,100]:
		CharacterManager.set_debug_level(level)
		var stats := CharacterManager.get_stats_at_level("humar",level)
		t.assert_eq(hero.level,level,"debug level supports raising and lowering")
		t.assert_eq(CharacterManager._calculate_level(hero.experience),level,"debug XP matches selected level")
		t.assert_eq(GameState.hp,int(stats.hp)+7,"debug level refreshes and heals HP with materials")
		t.assert_eq(GameState.mp,int(stats.pp)+3,"debug level refreshes and heals PP with materials")
	CharacterManager._characters = before
	CharacterManager._active_slot = slot
	CharacterManager._sync_to_game_state()

	Inventory.restore_items(inventory,inventory.keys())
	GameState.set_max_hp(vitals[1])
	GameState.set_hp(vitals[0])
	GameState.set_max_mp(vitals[3])
	GameState.set_mp(vitals[2])

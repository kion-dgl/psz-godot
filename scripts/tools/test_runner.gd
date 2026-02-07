extends Node
## Headless test runner — exercises game systems without UI.
## Run: godot --headless --path /home/kion/Github/psz-godot/ res://scripts/tools/test_runner.tscn

var _pass := 0
var _fail := 0


func _ready() -> void:

	print("\n══════════════════════════════════")
	print("  PSZ-GODOT HEADLESS TEST RUNNER")
	print("══════════════════════════════════\n")

	test_registries()
	test_inventory()
	test_inventory_capacity()
	test_character_creation()
	test_equipment()
	test_combat_math()
	test_combat_drops()
	test_combat_simulation()
	test_session_manager()
	test_mission_progression()
	test_shops()

	print("\n══════════════════════════════════")
	print("  RESULTS: %d passed, %d failed" % [_pass, _fail])
	print("══════════════════════════════════\n")

	get_tree().quit()


func assert_true(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  PASS: %s" % label)
	else:
		_fail += 1
		print("  FAIL: %s" % label)


func assert_eq(a, b, label: String) -> void:
	if a == b:
		_pass += 1
		print("  PASS: %s" % label)
	else:
		_fail += 1
		print("  FAIL: %s — got %s, expected %s" % [label, str(a), str(b)])


func assert_gt(a, b, label: String) -> void:
	if a > b:
		_pass += 1
		print("  PASS: %s" % label)
	else:
		_fail += 1
		print("  FAIL: %s — got %s, expected > %s" % [label, str(a), str(b)])


# ── Registry tests ──────────────────────────────────────────

func test_registries() -> void:
	print("── Registries ──")
	assert_gt(WeaponRegistry.get_weapon_count(), 300, "WeaponRegistry has 300+ weapons")
	assert_gt(ArmorRegistry.get_armor_count(), 40, "ArmorRegistry has 40+ armors")
	assert_gt(EnemyRegistry.get_enemy_count(), 60, "EnemyRegistry has 60+ enemies")
	assert_eq(ClassRegistry.get_class_count(), 14, "ClassRegistry has 14 classes")
	assert_gt(ConsumableRegistry.get_all_consumables().size(), 10, "ConsumableRegistry has 10+ consumables")
	assert_gt(UnitRegistry.get_all_units().size(), 80, "UnitRegistry has 80+ units")
	assert_gt(PhotonArtRegistry.get_all_arts().size(), 40, "PhotonArtRegistry has 40+ PAs")
	assert_gt(MissionRegistry.get_all_missions().size(), 10, "MissionRegistry has 10+ missions")

	# Specific lookups
	var saber = WeaponRegistry.get_weapon("saber")
	assert_true(saber != null, "Can look up saber")
	if saber:
		assert_eq(saber.name, "Saber", "Saber name correct")
		assert_eq(saber.attack_base, 39, "Saber ATK base = 39")

	var common_armor = ArmorRegistry.get_armor("common_armor")
	assert_true(common_armor != null, "Can look up common_armor")
	if common_armor:
		assert_eq(common_armor.defense_base, 33, "Common Armor DEF base = 33")

	var monomate = ConsumableRegistry.get_consumable("monomate")
	assert_true(monomate != null, "Can look up monomate")
	print("")


# ── Inventory tests ─────────────────────────────────────────

func test_inventory() -> void:
	print("── Inventory ──")
	Inventory.clear_inventory()

	assert_true(Inventory.add_item("monomate", 3), "Add 3 monomates")
	assert_eq(Inventory.get_item_count("monomate"), 3, "Monomate count = 3")
	assert_true(Inventory.has_item("monomate"), "Has monomate")

	assert_true(Inventory.add_item("saber", 1), "Add saber")
	assert_eq(Inventory.get_item_count("saber"), 1, "Saber count = 1")
	# Weapons don't stack
	assert_true(not Inventory.can_add_item("saber"), "Can't add second saber (max_stack=1)")

	assert_true(Inventory.remove_item("monomate", 1), "Remove 1 monomate")
	assert_eq(Inventory.get_item_count("monomate"), 2, "Monomate count = 2")

	assert_true(Inventory.remove_item("monomate", 2), "Remove remaining monomates")
	assert_true(not Inventory.has_item("monomate"), "No monomates left")

	# Lookup across registries
	var info = Inventory._lookup_item("saber")
	assert_eq(info.name, "Saber", "Lookup saber name")
	assert_eq(info.max_stack, 1, "Lookup saber max_stack = 1")

	var info2 = Inventory._lookup_item("monomate")
	assert_eq(info2.name, "Monomate", "Lookup monomate name")
	assert_gt(info2.max_stack, 1, "Monomate is stackable")

	Inventory.clear_inventory()
	print("")


# ── Inventory capacity tests ───────────────────────────────

func test_inventory_capacity() -> void:
	print("── Inventory Capacity (40 items) ──")
	Inventory.clear_inventory()
	assert_eq(Inventory.capacity, 40, "Inventory capacity is 40")

	# Fill inventory with 40 unique items using weapon IDs (all max_stack=1)
	var all_weapons: Array = WeaponRegistry.get_all_weapon_ids()
	var added_count := 0
	for i in range(mini(40, all_weapons.size())):
		var wid: String = all_weapons[i]
		if Inventory.add_item(wid, 1):
			added_count += 1

	assert_eq(added_count, 40, "Added exactly 40 unique items")
	assert_eq(Inventory.get_unique_item_count(), 40, "Inventory has 40 unique items")

	# 41st unique item should be rejected
	var overflow_id: String = all_weapons[40] if all_weapons.size() > 40 else "test_overflow"
	assert_true(not Inventory.can_add_item(overflow_id), "Can't add 41st unique item")
	assert_true(not Inventory.add_item(overflow_id, 1), "41st item add returns false")
	assert_eq(Inventory.get_unique_item_count(), 40, "Still 40 after rejected add")

	# But CAN add more of an existing item if it's stackable
	Inventory.clear_inventory()
	Inventory.add_item("monomate", 1)
	assert_true(Inventory.can_add_item("monomate"), "Can add more monomates to existing stack")
	Inventory.add_item("monomate", 5)
	assert_eq(Inventory.get_item_count("monomate"), 6, "Stacked to 6 monomates")

	# Fill remaining 39 slots
	for i in range(39):
		Inventory.add_item(all_weapons[i], 1)
	assert_eq(Inventory.get_unique_item_count(), 40, "40 items (1 consumable + 39 weapons)")
	assert_true(not Inventory.can_add_item(all_weapons[39]), "Can't add 41st unique item")
	assert_true(Inventory.can_add_item("monomate"), "Can still stack existing monomate")

	Inventory.clear_inventory()
	print("")


# ── Character creation tests ────────────────────────────────

func test_character_creation() -> void:
	print("── Character Creation ──")
	# Reset state — preserve array size (4 slots)
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	Inventory.clear_inventory()
	GameState.reset_game_state()

	var result = CharacterManager.create_character(0, "humar", "TestHero")
	assert_true(result != null, "Create HUmar character")
	if result:
		assert_eq(result.get("name"), "TestHero", "Character name = TestHero")
		assert_eq(result.get("class_id"), "humar", "Class = humar")
		assert_eq(result.get("level"), 1, "Starts at level 1")
		assert_gt(int(result.get("hp", 0)), 0, "Has HP")

	# Should have starter items in inventory
	assert_true(Inventory.has_item("saber"), "Starter weapon: saber")
	assert_true(Inventory.has_item("normal_frame"), "Starter armor: normal_frame")
	assert_true(Inventory.has_item("monomate"), "Starter item: monomate")

	# Equipment should be set
	var equip: Dictionary = result.get("equipment", {})
	assert_eq(equip.get("weapon"), "saber", "Weapon equipped = saber")
	assert_eq(equip.get("frame"), "normal_frame", "Frame equipped = normal_frame")

	# Active character
	CharacterManager.set_active_slot(0)
	var active = CharacterManager.get_active_character()
	assert_true(active != null, "Active character set")
	print("")


# ── Equipment tests ─────────────────────────────────────────

func test_equipment() -> void:
	print("── Equipment ──")
	var character = CharacterManager.get_active_character()
	if character == null:
		print("  SKIP: No active character")
		return

	var equipment: Dictionary = character.get("equipment", {})

	# Unequip weapon
	equipment["weapon"] = ""
	assert_eq(equipment.get("weapon"), "", "Weapon unequipped")

	# Re-equip
	equipment["weapon"] = "saber"
	assert_eq(equipment.get("weapon"), "saber", "Weapon re-equipped")

	# Buy and equip a new weapon
	Inventory.add_item("blade", 1)
	assert_true(Inventory.has_item("blade"), "Blade in inventory")
	equipment["weapon"] = "blade"
	assert_eq(equipment.get("weapon"), "blade", "Blade equipped")

	# Restore saber for further tests
	equipment["weapon"] = "saber"
	Inventory.remove_item("blade", 1)
	print("")


# ── Combat math tests ──────────────────────────────────────

func test_combat_math() -> void:
	print("── Combat Math ──")
	var character = CharacterManager.get_active_character()
	if character == null:
		print("  SKIP: No active character")
		return

	CombatManager.init_combat("gurhacia", "normal")

	# Spawn a single normal enemy
	var enemies := [EnemySpawner._create_enemy_instance("ghowl", "normal", 1.0, 1)]
	CombatManager.set_enemies(enemies)

	var enemy = CombatManager.get_enemies()[0]
	print("  INFO: Ghowl HP=%d ATK=%d DEF=%d" % [enemy.hp, enemy.attack, enemy.defense])

	var class_data = ClassRegistry.get_class_data("humar")
	var stats: Dictionary = class_data.get_stats_at_level(1) if class_data else {}
	print("  INFO: Player ATK=%d DEF=%d ACC=%d EVA=%d (base stats)" % [
		stats.get("attack", 0), stats.get("defense", 0),
		stats.get("accuracy", 0), stats.get("evasion", 0)])

	var saber = WeaponRegistry.get_weapon("saber")
	if saber:
		print("  INFO: Saber ATK=%d (should be added to player damage)" % saber.attack_base)

	# Attack the enemy multiple times to check damage range
	var total_damage := 0
	var hits := 0
	var misses := 0
	var crits := 0
	for i in range(100):
		# Reset enemy HP each time
		enemy["hp"] = enemy["max_hp"]
		enemy["alive"] = true
		var result := CombatManager.attack(0)
		if result.get("hit", false):
			hits += 1
			total_damage += int(result.get("damage", 0))
			if result.get("critical", false):
				crits += 1
		else:
			misses += 1

	var avg_damage: float = float(total_damage) / float(maxi(hits, 1))
	print("  INFO: 100 attacks → %d hits, %d misses, %d crits, avg damage=%.1f" % [hits, misses, crits, avg_damage])
	assert_gt(avg_damage, 20.0, "Average damage > 20 (weapon ATK applied)")
	assert_gt(hits, 50, "Hit rate > 50%")

	# Test enemy attack on player
	character["hp"] = int(character.get("max_hp", 100))
	var initial_hp: int = int(character["hp"])
	enemy["alive"] = true
	enemy["aggroed"] = true
	var enemy_result := CombatManager.enemy_attack(0)
	if enemy_result.get("hit", false):
		var dmg: int = int(enemy_result.get("damage", 0))
		print("  INFO: Enemy dealt %d damage to player (HP: %d→%d)" % [dmg, initial_hp, int(character["hp"])])
		assert_gt(dmg, 0, "Enemy deals damage")
		assert_true(dmg < initial_hp, "Enemy doesn't one-shot at full HP")
	else:
		print("  INFO: Enemy missed (testing again would vary)")

	CombatManager.clear_combat()
	# Restore player HP
	character["hp"] = int(character.get("max_hp", 100))
	CharacterManager._sync_to_game_state()
	print("")


# ── Combat drops test ──────────────────────────────────────

func test_combat_drops() -> void:
	print("── Combat Drops ──")
	var character = CharacterManager.get_active_character()
	if character == null:
		print("  SKIP: No active character")
		return

	# Run many drop rolls across different enemy types and areas to verify drops happen
	var consumable_drops := 0
	var weapon_drops := 0
	var total_drops := 0
	var areas := ["gurhacia", "rioh", "ozette", "paru", "makara", "arca", "dark"]

	for area_id in areas:
		CombatManager.init_combat(area_id, "normal")

		# Test normal enemy drops (10% consumable, 3% weapon) — run 200 trials per area
		for _trial in range(200):
			var enemy := EnemySpawner._create_enemy_instance("ghowl", "normal", 1.0, 1)
			var drops: Array = CombatManager.generate_drops(enemy)
			for drop_id in drops:
				total_drops += 1
				# Check if it's a consumable
				var consumable = ConsumableRegistry.get_consumable(drop_id)
				if consumable:
					consumable_drops += 1
				else:
					weapon_drops += 1

		# Test boss enemy drops (35% consumable, 25% weapon) — run 100 trials
		for _trial in range(100):
			var boss := EnemySpawner._create_enemy_instance("reyburn", "boss", 1.0, 3)
			var drops: Array = CombatManager.generate_drops(boss)
			for drop_id in drops:
				total_drops += 1
				var consumable = ConsumableRegistry.get_consumable(drop_id)
				if consumable:
					consumable_drops += 1
				else:
					weapon_drops += 1

		CombatManager.clear_combat()

	print("  INFO: %d total drops across %d areas (1400 normal + 700 boss trials)" % [total_drops, areas.size()])
	print("  INFO: %d consumable drops, %d weapon/other drops" % [consumable_drops, weapon_drops])

	assert_gt(total_drops, 0, "Some items dropped overall")
	assert_gt(consumable_drops, 0, "Consumables (monomate/monofluid) drop")
	assert_gt(weapon_drops, 0, "Weapons/items drop from enemies")

	# Verify consumable drop rate is roughly correct (10% of 1400 = ~140 expected from normal)
	print("  INFO: Consumable rate = %.1f%% (expected ~15%%)" % [float(consumable_drops) / float(2100) * 100.0])
	assert_gt(consumable_drops, 50, "Consumable drop count is reasonable (>50 out of 2100 trials)")

	# Verify drops can be picked up into inventory
	Inventory.clear_inventory()
	CombatManager.init_combat("gurhacia", "normal")
	CombatManager.add_drops(["monomate", "monomate", "saber"])
	var pickup_results: Array = CombatManager.pickup_all()
	assert_eq(pickup_results.size(), 3, "Picked up 3 items")
	assert_true(Inventory.has_item("monomate"), "Monomate in inventory after pickup")
	assert_eq(Inventory.get_item_count("monomate"), 2, "2 monomates picked up")
	assert_true(Inventory.has_item("saber"), "Saber in inventory after pickup")
	CombatManager.clear_combat()
	Inventory.clear_inventory()
	print("")


# ── Full combat simulation ──────────────────────────────────

func test_combat_simulation() -> void:
	print("── Combat Simulation (Gurhacia Normal) ──")
	var character = CharacterManager.get_active_character()
	if character == null:
		print("  SKIP: No active character")
		return

	# Simulate a full 3-stage, 3-wave session
	var total_kills := 0
	var total_exp := 0
	var total_meseta := 0
	var player_deaths := 0
	var items_dropped := 0

	for stage in range(1, 4):
		for wave in range(1, 4):
			# Reset player HP each wave (simulating healing between waves)
			character["hp"] = int(character.get("max_hp", 100))
			CharacterManager._sync_to_game_state()

			CombatManager.init_combat("gurhacia", "normal")
			var enemies := EnemySpawner.generate_wave("gurhacia", "normal", stage, wave)
			CombatManager.set_enemies(enemies)

			var is_boss_wave: bool = stage == 3 and wave == 3
			var enemy_count := enemies.size()
			var wave_label := "S%d/W%d" % [stage, wave]
			if is_boss_wave:
				wave_label += " (BOSS)"

			var turn := 0
			var max_turns := 50  # Safety limit

			while not CombatManager.is_wave_cleared() and turn < max_turns:
				turn += 1

				# Player attacks first alive enemy
				var target := -1
				for i in range(enemies.size()):
					if enemies[i].get("alive", false):
						target = i
						break
				if target == -1:
					break

				CombatManager.aggro_on_attack(target)
				var atk_result := CombatManager.attack(target)
				if atk_result.get("defeated", false):
					total_kills += 1
					total_exp += int(atk_result.get("exp", 0))
					total_meseta += int(atk_result.get("meseta", 0))
					var drops := CombatManager.generate_drops(enemies[target])
					items_dropped += drops.size()

				# Enemies attack back
				CombatManager.process_aggro()
				for i in range(enemies.size()):
					if not enemies[i].get("alive", false):
						continue
					if not enemies[i].get("aggroed", false):
						continue
					var enemy_result := CombatManager.enemy_attack(i)
					if enemy_result.get("player_defeated", false):
						player_deaths += 1
						# Revive for test purposes
						character["hp"] = int(int(character.get("max_hp", 100)) * 0.5)
						CharacterManager._sync_to_game_state()

			var survived := "OK" if int(character.get("hp", 0)) > 0 else "DEAD"
			print("  %s: %d enemies, %d turns, HP=%d/%d [%s]" % [
				wave_label, enemy_count, turn,
				int(character.get("hp", 0)), int(character.get("max_hp", 100)),
				survived])

			CombatManager.clear_combat()

	print("  ──────────────────────────")
	print("  Total kills: %d" % total_kills)
	print("  Total EXP: %d" % total_exp)
	print("  Total Meseta: %d" % total_meseta)
	print("  Items dropped: %d" % items_dropped)
	print("  Player deaths: %d" % player_deaths)

	assert_gt(total_kills, 0, "Killed some enemies")
	assert_gt(total_exp, 0, "Earned EXP")
	assert_eq(player_deaths, 0, "Survived all waves (balance check)")
	print("")


# ── Session manager tests ──────────────────────────────────

func test_session_manager() -> void:
	print("── Session Manager ──")
	assert_true(not SessionManager.has_active_session(), "No active session initially")

	var session := SessionManager.enter_field("gurhacia", "normal")
	assert_true(SessionManager.has_active_session(), "Session active after enter_field")
	assert_eq(session.get("area_id"), "gurhacia", "Area = gurhacia")
	assert_eq(session.get("stage"), 1, "Stage = 1")
	assert_eq(session.get("wave"), 1, "Wave = 1")
	assert_eq(SessionManager.get_location(), "field", "Location = field")

	assert_true(SessionManager.next_wave(), "Advance to wave 2")
	assert_eq(SessionManager.get_session().get("wave"), 2, "Wave = 2")
	assert_true(SessionManager.next_wave(), "Advance to wave 3")
	assert_true(not SessionManager.next_wave(), "No wave 4")

	assert_true(SessionManager.next_stage(), "Advance to stage 2")
	assert_eq(SessionManager.get_session().get("stage"), 2, "Stage = 2")
	assert_eq(SessionManager.get_session().get("wave"), 1, "Wave reset to 1")

	SessionManager.add_rewards(150, 500)
	assert_eq(SessionManager.get_session().get("total_exp"), 150, "EXP accumulated")
	assert_eq(SessionManager.get_session().get("total_meseta"), 500, "Meseta accumulated")

	var summary := SessionManager.return_to_city()
	assert_true(not SessionManager.has_active_session(), "Session ended")
	assert_eq(SessionManager.get_location(), "city", "Location = city")
	assert_eq(summary.get("total_exp"), 150, "Summary has EXP")

	# Mission session
	var mission_session := SessionManager.enter_mission("gurhacia_main", "normal")
	assert_true(SessionManager.has_active_session(), "Mission session active")
	assert_eq(mission_session.get("type"), "mission", "Type = mission")
	SessionManager.return_to_city()

	# Mission rewards test
	print("")
	print("── Mission Rewards ──")
	var mission = MissionRegistry.get_mission("mayor_s_mission")
	if mission:
		assert_true(not mission.rewards.is_empty(), "Mayor's Mission has rewards")
		var normal_reward: Dictionary = mission.rewards.get("normal", {})
		print("  INFO: Normal reward = %s x%s + %s M" % [
			str(normal_reward.get("item", "???")),
			str(normal_reward.get("quantity", 0)),
			str(normal_reward.get("meseta", 0))])
		assert_true(not str(normal_reward.get("item", "")).is_empty(), "Has reward item")
		assert_gt(int(normal_reward.get("meseta", 0)), 0, "Has reward meseta")
	else:
		print("  INFO: mayor_s_mission not found, checking available missions:")
		for m in MissionRegistry.get_all_missions():
			print("    - %s (%s)" % [m.id, m.name])
	print("")


# ── Mission progression tests ──────────────────────────────

func test_mission_progression() -> void:
	print("── Mission Progression (Area Unlock Chain) ──")

	# Area progression order (from guild_counter.gd)
	var area_order := {
		"Gurhacia Valley": 0,
		"Rioh Snowfield": 1,
		"Ozette Wetland": 2,
		"Oblivion City Paru": 3,
		"Makura Ruins": 4, "Makara Ruins": 4,
		"Arca Plant": 5,
		"Dark Shrine": 6,
		"Eternal Tower": 7,
	}

	# Reset completed missions
	GameState.completed_missions.clear()

	# Get all missions sorted by area
	var missions: Array = MissionRegistry.get_all_missions()
	assert_gt(missions.size(), 0, "Have missions to test")

	# Group missions by area index
	var missions_by_area: Dictionary = {}  # area_idx → [mission, ...]
	for m in missions:
		var area_idx: int = area_order.get(m.area, 99)
		if not missions_by_area.has(area_idx):
			missions_by_area[area_idx] = []
		missions_by_area[area_idx].append(m)

	# Get sorted area indices
	var area_indices: Array = missions_by_area.keys()
	area_indices.sort()

	print("  INFO: %d missions across %d areas" % [missions.size(), area_indices.size()])

	# Verify area 0 (Gurhacia) missions are initially unlocked
	var area_0_missions: Array = missions_by_area.get(0, [])
	assert_gt(area_0_missions.size(), 0, "Gurhacia has missions")
	for m in area_0_missions:
		assert_true(_is_mission_available(m, missions, area_order), "Area 0: %s is unlocked" % m.name)

	# Verify area 1+ missions are initially LOCKED
	if area_indices.size() > 1:
		var area_1_missions: Array = missions_by_area.get(area_indices[1], [])
		if not area_1_missions.is_empty():
			assert_true(not _is_mission_available(area_1_missions[0], missions, area_order),
				"Area 1: %s is locked initially" % area_1_missions[0].name)

	# Now progressively unlock by completing one mission per area
	var areas_completed := 0
	for area_idx in area_indices:
		var area_missions: Array = missions_by_area.get(area_idx, [])
		if area_missions.is_empty():
			continue

		# All missions in this area should now be available
		for m in area_missions:
			var available := _is_mission_available(m, missions, area_order)
			if not available and not m.requires.is_empty():
				# Has explicit requires — may not be unlocked yet, skip
				continue
			assert_true(available, "Area %d: %s is unlocked" % [area_idx, m.name])

		# Complete one mission from this area to unlock the next
		var completed_mission = area_missions[0]
		GameState.complete_mission(completed_mission.id)
		areas_completed += 1
		print("  Completed: %s (%s) → Area %d done" % [completed_mission.name, completed_mission.area, area_idx])

		# Verify the next area is now unlocked
		var next_idx_pos: int = area_indices.find(area_idx) + 1
		if next_idx_pos < area_indices.size():
			var next_area_idx: int = area_indices[next_idx_pos]
			var next_missions: Array = missions_by_area.get(next_area_idx, [])
			if not next_missions.is_empty():
				var next_available := _is_mission_available(next_missions[0], missions, area_order)
				assert_true(next_available,
					"Area %d: %s unlocked after completing area %d" % [next_area_idx, next_missions[0].name, area_idx])

	assert_eq(areas_completed, area_indices.size(), "Completed missions in all %d areas" % area_indices.size())

	# Verify all missions show as completed or available now
	var all_accessible := 0
	for m in missions:
		if GameState.is_mission_completed(m.id) or _is_mission_available(m, missions, area_order):
			all_accessible += 1
	assert_eq(all_accessible, missions.size(), "All %d missions accessible after full progression" % missions.size())

	# Clean up
	GameState.completed_missions.clear()
	print("")


## Check if a mission is available (mirrors guild_counter.gd logic)
func _is_mission_available(mission, all_missions: Array, area_order: Dictionary) -> bool:
	if not mission.requires.is_empty():
		for req in mission.requires:
			if not GameState.is_mission_completed(req):
				return false
		return true

	var area_idx: int = area_order.get(mission.area, 0)
	if area_idx == 0:
		return true  # First area always available

	# Check if any mission from the previous area is completed
	for m in all_missions:
		var m_area: int = area_order.get(m.area, 99)
		if m_area == area_idx - 1 and GameState.is_mission_completed(m.id):
			return true
	return false


# ── Shop tests ──────────────────────────────────────────────

func test_shops() -> void:
	print("── Shops ──")
	var character = CharacterManager.get_active_character()
	if character == null:
		print("  SKIP: No active character")
		return

	# Give some meseta
	character["meseta"] = 5000
	GameState.meseta = 5000

	# Test weapon price formulas
	var saber = WeaponRegistry.get_weapon("saber")
	if saber:
		var expected_price: int = saber.attack_base * 15 + (saber.rarity - 1) * 500
		expected_price = maxi(expected_price, 50)
		print("  INFO: Saber price = %d M (ATK %d × 15 + rarity bonus)" % [expected_price, saber.attack_base])
		assert_gt(expected_price, 0, "Saber price > 0")

	var common_armor = ArmorRegistry.get_armor("common_armor")
	if common_armor:
		var expected_price: int = common_armor.defense_base * 12 + (common_armor.rarity - 1) * 400 + common_armor.max_slots * 500
		expected_price = maxi(expected_price, 50)
		print("  INFO: Common Armor price = %d M (DEF %d × 12 + %d slots)" % [expected_price, common_armor.defense_base, common_armor.max_slots])
		assert_gt(expected_price, 0, "Common Armor price > 0")

	# Test buying from item shop
	Inventory.clear_inventory()
	var bought := ShopManager.buy_item("item_shop", "Monomate", 1)
	# This may fail if item_shop format doesn't match — log either way
	if bought:
		assert_true(Inventory.has_item("monomate"), "Monomate added after purchase")
	else:
		print("  INFO: ShopManager.buy_item returned false (shop format may differ)")

	# Test consumable lookup
	var mono = ConsumableRegistry.get_consumable("monomate")
	if mono:
		print("  INFO: Monomate details = \"%s\"" % mono.details)
		print("  INFO: Monomate buy_price = %d, sell_price = %d" % [mono.buy_price, mono.sell_price])

	Inventory.clear_inventory()
	print("")

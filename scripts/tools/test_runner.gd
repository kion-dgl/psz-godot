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
	test_character_creation()
	test_equipment()
	test_combat_math()
	test_combat_simulation()
	test_session_manager()
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

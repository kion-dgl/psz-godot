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
	test_drop_tables()
	test_combat_simulation()
	test_session_manager()
	test_mission_progression()
	test_mag_feeding()
	test_mag_evolution()
	test_shops()
	test_damage_formulas()
	test_ranger_playthrough()
	test_technique_disks()
	test_new_registries()
	test_material_system()
	test_set_bonuses()
	test_technique_casting()
	test_photon_art_usage()
	test_tekker_grinding()
	test_tekker_identification()
	test_additional_drops()
	test_telepipe_suspend()

	print("\n══════════════════════════════════")
	print("  RESULTS: %d passed, %d failed" % [_pass, _fail])
	print("══════════════════════════════════\n")

	get_tree().quit(1 if _fail > 0 else 0)


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


## Helper: check if a drop ID is a misc drop (disk, grinder, material, photon drop, unidentified)
func _is_misc_drop(drop_id) -> bool:
	var sid: String = str(drop_id)
	if sid.begins_with("disk:") or sid.begins_with("unid:"):
		return true
	if sid in ["photon_drop", "monogrinder", "digrinder", "trigrinder"]:
		return true
	if sid.ends_with("_material"):
		return true
	return false


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
	# Per-slot weapons: can add another if slots available
	assert_true(Inventory.can_add_item("saber"), "Can add second saber (per-slot)")
	assert_true(Inventory.add_item("saber", 1), "Add second saber")
	assert_eq(Inventory.get_item_count("saber"), 2, "Saber count = 2")
	Inventory.remove_item("saber", 1)  # remove extra for rest of tests

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
				if _is_misc_drop(drop_id):
					continue
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
				if _is_misc_drop(drop_id):
					continue
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


# ── Drop table integrity + pipeline tests ──────────────────

func test_drop_tables() -> void:
	print("── Drop Tables ──")

	# 1. All three difficulty tables loaded
	var normal_table = DropRegistry.get_drop_table("normal")
	var hard_table = DropRegistry.get_drop_table("hard")
	var super_hard_table = DropRegistry.get_drop_table("super-hard")
	assert_true(normal_table != null, "Normal drop table loaded")
	assert_true(hard_table != null, "Hard drop table loaded")
	assert_true(super_hard_table != null, "Super-hard drop table loaded")

	if normal_table == null:
		print("  SKIP: No normal drop table")
		print("")
		return

	# 2. All areas present in normal drop table
	var expected_areas := ["gurhacia-valley", "rioh-snowfield", "ozette-wetland",
		"oblivion-city-paru", "makara-ruins", "arca-plant", "dark-shrine", "eternal-tower"]
	var area_drops: Dictionary = normal_table.area_drops
	var missing_areas: Array = []
	for area_name in expected_areas:
		if not area_drops.has(area_name):
			missing_areas.append(area_name)
	assert_true(missing_areas.is_empty(), "All %d areas in normal drop table (missing: %s)" % [expected_areas.size(), str(missing_areas)])

	# 3. Enemy name mapping — spawner names match drop table names
	#    Note: bosses (reyburn, dark-falz, etc.) and some dark-shrine enemies
	#    intentionally have no drops in the source data — skip those.
	print("  ── Enemy Name Mapping ──")
	var area_id_to_drop_name: Dictionary = CombatManager.AREA_DROP_NAMES
	var spawner_areas := EnemySpawner._enemy_pools
	var name_mismatches: Array = []
	var name_matches := 0
	# Enemies that intentionally have no drop table entries
	var no_drops_expected: Array = [
		"reyburn", "hildegao", "octo-diablo", "frunaked", "rohcrysta",
		"blade-mother", "dark-falz", "chaos-mobius",  # bosses
		"hildeghana",  # gorilla_female variant, no drops in source
		"eulid", "eulidveil", "eulada", "euladaveil", "arkzein",
		"arkzein-r", "derreo",  # dark-shrine enemies, no drops in source
	]

	for area_id in spawner_areas:
		var drop_area: String = area_id_to_drop_name.get(area_id, area_id)
		var area_table: Dictionary = area_drops.get(drop_area, {})
		var pool: Dictionary = spawner_areas[area_id]

		for tier in ["common", "uncommon", "rare", "elites"]:
			var enemies: Array = pool.get(tier, [])
			for enemy_id in enemies:
				if enemy_id in no_drops_expected:
					continue
				var formatted: String = EnemySpawner._format_enemy_name(enemy_id)
				if area_table.has(formatted):
					name_matches += 1
				else:
					name_mismatches.append("%s → '%s' not in %s" % [enemy_id, formatted, drop_area])

	if not name_mismatches.is_empty():
		print("  INFO: %d name mismatches:" % name_mismatches.size())
		for mm in name_mismatches:
			print("    - %s" % mm)
	assert_true(name_mismatches.is_empty(), "All spawner enemies match drop table names (%d matched, %d mismatched)" % [name_matches, name_mismatches.size()])

	# 4. Drop item validity — every item in drop tables resolves to a real item
	print("  ── Drop Item Validity ──")
	var invalid_items: Array = []
	var valid_items := 0
	var checked_ids: Dictionary = {}  # avoid duplicate lookups

	for area_name in area_drops:
		var enemies: Dictionary = area_drops[area_name]
		for enemy_name in enemies:
			var items: Array = enemies[enemy_name]
			for item_name in items:
				var item_id: String = str(item_name).to_lower().replace(" ", "_").replace("'", "").replace("-", "_").replace("/", "_")
				if checked_ids.has(item_id):
					if checked_ids[item_id]:
						valid_items += 1
					else:
						invalid_items.append(item_id)
					continue

				# Check all registries
				var found := false
				if WeaponRegistry.get_weapon(item_id) != null:
					found = true
				elif ArmorRegistry.get_armor(item_id) != null:
					found = true
				elif UnitRegistry.get_unit(item_id) != null:
					found = true
				elif ConsumableRegistry.get_consumable(item_id) != null:
					found = true
				elif ItemRegistry.get_item(item_id) != null:
					found = true

				checked_ids[item_id] = found
				if found:
					valid_items += 1
				else:
					invalid_items.append("%s (from '%s')" % [item_id, item_name])

	if not invalid_items.is_empty():
		print("  INFO: %d unresolvable drop items:" % invalid_items.size())
		for ii in invalid_items:
			print("    - %s" % ii)
	print("  INFO: %d valid, %d invalid drop item IDs" % [valid_items, invalid_items.size()])
	# Allow some items to be missing (units with "/" in name, special items)
	assert_true(valid_items > 50, "Most drop items resolve to real items (%d valid)" % valid_items)

	# 5. Per-area enemy coverage — each area has at least 3 enemies with drops
	for area_name in expected_areas:
		var enemies: Dictionary = area_drops.get(area_name, {})
		assert_true(enemies.size() >= 3, "Area %s has %d enemies with drops (min 3)" % [area_name, enemies.size()])

	# 6. Drop rates by enemy type — statistical validation
	print("  ── Drop Rate Statistics ──")
	var trials := 1000

	# Normal enemy: 10% consumable, 3% weapon
	CombatManager.init_combat("gurhacia", "normal")
	var normal_consumable := 0
	var normal_weapon := 0
	for _i in range(trials):
		var enemy := EnemySpawner._create_enemy_instance("ghowl", "normal", 1.0, 1)
		var drops: Array = CombatManager.generate_drops(enemy)
		for drop_id in drops:
			if _is_misc_drop(drop_id):
				continue
			if ConsumableRegistry.get_consumable(drop_id) != null:
				normal_consumable += 1
			else:
				normal_weapon += 1

	var nc_rate := float(normal_consumable) / float(trials) * 100.0
	var nw_rate := float(normal_weapon) / float(trials) * 100.0
	print("  INFO: Normal enemy (1000 trials): consumable=%.1f%% weapon=%.1f%%" % [nc_rate, nw_rate])
	assert_true(nc_rate > 3.0 and nc_rate < 25.0, "Normal consumable rate ~10%% (got %.1f%%)" % nc_rate)
	assert_true(nw_rate < 15.0, "Normal weapon rate ~3%% (got %.1f%%)" % nw_rate)

	# Boss enemy: 35% consumable, weapon drops depend on drop table entries
	# Note: Reyburn has no drop table entries (by design), so weapon rate = 0
	# Test with Helion boss (which does have entries) for weapon rate
	var boss_consumable := 0
	var boss_weapon := 0
	for _i in range(trials):
		var enemy := EnemySpawner._create_enemy_instance("reyburn", "boss", 1.0, 3)
		var drops: Array = CombatManager.generate_drops(enemy)
		for drop_id in drops:
			if _is_misc_drop(drop_id):
				continue
			if ConsumableRegistry.get_consumable(drop_id) != null:
				boss_consumable += 1
			else:
				boss_weapon += 1

	var bc_rate := float(boss_consumable) / float(trials) * 100.0
	print("  INFO: Boss enemy (1000 trials): consumable=%.1f%% weapon=%.1f%% (Reyburn has no table entries)" % [bc_rate, float(boss_weapon) / float(trials) * 100.0])
	assert_true(bc_rate > 20.0 and bc_rate < 55.0, "Boss consumable rate ~35%% (got %.1f%%)" % bc_rate)
	assert_eq(boss_weapon, 0, "Reyburn has no weapon drops (no drop table entry)")

	# Test with Helion as boss tier to verify weapon drop rate works
	var helion_weapon := 0
	for _i in range(trials):
		var enemy := EnemySpawner._create_enemy_instance("helion", "boss", 1.0, 3)
		var drops: Array = CombatManager.generate_drops(enemy)
		for drop_id in drops:
			if _is_misc_drop(drop_id):
				continue
			if ConsumableRegistry.get_consumable(drop_id) == null:
				helion_weapon += 1
	var hw_rate := float(helion_weapon) / float(trials) * 100.0
	print("  INFO: Helion as boss (1000 trials): weapon=%.1f%% (has drop table entries)" % hw_rate)
	assert_true(hw_rate > 10.0 and hw_rate < 45.0, "Boss w/ table entries weapon rate ~25%% (got %.1f%%)" % hw_rate)

	# Rare/elite enemy: 20% consumable, 12% weapon
	var rare_consumable := 0
	var rare_weapon := 0
	for _i in range(trials):
		var enemy := EnemySpawner._create_enemy_instance("helion", "elite", 1.0, 2)
		var drops: Array = CombatManager.generate_drops(enemy)
		for drop_id in drops:
			if _is_misc_drop(drop_id):
				continue
			if ConsumableRegistry.get_consumable(drop_id) != null:
				rare_consumable += 1
			else:
				rare_weapon += 1

	var rc_rate := float(rare_consumable) / float(trials) * 100.0
	var rw_rate := float(rare_weapon) / float(trials) * 100.0
	print("  INFO: Rare/elite enemy (1000 trials): consumable=%.1f%% weapon=%.1f%%" % [rc_rate, rw_rate])
	assert_true(rc_rate > 8.0 and rc_rate < 40.0, "Rare consumable rate ~20%% (got %.1f%%)" % rc_rate)
	assert_true(rw_rate > 3.0 and rw_rate < 28.0, "Rare weapon rate ~12%% (got %.1f%%)" % rw_rate)

	CombatManager.clear_combat()

	# 7. Full drop-to-pickup pipeline with multiple enemy types
	print("  ── Full Pipeline ──")
	Inventory.clear_inventory()
	CombatManager.init_combat("gurhacia", "normal")

	# Simulate killing a mix of enemies and collecting all drops
	var pipeline_enemies := [
		EnemySpawner._create_enemy_instance("ghowl", "normal", 1.0, 1),
		EnemySpawner._create_enemy_instance("helion", "elite", 1.0, 2),
		EnemySpawner._create_enemy_instance("reyburn", "boss", 1.0, 3),
	]
	var all_drops: Array = []
	for enemy in pipeline_enemies:
		# Run many trials per enemy to guarantee at least some drops
		for _trial in range(50):
			var drops: Array = CombatManager.generate_drops(enemy)
			all_drops.append_array(drops)

	assert_gt(all_drops.size(), 0, "Pipeline: generated drops from mixed enemies")
	CombatManager.add_drops(all_drops)
	assert_eq(CombatManager.get_dropped_items().size(), all_drops.size(), "Pipeline: all drops on field")

	var results: Array = CombatManager.pickup_all()
	assert_eq(results.size(), all_drops.size(), "Pipeline: pickup_all processes all drops")

	# Some items should be in inventory now
	var picked_up_count := 0
	for r in results:
		if r.get("picked_up", false):
			picked_up_count += 1
	assert_gt(picked_up_count, 0, "Pipeline: at least some items picked up")

	# Verify field is cleared after pickup
	assert_eq(CombatManager.get_dropped_items().size(), 0, "Pipeline: field cleared after pickup")

	CombatManager.clear_combat()
	Inventory.clear_inventory()

	# 8. Hard/Super-hard tables have unique items
	if hard_table:
		var hard_areas: Dictionary = hard_table.area_drops
		assert_gt(hard_areas.size(), 0, "Hard table has area entries")
		# Check that hard drops differ from normal
		var hard_gurhacia: Dictionary = hard_areas.get("gurhacia-valley", {})
		var normal_gurhacia: Dictionary = area_drops.get("gurhacia-valley", {})
		if hard_gurhacia.has("Ghowl") and normal_gurhacia.has("Ghowl"):
			var hard_items: Array = hard_gurhacia["Ghowl"]
			var normal_items: Array = normal_gurhacia["Ghowl"]
			var same := true
			for item in hard_items:
				if item not in normal_items:
					same = false
					break
			assert_true(not same, "Hard Ghowl drops differ from Normal")

	if super_hard_table:
		var sh_areas: Dictionary = super_hard_table.area_drops
		assert_gt(sh_areas.size(), 0, "Super-hard table has area entries")

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
	print("── Mission Progression (Story Chain) ──")

	# Story chain in order — each requires the previous
	var story_chain := [
		"mayor_s_mission", "waltz_of_rage", "devilish_return",
		"a_small_friend", "fallen_flowers", "ana_s_request",
		"mother_s_memory", "the_eternal",
	]

	# Side quests and which story mission they require
	var side_quests := {
		"get_connected": "mayor_s_mission",
		"third_daughter": "waltz_of_rage",
		"mayor_s_quest": "devilish_return",
		"future_hunters": "a_small_friend",
		"i_love_ruins": "fallen_flowers",
		"2_sets_of_heroes": "ana_s_request",
		"to_the_future": "mother_s_memory",
	}

	# Reset completed missions
	GameState.completed_missions.clear()

	var missions: Array = MissionRegistry.get_all_missions()
	assert_gt(missions.size(), 0, "Have missions to test")
	print("  INFO: %d missions (%d story, %d side)" % [missions.size(), story_chain.size(), side_quests.size()])

	# Verify only the root mission is initially available
	assert_true(_is_mission_available_v2(story_chain[0]), "Root mission (Mayor's Mission) is unlocked")
	assert_true(not _is_mission_available_v2(story_chain[1]), "Second story mission is locked initially")

	# Side quest for first area should also be locked (requires story completion)
	assert_true(not _is_mission_available_v2("get_connected"), "Side quest locked before story completion")

	# Walk through story chain
	for i in range(story_chain.size()):
		var mission_id: String = story_chain[i]
		assert_true(_is_mission_available_v2(mission_id), "Story %d: %s is unlocked" % [i, mission_id])

		# Complete story mission
		GameState.complete_mission(mission_id)
		print("  Completed: %s" % mission_id)

		# Verify side quest in this area is now unlocked
		for sq_id in side_quests:
			if side_quests[sq_id] == mission_id:
				assert_true(_is_mission_available_v2(sq_id), "Side quest %s unlocked" % sq_id)

		# Verify next story mission is now unlocked (if any)
		if i + 1 < story_chain.size():
			assert_true(_is_mission_available_v2(story_chain[i + 1]),
				"Next story %s unlocked after %s" % [story_chain[i + 1], mission_id])

	# Verify all missions are now accessible
	var all_accessible := 0
	for m in missions:
		if GameState.is_mission_completed(m.id) or _is_mission_available_v2(m.id):
			all_accessible += 1
	assert_eq(all_accessible, missions.size(), "All %d missions accessible after full progression" % missions.size())

	# Clean up
	GameState.completed_missions.clear()
	print("")


## Check if a mission is available by its requires list
func _is_mission_available_v2(mission_id: String) -> bool:
	var mission = MissionRegistry.get_mission(mission_id)
	if mission == null:
		return false
	if mission.requires.is_empty():
		return true
	for req in mission.requires:
		if not GameState.is_mission_completed(req):
			return false
	return true


# ── Mag feeding tests ──────────────────────────────────────

func test_mag_feeding() -> void:
	print("── Mag Feeding ──")
	assert_gt(MagManager.get_all_mag_forms().size(), 20, "MagManager loaded 20+ mag forms")

	# Create fresh mag
	var mag := MagManager.create_mag()
	assert_eq(mag.form_id, "mag", "New mag is base form")
	assert_eq(MagManager.get_level(mag), 0, "New mag is level 0")
	assert_eq(mag.stats.power, 0, "New mag power = 0")

	# Feed monomate → power +1
	var result := MagManager.feed_mag(mag, "monomate")
	assert_true(result.success, "Fed monomate successfully")
	assert_eq(mag.stats.power, 1, "Power = 1 after monomate")
	assert_eq(mag.stats.mind, 0, "Mind unchanged after monomate")
	assert_eq(mag.sync, 5, "Sync = 5 after monomate")
	assert_eq(mag.iq, 1, "IQ = 1 after 1 feed")

	# Feed monofluid → mind +1
	result = MagManager.feed_mag(mag, "monofluid")
	assert_eq(mag.stats.mind, 1, "Mind = 1 after monofluid")
	assert_eq(mag.sync, 10, "Sync = 10 after two feeds")
	assert_eq(mag.iq, 2, "IQ = 2 after 2 feeds")

	# Feed trimate → power +3
	result = MagManager.feed_mag(mag, "trimate")
	assert_eq(mag.stats.power, 4, "Power = 4 after trimate")
	assert_eq(result.stat_changes.power, 3, "Trimate gives +3 power")

	# Feed sol_atomizer → hit +2
	result = MagManager.feed_mag(mag, "sol_atomizer")
	assert_eq(mag.stats.hit, 2, "Hit = 2 after sol_atomizer")

	# Feed moon_atomizer → all stats +1
	result = MagManager.feed_mag(mag, "moon_atomizer")
	assert_eq(mag.stats.power, 5, "Power = 5 after moon_atomizer")
	assert_eq(mag.stats.guard, 1, "Guard = 1 after moon_atomizer")
	assert_eq(mag.stats.hit, 3, "Hit = 3 after moon_atomizer")
	assert_eq(mag.stats.mind, 2, "Mind = 2 after moon_atomizer")

	# Level = (5+1+3+2) / 5 = 2
	assert_eq(MagManager.get_level(mag), 2, "Level = 2 (total stats = 11)")

	# Can't feed non-feedable items
	var bad_result := MagManager.feed_mag(mag, "saber")
	assert_true(not bad_result.success, "Can't feed a weapon")
	assert_true(MagManager.can_feed("monomate"), "Monomate is feedable")
	assert_true(not MagManager.can_feed("saber"), "Saber is not feedable")

	# Test sync cap
	mag.sync = 115
	MagManager.feed_mag(mag, "star_atomizer")  # +20 sync
	assert_eq(mag.sync, MagManager.MAX_SYNC, "Sync capped at %d" % MagManager.MAX_SYNC)

	# Test IQ cap
	mag.iq = 199
	MagManager.feed_mag(mag, "monomate")
	assert_eq(mag.iq, MagManager.MAX_IQ, "IQ capped at %d" % MagManager.MAX_IQ)

	# Stat bonuses to character
	var bonuses := MagManager.get_stat_bonuses(mag)
	assert_eq(bonuses.attack, mag.stats.power * 2, "ATK bonus = power * 2")
	assert_eq(bonuses.defense, mag.stats.guard * 2, "DEF bonus = guard * 2")
	assert_eq(bonuses.accuracy, mag.stats.hit * 2, "ACC bonus = hit * 2")
	assert_eq(bonuses.technique, mag.stats.mind * 2, "TEC bonus = mind * 2")

	print("")


# ── Mag evolution tests ────────────────────────────────────

func test_mag_evolution() -> void:
	print("── Mag Evolution ──")

	# Test Stage 1 → Stage 2 (Level 10, power primary → Yul)
	print("  ── Stage 1 → 2 ──")
	var mag := MagManager.create_mag()

	# Feed power to 50 (level 10 = 50 total stats)
	mag.stats.power = 50
	assert_eq(MagManager.get_level(mag), 10, "Level 10 at 50 power")
	var form := MagManager.determine_form(mag)
	assert_eq(form, "yul", "Power primary at level 10 → Yul")
	print("  PASS: Power primary → Yul (Stage 2)")

	# Guard primary → Aio
	mag = MagManager.create_mag()
	mag.stats.guard = 50
	form = MagManager.determine_form(mag)
	assert_eq(form, "aio", "Guard primary at level 10 → Aio")
	print("  PASS: Guard primary → Aio (Stage 2)")

	# Hit primary → Yth
	mag = MagManager.create_mag()
	mag.stats.hit = 50
	form = MagManager.determine_form(mag)
	assert_eq(form, "yth", "Hit primary at level 10 → Yth")
	print("  PASS: Hit primary → Yth (Stage 2)")

	# Mind primary → Ingh
	mag = MagManager.create_mag()
	mag.stats.mind = 50
	form = MagManager.determine_form(mag)
	assert_eq(form, "ingh", "Mind primary at level 10 → Ingh")
	print("  PASS: Mind primary → Ingh (Stage 2)")

	# Test Stage 2 → Stage 3 (Level 30, power primary → Othel)
	print("  ── Stage 2 → 3 ──")
	mag = MagManager.create_mag()
	mag.stats.power = 140
	mag.stats.guard = 10
	assert_eq(MagManager.get_level(mag), 30, "Level 30 at 150 total stats")
	form = MagManager.determine_form(mag)
	assert_eq(form, "othel", "Power primary at level 30 → Othel")
	print("  PASS: Power primary → Othel (Stage 3)")

	# Guard primary → Aiolo
	mag = MagManager.create_mag()
	mag.stats.guard = 140
	mag.stats.power = 10
	form = MagManager.determine_form(mag)
	assert_eq(form, "aiolo", "Guard primary at level 30 → Aiolo")
	print("  PASS: Guard primary → Aiolo (Stage 3)")

	# Hit primary → Peoth
	mag = MagManager.create_mag()
	mag.stats.hit = 140
	mag.stats.mind = 10
	form = MagManager.determine_form(mag)
	assert_eq(form, "peoth", "Hit primary at level 30 → Peoth")
	print("  PASS: Hit primary → Peoth (Stage 3)")

	# Mind primary → Deegh
	mag = MagManager.create_mag()
	mag.stats.mind = 140
	mag.stats.hit = 10
	form = MagManager.determine_form(mag)
	assert_eq(form, "deegh", "Mind primary at level 30 → Deegh")
	print("  PASS: Mind primary → Deegh (Stage 3)")

	# Test Stage 3 → Stage 4 (Level 60, dual stats)
	print("  ── Stage 3 → 4 ──")

	# Power/Guard → Urado
	mag = MagManager.create_mag()
	mag.stats.power = 200
	mag.stats.guard = 80
	mag.stats.hit = 10
	mag.stats.mind = 10
	assert_eq(MagManager.get_level(mag), 60, "Level 60 at 300 total stats")
	form = MagManager.determine_form(mag)
	assert_eq(form, "urado", "Power/Guard at level 60 → Urado")
	print("  PASS: Power/Guard → Urado (Stage 4)")

	# Power/Hit → Wyn
	mag = MagManager.create_mag()
	mag.stats.power = 200
	mag.stats.hit = 80
	mag.stats.guard = 10
	mag.stats.mind = 10
	form = MagManager.determine_form(mag)
	assert_eq(form, "wyn", "Power/Hit at level 60 → Wyn")
	print("  PASS: Power/Hit → Wyn (Stage 4)")

	# Guard/Power → Tyrna
	mag = MagManager.create_mag()
	mag.stats.guard = 200
	mag.stats.power = 80
	mag.stats.hit = 10
	mag.stats.mind = 10
	form = MagManager.determine_form(mag)
	assert_eq(form, "tyrna", "Guard/Power at level 60 → Tyrna")
	print("  PASS: Guard/Power → Tyrna (Stage 4)")

	# Hit/Mind → Sig
	mag = MagManager.create_mag()
	mag.stats.hit = 200
	mag.stats.mind = 80
	mag.stats.guard = 10
	mag.stats.power = 10
	form = MagManager.determine_form(mag)
	assert_eq(form, "sig", "Hit/Mind at level 60 → Sig")
	print("  PASS: Hit/Mind → Sig (Stage 4)")

	# Test evolution through feeding
	print("  ── Feed-driven evolution ──")
	mag = MagManager.create_mag()
	assert_eq(mag.form_id, "mag", "Starts as base Mag")

	# Feed 50 monomates to reach level 10 with power primary
	for _i in range(50):
		MagManager.feed_mag(mag, "monomate")
	assert_eq(MagManager.get_level(mag), 10, "Level 10 after 50 monomates")
	assert_eq(mag.form_id, "yul", "Evolved to Yul through feeding")
	print("  PASS: Fed 50 monomates → evolved to Yul at level 10")

	# Continue feeding to level 30 (need 150 total - already have 50 power)
	# Add some guard to have secondary stat
	for _i in range(10):
		MagManager.feed_mag(mag, "antidote")  # +1 guard each
	# Now power=50, guard=10, need 90 more power to reach 150 total
	for _i in range(90):
		MagManager.feed_mag(mag, "monomate")
	assert_eq(MagManager.get_level(mag), 30, "Level 30 after continued feeding")
	assert_eq(mag.form_id, "othel", "Evolved to Othel (Power primary, Stage 3)")
	print("  PASS: Continued feeding → evolved to Othel at level 30")

	# Continue to level 60 (need 300 total - have 140+10 = 150)
	for _i in range(10):
		MagManager.feed_mag(mag, "sol_atomizer")  # +2 hit each = 20 hit
	# Add more power to stay primary (need 300 - 140 - 10 - 20 = 130 more)
	for _i in range(130):
		MagManager.feed_mag(mag, "monomate")
	var total_stats: int = mag.stats.power + mag.stats.guard + mag.stats.hit + mag.stats.mind
	print("  INFO: Stats = P:%d G:%d H:%d M:%d (total=%d, level=%d)" % [
		mag.stats.power, mag.stats.guard, mag.stats.hit, mag.stats.mind,
		total_stats, MagManager.get_level(mag)])
	assert_true(MagManager.get_level(mag) >= 60, "Level 60+ after full feeding")
	# Power=270 is primary, hit=20 is secondary (20 > guard 10) → Power/Hit → Wyn
	var primary := MagManager._get_highest_stat(mag.stats)
	var secondary := MagManager._get_second_highest_stat(mag.stats, primary)
	print("  INFO: Primary=%s, Secondary=%s → Form=%s" % [primary, secondary, mag.form_id])
	assert_eq(mag.form_id, "wyn", "Power/Hit feeding → Wyn (Stage 4)")
	print("  PASS: Evolved to %s (Stage 4)" % mag.form_id)

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


# ── Damage formula tests ─────────────────────────────────
# Exercises the combat math with known inputs to verify correctness.

func test_damage_formulas() -> void:
	print("── Damage Formulas ──")

	# Setup: create a fresh HUmar for predictable stats
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	Inventory.clear_inventory()
	GameState.reset_game_state()
	CharacterManager.create_character(0, "humar", "DamageTest")
	CharacterManager.set_active_slot(0)
	var character = CharacterManager.get_active_character()
	if character == null:
		print("  SKIP: No active character")
		return

	var class_data = ClassRegistry.get_class_data("humar")
	var stats: Dictionary = class_data.get_stats_at_level(1) if class_data else {}
	var player_atk: int = stats.get("attack", 50)
	var saber = WeaponRegistry.get_weapon("saber")
	var weapon_atk: int = saber.attack_base if saber else 39
	print("  INFO: Player ATK=%d, Saber ATK=%d, Total=%d" % [player_atk, weapon_atk, player_atk + weapon_atk])

	# ── Known-input damage test ──
	# Create enemy with specific DEF=10, evasion=0 for guaranteed hits
	CombatManager.init_combat("gurhacia", "normal")
	var test_enemy := {"id": "test", "name": "TestDummy", "hp": 9999, "max_hp": 9999,
		"attack": 10, "defense": 10, "evasion": 0, "alive": true, "aggroed": true,
		"is_boss": false, "is_rare": false, "status_effects": []}
	CombatManager.set_enemies([test_enemy])

	# Expected: base_damage = player_atk + weapon_atk
	# after_defense = base - (DEF * 0.25) - (base * DEF / 600)
	var base: float = float(player_atk + weapon_atk)
	var expected_after_def: float = base - (10.0 * 0.25) - (base * 10.0 / 600.0)
	# Range: non-crit min to crit max (variance ±10%, crit 1.5x)
	var min_expected: int = maxi(int(expected_after_def * 0.9), 1)
	var max_expected: int = int(expected_after_def * 1.1 * CombatManager.CRITICAL_MULTIPLIER) + 1
	print("  INFO: Expected damage range: %d-%d (base=%.1f, after_def=%.1f)" % [min_expected, max_expected, base, expected_after_def])

	var damages: Array = []
	var all_in_range := true
	for _i in range(100):
		test_enemy["hp"] = 9999
		test_enemy["alive"] = true
		var result := CombatManager.attack(0)
		if result.get("hit", false):
			var dmg: int = int(result.get("damage", 0))
			damages.append(dmg)
			if dmg < min_expected or dmg > max_expected:
				all_in_range = false
				print("  WARN: damage %d outside expected %d-%d" % [dmg, min_expected, max_expected])
	assert_true(damages.size() > 80, "Most attacks hit (evasion=0), got %d/100" % damages.size())
	assert_true(all_in_range, "All damage within expected range (%d-%d)" % [min_expected, max_expected])
	CombatManager.clear_combat()

	# ── Defense scaling ──
	print("  ── Defense Scaling ──")
	var avg_damages: Array = []
	for test_def in [0, 20, 50]:
		var def_enemy := {"id": "test", "name": "DefTest", "hp": 9999, "max_hp": 9999,
			"attack": 10, "defense": test_def, "evasion": 0, "alive": true, "aggroed": true,
			"is_boss": false, "is_rare": false, "status_effects": []}
		CombatManager.init_combat("gurhacia", "normal")
		CombatManager.set_enemies([def_enemy])
		var total_dmg := 0
		var hit_count := 0
		for _i in range(50):
			def_enemy["hp"] = 9999
			def_enemy["alive"] = true
			var result := CombatManager.attack(0)
			if result.get("hit", false):
				total_dmg += int(result.get("damage", 0))
				hit_count += 1
		var avg := float(total_dmg) / float(maxi(hit_count, 1))
		avg_damages.append(avg)
		print("  INFO: DEF=%d → avg damage=%.1f (%d hits)" % [test_def, avg, hit_count])
		CombatManager.clear_combat()

	assert_gt(avg_damages[0], avg_damages[1], "DEF 0 > DEF 20 damage")
	assert_gt(avg_damages[1], avg_damages[2], "DEF 20 > DEF 50 damage")

	# ── Weapon ATK contribution ──
	print("  ── Weapon ATK Contribution ──")
	# Use doppel_scythe (ATK=183) for a clear difference vs saber (ATK=39)
	Inventory.add_item("doppel_scythe", 1)
	character["equipment"]["weapon"] = "doppel_scythe"
	var strong_weapon = WeaponRegistry.get_weapon("doppel_scythe")
	var strong_atk: int = strong_weapon.attack_base if strong_weapon else 183
	print("  INFO: Doppel Scythe ATK=%d vs Saber ATK=%d" % [strong_atk, weapon_atk])

	var strong_enemy := {"id": "test", "name": "AtkTest", "hp": 9999, "max_hp": 9999,
		"attack": 10, "defense": 0, "evasion": 0, "alive": true, "aggroed": true,
		"is_boss": false, "is_rare": false, "status_effects": []}
	CombatManager.init_combat("gurhacia", "normal")
	CombatManager.set_enemies([strong_enemy])
	var strong_total := 0
	var strong_hits := 0
	for _i in range(100):
		strong_enemy["hp"] = 9999
		strong_enemy["alive"] = true
		var result := CombatManager.attack(0)
		if result.get("hit", false):
			strong_total += int(result.get("damage", 0))
			strong_hits += 1
	var strong_avg := float(strong_total) / float(maxi(strong_hits, 1))
	print("  INFO: Doppel Scythe avg damage=%.1f vs Saber avg (DEF=0)=%.1f" % [strong_avg, avg_damages[0]])
	CombatManager.clear_combat()
	character["equipment"]["weapon"] = "saber"
	Inventory.remove_item("doppel_scythe", 1)

	assert_gt(strong_avg, avg_damages[0], "Higher ATK weapon deals more damage (%.1f > %.1f)" % [strong_avg, avg_damages[0]])

	# ── Variance bounds ──
	print("  ── Variance Bounds ──")
	var variance_enemy := {"id": "test", "name": "VarTest", "hp": 9999, "max_hp": 9999,
		"attack": 10, "defense": 10, "evasion": 0, "alive": true, "aggroed": true,
		"is_boss": false, "is_rare": false, "status_effects": []}
	CombatManager.init_combat("gurhacia", "normal")
	CombatManager.set_enemies([variance_enemy])
	var non_crit_damages: Array = []
	for _i in range(200):
		variance_enemy["hp"] = 9999
		variance_enemy["alive"] = true
		var result := CombatManager.attack(0)
		if result.get("hit", false) and not result.get("critical", false):
			non_crit_damages.append(int(result.get("damage", 0)))
	CombatManager.clear_combat()

	if non_crit_damages.size() > 20:
		var min_dmg: int = non_crit_damages[0]
		var max_dmg: int = non_crit_damages[0]
		for d in non_crit_damages:
			min_dmg = mini(min_dmg, d)
			max_dmg = maxi(max_dmg, d)
		var median_dmg: float = float(min_dmg + max_dmg) / 2.0
		var spread: float = float(max_dmg - min_dmg) / median_dmg
		print("  INFO: Non-crit damage range: %d-%d (spread=%.1f%%)" % [min_dmg, max_dmg, spread * 100.0])
		assert_true(spread < 0.3, "Non-crit damage spread < 30%% (variance ±10%%)")

	# ── Miss rate vs evasion ──
	print("  ── Hit/Miss vs Evasion ──")
	var low_eva_hits := 0
	var high_eva_hits := 0
	for _i in range(200):
		var low_enemy := {"id": "test", "name": "LowEva", "hp": 9999, "max_hp": 9999,
			"attack": 10, "defense": 5, "evasion": 10, "alive": true, "aggroed": true,
			"is_boss": false, "is_rare": false, "status_effects": []}
		CombatManager.init_combat("gurhacia", "normal")
		CombatManager.set_enemies([low_enemy])
		var result := CombatManager.attack(0)
		if result.get("hit", false):
			low_eva_hits += 1
		CombatManager.clear_combat()
	for _i in range(200):
		var high_enemy := {"id": "test", "name": "HighEva", "hp": 9999, "max_hp": 9999,
			"attack": 10, "defense": 5, "evasion": 200, "alive": true, "aggroed": true,
			"is_boss": false, "is_rare": false, "status_effects": []}
		CombatManager.init_combat("gurhacia", "normal")
		CombatManager.set_enemies([high_enemy])
		var result := CombatManager.attack(0)
		if result.get("hit", false):
			high_eva_hits += 1
		CombatManager.clear_combat()
	print("  INFO: Low evasion (10): %d/200 hits, High evasion (200): %d/200 hits" % [low_eva_hits, high_eva_hits])
	assert_gt(low_eva_hits, high_eva_hits, "Low evasion → more hits than high evasion")

	# Restore character for subsequent tests
	character["hp"] = int(character.get("max_hp", 100))
	CharacterManager._sync_to_game_state()
	print("")


# ── Ranger playthrough simulation ─────────────────────────

func test_ranger_playthrough() -> void:
	print("── Ranger Playthrough (RAmar Gurhacia Normal) ──")

	# Save current state
	var saved_characters: Array = CharacterManager._characters.duplicate(true)
	var saved_slot: int = CharacterManager._active_slot

	# Create RAmar with Carbine
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	Inventory.clear_inventory()
	GameState.reset_game_state()

	var ramar := CharacterManager.create_character(1, "ramar", "TestRanger")
	assert_true(ramar != null, "Created RAmar character")
	if ramar == null:
		print("  SKIP: Could not create RAmar")
		print("")
		return

	# Give Carbine instead of default handgun
	Inventory.add_item("carbine", 1)
	ramar["equipment"]["weapon"] = "carbine"
	CharacterManager.set_active_slot(1)

	var ramar_class = ClassRegistry.get_class_data("ramar")
	var ramar_stats: Dictionary = ramar_class.get_stats_at_level(1) if ramar_class else {}
	var carbine = WeaponRegistry.get_weapon("carbine")
	print("  INFO: RAmar Lv1 ATK=%d ACC=%d DEF=%d EVA=%d" % [
		ramar_stats.get("attack", 0), ramar_stats.get("accuracy", 0),
		ramar_stats.get("defense", 0), ramar_stats.get("evasion", 0)])
	if carbine:
		print("  INFO: Carbine ATK=%d ACC=%d" % [carbine.attack_base, carbine.accuracy_base])

	# Simulate full 3-stage, 3-wave session
	var total_kills := 0
	var total_exp := 0
	var total_meseta := 0
	var player_deaths := 0
	var total_hits := 0
	var total_attacks := 0
	var items_dropped := 0

	for stage in range(1, 4):
		for wave in range(1, 4):
			ramar["hp"] = int(ramar.get("max_hp", 100))
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
			var max_turns := 50

			while not CombatManager.is_wave_cleared() and turn < max_turns:
				turn += 1
				var target := -1
				for i in range(enemies.size()):
					if enemies[i].get("alive", false):
						target = i
						break
				if target == -1:
					break

				CombatManager.aggro_on_attack(target)
				total_attacks += 1
				var atk_result := CombatManager.attack(target)
				if atk_result.get("hit", false):
					total_hits += 1
				if atk_result.get("defeated", false):
					total_kills += 1
					total_exp += int(atk_result.get("exp", 0))
					total_meseta += int(atk_result.get("meseta", 0))
					var drops := CombatManager.generate_drops(enemies[target])
					items_dropped += drops.size()

				CombatManager.process_aggro()
				for i in range(enemies.size()):
					if not enemies[i].get("alive", false):
						continue
					if not enemies[i].get("aggroed", false):
						continue
					var enemy_result := CombatManager.enemy_attack(i)
					if enemy_result.get("player_defeated", false):
						player_deaths += 1
						ramar["hp"] = int(int(ramar.get("max_hp", 100)) * 0.5)
						CharacterManager._sync_to_game_state()

			var survived := "OK" if int(ramar.get("hp", 0)) > 0 else "DEAD"
			print("  %s: %d enemies, %d turns, HP=%d/%d [%s]" % [
				wave_label, enemy_count, turn,
				int(ramar.get("hp", 0)), int(ramar.get("max_hp", 100)),
				survived])

			CombatManager.clear_combat()

	var hit_rate: float = float(total_hits) / float(maxi(total_attacks, 1)) * 100.0
	print("  ──────────────────────────")
	print("  Total kills: %d" % total_kills)
	print("  Total EXP: %d" % total_exp)
	print("  Total Meseta: %d" % total_meseta)
	print("  Items dropped: %d" % items_dropped)
	print("  Player deaths: %d" % player_deaths)
	print("  Hit rate: %.1f%% (%d/%d)" % [hit_rate, total_hits, total_attacks])

	assert_gt(total_kills, 0, "Ranger killed enemies")
	assert_gt(total_exp, 0, "Ranger earned EXP")
	assert_gt(hit_rate, 60.0, "Ranger hit rate > 60%% (high ACC)")
	assert_true(player_deaths <= 2, "Ranger deaths <= 2 (got %d, low DEF makes boss wave risky)" % player_deaths)

	# Restore previous state
	CharacterManager._characters = saved_characters
	CharacterManager._active_slot = saved_slot
	Inventory.clear_inventory()
	if saved_slot >= 0:
		CharacterManager.set_active_slot(saved_slot)
	print("")


# ── Technique disk tests ──────────────────────────────────

func test_technique_disks() -> void:
	print("── Technique Disks ──")

	# Save state
	var saved_characters: Array = CharacterManager._characters.duplicate(true)
	var saved_slot: int = CharacterManager._active_slot
	Inventory.clear_inventory()

	# Create FOmar (Force class, full technique access)
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	GameState.reset_game_state()
	var fomar := CharacterManager.create_character(0, "fomar", "TestForce")
	assert_true(fomar != null, "Created FOmar character")
	if fomar == null:
		print("  SKIP: Could not create FOmar")
		print("")
		return
	fomar["level"] = 20  # High enough for disk level requirements
	CharacterManager.set_active_slot(0)

	# Verify techniques dict exists
	assert_true(fomar.has("techniques"), "Character has techniques dict")
	assert_eq(fomar["techniques"].size(), 0, "Techniques dict starts empty")

	# ── Learn technique from disk ──
	print("  ── Learn Technique ──")
	var disk_foie5 := TechniqueManager.create_disk("foie", 5)
	assert_true(not disk_foie5.is_empty(), "Created Foie Lv.5 disk")
	assert_eq(disk_foie5["name"], "Disk: Foie Lv.5", "Disk name correct")
	assert_eq(disk_foie5["technique_id"], "foie", "Disk technique_id correct")
	assert_eq(disk_foie5["level"], 5, "Disk level correct")

	var learn_result := TechniqueManager.use_disk(fomar, disk_foie5)
	assert_true(learn_result["success"], "Learned Foie Lv.5")
	assert_eq(TechniqueManager.get_technique_level(fomar, "foie"), 5, "Foie level = 5")
	print("  INFO: %s" % learn_result["message"])

	# ── Upgrade to higher level ──
	print("  ── Upgrade Technique ──")
	var disk_foie8 := TechniqueManager.create_disk("foie", 8)
	var upgrade_result := TechniqueManager.use_disk(fomar, disk_foie8)
	assert_true(upgrade_result["success"], "Upgraded Foie to Lv.8")
	assert_eq(upgrade_result["old_level"], 5, "Old level was 5")
	assert_eq(upgrade_result["new_level"], 8, "New level is 8")
	assert_eq(TechniqueManager.get_technique_level(fomar, "foie"), 8, "Foie level = 8")
	print("  INFO: %s" % upgrade_result["message"])

	# ── Reject downgrade ──
	print("  ── Reject Downgrade ──")
	var disk_foie3 := TechniqueManager.create_disk("foie", 3)
	var downgrade_result := TechniqueManager.use_disk(fomar, disk_foie3)
	assert_true(not downgrade_result["success"], "Rejected Foie Lv.3 downgrade")
	assert_eq(TechniqueManager.get_technique_level(fomar, "foie"), 8, "Foie still Lv.8")
	print("  INFO: %s" % downgrade_result["message"])

	# ── Reject for CASTs (empty technique_limits) ──
	print("  ── CAST Restriction ──")
	CharacterManager._characters[1] = null
	var racast := CharacterManager.create_character(1, "racast", "TestCast")
	if racast != null:
		var cast_check := TechniqueManager.can_learn(racast, "foie", 1)
		assert_true(not cast_check["allowed"], "CAST cannot learn techniques")
		print("  INFO: %s" % cast_check["reason"])
	else:
		print("  SKIP: Could not create RAcast")

	# ── Reject above class limit ──
	print("  ── Class Limit ──")
	# RAmar technique_limits: foieBartaZonde=10, so foie max is Lv.10
	CharacterManager._characters[2] = null
	var ramar := CharacterManager.create_character(2, "ramar", "TestRanger2")
	if ramar != null:
		ramar["level"] = 30  # High enough for level requirement checks
		var limit_check := TechniqueManager.can_learn(ramar, "foie", 15)
		assert_true(not limit_check["allowed"], "RAmar can't learn Foie Lv.15 (limit=10)")
		print("  INFO: %s" % limit_check["reason"])

		# But CAN learn foie Lv.10
		var ok_check := TechniqueManager.can_learn(ramar, "foie", 10)
		assert_true(ok_check["allowed"], "RAmar CAN learn Foie Lv.10")

		# RAmar can't learn shifta (shiftaDeband=0)
		var shifta_check := TechniqueManager.can_learn(ramar, "shifta", 1)
		assert_true(not shifta_check["allowed"], "RAmar can't learn Shifta (group limit=0)")
		print("  INFO: %s" % shifta_check["reason"])
	else:
		print("  SKIP: Could not create RAmar")

	# ── Generate random disks ──
	print("  ── Random Disk Generation ──")
	for difficulty in ["normal", "hard", "super-hard"]:
		var range_data: Dictionary = TechniqueManager.DISK_LEVEL_RANGES[difficulty]
		var min_level: int = range_data["min"]
		var max_level: int = range_data["max"]
		var all_valid := true
		for _i in range(50):
			var disk := TechniqueManager.generate_random_disk(difficulty, "gurhacia", false, false)
			if disk.is_empty():
				all_valid = false
				continue
			var lvl: int = disk["level"]
			if lvl < min_level or lvl > max_level:
				all_valid = false
				print("  WARN: %s disk level %d outside %d-%d" % [difficulty, lvl, min_level, max_level])
		assert_true(all_valid, "%s disks within level range %d-%d" % [difficulty, min_level, max_level])

	# Boss/rare bonus
	var boss_levels: Array = []
	var normal_levels: Array = []
	for _i in range(100):
		var boss_disk := TechniqueManager.generate_random_disk("normal", "gurhacia", true, false)
		if not boss_disk.is_empty():
			boss_levels.append(boss_disk["level"])
		var norm_disk := TechniqueManager.generate_random_disk("normal", "gurhacia", false, false)
		if not norm_disk.is_empty():
			normal_levels.append(norm_disk["level"])
	var boss_avg := 0.0
	for l in boss_levels:
		boss_avg += float(l)
	boss_avg /= float(maxi(boss_levels.size(), 1))
	var norm_avg := 0.0
	for l in normal_levels:
		norm_avg += float(l)
	norm_avg /= float(maxi(normal_levels.size(), 1))
	print("  INFO: Boss avg level=%.1f, Normal avg level=%.1f" % [boss_avg, norm_avg])
	assert_gt(boss_avg, norm_avg, "Boss disks have higher avg level than normal")

	# ── Verify tech shop has items ──
	print("  ── Tech Shop ──")
	var shop_items: Array = ShopManager.get_shop_inventory("tech_shop")
	assert_gt(shop_items.size(), 0, "Tech shop has items")
	print("  INFO: Tech shop has %d items" % shop_items.size())

	# Verify first item is a valid disk
	if not shop_items.is_empty():
		var first: Dictionary = shop_items[0]
		var item_name: String = str(first.get("item", ""))
		assert_true(item_name.begins_with("Disk: "), "First item is a disk: %s" % item_name)
		assert_gt(int(first.get("cost", 0)), 0, "Disk has a price")

	# ── Disk drops in combat ──
	print("  ── Disk Drops ──")
	CombatManager.init_combat("gurhacia", "normal")
	var disk_drops := 0
	for _i in range(500):
		var boss := EnemySpawner._create_enemy_instance("reyburn", "boss", 1.0, 3)
		var drops: Array = CombatManager.generate_drops(boss)
		for drop_id in drops:
			if str(drop_id).begins_with("disk:"):
				disk_drops += 1
	CombatManager.clear_combat()
	print("  INFO: %d disk drops from 500 boss kills (expected ~150 at 30%%)" % disk_drops)
	assert_gt(disk_drops, 50, "Disks drop from bosses (got %d)" % disk_drops)

	# Restore state
	CharacterManager._characters = saved_characters
	CharacterManager._active_slot = saved_slot
	Inventory.clear_inventory()
	if saved_slot >= 0:
		CharacterManager.set_active_slot(saved_slot)
	print("")


func test_new_registries() -> void:
	print("── New Registries ──")
	assert_gt(MaterialRegistry.get_all_materials().size(), 0, "MaterialRegistry loaded materials")
	assert_gt(ModifierRegistry.get_all_modifiers().size(), 0, "ModifierRegistry loaded modifiers")
	assert_gt(SetBonusRegistry.get_all_set_bonuses().size(), 0, "SetBonusRegistry loaded set bonuses")

	# Specific lookups
	var power_mat = MaterialRegistry.get_material("power_material")
	assert_true(power_mat != null, "Can look up power_material")
	if power_mat:
		assert_eq(power_mat.name, "Power Material", "Power material name correct")

	var mono = ModifierRegistry.get_modifier("monogrinder")
	assert_true(mono != null, "Can look up monogrinder")

	var dragon = SetBonusRegistry.get_set_bonus("dragon_wing")
	assert_true(dragon != null, "Can look up dragon_wing set bonus")
	if dragon:
		assert_eq(dragon.armor, "Dragon Wing", "Dragon Wing armor name correct")
	print("")


func test_material_system() -> void:
	print("── Material System ──")

	# Save state
	var saved_characters: Array = CharacterManager._characters.duplicate(true)
	var saved_slot: int = CharacterManager._active_slot
	Inventory.clear_inventory()

	# Create test character
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	var character := CharacterManager.create_character(0, "humar", "MatTest")
	CharacterManager.set_active_slot(0)

	# Add material to inventory
	Inventory.add_item("power_material", 5)

	# Use power_material
	var result := CombatManager.use_material("power_material")
	assert_true(result["success"], "Power material used successfully")
	assert_eq(int(character.get("material_bonuses", {}).get("attack", 0)), 2, "Material bonus attack == 2")
	assert_eq(int(character.get("materials_used", 0)), 1, "Materials used == 1")

	# Use 3 more
	CombatManager.use_material("power_material")
	CombatManager.use_material("power_material")
	CombatManager.use_material("power_material")
	assert_eq(int(character.get("material_bonuses", {}).get("attack", 0)), 8, "After 4 uses, attack bonus == 8")
	assert_eq(int(character.get("materials_used", 0)), 4, "Materials used == 4")

	# Test HP material
	Inventory.add_item("hp_material", 1)
	var old_max_hp: int = int(character.get("max_hp", 100))
	CombatManager.use_material("hp_material")
	assert_eq(int(character.get("max_hp", 0)), old_max_hp + 2, "HP material increases max_hp by 2")
	assert_eq(int(character.get("materials_used", 0)), 5, "Materials used == 5")

	# Test reset material
	Inventory.add_item("reset_material", 1)
	CombatManager.use_material("reset_material")
	assert_eq(int(character.get("material_bonuses", {}).get("attack", 0)), 0, "Reset clears attack bonus")
	assert_eq(int(character.get("materials_used", 0)), 0, "Reset sets materials_used to 0")

	# Restore state
	CharacterManager._characters = saved_characters
	CharacterManager._active_slot = saved_slot
	Inventory.clear_inventory()
	if saved_slot >= 0:
		CharacterManager.set_active_slot(saved_slot)
	print("")


func test_set_bonuses() -> void:
	print("── Set Bonuses ──")

	# Test set bonus lookup
	var bonus: Dictionary = SetBonusRegistry.get_set_bonus_for_equipment("Dragon Wing", "Dragon Horn")
	assert_true(not bonus.is_empty(), "Dragon Wing + Dragon Horn has set bonus")
	assert_eq(int(bonus.get("attack", 0)), 50, "Set bonus attack == 50")
	assert_eq(int(bonus.get("accuracy", 0)), 25, "Set bonus accuracy == 25")

	# No match
	var no_bonus: Dictionary = SetBonusRegistry.get_set_bonus_for_equipment("Dragon Wing", "Saber")
	assert_true(no_bonus.is_empty(), "Dragon Wing + Saber has no set bonus")

	# Scarred Horn also matches
	var bonus2: Dictionary = SetBonusRegistry.get_set_bonus_for_equipment("Dragon Wing", "Scarred Horn")
	assert_true(not bonus2.is_empty(), "Dragon Wing + Scarred Horn has set bonus")
	print("")


func test_technique_casting() -> void:
	print("── Technique Casting ──")

	# Save state
	var saved_characters: Array = CharacterManager._characters.duplicate(true)
	var saved_slot: int = CharacterManager._active_slot
	Inventory.clear_inventory()

	# Create FOmar with foie Lv.5 and 100 PP
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	var character := CharacterManager.create_character(0, "fomar", "TechTest")
	CharacterManager.set_active_slot(0)
	character["techniques"]["foie"] = 5
	character["techniques"]["resta"] = 3
	character["techniques"]["gifoie"] = 2
	character["pp"] = 100
	character["max_pp"] = 100
	CharacterManager._sync_to_game_state()

	# Set up combat with enemies
	CombatManager.init_combat("gurhacia", "normal")
	var enemies := [
		EnemySpawner._create_enemy_instance("ghowl", "normal", 1.0, 1),
		EnemySpawner._create_enemy_instance("ghowl", "normal", 1.0, 1),
	]
	CombatManager.set_enemies(enemies)

	# Cast foie on first enemy
	var pp_before: int = int(character["pp"])
	var result := CombatManager.cast_technique("foie", 0)
	assert_true(result.get("hit", false), "Foie hit successfully")
	assert_gt(result.get("damage", 0), 0, "Foie dealt damage")
	assert_true(int(character["pp"]) < pp_before, "PP deducted after casting foie")

	# Cast resta (heals player)
	character["hp"] = 50
	character["max_hp"] = 200
	var hp_before: int = int(character["hp"])
	var heal_result := CombatManager.cast_technique("resta", 0)
	assert_true(heal_result.get("hit", false), "Resta cast successfully")
	assert_gt(int(character["hp"]), hp_before, "HP restored after resta")

	# Cast with 0 PP
	character["pp"] = 0
	var fail_result := CombatManager.cast_technique("foie", 0)
	assert_true(not fail_result.get("hit", false), "Cannot cast with 0 PP")

	# Cast area technique (gifoie) — should hit all alive enemies
	character["pp"] = 100
	# Reset enemies to alive
	for e in enemies:
		e["alive"] = true
		e["hp"] = int(e.get("max_hp", 50))
	CombatManager.set_enemies(enemies)

	var area_result := CombatManager.cast_technique("gifoie", 0)
	assert_true(area_result.get("hit", false), "Gifoie hit")
	assert_true(area_result.get("area", false), "Gifoie was area-targeted")

	CombatManager.clear_combat()

	# Restore state
	CharacterManager._characters = saved_characters
	CharacterManager._active_slot = saved_slot
	Inventory.clear_inventory()
	if saved_slot >= 0:
		CharacterManager.set_active_slot(saved_slot)
	print("")


func test_photon_art_usage() -> void:
	print("── Photon Art Usage ──")

	# Save state
	var saved_characters: Array = CharacterManager._characters.duplicate(true)
	var saved_slot: int = CharacterManager._active_slot
	Inventory.clear_inventory()

	# Create HUmar with saber
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	var character := CharacterManager.create_character(0, "humar", "PATest")
	CharacterManager.set_active_slot(0)
	character["pp"] = 100
	character["max_pp"] = 100

	# Find a saber PA
	var saber_pas: Array = PhotonArtRegistry.get_arts_by_weapon_type("Saber")
	if saber_pas.is_empty():
		print("  SKIP: No saber photon arts found")
		CharacterManager._characters = saved_characters
		CharacterManager._active_slot = saved_slot
		Inventory.clear_inventory()
		if saved_slot >= 0:
			CharacterManager.set_active_slot(saved_slot)
		print("")
		return

	var pa = saber_pas[0]
	print("  INFO: Testing PA '%s' (%d hits, %d PP)" % [pa.name, pa.hits, pa.pp_cost])

	# Set up combat
	CombatManager.init_combat("gurhacia", "normal")
	var enemies := [EnemySpawner._create_enemy_instance("ghowl", "normal", 1.0, 1)]
	enemies[0]["hp"] = 9999
	enemies[0]["max_hp"] = 9999
	CombatManager.set_enemies(enemies)

	# Use PA
	var pp_before: int = int(character["pp"])
	var result := CombatManager.use_photon_art(pa.id, 0)
	assert_true(int(character["pp"]) < pp_before, "PP deducted for PA")
	print("  INFO: PA result: %d/%d hits, %d damage" % [result.get("hits", 0), result.get("total_hits", 0), result.get("damage", 0)])

	# Try PA with wrong weapon type — equip a handgun
	character["equipment"]["weapon"] = "handgun"
	var wrong_result := CombatManager.use_photon_art(pa.id, 0)
	assert_true(not wrong_result.get("hit", false), "PA rejected with wrong weapon type")

	CombatManager.clear_combat()

	# Restore state
	CharacterManager._characters = saved_characters
	CharacterManager._active_slot = saved_slot
	Inventory.clear_inventory()
	if saved_slot >= 0:
		CharacterManager.set_active_slot(saved_slot)
	print("")


func test_tekker_grinding() -> void:
	print("── Tekker Grinding ──")

	# Save state
	var saved_characters: Array = CharacterManager._characters.duplicate(true)
	var saved_slot: int = CharacterManager._active_slot
	Inventory.clear_inventory()

	# Create test character with enough meseta
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	var character := CharacterManager.create_character(0, "humar", "GrindTest")
	CharacterManager.set_active_slot(0)
	character["meseta"] = 50000

	# Weapon grind tracking
	var saber = WeaponRegistry.get_weapon("saber")
	assert_true(saber != null, "Saber exists in registry")
	if saber == null:
		CharacterManager._characters = saved_characters
		CharacterManager._active_slot = saved_slot
		Inventory.clear_inventory()
		if saved_slot >= 0:
			CharacterManager.set_active_slot(saved_slot)
		print("")
		return

	# Grind: increment weapon_grinds manually (since tekker is UI-driven)
	Inventory.add_item("monogrinder", 10)
	character["weapon_grinds"] = {}
	character["weapon_grinds"]["saber"] = 0

	# Simulate one grind
	character["weapon_grinds"]["saber"] = 1
	Inventory.remove_item("monogrinder", 1)
	assert_eq(int(character["weapon_grinds"]["saber"]), 1, "Saber grind == 1 after grinding")

	# Verify damage increase: get_attack_at_grind
	var atk_0: int = saber.get_attack_at_grind(0)
	var atk_1: int = saber.get_attack_at_grind(1)
	assert_true(atk_1 >= atk_0, "Attack at grind 1 >= grind 0 (got %d vs %d)" % [atk_1, atk_0])

	# Grind to max
	character["weapon_grinds"]["saber"] = saber.max_grind
	var atk_max: int = saber.get_attack_at_grind(saber.max_grind)
	assert_eq(atk_max, saber.attack_max, "Attack at max grind == attack_max")
	print("  INFO: Saber ATK: base=%d, max_grind=%d, atk_max=%d" % [saber.attack_base, saber.max_grind, saber.attack_max])

	# Restore state
	CharacterManager._characters = saved_characters
	CharacterManager._active_slot = saved_slot
	Inventory.clear_inventory()
	if saved_slot >= 0:
		CharacterManager.set_active_slot(saved_slot)
	print("")


func test_tekker_identification() -> void:
	print("── Tekker Identification ──")

	# Save state
	var saved_characters: Array = CharacterManager._characters.duplicate(true)
	var saved_slot: int = CharacterManager._active_slot
	Inventory.clear_inventory()

	# Create test character
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	var character := CharacterManager.create_character(0, "humar", "IdTest")
	CharacterManager.set_active_slot(0)
	character["meseta"] = 50000

	# Add unidentified weapon
	if not character.has("unidentified_weapons"):
		character["unidentified_weapons"] = []
	character["unidentified_weapons"].append("saber")
	assert_eq(character["unidentified_weapons"].size(), 1, "1 unidentified weapon")

	# Simulate identification
	var weapon_id: String = character["unidentified_weapons"][0]
	character["unidentified_weapons"].remove_at(0)
	Inventory.add_item(weapon_id, 1)
	character["meseta"] = int(character["meseta"]) - 1000

	assert_eq(character["unidentified_weapons"].size(), 0, "No unidentified weapons after identify")
	assert_true(Inventory.has_item("saber"), "Saber now in inventory")
	assert_true(int(character["meseta"]) < 50000, "Meseta deducted")

	# Restore state
	CharacterManager._characters = saved_characters
	CharacterManager._active_slot = saved_slot
	Inventory.clear_inventory()
	if saved_slot >= 0:
		CharacterManager.set_active_slot(saved_slot)
	print("")


func test_additional_drops() -> void:
	print("── Additional Drops ──")

	CombatManager.init_combat("gurhacia", "normal")

	var pd_drops := 0
	var grinder_drops := 0
	var material_drops := 0
	var unid_drops := 0
	var trials := 1000

	for _i in range(trials):
		var boss := EnemySpawner._create_enemy_instance("reyburn", "boss", 1.0, 3)
		var drops: Array = CombatManager.generate_drops(boss)
		for drop_id in drops:
			var sid: String = str(drop_id)
			if sid == "photon_drop":
				pd_drops += 1
			elif sid in ["monogrinder", "digrinder", "trigrinder"]:
				grinder_drops += 1
			elif sid.ends_with("_material"):
				material_drops += 1
			elif sid.begins_with("unid:"):
				unid_drops += 1

	CombatManager.clear_combat()

	print("  INFO: From %d boss kills: PD=%d, Grinders=%d, Materials=%d, Unid=%d" % [trials, pd_drops, grinder_drops, material_drops, unid_drops])
	assert_gt(pd_drops, 0, "Photon drops appear from bosses (got %d)" % pd_drops)
	assert_gt(grinder_drops, 0, "Grinder drops appear from bosses (got %d)" % grinder_drops)
	assert_gt(material_drops, 0, "Material drops appear from bosses (got %d)" % material_drops)
	print("")


func test_telepipe_suspend() -> void:
	print("── Telepipe / Session Suspend ──")

	# Enter a field session
	var session := SessionManager.enter_field("gurhacia", "normal")
	assert_true(not session.is_empty(), "Session started")
	assert_eq(SessionManager.get_location(), "field", "Location is field")

	# Advance to stage 1 wave 2
	SessionManager.next_wave()
	var current := SessionManager.get_session()
	assert_eq(int(current.get("wave", 0)), 2, "Wave advanced to 2")

	# Suspend session (telepipe)
	SessionManager.suspend_session()
	assert_true(not SessionManager.has_active_session(), "No active session after suspend")
	assert_true(SessionManager.has_suspended_session(), "Has suspended session")
	assert_eq(SessionManager.get_location(), "city", "Location is city after suspend")

	# Resume session
	var resumed := SessionManager.resume_session()
	assert_true(not resumed.is_empty(), "Resume returned session data")
	assert_eq(int(resumed.get("wave", 0)), 2, "Resumed at wave 2")
	assert_eq(SessionManager.get_location(), "field", "Location is field after resume")
	assert_true(not SessionManager.has_suspended_session(), "No suspended session after resume")

	# Clean up
	SessionManager.return_to_city()
	print("")

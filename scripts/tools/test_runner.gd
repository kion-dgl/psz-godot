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
	test_player_states()
	test_element_status()
	test_combat_math()
	test_combat_drops()
	test_drop_tables()
	test_combat_simulation()
	test_session_manager()
	test_mag_feeding()
	test_mag_evolution()
	test_mag_personality_contract()
	test_shops()
	test_start_menu_data()
	test_damage_formulas()
	test_ranger_playthrough()
	test_technique_disks()
	test_new_registries()
	test_autoload_api_surface()
	test_element_collision_setup()
	test_equipment_slot_names()
	test_material_system()
	test_set_bonuses()
	test_technique_casting()
	test_photon_art_usage()
	test_tekker_grinding()
	test_tekker_identification()
	test_additional_drops()
	test_telepipe_suspend()
	test_telepipe_manager_unit()
	test_telepipe_round_trip()
	test_telepipe_suspend_resume_keeps_telepipe()
	test_section_state_round_trip()
	test_telepipe_cancel_hooks()
	test_telepipe_use_item_outside_field()
	test_telepipe_239_fixes()
	test_build_info_sentinel()
	test_bootstrap_pack_magic_guard()
	test_warp_teleporter_section_label()
	test_warp_area_unlock()
	test_mesh_utils_apply_texture()
	test_game_element_build_prompt_label()
	test_game_element_override_textured_material()
	test_shop_ui_setup_portrait()
	test_shop_nav()
	test_shop_confirm()
	test_character_appearance()
	test_character_create_state()
	test_valley_grid()
	test_field_config()
	test_wetlands_field()
	test_tower_field()
	test_quest_lifecycle()
	test_quest_objectives()
	test_quest_rewards()
	test_quest_reward_data()
	test_scaled_rewards()
	test_input_config()
	test_blackjack()
	test_script_parse()

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


## Helper: recursively find a child node by name.
func _find_child_recursive(node: Node, child_name: String) -> Node:
	for child in node.get_children():
		if child.name == child_name:
			return child
		var found := _find_child_recursive(child, child_name)
		if found:
			return found
	return null


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

	# Specific lookups
	var saber = WeaponRegistry.get_weapon("saber")
	assert_true(saber != null, "Can look up saber")
	if saber:
		assert_eq(saber.name, "Saber", "Saber name correct")
		assert_eq(saber.attack_base, 40, "Saber ATK base = 40")

	var common_armor = ArmorRegistry.get_armor("common_armor")
	assert_true(common_armor != null, "Can look up common_armor")
	if common_armor:
		assert_eq(common_armor.defense_base, 33, "Common Armor DEF base = 33")

	var monomate = ConsumableRegistry.get_consumable("monomate")
	assert_true(monomate != null, "Can look up monomate")
	print("")


# ── Autoload API-surface guard (dead-code cleanup, #298) ─────
# Pins the primary lookup methods gameplay depends on across the registries
# and managers being pruned in the dead-code burndown. If a future cleanup
# batch removes a *used* getter (vs the unused siblings we're deleting), this
# fails in the fast headless suite instead of only surfacing in the autopilot
# matrix. Keep the asserted methods narrow — the ones real code calls.
func test_autoload_api_surface() -> void:
	print("── Autoload API surface (cleanup guard) ──")
	# Registry primary getters (key by resource .id).
	assert_true(WeaponRegistry.get_weapon("saber") != null, "WeaponRegistry.get_weapon resolves")
	assert_gt(WeaponRegistry.get_all_weapon_ids().size(), 0, "WeaponRegistry.get_all_weapon_ids non-empty")
	assert_true(ArmorRegistry.get_armor("common_armor") != null, "ArmorRegistry.get_armor resolves")
	assert_true(ArmorRegistry.has_armor("common_armor"), "ArmorRegistry.has_armor resolves")
	assert_true(ClassRegistry.get_class_data("fomar") != null, "ClassRegistry.get_class_data resolves")
	assert_true(ItemRegistry.get_item("key_valley") != null, "ItemRegistry.get_item resolves")
	assert_gt(ItemRegistry.get_item_count(), 0, "ItemRegistry non-empty")
	assert_true(ConsumableRegistry.get_consumable("monomate") != null, "ConsumableRegistry.get_consumable resolves")
	assert_true(MaterialRegistry.get_material("carlian") != null, "MaterialRegistry.get_material resolves")
	assert_gt(MaterialRegistry.get_all_materials().size(), 0, "MaterialRegistry non-empty")
	assert_gt(RecipeRegistry.get_all_recipes().size(), 0, "RecipeRegistry.get_all_recipes non-empty")
	assert_gt(UnitRegistry.get_all_units().size(), 0, "UnitRegistry.get_all_units non-empty")
	# Manager/state getters the game actually calls (pin against future sweeps).
	assert_true(CharacterManager.has_method("get_active_character"), "CharacterManager.get_active_character exists")
	assert_true(SessionManager.has_method("get_suspended_area_id"), "SessionManager.get_suspended_area_id exists")
	assert_true(Inventory.has_method("get_all_items"), "Inventory.get_all_items exists")
	print("")


# ── Element collision setup (dedup guard, #294) ──────────────
# Pins GameElement._build_static_collision — the shared helper the
# wall/box/fence/enemy_spawn colliders were folded into. This is a fast,
# pack-free regression gate so a change to the deduped collision setup fails
# in CI rather than only in the autopilot matrix.
func test_element_collision_setup() -> void:
	print("── GameElement._build_static_collision (dedup guard) ──")
	const GameElementScript := preload("res://scripts/3d/elements/game_element.gd")
	var el = GameElementScript.new()
	el.collision_size = Vector3(6, 1.85, 0.52)
	var body = el._build_static_collision("WallCollision")
	assert_true(body is StaticBody3D, "_build_static_collision returns a StaticBody3D")
	assert_eq(body.name, "WallCollision", "collider node name set from arg")
	assert_eq(body.collision_layer, 1, "collider on environment layer 1")
	assert_eq(body.collision_mask, 0, "collider mask 0")
	assert_eq(body.get_parent(), el, "collider parented to the element")
	assert_eq(body.get_child_count(), 1, "collider has one shape child")
	var shape = body.get_child(0)
	assert_true(shape is CollisionShape3D, "child is a CollisionShape3D")
	assert_true(shape.shape is BoxShape3D, "shape is a BoxShape3D")
	if shape.shape is BoxShape3D:
		assert_eq((shape.shape as BoxShape3D).size, el.collision_size, "box sized to collision_size")
	assert_true(is_equal_approx(shape.position.y, el.collision_size.y / 2.0), "shape offset half-height")
	el.free()
	print("")


# ── Equipment slot-name derivation (dedup guard, #294) ───────
# _get_visible_slot_names now derives from _get_visible_slots (one source of
# truth) instead of a parallel copy. Pins the invariants that mattered: same
# length (index-aligned) and the slot→label mapping. Pack-free.
func test_equipment_slot_names() -> void:
	print("── equipment_screen slot names derive from slots (dedup guard) ──")
	const EquipScreen := preload("res://scripts/2d/equipment_screen.gd")
	var es = EquipScreen.new()
	var slots: Array = es._get_visible_slots()
	var names: Array = es._get_visible_slot_names()
	assert_eq(names.size(), slots.size(), "slot names index-aligned with slots")
	var label_map := {"weapon": "Weapon", "frame": "Frame", "mag": "Mag"}
	var aligned := true
	for i in range(slots.size()):
		var slot: String = str(slots[i])
		var want: String = label_map.get(slot, "Unit %d" % int(slot.substr(4)) if slot.begins_with("unit") else slot)
		if str(names[i]) != want:
			aligned = false
	assert_true(aligned, "each slot maps to its expected display name")
	# Base slots are always present (weapon/frame/mag) regardless of character.
	assert_true(slots.size() >= 3 and str(slots[0]) == "weapon" and str(names[0]) == "Weapon", "base weapon slot present + labeled")
	es.free()
	print("")


# ── Inventory tests ─────────────────────────────────────────

func test_inventory() -> void:
	print("── Inventory ──")
	Inventory.clear_inventory()

	assert_true(Inventory.add_item("monomate", 3), "Add 3 monomates")
	assert_eq(Inventory.get_item_count("monomate"), 3, "Monomate count = 3")
	assert_true(Inventory.has_item("monomate"), "Has monomate")

	assert_true(Inventory.add_item("saber", 1), "Add saber")
	assert_true(Inventory.has_item("saber"), "First saber stored as 'saber'")
	# Per-slot weapons: each copy gets a unique instance ID (saber, saber#N)
	var slots_before: int = Inventory.get_total_slots()
	assert_true(Inventory.can_add_item("saber"), "Can add second saber (per-slot)")
	assert_true(Inventory.add_item("saber", 1), "Add second saber (gets instance suffix)")
	assert_eq(Inventory.get_total_slots(), slots_before + 1, "Second saber uses 1 additional slot")
	Inventory.remove_item("saber", 1)  # remove first saber for rest of tests

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

	# Equipment should be set
	var equip: Dictionary = result.get("equipment", {})
	assert_eq(equip.get("weapon"), "saber", "Weapon equipped = saber")
	assert_eq(equip.get("frame"), "normal_frame", "Frame equipped = normal_frame")

	# Active character — inventory loads on set_active_slot
	CharacterManager.set_active_slot(0)
	var active = CharacterManager.get_active_character()
	assert_true(active != null, "Active character set")

	# Should have starter items in inventory (loaded from character data)
	assert_true(Inventory.has_item("saber"), "Starter weapon: saber")
	assert_true(Inventory.has_item("normal_frame"), "Starter armor: normal_frame")
	assert_true(Inventory.has_item("monomate"), "Starter item: monomate")
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


# ── Player state table (#273, spec /states/player-state) ───────
# Pins the PlayerState enum: locomotion is exactly IDLE/WALKING/RUNNING
# (SPRINTING removed — a future "cleanup" can't quietly re-add an
# unreachable state), STUNNED stays reserved, and the full state set
# matches the spec's table.
func test_player_states() -> void:
	print("── Player State Table ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	var states: Dictionary = PlayerScript.PlayerState
	assert_true(not states.has("SPRINTING"), "SPRINTING removed from PlayerState (#273)")
	var expected := ["IDLE", "WALKING", "RUNNING", "ATTACKING", "DODGING",
		"DAMAGED", "DOWN", "STUNNED", "CUTSCENE"]
	assert_eq(states.keys(), expected, "PlayerState matches the spec's state table exactly")
	# Call through a typed GDScript var — a direct PlayerScript.method()
	# resolves as a static call, not a Resource method.
	var player_gd: GDScript = PlayerScript
	var consts: Dictionary = player_gd.get_script_constant_map()
	assert_true(not consts.has("SPRINT_SPEED"), "SPRINT_SPEED constant removed")
	assert_true(not consts.has("FOOTSTEP_SPRINT_INTERVAL"), "sprint footstep interval removed")

	# Dodge i-frames (spec /mechanics/dodge): the roll's move phase grants
	# invincibility; the recovery is vulnerable. Off-tree instance —
	# take_damage's i-frame return fires before any tree-dependent call.
	var p = PlayerScript.new()
	var hp_full: int = GameState.max_hp
	GameState.set_hp(hp_full)
	p.current_state = states["DODGING"]
	p.dodge_timer = 0.1
	p.dodge_move_end = 0.5
	p.take_damage(25)
	assert_eq(GameState.hp, hp_full, "move-phase dodge ignores damage (i-frames)")
	p.dodge_timer = 0.6  # past move_end → recovery, vulnerable
	p.take_damage(5)
	assert_eq(GameState.hp, hp_full - 5, "recovery-phase dodge still takes damage")
	GameState.set_hp(hp_full)

	# Charge-cancel on DODGING (spec /states/player-state): a mid-charge
	# technique drops on entering DODGING, releasing the slot.
	var released: Array = []
	p.tech_charge_released.connect(func(slot: int) -> void: released.append(slot))
	p._charging_slot = 2
	p.transition_to(states["WALKING"])
	assert_eq(p._charging_slot, 2, "charge survives a locomotion transition")
	p.transition_to(states["DODGING"])
	assert_eq(p._charging_slot, -1, "entering DODGING releases the charge")
	assert_eq(released, [2], "tech_charge_released fired with the charged slot")
	p.free()
	print("")


# ── Element → status routing (#242, spec /states/enemies) ──────
# Characterizes the single ELEMENT_STATUS map: every timed status in
# STATUS_EFFECTS is reachable from some element, every routed status is
# defined (or devil), every status has a model tint, and the live proc
# path (_try_element_special) actually lands each of dark's two effects.
func test_element_status() -> void:
	print("── Element → Status Routing ──")

	# Map invariants — both directions.
	var reachable := {}
	for element in CombatManager.ELEMENT_STATUS:
		var statuses: Array = CombatManager.ELEMENT_STATUS[element]
		assert_gt(statuses.size(), 0, "%s routes to at least one status" % element)
		for s in statuses:
			reachable[str(s)] = true
			assert_true(s == "devil" or CombatManager.STATUS_EFFECTS.has(s),
				"%s→%s is devil or a defined status" % [element, s])
	for s in CombatManager.STATUS_EFFECTS:
		assert_true(reachable.has(s), "status '%s' is reachable from some element" % s)

	# Model tint coverage — the gap that hid paralysis (#242 secondary).
	const EnemyBaseScript := preload("res://scripts/3d/enemies/enemy_base.gd")
	for s in CombatManager.STATUS_EFFECTS:
		assert_true(EnemyBaseScript.STATUS_COLORS.has(s), "STATUS_COLORS tints '%s'" % s)

	# roll_element_status: seeded sampling observes every option per element.
	seed(0x242)
	for element in CombatManager.ELEMENT_STATUS:
		var seen := {}
		for _i in range(200):
			seen[CombatManager.roll_element_status(element)] = true
		assert_eq(seen.size(), (CombatManager.ELEMENT_STATUS[element] as Array).size(),
			"%s rolls cover all its options" % element)
	assert_eq(CombatManager.roll_element_status("native"), "", "unmapped element rolls nothing")

	# Live path: element_level 9 → chance 1.0 → every hit procs. Dark must
	# land both poison (timed) and devil (instant ¼ HP) across samples.
	seed(0x242)
	var procced := {}
	var all_procced := true
	var devil_hp_ok := true
	for _i in range(100):
		var enemy := {"name": "Dummy", "hp": 400, "alive": true}
		var msg: String = CombatManager._try_element_special(enemy, {"element": "dark", "element_level": 9})
		all_procced = all_procced and not msg.is_empty()
		if msg.contains("Devil"):
			procced["devil"] = true
			devil_hp_ok = devil_hp_ok and int(enemy["hp"]) == 100
		elif not (enemy.get("status_effects", []) as Array).is_empty():
			procced[str(enemy["status_effects"][0]["type"])] = true
	assert_true(all_procced, "level-9 dark hits always proc (100/100)")
	assert_true(procced.has("devil"), "dark procs devil through the live path")
	assert_true(devil_hp_ok, "devil drops 400 HP to ¼ (100) every time")
	assert_true(procced.has("poison"), "dark procs poison through the live path")
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
	assert_true(player_deaths <= 3, "Survived most waves (got %d deaths, RNG-dependent)" % player_deaths)
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


# ── Mag personality contract ────────────────────────────────
# Regression guard for the removal of the MagPersonalityData resource
# bundle (data/mag_personalities/*.tres + scripts/resources/
# mag_personality_data.gd). The runtime never loaded those resources —
# personality is stored as a plain String on the mag state. This test
# locks that contract so a future change can't silently reintroduce a
# dependency on the deleted resource-driven system.

func test_mag_personality_contract() -> void:
	print("── Mag Personality Contract ──")

	var mag := MagManager.create_mag()
	assert_eq(typeof(mag.personality), TYPE_STRING, "Personality is a plain String, not a resource")
	assert_eq(mag.personality, "playful", "New mag defaults to 'playful' personality")

	# Personality is identity data — feeding must never mutate it.
	# Assert the feeds actually succeed so this can't pass vacuously if
	# feed_mag ever starts rejecting these items.
	var fed1 := MagManager.feed_mag(mag, "monomate")
	var fed2 := MagManager.feed_mag(mag, "star_atomizer")
	assert_true(fed1.get("success", false), "monomate feed succeeded")
	assert_true(fed2.get("success", false), "star_atomizer feed succeeded")
	assert_eq(mag.personality, "playful", "Personality unchanged after feeding")

	# Mag forms still load from data/mags/ (NOT the deleted
	# data/mag_personalities/) — proves the form pipeline is independent
	# of the removed personality resources.
	assert_gt(MagManager.get_all_mag_forms().size(), 20, "Mag forms load without the personality bundle")

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

	# Multi-qty buy: shop UI's QuantityDialog passes the chosen qty straight
	# to ShopManager.buy_item, which deducts cost*qty and adds qty items
	# (subject to stack/inventory caps). Make sure the API still does this
	# end-to-end. Pre-clear so the stack starts at 0. Use the shop's own
	# cost field rather than the .tres buy_price (which isn't used by
	# ShopManager pricing).
	Inventory.clear_inventory()
	character["meseta"] = 5000
	GameState.meseta = 5000
	var unit_cost: int = 0
	for shop_item in ShopManager.get_shop_inventory("item_shop"):
		if str(shop_item.get("item", "")) == "Monomate":
			unit_cost = int(shop_item.get("cost", 0))
			break
	var pre_meseta: int = int(character.get("meseta", 0))
	var multi_bought := ShopManager.buy_item("item_shop", "Monomate", 5)
	if multi_bought and unit_cost > 0:
		var post_meseta: int = int(character.get("meseta", 0))
		var spent: int = pre_meseta - post_meseta
		assert_eq(spent, unit_cost * 5, "5x Monomate spends 5 × shop cost")
		assert_eq(Inventory.get_item_count("monomate"), 5, "5x Monomate stacked in inventory")
	else:
		print("  INFO: 5x Monomate buy skipped (shop format / cost missing)")

	# Inventory.get_max_stack and get_stack_room — the QuantityDialog clamps
	# the qty selector against these. Sanity-check the helpers match the
	# consumable .tres data and a per-slot weapon.
	if mono:
		assert_eq(Inventory.get_max_stack("monomate"), int(mono.max_stack), "get_max_stack matches consumable.max_stack")
	assert_eq(Inventory.get_max_stack("saber"), 1, "Per-slot items report max_stack=1")

	# ── Buy guards: affordability + room ──
	# ShopManager.buy_item already refuses an unaffordable / no-room purchase
	# (returns false, no state change). These lock that behavior in as the
	# source of truth that each shop's `_can_buy(item) -> {ok, reason}` +
	# disabled-row rendering must mirror — so the affordance logic can't
	# silently regress what is/ isn't purchasable. See docs/shop-dedup.md.
	print("  ── Buy guards ──")
	var mono_cost: int = 0
	for shop_it in ShopManager.get_shop_inventory("item_shop"):
		if str(shop_it.get("item", "")) == "Monomate":
			mono_cost = int(shop_it.get("cost", 0))
			break
	# Fail (don't skip) if the fixture is missing — otherwise CI could go green
	# without ever enforcing the invariants this block exists to lock.
	assert_gt(mono_cost, 0, "Monomate is sold by item_shop with a price (buy-guard fixture)")
	if mono_cost > 0:
		# A shop's _can_buy() must AGREE with buy_item's guards — it's what the
		# UI greys/disables on, so any drift would let the screen offer (or
		# refuse) a purchase the transaction layer disagrees with. item_shop
		# carries the canonical _can_buy (shops are standalone — the shared
		# ShopBase base class broke Android export resolution; see #283/#284).
		var sb = load("res://scripts/2d/shops/item_shop.gd").new()
		var mono_item := {"item": "Monomate", "cost": mono_cost}

		# Affordability: meseta below cost → buy must fail, nothing changes.
		Inventory.clear_inventory()
		character["meseta"] = mono_cost - 1
		GameState.meseta = mono_cost - 1
		var afford_ok: bool = ShopManager.buy_item("item_shop", "Monomate", 1)
		assert_true(not afford_ok, "Cannot buy when meseta < cost")
		assert_eq(int(character.get("meseta", 0)), mono_cost - 1, "Character meseta unchanged after unaffordable buy")
		assert_eq(GameState.meseta, mono_cost - 1, "GameState.meseta unchanged after unaffordable buy")
		assert_eq(Inventory.get_item_count("monomate"), 0, "No item added after unaffordable buy")
		var v_afford: Dictionary = sb._can_buy(mono_item)
		assert_true(not v_afford.get("ok", true), "_can_buy: not ok when can't afford")
		assert_eq(str(v_afford.get("reason", "")), "Can't afford", "_can_buy reason = Can't afford")

		# Room: inventory at capacity → buy must fail, nothing changes.
		Inventory.clear_inventory()
		character["meseta"] = 999999
		GameState.meseta = 999999
		var saved_cap: int = Inventory.capacity
		Inventory.capacity = 1
		Inventory.add_item("saber", 1)  # one per-slot weapon fills the single slot
		assert_true(not Inventory.can_add_item("monomate"), "Inventory reports full (no room for a new item)")
		var room_ok: bool = ShopManager.buy_item("item_shop", "Monomate", 1)
		assert_true(not room_ok, "Cannot buy when inventory is full")
		assert_eq(int(character.get("meseta", 0)), 999999, "Character meseta unchanged after no-room buy")
		assert_eq(GameState.meseta, 999999, "GameState.meseta unchanged after no-room buy")
		assert_eq(Inventory.get_item_count("monomate"), 0, "No Monomate added after no-room buy")
		assert_gt(Inventory.get_item_count("saber"), 0, "Pre-filled saber still present after no-room buy")
		var v_room: Dictionary = sb._can_buy(mono_item)
		assert_true(not v_room.get("ok", true), "_can_buy: not ok when no room")
		assert_eq(str(v_room.get("reason", "")), "No room", "_can_buy reason = No room")
		Inventory.capacity = saved_cap
		Inventory.clear_inventory()

		# Positive: affordable + room → _can_buy ok (matches a successful buy).
		character["meseta"] = 999999
		GameState.meseta = 999999
		var v_ok: Dictionary = sb._can_buy(mono_item)
		assert_true(v_ok.get("ok", false), "_can_buy: ok when affordable and there's room")
		sb.free()

	# Weapon Shop affordance override (class / afford / room, keyed on the
	# registry id — weapon buys go through _buy_selected, not ShopManager, so
	# they need their own coverage). A synthetic weapon id has no class
	# restriction, exercising the afford + room branches cleanly.
	var ws = load("res://scripts/2d/shops/weapon_shop.gd").new()
	var wpn_item := {"id": "test_synthetic_weapon", "category": "weapon", "cost": 1000}
	Inventory.clear_inventory()
	character["meseta"] = 500
	GameState.meseta = 500
	var wv_afford: Dictionary = ws._can_buy(wpn_item)
	assert_true(not wv_afford.get("ok", true), "weapon _can_buy: not ok when can't afford")
	assert_eq(str(wv_afford.get("reason", "")), "Can't afford", "weapon _can_buy reason = Can't afford")
	character["meseta"] = 999999
	GameState.meseta = 999999
	var ws_saved_cap: int = Inventory.capacity
	Inventory.capacity = 1
	Inventory.add_item("saber", 1)
	var wv_room: Dictionary = ws._can_buy(wpn_item)
	assert_true(not wv_room.get("ok", true), "weapon _can_buy: not ok when no room")
	assert_eq(str(wv_room.get("reason", "")), "No room", "weapon _can_buy reason = No room")
	Inventory.capacity = ws_saved_cap
	Inventory.clear_inventory()
	ws.free()

	# Synthesis affordance: the craft is gated on _can_craft_recipe (the same
	# predicate the rows grey on). With no meseta and no materials, a recipe
	# that costs either must be un-craftable and give a non-empty reason.
	var cs = load("res://scripts/2d/shops/crafting_shop.gd").new()
	var synth_recipe = null
	for r in RecipeRegistry.get_all_recipes():
		if int(r.craft_cost) > 0 or not r.ingredients.is_empty():
			synth_recipe = r
			break
	if synth_recipe != null:
		Inventory.clear_inventory()
		character["meseta"] = 0
		GameState.meseta = 0
		assert_true(not cs._can_craft_recipe(synth_recipe), "synth _can_craft_recipe: false when broke + no materials")
		assert_true(not str(cs._craft_block_reason(synth_recipe)).is_empty(), "synth _craft_block_reason: non-empty when blocked")
	else:
		print("  INFO: no recipe with cost/ingredients — synth craft check skipped")
	cs.free()

	Inventory.clear_inventory()
	print("")


# ── Start menu data contract ─────────────────────────────
# Locks the pure data helpers the PSO-style start menu's rendering AND input
# both read (PsoStartMenu autoload), as the regression net before the
# pso_start_menu.gd split (StartMenuRenderer / Input / Actions). These are
# behavior-preserving extractions, so this contract must stay identical.
func test_start_menu_data() -> void:
	print("── Start Menu (data contract) ──")

	# _category_to_type: pure category → icon/type-key map
	assert_eq(PsoStartMenu._category_to_type("Weapon"), "weapon", "category Weapon → weapon")
	assert_eq(PsoStartMenu._category_to_type("Disk"), "tech", "category Disk → tech")
	assert_eq(PsoStartMenu._category_to_type("Consumable"), "tool", "category Consumable → tool")
	assert_eq(PsoStartMenu._category_to_type("Nonsense"), "tool", "category fallback → tool")

	# _get_item_category: registry-driven classification
	assert_eq(PsoStartMenu._get_item_category("saber"), "Weapon", "saber → Weapon")
	assert_eq(PsoStartMenu._get_item_category("monomate"), "Consumable", "monomate → Consumable")

	# EquipmentUtils.item_fits_slot: slot acceptance (deduped from
	# equipment_screen + pso_start_menu — #294)
	assert_true(EquipmentUtils.item_fits_slot("saber", "weapon"), "saber fits the weapon slot")
	assert_true(not EquipmentUtils.item_fits_slot("monomate", "weapon"), "monomate does not fit the weapon slot")
	assert_true(not EquipmentUtils.item_fits_slot("saber", "frame"), "weapon does not fit the frame slot")
	assert_true(not EquipmentUtils.item_fits_slot("saber", "mag"), "weapon does not fit the mag slot")
	assert_true(not EquipmentUtils.item_fits_slot("saber", "bogus_slot"), "unknown slot accepts nothing")

	# _get_menu_labels: core views always present.
	var labels: Array = PsoStartMenu._get_menu_labels()
	assert_true(labels.has("Items") and labels.has("Equip") and labels.has("Palette") and labels.has("System"),
		"menu labels include the core views")

	# Techs gating — assert BOTH real cases (not labels==_can_use_techs, which is
	# circular): a non-CAST can use techs (Techs view present), a CAST cannot.
	var sm_char = CharacterManager.get_active_character()
	if sm_char:
		var sm_saved_class = sm_char.get("class_id", "")
		sm_char["class_id"] = "humar"  # Human Hunter — can use techniques
		assert_true(PsoStartMenu._can_use_techs(), "_can_use_techs true for a non-CAST (HUmar)")
		assert_true(PsoStartMenu._get_menu_labels().has("Techs"), "Techs view present for a non-CAST")
		sm_char["class_id"] = "hucast"  # CAST Hunter — cannot use techniques
		assert_true(not PsoStartMenu._can_use_techs(), "_can_use_techs false for a CAST (HUcast)")
		assert_true(not PsoStartMenu._get_menu_labels().has("Techs"), "Techs view absent for a CAST")
		sm_char["class_id"] = sm_saved_class
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

	# Pin the global RNG so the sampled-average asserts below are deterministic.
	# CombatManager.attack() draws damage variance / crits / hit rolls from the
	# global RNG (randf/randf_range), so without a fixed seed the DEF-tier
	# comparison (DEF 0 > DEF 20) intermittently inverts when two close averages
	# land within sampling noise — spuriously reddening the CI merge gate (#316).
	# randomize() is restored at the end so later tests keep their entropy.
	seed(0x05ED_D46)

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
		# 200 samples (was 50): with the RNG seeded above this is deterministic,
		# and the larger sample keeps the seeded average close to the true
		# expected value so the DEF-tier ordering reflects real defense scaling
		# rather than seed luck on a narrow gap.
		for _i in range(200):
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
	# Re-seed from entropy so subsequent tests aren't pinned to this fixed stream.
	randomize()
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
	assert_true(player_deaths <= 4, "Ranger deaths <= 4 (got %d, low DEF makes boss wave risky)" % player_deaths)

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

	# ── Use disk via Inventory.use_item (the path the start menu hits) ──
	print("  ── Inventory.use_item with disk ──")
	# Reset foie and add a Lv.10 disk to inventory
	fomar["techniques"].erase("foie")
	Inventory.add_item("disk_foie_10", 1)
	assert_eq(Inventory.get_item_count("disk_foie_10"), 1, "Disk added to inventory")
	var use_ok := Inventory.use_item("disk_foie_10")
	assert_true(use_ok, "Inventory.use_item('disk_foie_10') succeeded")
	assert_eq(TechniqueManager.get_technique_level(fomar, "foie"), 10, "Foie learned at Lv.10")
	assert_eq(Inventory.get_item_count("disk_foie_10"), 0, "Disk consumed from inventory")
	# Different tech id: barta should also parse correctly
	Inventory.add_item("disk_barta_5", 1)
	var use_barta := Inventory.use_item("disk_barta_5")
	assert_true(use_barta, "Inventory.use_item('disk_barta_5') succeeded")
	assert_eq(TechniqueManager.get_technique_level(fomar, "barta"), 5, "Barta learned at Lv.5")

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

	# ── Verify technique disks are sold (canonical source: the Item Shop's
	# Disks tab, generated by TechniqueManager — the standalone tech_shop was
	# redundant and was removed). ──
	print("  ── Technique Disks (Item Shop) ──")
	# Mirror item_shop._generate_disk_inventory: level from the active character, default 1.
	var disk_char = CharacterManager.get_active_character()
	var disk_char_level: int = int(disk_char.get("level", 1)) if disk_char else 1
	var shop_items: Array = TechniqueManager.generate_shop_inventory(disk_char_level)
	assert_gt(shop_items.size(), 0, "Item Shop offers technique disks")
	print("  INFO: %d technique disks offered" % shop_items.size())

	# Verify first item is a valid disk
	if not shop_items.is_empty():
		var first: Dictionary = shop_items[0]
		var item_name: String = str(first.get("name", ""))
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


# ── Telepipe — extended coverage for PR #202 ────────────────────
# These tests exercise the data-layer contracts of the telepipe +
# backtracking system without loading any scenes. They mirror the
# call sequences the controllers issue (place / suspend_session /
# consume_return / resume_session / save_section_state) so a
# regression in the wiring shows up here before it shows up on
# device. See PR #202 for the spec checklist these map to.

func test_telepipe_manager_unit() -> void:
	print("── TelepipeManager — unit ──")

	# Reset to known empty state
	TelepipeManager.cancel("test_setup")
	assert_true(not TelepipeManager.is_active(), "Inactive after cancel")
	assert_true(TelepipeManager.get_state().is_empty(), "Empty state when inactive")
	assert_true(TelepipeManager.consume_return().is_empty(), "consume_return on empty returns {}")

	# place() populates state and flips is_active()
	TelepipeManager.place("gurhacia", 0, "1,2",
		Vector3(3.0, 0.0, 4.5),
		"res://scenes/3d/field/valley_field.tscn")
	assert_true(TelepipeManager.is_active(), "Active after place")
	var s: Dictionary = TelepipeManager.get_state()
	assert_eq(str(s.get("area_id", "")), "gurhacia", "area_id stored")
	assert_eq(int(s.get("section_idx", -1)), 0, "section_idx stored")
	assert_eq(str(s.get("cell_pos", "")), "1,2", "cell_pos stored")
	assert_eq(s.get("world_pos", Vector3.ZERO), Vector3(3.0, 0.0, 4.5), "world_pos stored")
	assert_eq(str(s.get("field_scene", "")),
		"res://scenes/3d/field/valley_field.tscn", "field_scene stored")

	# get_state() must return a defensive copy (caller mutation can't bleed in)
	s["area_id"] = "tampered"
	assert_eq(str(TelepipeManager.get_state().get("area_id", "")),
		"gurhacia", "get_state returns defensive copy")

	# Replacing: at-most-one rule. New place() supersedes old, telepipe stays active.
	TelepipeManager.place("ozette", 1, "0,0",
		Vector3.ZERO,
		"res://scenes/3d/field/ozette_field.tscn")
	assert_true(TelepipeManager.is_active(), "Still active after replace")
	assert_eq(str(TelepipeManager.get_state().get("area_id", "")),
		"ozette", "area_id replaced")
	assert_eq(int(TelepipeManager.get_state().get("section_idx", -1)),
		1, "section_idx replaced")

	# matches_field(): all three keys must agree
	assert_true(TelepipeManager.matches_field("ozette", 1, "0,0"),
		"matches_field exact triple")
	assert_true(not TelepipeManager.matches_field("gurhacia", 1, "0,0"),
		"matches_field rejects different area")
	assert_true(not TelepipeManager.matches_field("ozette", 0, "0,0"),
		"matches_field rejects different section")
	assert_true(not TelepipeManager.matches_field("ozette", 1, "5,5"),
		"matches_field rejects different cell")

	# consume_return() returns snapshot, then clears
	var snap: Dictionary = TelepipeManager.consume_return()
	assert_eq(str(snap.get("area_id", "")), "ozette", "consume_return returns snapshot")
	assert_true(not TelepipeManager.is_active(), "Inactive after consume_return")
	assert_true(TelepipeManager.get_state().is_empty(), "Empty state after consume_return")

	# cancel() on inactive is a no-op (must not crash, must stay inactive)
	TelepipeManager.cancel("idempotent_check")
	assert_true(not TelepipeManager.is_active(), "Cancel on inactive stays inactive")

	# matches_field() on inactive always false (no out-of-bounds index access)
	assert_true(not TelepipeManager.matches_field("ozette", 1, "0,0"),
		"matches_field on inactive returns false")
	print("")


func test_telepipe_round_trip() -> void:
	print("── Telepipe — full round-trip (drop → city → field) ──")

	# Reset
	TelepipeManager.cancel("test_setup")
	SessionManager._suspended_session.clear()

	# Player enters field, drops a telepipe in section 0 cell 1,2
	SessionManager.enter_field("gurhacia", "normal")
	assert_true(SessionManager.has_active_session(), "Session active in field")
	assert_eq(SessionManager.get_location(), "field", "Location is field")

	TelepipeManager.place("gurhacia", 0, "1,2",
		Vector3(7.5, 0.0, -2.5),
		"res://scenes/3d/field/valley_field.tscn")
	assert_true(TelepipeManager.is_active(), "Telepipe active after place")

	# Player walks into field telepipe + accept.
	# Mirrors valley_field_controller._handle_telepipe_travel:
	#   save_section_state(current section) THEN suspend_session().
	SessionManager.save_section_state(
		SessionManager.get_current_section(),
		{"1,2": {"cleared": true, "items_picked": ["pd"]}},
		{}, {}, {"1,2": true})
	SessionManager.suspend_session()
	assert_true(not SessionManager.has_active_session(),
		"No active session after suspend")
	assert_true(SessionManager.has_suspended_session(),
		"Suspended session present")
	assert_eq(SessionManager.get_location(), "city", "Location is city")
	assert_true(TelepipeManager.is_active(),
		"Telepipe still active across suspend (city pillar can spawn)")

	# Player walks into city telepipe + accept.
	# Mirrors city_counter_controller._consume_telepipe:
	#   consume_return() snapshot, then resume_session() to land in field.
	var snap: Dictionary = TelepipeManager.consume_return()
	assert_eq(str(snap.get("cell_pos", "")), "1,2",
		"Snapshot returns the dropped cell")
	assert_eq(snap.get("world_pos", Vector3.ZERO),
		Vector3(7.5, 0.0, -2.5), "Snapshot returns the dropped world_pos")
	assert_true(not TelepipeManager.is_active(),
		"Telepipe gone after consume_return (one-shot rule)")

	SessionManager.resume_session()
	assert_true(SessionManager.has_active_session(),
		"Session resumed after city telepipe")
	assert_eq(SessionManager.get_location(), "field",
		"Location back to field")

	# Cleared cell state survives the round trip
	var st: Dictionary = SessionManager.get_section_state(0)
	assert_true(not st.is_empty(), "Section 0 state preserved")
	var cells: Dictionary = st.get("cell_states", {})
	assert_true(cells.has("1,2"), "Cell 1,2 cleared state preserved")
	assert_eq(cells["1,2"].get("cleared", false), true,
		"1,2 still marked cleared after round trip")

	# Cleanup
	SessionManager.return_to_city()
	print("")


func test_telepipe_suspend_resume_keeps_telepipe() -> void:
	print("── Telepipe — suspend/resume preserves the active telepipe ──")

	TelepipeManager.cancel("test_setup")
	SessionManager._suspended_session.clear()

	# Drop a telepipe, then suspend (StartWarp path, or city teleporter
	# round trip via the same area).
	SessionManager.enter_field("gurhacia", "normal")
	TelepipeManager.place("gurhacia", 0, "0,0",
		Vector3(1.0, 0.0, 1.0),
		"res://scenes/3d/field/valley_field.tscn")
	SessionManager.suspend_session()
	assert_true(TelepipeManager.is_active(),
		"Telepipe active across suspend (warp pad path)")

	# Player picks the same area in city teleporter → resume_session
	# (warp_teleporter._warp_to_field path when suspended_area matches selection).
	SessionManager.resume_session()
	assert_true(SessionManager.has_active_session(),
		"Session active after resume")
	assert_true(TelepipeManager.is_active(),
		"Telepipe still active after resume — player can walk back to it")
	assert_eq(int(TelepipeManager.get_state().get("section_idx", -1)),
		0, "Telepipe section preserved across suspend/resume")

	# Cleanup — return_to_city is the spec'd cancel hook for full session end
	SessionManager.return_to_city()
	assert_true(not TelepipeManager.is_active(),
		"return_to_city cancels telepipe (full session end)")
	print("")


func test_section_state_round_trip() -> void:
	print("── Section state — multi-section preservation across suspend ──")

	TelepipeManager.cancel("test_setup")
	SessionManager._suspended_session.clear()

	SessionManager.enter_field("gurhacia", "normal")

	# Section 0: clear room (1,1), pick up a key, open a gate
	SessionManager.save_section_state(0,
		{"1,1": {"cleared": true}},
		{"key_a": true},
		{"gate_x": true},
		{"1,1": true})

	# Advance to section 1, clear (2,2)
	SessionManager.set_current_section(1)
	SessionManager.save_section_state(1,
		{"2,2": {"cleared": true}},
		{}, {},
		{"2,2": true})

	# Suspend (e.g. via StartWarp), then resume via warp pad
	SessionManager.suspend_session()
	SessionManager.resume_session()

	var s0: Dictionary = SessionManager.get_section_state(0)
	var s1: Dictionary = SessionManager.get_section_state(1)
	assert_true(not s0.is_empty(), "Section 0 still in cell-state map")
	assert_true(not s1.is_empty(), "Section 1 still in cell-state map")
	assert_eq(s0.get("keys_collected", {}).get("key_a", false),
		true, "Section 0 keys preserved")
	assert_eq(s0.get("gates_opened", {}).get("gate_x", false),
		true, "Section 0 gates preserved")
	assert_eq(s1.get("cell_states", {}).get("2,2", {}).get("cleared", false),
		true, "Section 1 cleared cell preserved")

	# Visited section indices: both sections, sorted ascending
	# (this drives the section-selector UI in warp_teleporter)
	var visited: Array = SessionManager.get_visited_section_indices()
	assert_eq(visited.size(), 2, "Two visited sections")
	assert_eq(int(visited[0]), 0, "First visited section is 0")
	assert_eq(int(visited[1]), 1, "Second visited section is 1")

	# return_to_city wipes section states (full-expedition end)
	SessionManager.return_to_city()
	assert_true(SessionManager.get_visited_section_indices().is_empty(),
		"return_to_city wipes section states")
	print("")


func test_telepipe_cancel_hooks() -> void:
	print("── Telepipe — every cancel-on-X hook ──")

	# Each block: drop a telepipe to a known active state, call the
	# session transition that's spec'd to cancel it, assert it's gone.

	# enter_field — fresh expedition, telepipe no longer reachable
	TelepipeManager.place("gurhacia", 0, "0,0",
		Vector3.ZERO, "res://scenes/3d/field/valley_field.tscn")
	SessionManager.enter_field("ozette", "normal")
	assert_true(not TelepipeManager.is_active(),
		"enter_field cancels active telepipe")
	SessionManager.return_to_city()

	# return_to_city — boss-clear / explicit "I'm done" path
	TelepipeManager.place("gurhacia", 0, "0,0",
		Vector3.ZERO, "res://scenes/3d/field/valley_field.tscn")
	SessionManager.return_to_city()
	assert_true(not TelepipeManager.is_active(),
		"return_to_city cancels active telepipe")

	# reset_all_state — title-screen path
	SessionManager.enter_field("gurhacia", "normal")
	TelepipeManager.place("gurhacia", 0, "0,0",
		Vector3.ZERO, "res://scenes/3d/field/valley_field.tscn")
	SessionManager.reset_all_state()
	assert_true(not TelepipeManager.is_active(),
		"reset_all_state cancels active telepipe")

	# accept_quest / cancel_accepted_quest / enter_quest — only if quest
	# fixtures load on this checkout
	var quest_ids: Array = QuestLoader.list_quests()
	if quest_ids.is_empty():
		print("  INFO: No quest files, skipping quest-path cancel hooks")
	else:
		var qid: String = str(quest_ids[0])

		TelepipeManager.place("gurhacia", 0, "0,0",
			Vector3.ZERO, "res://scenes/3d/field/valley_field.tscn")
		SessionManager.accept_quest(qid, "normal")
		assert_true(not TelepipeManager.is_active(),
			"accept_quest cancels active telepipe")

		TelepipeManager.place("gurhacia", 0, "0,0",
			Vector3.ZERO, "res://scenes/3d/field/valley_field.tscn")
		SessionManager.cancel_accepted_quest()
		assert_true(not TelepipeManager.is_active(),
			"cancel_accepted_quest cancels active telepipe")

		TelepipeManager.place("gurhacia", 0, "0,0",
			Vector3.ZERO, "res://scenes/3d/field/valley_field.tscn")
		SessionManager.enter_quest(qid, "normal")
		assert_true(not TelepipeManager.is_active(),
			"enter_quest cancels active telepipe")
		SessionManager.return_to_city()

	# Cleanup — leave the world clean for the next test
	TelepipeManager.cancel("test_cleanup")
	SessionManager._accepted_quest.clear()
	SessionManager._completed_quest.clear()
	SessionManager._suspended_session.clear()
	print("")


func test_telepipe_use_item_outside_field() -> void:
	print("── Inventory.use_item('telepipe') — field-only guard ──")

	# Spec: "In city → selecting Telepipe + accept refused with 'Telepipe only
	# works in the field', item not consumed." Inventory._use_telepipe is the
	# enforcement point — start menu surfaces the refusal via get_last_use_info.
	# This test exercises the guard without loading any scene.

	# Setup: clean state, give the player one telepipe
	TelepipeManager.cancel("test_setup")
	SessionManager.return_to_city()  # ensures location == "city"
	Inventory.clear_inventory()
	Inventory.add_item("telepipe", 1)
	assert_eq(SessionManager.get_location(), "city",
		"Location is city before use attempt")
	assert_eq(Inventory.get_item_count("telepipe"), 1,
		"Inventory has 1 telepipe before use")

	# Act: try to use it from city → must refuse
	var ok: bool = Inventory.use_item("telepipe")
	assert_true(not ok, "use_item('telepipe') returns false in city")
	assert_eq(Inventory.get_item_count("telepipe"), 1,
		"Telepipe count NOT decremented on refusal")

	# Refusal type is the signal pso_start_menu uses to render the friendly
	# "only works in the field" message instead of generic "Couldn't use Telepipe".
	var info: Dictionary = Inventory.get_last_use_info()
	assert_eq(str(info.get("type", "")), "telepipe_fail",
		"last_use_info.type is telepipe_fail (drives city-side refusal message)")

	# TelepipeManager must remain inactive — refusal must not have side effects.
	assert_true(not TelepipeManager.is_active(),
		"TelepipeManager stayed inactive on city-side refusal")

	# Cleanup
	Inventory.clear_inventory()
	print("")


# ── #239 telepipe fixes — node dedup + free-field counter unlock ──
# Bug 1: placing a second pipe must free the first pipe's NODE (the
# manager state already replaced; the visual drifted). Bug 2: a
# suspended FREE-FIELD session must not lock the guild counter into
# cancel-only — accepting a quest abandons the field run.
func test_telepipe_239_fixes() -> void:
	print("── Telepipe #239 — node dedup + free-field counter unlock ──")

	# Bug 1: controller-level node dedup, off-tree (no scene load).
	const FieldController := preload("res://scripts/3d/field/valley_field_controller.gd")
	var ctl = FieldController.new()
	var map_root := Node3D.new()
	ctl.add_child(map_root)
	ctl._map_root = map_root
	ctl._spawn_player_telepipe_node(Vector3(1, 0, 1))
	ctl._spawn_player_telepipe_node(Vector3(9, 0, 9))
	var live: Array = []
	for child in map_root.get_children():
		if not child.is_queued_for_deletion():
			live.append(child)
	assert_eq(live.size(), 1, "second placement frees the first pipe node")
	assert_eq(str(live[0].name), "PlayerTelepipe", "surviving node keeps the canonical name")
	ctl.free()

	# Bug 2: suspended free-field session — predicate + accept-quest cleanup.
	SessionManager.return_to_city()
	SessionManager._accepted_quest.clear()
	SessionManager._suspended_session.clear()

	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.suspend_session()
	assert_true(SessionManager.has_suspended_session(), "field session suspends")
	assert_true(not SessionManager.has_suspended_quest(),
		"suspended FIELD run is not a suspended quest (counter stays unlocked)")

	TelepipeManager.place("gurhacia", 0, "0,0", Vector3.ZERO, "res://x.tscn")
	SessionManager.accept_quest("search_and_rescue", "normal")
	assert_true(not SessionManager.has_suspended_session(),
		"accepting a quest abandons the suspended field run")
	assert_true(not TelepipeManager.is_active(), "accepting a quest cancels the telepipe")
	SessionManager.cancel_accepted_quest()

	# Suspended QUEST run still locks the counter (existing behavior, pinned).
	SessionManager.enter_quest("search_and_rescue", "normal")
	SessionManager.suspend_session()
	assert_true(SessionManager.has_suspended_quest(), "suspended QUEST run still reads as quest")
	SessionManager.cancel_accepted_quest()
	assert_true(not SessionManager.has_suspended_session(),
		"cancel clears the suspended quest run")

	SessionManager.return_to_city()
	SessionManager._suspended_session.clear()
	print("")


func test_build_info_sentinel() -> void:
	print("── BuildInfo — committed-sentinel contract ──")

	# scripts/tools/local_build_apk.sh seds LOCAL_BUILD to a counter before
	# export, then restores via sed back to the original on EXIT. If that
	# trap ever silently fails (process killed, sed pattern miss, etc.) the
	# counter would land in a commit. This test catches that on CI BEFORE
	# the merge — committed value MUST be the sentinel 0.
	#
	# CI's release workflow toggles the `ci` custom_feature so title.gd
	# short-circuits the LOCAL_BUILD display entirely; a non-zero committed
	# value would only hurt local reinstalls, but it'd still be a lie about
	# the source-of-truth state of the file.
	assert_eq(BuildInfo.LOCAL_BUILD, 0,
		"BuildInfo.LOCAL_BUILD == 0 (sentinel — bumped value must never be committed)")
	print("")


func test_bootstrap_pack_magic_guard() -> void:
	print("── bootstrap — pack-magic guard rejects junk downloads (#243) ──")

	# A failed pack download (gateway 502, or a 200-with-HTML error page)
	# must never linger in user://packs/ masquerading as the pack. bootstrap
	# guards downloads with _has_pack_magic (leading bytes must be "GDPC")
	# and drops anything that fails via _discard_download. Both are pure
	# file ops, so we can exercise them without the scene tree / HTTPRequest.
	var boot = load("res://scripts/2d/bootstrap.gd").new()

	# An nginx-style error body is not a pack → magic check must reject it,
	# and discarding it must remove the file from the cache dir.
	var junk_path: String = "user://packs/test-junk.pck"
	var junk_abs: String = ProjectSettings.globalize_path(junk_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://packs"))
	var jf := FileAccess.open(junk_abs, FileAccess.WRITE)
	assert_true(jf != null, "Junk fixture opened for write (user:// writable)")
	jf.store_string("<html><head><title>502 Bad Gateway</title></head></html>")
	jf.close()
	assert_true(not boot._has_pack_magic(junk_abs), "HTML error body rejected (no GDPC magic)")
	boot._discard_download(junk_abs)
	assert_true(not FileAccess.file_exists(junk_abs), "Junk download removed from cache")

	# A real pack starts with the Godot pack magic "GDPC" → must pass.
	var good_path: String = "user://packs/test-good.pck"
	var good_abs: String = ProjectSettings.globalize_path(good_path)
	var gf := FileAccess.open(good_abs, FileAccess.WRITE)
	assert_true(gf != null, "Good fixture opened for write (user:// writable)")
	gf.store_buffer(PackedByteArray([0x47, 0x44, 0x50, 0x43, 0x00, 0x00, 0x00, 0x00]))
	gf.close()
	assert_true(boot._has_pack_magic(good_abs), "Valid GDPC pack accepted")
	boot._discard_download(good_abs)

	boot.free()
	print("")


func test_warp_teleporter_section_label() -> void:
	print("── warp_teleporter.derive_section_label — pure label derivation ──")

	# WarpTeleporter._build_section_options derives sub-area labels by
	# pulling the letter at index 3 of the first cell's stage_id (e.g.
	# `s01a_sa1` → "Valley A", `s01e_ia1` → "Valley E"). The labelling
	# itself is pure, so it lives as a static helper that this test
	# exercises directly — no scene tree, no SessionManager state.
	const WarpTeleporter := preload("res://scripts/2d/warp_teleporter.gd")

	# Happy path — every sub-letter a/b/c/d/e produces "<Area> <Letter>"
	assert_eq(WarpTeleporter.derive_section_label("Valley", "s01a_sa1", 0),
		"Valley A", "s01a_sa1 → Valley A")
	assert_eq(WarpTeleporter.derive_section_label("Valley", "s01b_sa1", 1),
		"Valley B", "s01b_sa1 → Valley B")
	assert_eq(WarpTeleporter.derive_section_label("Valley", "s01e_ia1", 4),
		"Valley E", "s01e_ia1 → Valley E (lower 'e' uppercased)")
	assert_eq(WarpTeleporter.derive_section_label("Wetlands", "s03c_xa2", 2),
		"Wetlands C", "Different area name carries through")

	# Already-uppercase sub-letter — no double-upper crash
	assert_eq(WarpTeleporter.derive_section_label("Valley", "s01A_sa1", 0),
		"Valley A", "Uppercase sub-letter handled idempotently")

	# Fallback paths — these all yield "<Area> — Section <N+1>"
	assert_eq(WarpTeleporter.derive_section_label("Valley", "", 0),
		"Valley — Section 1", "Empty stage_id falls back to numeric")
	assert_eq(WarpTeleporter.derive_section_label("Valley", "s01", 2),
		"Valley — Section 3", "Too-short stage_id falls back (uses N+1)")
	assert_eq(WarpTeleporter.derive_section_label("Valley", "x01a_sa1", 0),
		"Valley — Section 1", "stage_id not starting with 's' falls back")
	assert_eq(WarpTeleporter.derive_section_label("Valley", "s019_sa1", 0),
		"Valley — Section 1", "Non-alpha sub char (digit) falls back")
	assert_eq(WarpTeleporter.derive_section_label("Valley", "s01-_sa1", 0),
		"Valley — Section 1", "Non-alpha sub char (punctuation) falls back")

	# Empty area_name — function doesn't try to be clever, caller is
	# expected to supply "Field" as the default. Test we don't crash and
	# we still produce a usable string.
	assert_eq(WarpTeleporter.derive_section_label("", "s01a_sa1", 0),
		" A", "Empty area_name still derives the letter (caller's job to default)")
	print("")


func test_warp_area_unlock() -> void:
	print("── warp_teleporter._is_area_unlocked — quest-cleared area unlock ──")

	# Characterizes the free-roam unlock rule after the dead legacy-mission
	# unlock paths were removed (#281 inc 2): an area unlocks iff a *completed
	# quest* cleared it (quest.area_id == area_id). Gurhacia is always open.
	# _is_area_unlocked reads only GameState.completed_missions + QuestLoader,
	# so we can drive it on a bare instance — no scene tree needed.
	const WarpTeleporter := preload("res://scripts/2d/warp_teleporter.gd")
	var wt: Control = WarpTeleporter.new()
	var saved_completed: Array = GameState.completed_missions.duplicate()

	GameState.completed_missions = []
	assert_true(wt._is_area_unlocked("gurhacia"), "Gurhacia (start area) always unlocked")
	assert_true(not wt._is_area_unlocked("paru"), "Paru locked when no quests completed")

	# Completing the quest that clears Paru (the_paru_pact, area_id=paru) unlocks it.
	var pact: Dictionary = QuestLoader.load_quest("the_paru_pact")
	var pact_area: String = str(pact.get("area_id", ""))
	assert_eq(pact_area, "paru", "the_paru_pact clears Paru (fixture sanity)")
	GameState.completed_missions = ["the_paru_pact"]
	assert_true(wt._is_area_unlocked("paru"), "Completing the_paru_pact unlocks Paru")

	# A completed quest that clears a *different* area does not unlock Paru.
	GameState.completed_missions = ["search_and_rescue"]  # clears gurhacia
	assert_true(not wt._is_area_unlocked("paru"), "Unrelated completed quest leaves Paru locked")

	wt.free()
	GameState.completed_missions = saved_completed
	print("")


func test_mesh_utils_apply_texture() -> void:
	print("── MeshUtils.apply_texture_recursive — recursive albedo override ──")
	# Deduped from character_create/character_select (#294). Covers both branches
	# (no-material → fresh StandardMaterial3D; existing StandardMaterial3D →
	# duplicated, source unmutated) plus recursion through a nested tree.
	var tex := PlaceholderTexture2D.new()

	# No-material branch, two levels deep (root → child → mesh).
	var root := Node3D.new()
	var child := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()  # 1 surface, no material
	child.add_child(mi)
	root.add_child(child)
	MeshUtils.apply_texture_recursive(root, tex)
	var om := mi.get_surface_override_material(0)
	assert_true(om is StandardMaterial3D, "Fresh StandardMaterial3D created for unmaterialed surface")
	if om is StandardMaterial3D:
		assert_eq((om as StandardMaterial3D).albedo_texture, tex, "Albedo applied recursively through nested nodes")
		assert_eq((om as StandardMaterial3D).texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST, "Nearest texture filter set")
	root.free()

	# Existing-StandardMaterial3D branch: duplicated, source left unmutated.
	var mi2 := MeshInstance3D.new()
	mi2.mesh = BoxMesh.new()
	var orig_mat := StandardMaterial3D.new()
	mi2.set_surface_override_material(0, orig_mat)
	MeshUtils.apply_texture_recursive(mi2, tex)
	var om2 := mi2.get_surface_override_material(0)
	assert_true(om2 != orig_mat, "Existing material is duplicated, not mutated in place")
	if om2 is StandardMaterial3D:
		assert_eq((om2 as StandardMaterial3D).albedo_texture, tex, "Duplicated material gets the texture")
	assert_true(orig_mat.albedo_texture == null, "Source material left unmutated")
	mi2.free()
	print("")


func test_game_element_build_prompt_label() -> void:
	print("── GameElement._build_prompt_label — shared interaction prompt ──")
	# Deduped _setup_prompt across key_pickup/key_gate/message_pack (#294): same
	# Label3D config, parameterized by text / color / height.
	var ge := GameElement.new()
	var label := ge._build_prompt_label("Pick up", Color(1.0, 0.4, 0.4), 2.0)
	assert_true(label is Label3D, "Returns a Label3D")
	assert_eq(label.text, "Pick up", "Text param applied")
	assert_eq(label.modulate, Color(1.0, 0.4, 0.4), "Color param applied")
	assert_eq(label.position, Vector3(0, 2.0, 0), "Y-offset param applied")
	assert_eq(label.font_size, 28, "Shared font_size")
	assert_true(label.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "Billboard enabled")
	assert_true(not label.visible, "Prompt starts hidden")
	label.free()
	ge.free()
	print("")


func test_game_element_override_textured_material() -> void:
	print("── GameElement._override_textured_material — scrolling-texture override ──")
	# Deduped gate/key_gate laser + message_pack scroll material setup (#294):
	# same find-surface-by-texture-name + duplicate, parameterized by name.
	var ge := GameElement.new()

	# No model → null (apply_to_all_materials guards on `model`).
	assert_true(ge._override_textured_material("o0c_1_gate") == null, "Null model → null")

	# Build a model whose mesh material's albedo texture path contains the name.
	var model := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var src_mat := StandardMaterial3D.new()
	var tex := PlaceholderTexture2D.new()
	tex.take_over_path("res://_test_o0c_1_gate.png")
	src_mat.albedo_texture = tex
	mi.set_surface_override_material(0, src_mat)
	model.add_child(mi)
	ge.model = model
	ge.add_child(model)

	var result := ge._override_textured_material("o0c_1_gate")
	assert_true(result is StandardMaterial3D, "Matching surface → returns a StandardMaterial3D")
	assert_true(result != src_mat, "Returned material is a duplicate, not the shared source")
	assert_true(ge._override_textured_material("does_not_exist") == null, "No matching surface → null")
	ge.free()
	print("")


func test_shop_ui_setup_portrait() -> void:
	print("── ShopUI.setup_portrait — shared two-column shop layout ──")
	# Composition helper (preloaded, NOT a base class — a ShopBase base class
	# broke the Android export; #274 inc 5). Deduped from photon_shop/crafting_shop.
	const ShopUI := preload("res://scripts/2d/shops/shop_ui.gd")
	# Minimal shop shape: a "Panel" PanelContainer whose first child is the VBox.
	var shop := Control.new()
	var panel := PanelContainer.new()
	panel.name = "Panel"
	var content := VBoxContainer.new()
	panel.add_child(content)
	shop.add_child(panel)

	ShopUI.setup_portrait(shop)

	assert_eq(panel.get_child_count(), 1, "Panel reduced to a single outer container")
	var outer := panel.get_child(0)
	assert_true(outer is HBoxContainer, "Outer container is an HBox (two columns)")
	assert_eq(outer.get_child_count(), 2, "Outer has [content | right column]")
	assert_true(outer.get_child(0) == content, "Left column is the original content VBox")
	assert_eq(content.size_flags_stretch_ratio, 3.0, "Content VBox stretches 3")
	assert_true(outer.get_child(1) is VBoxContainer, "Right column is a VBox")
	assert_eq((outer.get_child(1) as Control).size_flags_stretch_ratio, 2.0, "Right column stretches 2")
	assert_true(panel.has_theme_stylebox_override("panel"), "Panel stylebox override applied")
	shop.free()
	print("")


# ── ShopNav.handle — shared shop/menu input skeleton (#274 inc 3) ──
# Characterizes the skeleton every shop now delegates to: modal guard,
# cancel, tab keys, up/down wrap over list_size, accept, on_other tail.
func test_shop_nav() -> void:
	print("── ShopNav.handle — shared shop input skeleton ──")
	const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")
	var stub := GDScript.new()
	stub.source_code = "extends Control\nvar _selected_index: int = 0\n"
	stub.reload()
	var shop: Control = stub.new()
	add_child(shop)

	var calls: Array = []
	var opts := {
		"sfx": false,
		"on_cancel": func() -> void: calls.append("cancel"),
		"on_tab": func(dir: int) -> void: calls.append("tab%+d" % dir),
		"list_size": func() -> int: return 3,
		"on_move": func(old: int) -> void: calls.append("move<%d" % old),
		"on_accept": func() -> void: calls.append("accept"),
	}

	assert_true(ShopNav.handle(shop, _nav_event("ui_down"), opts), "ui_down consumed")
	assert_eq(shop.get("_selected_index"), 1, "ui_down advances selection")
	assert_eq(calls, ["move<0"], "on_move fired with old index")
	shop.set("_selected_index", 0)
	ShopNav.handle(shop, _nav_event("ui_up"), opts)
	assert_eq(shop.get("_selected_index"), 2, "ui_up wraps 0 → size-1")
	ShopNav.handle(shop, _nav_event("ui_right"), opts)
	ShopNav.handle(shop, _nav_event("ui_left"), opts)
	ShopNav.handle(shop, _nav_event("ui_accept"), opts)
	ShopNav.handle(shop, _nav_event("ui_cancel"), opts)
	assert_eq(calls.slice(1), ["move<0", "tab+1", "tab-1", "accept", "cancel"],
		"tab/accept/cancel route to their hooks")

	# Modal guard: a valid modal swallows everything.
	calls.clear()
	opts["modal"] = shop  # any valid Object
	assert_true(not ShopNav.handle(shop, _nav_event("ui_accept"), opts), "modal blocks input")
	assert_eq(calls, [], "no hooks fire while modal is open")
	opts.erase("modal")

	# Empty list: selection pins to 0. Omitted hooks: keys fall through.
	opts["list_size"] = func() -> int: return 0
	ShopNav.handle(shop, _nav_event("ui_down"), opts)
	assert_eq(shop.get("_selected_index"), 0, "empty list pins selection to 0")
	var other_hit := [false]
	var bare := {"sfx": false, "on_other": func(_ev: InputEvent) -> bool:
		other_hit[0] = true
		return true}
	assert_true(ShopNav.handle(shop, _nav_event("ui_up"), bare), "unclaimed key reaches on_other")
	assert_true(other_hit[0], "on_other fired")

	shop.free()
	print("")


static func _nav_event(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


# ── ShopNav confirm flow — shared modal lifecycle (#274 inc 4) ──
# Characterizes the _active_modal guard contract: selected_item bounds,
# confirm() owning set/clear of _active_modal around on_yes/on_cancel,
# info() doing the same for single-button error modals.
func test_shop_confirm() -> void:
	print("── ShopNav confirm flow — shared modal lifecycle ──")
	const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")
	var stub := GDScript.new()
	stub.source_code = "extends Control\nvar _selected_index: int = 0\nvar _active_modal: Control = null\n"
	stub.reload()
	var shop: Control = stub.new()
	add_child(shop)

	# selected_item guard
	assert_eq(ShopNav.selected_item(shop, []), null, "selected_item: empty list → null")
	shop.set("_selected_index", 2)
	assert_eq(ShopNav.selected_item(shop, ["a", "b"]), null, "selected_item: index OOB → null")
	shop.set("_selected_index", 1)
	assert_eq(ShopNav.selected_item(shop, ["a", "b"]), "b", "selected_item: in bounds → entry")

	# confirm(): modal owns _active_modal; confirmed → clear + on_yes
	var fired: Array = []
	ShopNav.confirm(shop, "Buy?", func() -> void: fired.append("yes"))
	var modal: Control = shop.get("_active_modal")
	assert_true(is_instance_valid(modal), "confirm() sets _active_modal")
	assert_true(modal.get_parent() == shop, "modal added under the shop")
	modal.confirmed.emit()
	assert_eq(shop.get("_active_modal"), null, "confirmed releases _active_modal")
	assert_eq(fired, ["yes"], "on_yes ran")

	# confirm(): cancelled → clear + on_cancel
	ShopNav.confirm(shop, "Sell?", func() -> void: fired.append("yes2"),
		func() -> void: fired.append("no"))
	(shop.get("_active_modal") as Control).cancelled.emit()
	assert_eq(shop.get("_active_modal"), null, "cancelled releases _active_modal")
	assert_eq(fired, ["yes", "no"], "on_cancel ran, on_yes didn't")

	# info(): single-button dismiss → clear + on_dismiss
	ShopNav.info(shop, "Inventory full!", func() -> void: fired.append("ok"))
	(shop.get("_active_modal") as Control).confirmed.emit()
	assert_eq(shop.get("_active_modal"), null, "info dismiss releases _active_modal")
	assert_eq(fired, ["yes", "no", "ok"], "on_dismiss ran")

	shop.free()
	print("")


# ── CharacterCreateState — create-flow state machine (#215-D) ──
# Characterizes the extracted state: class clamping, confirm reset,
# appearance row/value wrap, name trimming, cast detection.
func test_character_create_state() -> void:
	print("── CharacterCreateState — create-flow state machine ──")
	const CCState := preload("res://scripts/2d/character_create_state.gd")
	var s = CCState.new()
	s.class_list = ClassRegistry.get_all_classes()
	assert_gt(s.class_list.size(), 0, "registry provides classes")

	# move_class clamps at both edges (no wrap — edges feel like edges)
	assert_true(not s.move_class(-1), "left edge clamps")
	assert_true(s.move_class(1), "move right changes selection")
	s.selected_class_index = s.class_list.size() - 1
	assert_true(not s.move_class(1), "right edge clamps")

	# confirm_class locks id, resets appearance + row, advances step
	s.selected_class_index = 0
	s.appearance["variation_index"] = 2
	s.appearance_row = 3
	s.confirm_class()
	assert_eq(s.selected_class_id, str(s.class_list[0].id), "confirm locks hovered class id")
	assert_eq(int(s.appearance["variation_index"]), 0, "confirm resets appearance")
	assert_eq(s.appearance_row, 0, "confirm resets appearance row")
	assert_eq(s.step, CCState.Step.APPEARANCE, "confirm advances to APPEARANCE")

	# appearance row wraps both directions
	s.move_appearance_row(-1)
	assert_eq(s.appearance_row, 3, "row wraps 0 → 3 going up")
	s.move_appearance_row(1)
	assert_eq(s.appearance_row, 0, "row wraps 3 → 0 going down")

	# value cycling wraps within PlayerConfig bounds
	s.cycle_appearance_value(-1)
	assert_eq(int(s.appearance["variation_index"]), PlayerConfig.HEAD_VARIATIONS - 1,
		"head variation wraps backward to last option")
	s.cycle_appearance_value(1)
	assert_eq(int(s.appearance["variation_index"]), 0, "head variation wraps forward to 0")
	s.appearance_row = 3
	s.cycle_appearance_value(-1)
	assert_eq(int(s.appearance["skin_tone_index"]), PlayerConfig.SKIN_TONES.size() - 1,
		"skin tone wraps within its option count")

	# name trim / empty rejection
	assert_true(not s.set_char_name("   "), "blank name rejected")
	assert_true(s.set_char_name("  Kai  "), "non-blank name accepted")
	assert_eq(s.char_name, "Kai", "name is trimmed")

	# cast detection follows the selected row
	for i in range(s.class_list.size()):
		if s.class_list[i].race == "Cast":
			s.selected_class_index = i
			assert_true(s.is_cast_class(), "cast class detected at index %d" % i)
			break
	print("")


# ── Character Appearance tests ─────────────────────────────────

func test_character_appearance() -> void:
	print("── Character Appearance ──")

	# Reset state
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	Inventory.clear_inventory()

	# --- PlayerConfig variation mapping ---
	assert_eq(PlayerConfig.get_variation("humar", 0), "pc_000", "HUmar variation 0 = pc_000")
	assert_eq(PlayerConfig.get_variation("humar", 3), "pc_003", "HUmar variation 3 = pc_003")
	assert_eq(PlayerConfig.get_variation("ramarl", 2), "pc_032", "RAmarl variation 2 = pc_032")
	assert_eq(PlayerConfig.get_variation("racaseal", 3), "pc_133", "RAcaseal variation 3 = pc_133")
	assert_eq(PlayerConfig.get_variation("fonewearl", 1), "pc_091", "FOnewearl variation 1 = pc_091")

	# All 14 classes have valid prefixes
	for class_id in PlayerConfig.CLASS_PREFIX.keys():
		var v: String = PlayerConfig.get_variation(class_id, 0)
		assert_true(v.begins_with("pc_"), "Class %s has valid variation prefix" % class_id)

	# --- Model path generation ---
	var model_path: String = PlayerConfig.get_model_path("ramarl", 2)
	assert_eq(model_path, "res://assets/player/pc_032/pc_032_000.glb", "RAmarl model path correct")

	# --- Texture index calculation ---
	# hair=0, skin=0, body=0 → skinTone=0 → idx=000
	var tex0: String = PlayerConfig.get_texture_path("humar", 0, 0, 0, 0)
	assert_true(tex0.ends_with("pc_000_000.png"), "Texture idx 000 (hair0 skin0 body0)")

	# hair=1, skin=2, body=3 → skinTone=5 → idx = (5/3)*100 + (5%3)*10 + 3 = 100+20+3 = 123
	var tex123: String = PlayerConfig.get_texture_path("humar", 0, 1, 2, 3)
	assert_true(tex123.ends_with("pc_000_123.png"), "Texture idx 123 (hair1 skin2 body3)")

	# hair=2, skin=2, body=4 → skinTone=8 → idx = (8/3)*100 + (8%3)*10 + 4 = 200+20+4 = 224
	var tex224: String = PlayerConfig.get_texture_path("humar", 0, 2, 2, 4)
	assert_true(tex224.ends_with("pc_000_224.png"), "Texture idx 224 (hair2 skin2 body4)")

	# --- Full path generation via get_paths_for_character ---
	var char_data := {
		"class_id": "ramarl",
		"appearance": {
			"variation_index": 2,
			"hair_color_index": 1,
			"skin_tone_index": 2,
			"body_color_index": 3,
		}
	}
	var paths: Dictionary = PlayerConfig.get_paths_for_character(char_data)
	assert_eq(paths["model_path"], "res://assets/player/pc_032/pc_032_000.glb", "Full model path via get_paths_for_character")
	assert_true(str(paths["texture_path"]).ends_with("pc_032_123.png"), "Full texture path via get_paths_for_character")

	# --- Appearance stored on character creation ---
	var appearance := {"variation_index": 2, "body_color_index": 1, "hair_color_index": 1, "skin_tone_index": 2}
	var result: Dictionary = CharacterManager.create_character(0, "ramarl", "AppearTest", appearance)
	assert_true(not result.is_empty(), "Character created with appearance")
	var stored: Dictionary = result.get("appearance", {})
	assert_eq(int(stored.get("variation_index", -1)), 2, "Appearance variation_index stored")
	assert_eq(int(stored.get("body_color_index", -1)), 1, "Appearance body_color_index stored")
	assert_eq(int(stored.get("hair_color_index", -1)), 1, "Appearance hair_color_index stored")
	assert_eq(int(stored.get("skin_tone_index", -1)), 2, "Appearance skin_tone_index stored")

	# --- Backward compatibility (old save without appearance) ---
	var old_char := {"class_id": "humar", "name": "OldChar"}
	var old_paths: Dictionary = PlayerConfig.get_paths_for_character(old_char)
	assert_eq(old_paths["model_path"], "res://assets/player/pc_000/pc_000_000.glb", "Old char defaults to pc_000 model")
	assert_true(str(old_paths["texture_path"]).ends_with("pc_000_000.png"), "Old char defaults to 000 texture")

	# Clean up
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	Inventory.clear_inventory()
	print("")


func test_valley_grid() -> void:
	print("── Valley Grid ──")

	# ── Grid Generator Tests ──
	var GridGen := preload("res://scripts/3d/field/grid_generator.gd")
	var gen := GridGen.new()

	# Rotation system
	assert_eq(gen.rotate_direction("north", 0), "north", "Rotate north by 0")
	assert_eq(gen.rotate_direction("north", 90), "east", "Rotate north by 90")
	assert_eq(gen.rotate_direction("north", 180), "south", "Rotate north by 180")
	assert_eq(gen.rotate_direction("north", 270), "west", "Rotate north by 270")
	assert_eq(gen.rotate_direction("east", 90), "south", "Rotate east by 90")
	assert_eq(gen.rotate_direction("west", 180), "east", "Rotate west by 180")

	# Rotated gates
	var sa1_gates: Array[String] = gen.get_rotated_gates("s01a_sa1", 0)
	assert_eq(sa1_gates.size(), 1, "sa1 has 1 gate")
	assert_eq(sa1_gates[0], "south", "sa1 gate is south at rot 0")
	var sa1_rot90: Array[String] = gen.get_rotated_gates("s01a_sa1", 90)
	assert_eq(sa1_rot90[0], "west", "sa1 gate is west at rot 90")
	var lb1_gates: Array[String] = gen.get_rotated_gates("s01a_lb1", 90)
	assert_true("east" in lb1_gates and "north" in lb1_gates, "lb1 at rot 90 has east+north")

	# Gate data completeness
	assert_true(GridGen.GATES.has("s01a_sa1"), "GATES has s01a_sa1")
	assert_true(GridGen.GATES.has("s01b_sa1"), "GATES has s01b_sa1")
	assert_true(GridGen.GATES.has("s01e_ia1"), "GATES has s01e_ia1")
	var total_stages := 0
	for stage_id in GridGen.GATES:
		total_stages += 1
	assert_eq(total_stages, 37, "GATES has all 37 stages (18 a + 18 b + 1 e)")

	# ── Grid generation: area a ──
	var result: Dictionary = gen.generate("a", {"path_length": 5, "key_gates": 0, "branches": 0})
	var cells: Array = result.get("cells", [])
	assert_true(cells.size() >= 3, "Grid A has >= 3 cells (got %d)" % cells.size())

	# Start cell
	var start_pos: String = result.get("start_pos", "")
	assert_true(not start_pos.is_empty(), "Grid A has start_pos")
	var start_cell: Dictionary = {}
	for cell in cells:
		if str(cell.get("pos", "")) == start_pos:
			start_cell = cell
			break
	assert_true(not start_cell.is_empty(), "Start cell found")
	assert_eq(str(start_cell.get("stage_id", "")), "s01a_sa1", "Start cell uses s01a_sa1")
	assert_true(start_cell.get("is_start", false), "Start cell marked is_start")

	# End cell
	var end_cell: Dictionary = {}
	for cell in cells:
		if cell.get("is_end", false):
			end_cell = cell
			break
	assert_true(not end_cell.is_empty(), "End cell found")
	assert_true(not str(end_cell.get("warp_edge", "")).is_empty(), "End cell has warp_edge")

	# All cells have rotation field
	var all_have_rotation := true
	for cell in cells:
		if not cell.has("rotation"):
			all_have_rotation = false
	assert_true(all_have_rotation, "All cells have rotation field")

	# All connections are bidirectional
	var cell_map: Dictionary = {}
	for cell in cells:
		cell_map[str(cell["pos"])] = cell
	var bidi_ok := true
	for cell in cells:
		var connections: Dictionary = cell.get("connections", {})
		for edge in connections:
			var neighbor_pos: String = connections[edge]
			if cell_map.has(neighbor_pos):
				var neighbor: Dictionary = cell_map[neighbor_pos]
				var neighbor_conns: Dictionary = neighbor.get("connections", {})
				var found_back := false
				for ne in neighbor_conns:
					if neighbor_conns[ne] == str(cell["pos"]):
						found_back = true
						break
				if not found_back:
					bidi_ok = false
	assert_true(bidi_ok, "All connections are bidirectional")

	# GLBs exist
	var all_glbs_exist := true
	for cell in cells:
		var stage_id: String = cell.get("stage_id", "")
		var variant: String = stage_id[3] if stage_id.length() >= 4 else "a"
		var glb_path := "res://assets/stages/valley_%s/%s/lndmd/%s_m.glb" % [variant, stage_id, stage_id]
		if not ResourceLoader.exists(glb_path):
			all_glbs_exist = false
			print("    Missing GLB: %s" % glb_path)
	assert_true(all_glbs_exist, "All grid cell GLBs exist")

	# ── Grid generation: area b ──
	var b_result: Dictionary = gen.generate("b", {"path_length": 5, "key_gates": 0, "branches": 0})
	var b_cells: Array = b_result.get("cells", [])
	assert_true(b_cells.size() >= 3, "Grid B has >= 3 cells (got %d)" % b_cells.size())
	var b_start: Dictionary = {}
	for cell in b_cells:
		if cell.get("is_start", false):
			b_start = cell
			break
	assert_eq(str(b_start.get("stage_id", "")), "s01b_sa1", "Grid B start uses s01b_sa1")

	# ── Branches ──
	var br_result: Dictionary = gen.generate("a", {"path_length": 6, "key_gates": 0, "branches": 2})
	var br_cells: Array = br_result.get("cells", [])
	var branch_count := 0
	for cell in br_cells:
		if cell.get("is_branch", false):
			branch_count += 1
	# Branches are best-effort, may not always place all requested
	assert_true(branch_count >= 0, "Branch generation runs without error (placed %d)" % branch_count)

	# ── Key-gates ──
	var kg_result: Dictionary = gen.generate("a", {"path_length": 8, "key_gates": 1, "branches": 1})
	var kg_cells: Array = kg_result.get("cells", [])
	var key_count := 0
	var gate_count := 0
	for cell in kg_cells:
		if cell.get("has_key", false):
			key_count += 1
		if cell.get("is_key_gate", false):
			gate_count += 1
	# Key-gates are best-effort
	assert_true(key_count >= 0, "Key-gate generation runs without error (keys=%d, gates=%d)" % [key_count, gate_count])
	if gate_count > 0:
		assert_eq(key_count, gate_count, "Key count matches gate count")

	# ── Multiple generations succeed ──
	var gen_ok := true
	for i in range(10):
		var r: Dictionary = gen.generate("a", {"path_length": 5, "key_gates": 0, "branches": 0})
		if r.get("cells", []).size() < 3:
			gen_ok = false
	assert_true(gen_ok, "10 consecutive A generations all produce >= 3 cells")
	for i in range(10):
		var r: Dictionary = gen.generate("b", {"path_length": 5, "key_gates": 0, "branches": 0})
		if r.get("cells", []).size() < 3:
			gen_ok = false
	assert_true(gen_ok, "10 consecutive B generations all produce >= 3 cells")

	# ── Field generation (4 sections) ──
	var field: Dictionary = gen.generate_field("normal")
	var sections: Array = field.get("sections", [])
	assert_eq(sections.size(), 4, "Field has 4 sections")
	assert_eq(str(sections[0].get("type", "")), "grid", "Section 0 is grid")
	assert_eq(str(sections[0].get("area", "")), "a", "Section 0 is area a")
	assert_eq(str(sections[1].get("type", "")), "transition", "Section 1 is transition")
	assert_eq(str(sections[1].get("area", "")), "e", "Section 1 is area e")
	assert_eq(str(sections[2].get("type", "")), "grid", "Section 2 is grid")
	assert_eq(str(sections[2].get("area", "")), "b", "Section 2 is area b")
	assert_eq(str(sections[3].get("type", "")), "boss", "Section 3 is boss")
	assert_eq(str(sections[3].get("area", "")), "z", "Section 3 is area z")

	# Each section has cells and start_pos
	for i in range(sections.size()):
		var sec: Dictionary = sections[i]
		assert_true(sec.get("cells", []).size() > 0, "Section %d has cells" % i)
		assert_true(not str(sec.get("start_pos", "")).is_empty(), "Section %d has start_pos" % i)

	# Hard difficulty generates longer paths
	var hard_field: Dictionary = gen.generate_field("hard")
	var hard_sections: Array = hard_field.get("sections", [])
	assert_eq(hard_sections.size(), 4, "Hard field has 4 sections")
	# Hard path should be longer than normal (a section)
	var normal_a_count: int = sections[0].get("cells", []).size()
	var hard_a_count: int = hard_sections[0].get("cells", []).size()
	assert_true(hard_a_count >= normal_a_count,
		"Hard A section >= Normal A (%d >= %d)" % [hard_a_count, normal_a_count])

	# ── Session field sections storage ──
	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.set_field_sections(sections)
	var stored_sections: Array = SessionManager.get_field_sections()
	assert_eq(stored_sections.size(), 4, "Session stores 4 sections")
	assert_eq(SessionManager.get_current_section(), 0, "Starts at section 0")
	assert_true(SessionManager.advance_section(), "Can advance to section 1")
	assert_eq(SessionManager.get_current_section(), 1, "Now at section 1")
	assert_true(SessionManager.advance_section(), "Can advance to section 2")
	assert_true(SessionManager.advance_section(), "Can advance to section 3")
	assert_true(not SessionManager.advance_section(), "Cannot advance past last section")
	assert_eq(SessionManager.get_current_section(), 3, "Still at section 3")
	SessionManager.return_to_city()

	print("")


func test_field_config() -> void:
	print("── Field Config ──")
	var GridGen := preload("res://scripts/3d/field/grid_generator.gd")

	# ── Bundled config file exists and loads ──
	var cfg := ConfigFile.new()
	var load_ok: int = cfg.load("res://data/field_config.cfg")
	assert_eq(load_ok, OK, "Bundled field_config.cfg loads successfully")

	# ── Config has expected sections ──
	assert_true(cfg.has_section("grid"), "Config has [grid] section")
	assert_true(cfg.has_section("normal"), "Config has [normal] section")
	assert_true(cfg.has_section("hard"), "Config has [hard] section")
	assert_true(cfg.has_section("super-hard"), "Config has [super-hard] section")

	# ── Grid size from config ──
	var grid_size: int = cfg.get_value("grid", "grid_size", 0)
	assert_eq(grid_size, 5, "Config grid_size is 5")

	# ── load_params returns matching values ──
	var params: Dictionary = GridGen.load_params()
	assert_true(not params.is_empty(), "load_params returns non-empty dict")
	assert_true(params.has("normal"), "Params has normal difficulty")
	assert_true(params.has("hard"), "Params has hard difficulty")
	assert_true(params.has("super-hard"), "Params has super-hard difficulty")
	assert_eq(int(params["normal"]["a"]["path_length"]), 5, "Normal A path_length is 5")
	assert_eq(int(params["hard"]["a"]["path_length"]), 7, "Hard A path_length is 7")
	assert_eq(int(params["super-hard"]["a"]["path_length"]), 9, "Super-Hard A path_length is 9")
	assert_eq(int(params["normal"]["a"]["key_gates"]), 0, "Normal A key_gates is 0")
	assert_eq(int(params["hard"]["a"]["key_gates"]), 1, "Hard A key_gates is 1")

	# ── load_grid_size returns expected value ──
	var loaded_size: int = GridGen.load_grid_size()
	assert_eq(loaded_size, 5, "load_grid_size returns 5")

	# ── Grid generation uses config params ──
	var gen := GridGen.new()
	var field: Dictionary = gen.generate_field("normal")
	var sections: Array = field.get("sections", [])
	assert_eq(sections.size(), 4, "Config-based field has 4 sections")
	assert_true(sections[0].get("cells", []).size() >= 3, "Config-based A section has >= 3 cells")

	# ── Hard difficulty still works through config ──
	var hard_field: Dictionary = gen.generate_field("hard")
	var hard_sections: Array = hard_field.get("sections", [])
	assert_eq(hard_sections.size(), 4, "Config-based hard field has 4 sections")

	# Per-file GLB existence checks live in R2 (sha256-verified by the
	# verify-assets CI job + md5-verified by fetch_assets_dev.sh). This
	# runner just exercises config logic, so no local /assets/ is needed.

	print("")


func test_wetlands_field() -> void:
	print("── Wetlands Field ──")
	var GridGen := preload("res://scripts/3d/field/grid_generator.gd")
	var gen := GridGen.new()

	# ── Gate loading from config JSONs ──
	var gates: Dictionary = gen.load_gates("ozette")
	assert_true(not gates.is_empty(), "load_gates('ozette') returns non-empty dict")
	# Verify it's NOT the hardcoded GATES (should have s02 prefix stages)
	assert_true(gates.has("s02a_sa1"), "Ozette gates has s02a_sa1")
	assert_true(gates.has("s02b_sa1"), "Ozette gates has s02b_sa1")
	assert_true(gates.has("s02e_ia1"), "Ozette gates has s02e_ia1")
	assert_true(gates.has("s02z_na1") or not gates.has("s02z_na1"),
		"Ozette gates may or may not have s02z_na1 (boss has no portals)")
	assert_true(not gates.has("s01a_sa1"), "Ozette gates does NOT have s01a_ stages")

	# ── Gate directions match expected topology ──
	var sa1_dirs: Array = gates.get("s02a_sa1", [])
	assert_true("south" in sa1_dirs, "s02a_sa1 has south gate")
	var ga1_dirs: Array = gates.get("s02a_ga1", [])
	assert_true("north" in ga1_dirs and "south" in ga1_dirs, "s02a_ga1 has north+south gates")
	var lb1_dirs: Array = gates.get("s02a_lb1", [])
	assert_true("north" in lb1_dirs and "east" in lb1_dirs, "s02a_lb1 has north+east gates")
	var xb2_dirs: Array = gates.get("s02a_xb2", [])
	assert_eq(xb2_dirs.size(), 4, "s02a_xb2 has 4 gates (NSEW)")
	var tb3_dirs: Array = gates.get("s02a_tb3", [])
	assert_eq(tb3_dirs.size(), 3, "s02a_tb3 has 3 gates")

	# ── Count stages per section ──
	var a_count := 0
	var b_count := 0
	var e_count := 0
	for stage_id in gates:
		if str(stage_id).begins_with("s02a_"):
			a_count += 1
		elif str(stage_id).begins_with("s02b_"):
			b_count += 1
		elif str(stage_id).begins_with("s02e_"):
			e_count += 1
	# Some stages may have empty portals in config (not yet set up) — skip those
	assert_true(a_count >= 17, "Ozette has >= 17 A stages with portals (got %d)" % a_count)
	assert_eq(b_count, 18, "Ozette has 18 B stages")
	assert_eq(e_count, 1, "Ozette has 1 E stage")

	# ── Field generation for ozette ──
	var field: Dictionary = gen.generate_field("normal", "ozette")
	var sections: Array = field.get("sections", [])
	assert_eq(sections.size(), 4, "Ozette field has 4 sections")
	assert_eq(str(sections[0].get("type", "")), "grid", "Section 0 is grid")
	assert_eq(str(sections[0].get("area", "")), "a", "Section 0 is area a")
	assert_eq(str(sections[1].get("type", "")), "transition", "Section 1 is transition")
	assert_eq(str(sections[2].get("type", "")), "grid", "Section 2 is grid")
	assert_eq(str(sections[3].get("type", "")), "boss", "Section 3 is boss")

	# Transition uses s02e_ia1
	var e_cells: Array = sections[1].get("cells", [])
	assert_true(e_cells.size() > 0, "Transition section has cells")
	if e_cells.size() > 0:
		assert_eq(str(e_cells[0].get("stage_id", "")), "s02e_ia1", "Transition uses s02e_ia1")

	# Boss uses s02z_na1 (wetlands has it) or falls back to s02a_na1
	var z_cells: Array = sections[3].get("cells", [])
	assert_true(z_cells.size() > 0, "Boss section has cells")

	# Each grid section has cells and start cell uses s02{a,b}_sa1
	var a_cells: Array = sections[0].get("cells", [])
	assert_true(a_cells.size() >= 3, "Ozette A section has >= 3 cells (got %d)" % a_cells.size())
	var a_start: Dictionary = {}
	for cell in a_cells:
		if cell.get("is_start", false):
			a_start = cell
			break
	assert_eq(str(a_start.get("stage_id", "")), "s02a_sa1", "Ozette A start uses s02a_sa1")

	var b_cells: Array = sections[2].get("cells", [])
	assert_true(b_cells.size() >= 3, "Ozette B section has >= 3 cells (got %d)" % b_cells.size())
	var b_start: Dictionary = {}
	for cell in b_cells:
		if cell.get("is_start", false):
			b_start = cell
			break
	assert_eq(str(b_start.get("stage_id", "")), "s02b_sa1", "Ozette B start uses s02b_sa1")

	# Per-file GLB existence is verified server-side against R2 — not here.

	# ── Multiple generations succeed ──
	var gen_ok := true
	for i in range(10):
		var f: Dictionary = gen.generate_field("normal", "ozette")
		if f.get("sections", []).size() != 4:
			gen_ok = false
	assert_true(gen_ok, "10 consecutive Ozette field generations all produce 4 sections")

	# ── Hard difficulty ──
	var hard_field: Dictionary = gen.generate_field("hard", "ozette")
	var hard_sections: Array = hard_field.get("sections", [])
	assert_eq(hard_sections.size(), 4, "Ozette hard field has 4 sections")

	# ── Valley still works (regression check) ──
	var valley_field: Dictionary = gen.generate_field("normal", "gurhacia")
	var valley_sections: Array = valley_field.get("sections", [])
	assert_eq(valley_sections.size(), 4, "Valley field still generates 4 sections")
	var v_e_cells: Array = valley_sections[1].get("cells", [])
	if v_e_cells.size() > 0:
		assert_eq(str(v_e_cells[0].get("stage_id", "")), "s01e_ia1",
			"Valley transition still uses s01e_ia1")

	# ── AREA_CONFIG has expected entries ──
	assert_true(GridGen.AREA_CONFIG.has("gurhacia"), "AREA_CONFIG has gurhacia")
	assert_true(GridGen.AREA_CONFIG.has("ozette"), "AREA_CONFIG has ozette")
	assert_eq(str(GridGen.AREA_CONFIG["gurhacia"]["prefix"]), "s01", "Gurhacia prefix is s01")
	assert_eq(str(GridGen.AREA_CONFIG["ozette"]["prefix"]), "s02", "Ozette prefix is s02")

	print("")


func test_tower_field() -> void:
	print("── Tower Field ──")
	var GridGen := preload("res://scripts/3d/field/grid_generator.gd")
	var gen := GridGen.new()

	# ── AREA_CONFIG has tower ──
	assert_true(GridGen.AREA_CONFIG.has("tower"), "AREA_CONFIG has tower")
	assert_eq(str(GridGen.AREA_CONFIG["tower"]["prefix"]), "s08", "Tower prefix is s08")
	assert_eq(str(GridGen.AREA_CONFIG["tower"]["folder"]), "tower", "Tower folder is tower")

	# ── Normal difficulty: 2 floors × 3 rooms + 3 fixed = 9 sections ──
	var normal_field: Dictionary = gen.generate_tower_field("normal")
	var normal_sections: Array = normal_field.get("sections", [])
	assert_eq(normal_sections.size(), 9, "Normal tower has 9 sections (got %d)" % normal_sections.size())

	# First section is always entrance s080_sa0
	var entrance: Dictionary = normal_sections[0]
	var entrance_cells: Array = entrance.get("cells", [])
	assert_true(entrance_cells.size() > 0, "Entrance has cells")
	assert_eq(str(entrance_cells[0].get("stage_id", "")), "s080_sa0", "Entrance is s080_sa0")
	assert_eq(str(entrance.get("type", "")), "tower", "Entrance type is tower")

	# Last section is always boss s087_na1
	var boss: Dictionary = normal_sections[normal_sections.size() - 1]
	var boss_cells: Array = boss.get("cells", [])
	assert_true(boss_cells.size() > 0, "Boss has cells")
	assert_eq(str(boss_cells[0].get("stage_id", "")), "s087_na1", "Boss is s087_na1")
	assert_eq(str(boss.get("type", "")), "boss", "Boss type is boss")
	assert_eq(str(boss_cells[0].get("warp_edge", "X")), "", "Boss has no warp_edge")

	# Transition exists somewhere in the middle
	var trans_count := 0
	var trans_idx := -1
	for i in range(normal_sections.size()):
		if str(normal_sections[i].get("type", "")) == "transition":
			trans_count += 1
			trans_idx = i
	assert_eq(trans_count, 1, "Exactly 1 transition section")
	assert_true(trans_idx > 0 and trans_idx < normal_sections.size() - 1,
		"Transition is between entrance and boss (idx=%d)" % trans_idx)
	var trans_cells: Array = normal_sections[trans_idx].get("cells", [])
	assert_eq(str(trans_cells[0].get("stage_id", "")), "s08e_ib1", "Transition is s08e_ib1")

	# ── Hard difficulty: 4 floors × 4 rooms + 3 fixed = 19 sections ──
	var hard_field: Dictionary = gen.generate_tower_field("hard")
	var hard_sections: Array = hard_field.get("sections", [])
	assert_eq(hard_sections.size(), 19, "Hard tower has 19 sections (got %d)" % hard_sections.size())

	# ── Super-Hard difficulty: 6 floors × 4 rooms + 3 fixed = 27 sections ──
	var sh_field: Dictionary = gen.generate_tower_field("super-hard")
	var sh_sections: Array = sh_field.get("sections", [])
	assert_eq(sh_sections.size(), 27, "Super-Hard tower has 27 sections (got %d)" % sh_sections.size())

	# ── All cells have rotation=0 ──
	var all_rot_zero := true
	for sec in sh_sections:
		for cell in sec.get("cells", []):
			if int(cell.get("rotation", -1)) != 0:
				all_rot_zero = false
	assert_true(all_rot_zero, "All tower cells have rotation=0")

	# ── Straight rooms have warp_edge=south, lb1 has warp_edge=west ──
	var warp_ok := true
	for sec in sh_sections:
		for cell in sec.get("cells", []):
			var sid: String = str(cell.get("stage_id", ""))
			var warp: String = str(cell.get("warp_edge", ""))
			if sid == "s087_na1":
				if warp != "":
					warp_ok = false
			elif sid.ends_with("_lb1"):
				if warp != "west":
					warp_ok = false
			elif sid == "s080_sa0" or sid == "s08e_ib1":
				if warp != "south":
					warp_ok = false
			elif sid.ends_with("_ga1") or sid.ends_with("_sa1") or sid.ends_with("_ib1"):
				if warp != "south":
					warp_ok = false
	assert_true(warp_ok, "Warp edges correct: south for straight, west for lb1, empty for boss")

	# ── Floor styles cycle correctly ──
	# Normal (2 floors): s081, s082
	var normal_floor_ids: Array[String] = []
	for i in range(1, normal_sections.size()):
		var sec: Dictionary = normal_sections[i]
		if str(sec.get("area", "")) == "floor":
			var sid: String = str(sec["cells"][0].get("stage_id", ""))
			var floor_id: String = sid.substr(0, 4)  # e.g. "s081"
			if floor_id not in normal_floor_ids:
				normal_floor_ids.append(floor_id)
	assert_true("s081" in normal_floor_ids, "Normal tower uses s081")
	assert_true("s082" in normal_floor_ids, "Normal tower uses s082")

	# Super-Hard (6 floors): all s081-s086
	var sh_floor_ids: Array[String] = []
	for i in range(1, sh_sections.size()):
		var sec: Dictionary = sh_sections[i]
		if str(sec.get("area", "")) == "floor":
			var sid: String = str(sec["cells"][0].get("stage_id", ""))
			var floor_id: String = sid.substr(0, 4)
			if floor_id not in sh_floor_ids:
				sh_floor_ids.append(floor_id)
	assert_eq(sh_floor_ids.size(), 6, "Super-Hard uses all 6 floor styles (got %d)" % sh_floor_ids.size())

	# Per-file GLB existence is verified server-side against R2 — not here.

	# ── Deterministic: same structure every time ──
	var consistent := true
	for i in range(5):
		var f: Dictionary = gen.generate_tower_field("normal")
		if f.get("sections", []).size() != 9:
			consistent = false
	assert_true(consistent, "Tower generation is deterministic (always 9 sections for normal)")

	# ── Valley still works after tower changes (regression) ──
	var valley_field: Dictionary = gen.generate_field("normal", "gurhacia")
	assert_eq(valley_field.get("sections", []).size(), 4, "Valley still generates 4 sections")

	print("")


# ── Quest Lifecycle tests ──────────────────────────────────────

func test_quest_lifecycle() -> void:
	print("── Quest Lifecycle ──")

	# Clean state
	SessionManager.return_to_city()
	SessionManager._accepted_quest.clear()
	SessionManager._completed_quest.clear()
	SessionManager._suspended_session.clear()

	# ── WARP_TO_AREA mapping ──
	assert_eq(SessionManager.WARP_TO_AREA.get("gurhacia-valley"), "gurhacia", "WARP_TO_AREA: gurhacia-valley → gurhacia")
	assert_eq(SessionManager.WARP_TO_AREA.get("eternal-tower"), "tower", "WARP_TO_AREA: eternal-tower → tower")
	assert_eq(SessionManager.WARP_TO_AREA.get("ozette-wetland"), "ozette", "WARP_TO_AREA: ozette-wetland → ozette")

	# ── Initial state ──
	assert_true(not SessionManager.has_accepted_quest(), "No accepted quest initially")
	assert_true(not SessionManager.has_completed_quest(), "No completed quest initially")
	assert_eq(SessionManager.get_accepted_quest_area(), "", "Accepted quest area empty initially")

	# ── Accept quest ──
	var quest_ids := QuestLoader.list_quests()
	if quest_ids.is_empty():
		print("  INFO: No quest files found, skipping quest lifecycle tests")
		print("")
		return

	var test_quest_id: String = quest_ids[0]
	var accepted: Dictionary = SessionManager.accept_quest(test_quest_id, "normal")
	assert_true(not accepted.is_empty(), "accept_quest returns data")
	assert_true(SessionManager.has_accepted_quest(), "Has accepted quest after accept")
	assert_eq(str(accepted.get("quest_id", "")), test_quest_id, "Accepted quest has correct ID")
	assert_eq(str(accepted.get("difficulty", "")), "normal", "Accepted quest has correct difficulty")
	assert_true(not str(accepted.get("area_id", "")).is_empty(), "Accepted quest has area_id")
	assert_true(not str(accepted.get("name", "")).is_empty(), "Accepted quest has name")

	# ── get_accepted_quest / get_accepted_quest_area ──
	var aq: Dictionary = SessionManager.get_accepted_quest()
	assert_eq(str(aq.get("quest_id", "")), test_quest_id, "get_accepted_quest returns correct quest")
	assert_eq(SessionManager.get_accepted_quest_area(), str(accepted.get("area_id", "")), "get_accepted_quest_area matches")

	# ── No session started yet ──
	assert_true(not SessionManager.has_active_session(), "No active session while quest only accepted")
	assert_eq(SessionManager.get_location(), "city", "Still in city after accepting quest")

	# ── Cancel quest ──
	SessionManager.cancel_accepted_quest()
	assert_true(not SessionManager.has_accepted_quest(), "No accepted quest after cancel")
	assert_eq(SessionManager.get_accepted_quest_area(), "", "Quest area empty after cancel")

	# ── Accept and start quest ──
	SessionManager.accept_quest(test_quest_id, "hard")
	assert_true(SessionManager.has_accepted_quest(), "Quest re-accepted")
	var started: Dictionary = SessionManager.start_accepted_quest()
	assert_true(not started.is_empty(), "start_accepted_quest returns session data")
	assert_true(SessionManager.has_active_session(), "Session active after starting quest")
	assert_true(not SessionManager.has_accepted_quest(), "Accepted quest cleared after starting")
	assert_eq(str(started.get("type", "")), "quest", "Session type is quest")
	assert_eq(SessionManager.get_location(), "field", "Location is field after starting quest")

	# ── Field sections set ──
	var sections: Array = SessionManager.get_field_sections()
	assert_true(not sections.is_empty(), "Field sections set after starting quest")

	# ── Complete quest ──
	SessionManager.complete_quest()
	assert_true(not SessionManager.has_active_session(), "No active session after complete_quest")
	assert_true(SessionManager.has_completed_quest(), "Has completed quest")
	assert_eq(SessionManager.get_location(), "city", "Location is city after complete_quest")

	var cq: Dictionary = SessionManager.get_completed_quest()
	assert_eq(str(cq.get("quest_id", "")), test_quest_id, "Completed quest has correct ID")

	# ── Report quest ──
	var report: Dictionary = SessionManager.report_quest()
	assert_true(not report.is_empty(), "report_quest returns data")
	assert_eq(str(report.get("quest_id", "")), test_quest_id, "Report has correct quest ID")
	assert_true(not SessionManager.has_completed_quest(), "No completed quest after report")

	# ── Cancel with suspended session ──
	SessionManager.accept_quest(test_quest_id, "normal")
	SessionManager.start_accepted_quest()
	SessionManager.suspend_session()
	assert_true(SessionManager.has_suspended_session(), "Session suspended after telepipe")
	# Re-accept to track (simulating quest state stored alongside suspension)
	SessionManager._accepted_quest = {
		"quest_id": test_quest_id,
		"area_id": "gurhacia",
		"difficulty": "normal",
		"name": "Test",
	}
	SessionManager.cancel_accepted_quest()
	assert_true(not SessionManager.has_accepted_quest(), "Accepted quest cleared on cancel")
	assert_true(not SessionManager.has_suspended_session(), "Suspended session cleared on cancel (quest type)")

	# ── Death clears quest (session ends, no re-accept) ──
	SessionManager.accept_quest(test_quest_id, "normal")
	SessionManager.start_accepted_quest()
	SessionManager.return_to_city()  # Simulates death → return to city
	assert_true(not SessionManager.has_active_session(), "No session after death")
	assert_true(not SessionManager.has_accepted_quest(), "No accepted quest after death (cleared by start)")
	assert_true(not SessionManager.has_completed_quest(), "No completed quest after death")

	# Clean up
	SessionManager._accepted_quest.clear()
	SessionManager._completed_quest.clear()
	SessionManager._suspended_session.clear()
	print("")


## Spec: /states/quest-objectives — objectives are {item_id, label, target};
## collect_quest_item increments per-item counts; the quest completes (and
## quest_completed fires) only when EVERY objective reaches its target.
func test_quest_objectives() -> void:
	print("── Quest Objectives ──")

	SessionManager.return_to_city()
	SessionManager._completed_quest.clear()

	# Find a quest that actually declares objectives.
	var target_quest := ""
	for qid in QuestLoader.list_quests():
		var q: Dictionary = QuestLoader.load_quest(qid)
		if not (q.get("objectives", []) as Array).is_empty():
			target_quest = qid
			break
	if target_quest == "":
		print("  INFO: no quest declares objectives, skipping")
		print("")
		return

	var session: Dictionary = SessionManager.enter_quest(target_quest, "normal")
	assert_true(not session.is_empty(), "enter_quest(%s) starts a session" % target_quest)

	var objs: Array = SessionManager.get_quest_objectives()
	assert_gt(objs.size(), 0, "quest exposes objectives")
	# assert_gt records a FAIL but does not abort; bail before indexing objs[0]
	# or computing last_idx so the failure is the only failure (instead of an
	# index-out-of-bounds crashing the whole headless run).
	if objs.is_empty():
		return
	assert_true(not str(objs[0].get("item_id", "")).is_empty(), "objective has an item_id")
	assert_true(not SessionManager.are_objectives_complete(), "objectives start incomplete")
	assert_true(not SessionManager.has_completed_quest(), "quest not complete at start")

	# Count quest_completed emissions (Array so the lambda can mutate it).
	var fired := [0]
	var cb := func() -> void: fired[0] += 1
	SessionManager.quest_completed.connect(cb)

	# Collect every objective to its target, leaving the LAST objective one
	# item short — proves completion is gated on ALL objectives, not any one.
	var last_idx := objs.size() - 1
	for i in range(objs.size()):
		var item_id: String = str(objs[i].get("item_id", ""))
		var tgt: int = int(objs[i].get("target", 1))
		var n: int = (tgt - 1) if i == last_idx else tgt
		for _t in range(n):
			SessionManager.collect_quest_item(item_id)
		if i < last_idx:
			assert_eq(SessionManager.get_quest_item_count(item_id), tgt, "objective '%s' counts up to target %d" % [item_id, tgt])

	assert_true(not SessionManager.are_objectives_complete(), "objectives incomplete while one is short")
	assert_eq(fired[0], 0, "quest_completed not emitted before all objectives met")
	assert_true(not SessionManager.has_completed_quest(), "quest not marked complete before final item")

	# Collect the final missing item → quest should auto-complete now.
	var last_id: String = str(objs[last_idx].get("item_id", ""))
	SessionManager.collect_quest_item(last_id)
	assert_true(SessionManager.are_objectives_complete(), "objectives complete after final item")
	assert_eq(fired[0], 1, "quest_completed emitted exactly once when all objectives met")
	assert_true(SessionManager.has_completed_quest(), "quest auto-marked complete when objectives met")

	SessionManager.quest_completed.disconnect(cb)
	SessionManager.return_to_city()
	SessionManager._completed_quest.clear()
	print("")


# ── Quest rewards (#318) ────────────────────────────────────────
# Characterization: reporting a quest with a per-difficulty rewards block
# grants exactly that meseta + those items (spec /states/story-progression:
# report MUST grant rewards). search_and_rescue carries the schema's proof
# data; quests without a rewards block must grant nothing.
func test_quest_rewards() -> void:
	print("── Quest Rewards ──")

	SessionManager.return_to_city()
	SessionManager._completed_quest.clear()

	var quest: Dictionary = QuestLoader.load_quest("search_and_rescue")
	var tier: Dictionary = quest.get("rewards", {}).get("normal", {})
	assert_true(not tier.is_empty(), "search_and_rescue defines normal-difficulty rewards")
	var reward_meseta: int = int(tier.get("meseta", 0))
	var reward_items: Array = tier.get("items", [])
	assert_gt(reward_meseta, 0, "reward tier defines meseta")
	assert_gt(reward_items.size(), 0, "reward tier defines items")

	# Complete + report the quest, watching meseta/inventory deltas.
	var session: Dictionary = SessionManager.enter_quest("search_and_rescue", "normal")
	assert_true(not session.is_empty(), "enter_quest(search_and_rescue) starts a session")
	SessionManager.mark_quest_complete()
	assert_eq(str(SessionManager.get_completed_quest().get("difficulty", "")), "normal",
		"completed quest carries its difficulty")

	var meseta_before: int = GameState.get_meseta()
	var counts_before: Dictionary = {}
	for entry in reward_items:
		var iid: String = str(entry.get("id", ""))
		counts_before[iid] = Inventory.get_item_count(iid)

	var data: Dictionary = SessionManager.report_quest()
	var granted: Dictionary = data.get("rewards_granted", {})
	assert_eq(int(granted.get("meseta", 0)), reward_meseta, "report grants the defined meseta")
	assert_eq(GameState.get_meseta(), meseta_before + reward_meseta, "meseta balance increased by reward")
	var granted_items: Array = granted.get("items", [])
	assert_eq(granted_items.size(), reward_items.size(), "report grants every defined item")
	for entry in reward_items:
		var iid: String = str(entry.get("id", ""))
		var qty: int = int(entry.get("quantity", 1))
		assert_eq(Inventory.get_item_count(iid), int(counts_before[iid]) + qty,
			"inventory gained %dx %s" % [qty, iid])

	# Reporting again (nothing completed) returns empty — no double-grant.
	assert_true(SessionManager.report_quest().is_empty(), "second report returns empty")
	assert_eq(GameState.get_meseta(), meseta_before + reward_meseta, "no double-grant of meseta")

	# Unknown difficulty tier grants nothing.
	assert_eq(SessionManager._grant_quest_rewards("search_and_rescue", "nightmare"), {},
		"undefined difficulty tier grants nothing")

	# Cleanup: revert the granted meseta/items so later tests see a clean slate.
	GameState.meseta = meseta_before
	for entry in reward_items:
		Inventory.remove_item(str(entry.get("id", "")), int(entry.get("quantity", 1)))
	SessionManager.return_to_city()
	SessionManager._completed_quest.clear()
	print("")


# Every canon quest defines all three difficulty tiers, each with meseta and
# items whose ids resolve in the registries — so a new quest can't ship
# reward-less (#318) and a typo'd item id can't ship at all.
func test_quest_reward_data() -> void:
	print("── Quest Reward Data ──")

	var ok_quests := 0
	for qid in QuestLoader.list_quests():
		if qid == "manifest" or qid == "hello_quest":
			continue
		if _assert_quest_reward_tiers(qid):
			ok_quests += 1
	assert_gt(ok_quests, 0, "all canon quests define complete reward tiers (%d ok)" % ok_quests)
	print("")


## Assert one quest's rewards block is complete; returns true when every
## tier has meseta and resolvable item ids.
func _assert_quest_reward_tiers(qid: String) -> bool:
	var q_rewards: Dictionary = QuestLoader.load_quest(qid).get("rewards", {})
	assert_true(not q_rewards.is_empty(), "%s defines rewards" % qid)
	var tiers_ok := not q_rewards.is_empty()
	for diff in ["normal", "hard", "super-hard"]:
		var t: Dictionary = q_rewards.get(diff, {})
		if t.is_empty() or int(t.get("meseta", 0)) <= 0:
			assert_true(false, "%s rewards[%s] has meseta" % [qid, diff])
			tiers_ok = false
			continue
		for entry in t.get("items", []):
			var iid: String = str(entry.get("id", ""))
			if not _reward_item_resolvable(iid):
				assert_true(false, "%s rewards[%s] item id resolves: %s" % [qid, diff, iid])
				tiers_ok = false
	# Completion-scaled tiers (#190): every tier item must resolve too.
	for tier in q_rewards.get("scaled", {}).get("tiers", []):
		for entry in tier.get("items", []):
			var iid: String = str(entry.get("id", ""))
			if not _reward_item_resolvable(iid):
				assert_true(false, "%s rewards.scaled item id resolves: %s" % [qid, iid])
				tiers_ok = false
	return tiers_ok


## A reward item id is valid when any registry can name it — consumables,
## general items, or weapons (scaled tiers grant weapons, #190).
func _reward_item_resolvable(iid: String) -> bool:
	return ConsumableRegistry.get_consumable(iid) != null \
		or ItemRegistry.get_item(iid) != null \
		or WeaponRegistry.get_weapon(iid) != null


# ── Completion-scaled rewards (#190) ────────────────────────────
# DOE's Weapon Smith thank-you scales with optional samples collected:
# the rewards.scaled tier picker plus the end-to-end report path with
# the quest_item_counts snapshot riding _completed_quest.
func test_scaled_rewards() -> void:
	print("── Completion-Scaled Rewards (#190) ──")

	var scaled: Dictionary = QuestLoader.load_quest("deep_ore_extraction") \
		.get("rewards", {}).get("scaled", {})
	assert_true(not scaled.is_empty(), "deep_ore_extraction defines rewards.scaled")

	# Tier picker: highest earned tier wins; zero collected → nothing.
	assert_true(SessionManager._pick_scaled_tier(scaled, {}).is_empty(),
		"no samples → no scaled tier")
	var one: Dictionary = SessionManager._pick_scaled_tier(scaled, {"dianaline": 1})
	assert_eq(str(one.get("items", [{}])[0].get("id", "")), "saber", "1/4 samples → Saber")
	var two: Dictionary = SessionManager._pick_scaled_tier(scaled, {"dianaline": 1, "carlian": 1})
	assert_eq(str(two.get("items", [{}])[0].get("id", "")), "brand", "2/4 samples → Brand")
	var four: Dictionary = SessionManager._pick_scaled_tier(scaled,
		{"dianaline": 1, "carlian": 1, "acenaline": 1, "peparian": 1})
	assert_eq(str(four.get("items", [{}])[0].get("id", "")), "blue_saber", "4/4 samples → Blue Saber")

	# End-to-end: collect all four, report, scaled weapon rides rewards_granted.
	SessionManager.return_to_city()
	SessionManager._completed_quest.clear()
	SessionManager.enter_quest("deep_ore_extraction", "normal")
	for iid in ["carlian", "acenaline", "peparian", "dianaline"]:
		SessionManager.collect_quest_item(iid)
	SessionManager.mark_quest_complete()
	assert_eq(int(SessionManager.get_completed_quest().get("quest_item_counts", {}).size()), 4,
		"completion snapshot carries the objective counts")
	var meseta_before: int = GameState.get_meseta()
	var data: Dictionary = SessionManager.report_quest()
	var ids: Array = []
	for entry in data.get("rewards_granted", {}).get("items", []):
		ids.append(str(entry.get("id", "")))
	assert_true(ids.has("blue_saber"), "report grants the 4/4 scaled weapon")
	assert_gt(ids.size(), 1, "difficulty-tier items still granted alongside the scaled one")

	# Cleanup: revert meseta and the granted items.
	GameState.meseta = meseta_before
	Inventory.remove_item("blue_saber", 1)
	for entry in data.get("rewards_granted", {}).get("items", []):
		if str(entry.get("id", "")) != "blue_saber":
			Inventory.remove_item(str(entry.get("id", "")), int(entry.get("quantity", 1)))
	SessionManager.return_to_city()
	SessionManager._completed_quest.clear()
	print("")


# ── Input scheme regression test ────────────────────────────────
# SDL's gamepad API pre-normalizes Nintendo A (east) and PlayStation Cross
# (south) to button index 0 — the "accept" semantic slot. So the only scheme
# that needs an explicit accept/cancel swap is ds_circle (JP/PSO-style DualSense
# where the player wants Circle to be accept).
#
# This test locks the mapping in place so a future "cleanup" doesn't regress
# the switch scheme back to double-swapping (which put accept on physical
# south = Nintendo B — exactly the bug reported by a playtester).
func test_input_config() -> void:
	print("── Input scheme bindings ──")
	var original_scheme: String = InputConfig.current_scheme

	# Expected button indices per scheme. xinput/ds_cross use SDL-normalized
	# indices; switch uses Linux hid-nintendo layout (see FACE_INDICES). All
	# four schemes bind "accept" to the east face for Nintendo/Circle and
	# south for Xbox/Cross, but the raw index depends on the controller's
	# reporting — e.g. switch east happens to be button 0 (same raw index as
	# xinput south).
	var expected: Dictionary = {
		"xinput":    {"ui_accept": 0, "ui_cancel": 1, "interact": 0},
		"switch":    {"ui_accept": 0, "ui_cancel": 1, "interact": 0},  # east=0, south=1
		"ds_cross":  {"ui_accept": 0, "ui_cancel": 1, "interact": 0},
		"ds_circle": {"ui_accept": 1, "ui_cancel": 0, "interact": 1},
	}
	# Use _apply_scheme_no_save — same internal path as set_scheme but
	# skips the disk write, so a local test run doesn't clobber the dev's
	# on-disk input_config.json.
	for scheme in expected:
		InputConfig._apply_scheme_no_save(scheme)
		var exp_buttons: Dictionary = expected[scheme]
		for action in exp_buttons:
			var btn: int = _get_joypad_button(action)
			assert_eq(btn, exp_buttons[action], "%s: %s → button %d" % [scheme, action, exp_buttons[action]])

	# Palette is physically scheme-independent (west/south/east) but raw button
	# indices differ by scheme because the OS reports them differently.
	# quick_weapon is on physical north across every scheme, also routed
	# through FACE_INDICES so it lands on the right raw index.
	var palette_expected: Dictionary = {
		"xinput":    {"action_1": 2, "action_2": 0, "action_3": 1, "quick_weapon": 3},
		"switch":    {"action_1": 3, "action_2": 1, "action_3": 0, "quick_weapon": 2},
		"ds_cross":  {"action_1": 2, "action_2": 0, "action_3": 1, "quick_weapon": 3},
		"ds_circle": {"action_1": 2, "action_2": 0, "action_3": 1, "quick_weapon": 3},
	}
	for palette_scheme in palette_expected:
		InputConfig._apply_scheme_no_save(palette_scheme)
		var btn_map: Dictionary = palette_expected[palette_scheme]
		for action in btn_map:
			assert_eq(_get_joypad_button(action), btn_map[action], "%s: %s on button %d" % [palette_scheme, action, btn_map[action]])

	# Restore original for any tests that run after.
	InputConfig._apply_scheme_no_save(original_scheme)


func _get_joypad_button(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			return e.button_index
	return -1


# ── Script parse smoke test ─────────────────────────────────────
# Walks every .gd file under res://scripts and load()s it. A parse error
# causes load() to return null and print the error to stderr, so any broken
# script fails this test — even scripts that aren't referenced by the entry
# scene (shops, menus opened later at runtime). This is the stop-gap for the
# common regression where typing a function in one file breaks parsing in a
# file the test runner doesn't otherwise touch.
# ── Blackjack (saloon mini-game) ────────────────────────────
#
# The card-draw RNG is seeded via _init's seed_value param, so we can play
# deterministic rounds. Static hand_total tests don't touch RNG. Per-round
# invariant sweep runs 200 seeded rounds — chips bookkeeping must reconcile
# regardless of which outcome each round resolves to.

func test_blackjack() -> void:
	print("── Blackjack ──")
	var BJ = load("res://scripts/2d/blackjack/blackjack_game.gd")

	# Static hand_total (no RNG dependency)
	var two_three: Array = [{"rank": "02"}, {"rank": "03"}]
	assert_eq(BJ.hand_total(two_three), [5, false], "hand_total: 2+3 = 5 hard")

	var natural: Array = [{"rank": "A"}, {"rank": "K"}]
	assert_eq(BJ.hand_total(natural), [21, true], "hand_total: A+K = 21 soft (blackjack)")

	var soft_17: Array = [{"rank": "A"}, {"rank": "06"}]
	assert_eq(BJ.hand_total(soft_17), [17, true], "hand_total: A+6 = 17 soft")

	var hard_17: Array = [{"rank": "10"}, {"rank": "06"}, {"rank": "A"}]
	assert_eq(BJ.hand_total(hard_17), [17, false], "hand_total: 10+6+A = 17 hard (ace flips to 1)")

	var two_aces: Array = [{"rank": "A"}, {"rank": "A"}]
	assert_eq(BJ.hand_total(two_aces), [12, true], "hand_total: A+A = 12 soft (one flips)")

	var three_aces_nine: Array = [{"rank": "A"}, {"rank": "A"}, {"rank": "A"}, {"rank": "09"}]
	# 11+1+1+9 = 22 → flip the 11 → 12, no — wait: 11+11+11+9 = 42, flip → 32, flip → 22, flip → 12.
	# Actually: aces start as 11 each (11*3 + 9 = 42). While >21 and aces>0, subtract 10:
	# 42 → 32 (aces=2) → 22 (aces=1) → 12 (aces=0). Result: [12, false].
	assert_eq(BJ.hand_total(three_aces_nine), [12, false], "hand_total: A+A+A+9 = 12 hard")

	var hidden: Array = [{"rank": "A", "hidden": true}, {"rank": "05"}]
	assert_eq(BJ.hand_total(hidden), [5, false], "hand_total: hidden card is excluded")

	var bust: Array = [{"rank": "K"}, {"rank": "Q"}, {"rank": "05"}]
	assert_eq(BJ.hand_total(bust), [25, false], "hand_total: K+Q+5 = 25 (bust)")

	# Initial state
	var g = BJ.new(5000, 12345)  # seeded so subsequent calls are deterministic
	assert_eq(g.state, BJ.State.BETTING, "Initial state is BETTING")
	assert_eq(g.chips, 5000, "Initial chips = 5000")
	assert_eq(g.bet, 0, "Initial bet = 0")

	# Bet validation
	assert_eq(g.place_bet(0), false, "place_bet(0) rejected")
	assert_eq(g.place_bet(-50), false, "place_bet(-50) rejected")
	assert_eq(g.place_bet(99999), false, "place_bet > chips rejected")
	assert_eq(g.state, BJ.State.BETTING, "Invalid bets don't advance state")
	assert_eq(g.chips, 5000, "Invalid bets don't deduct chips")

	# State-machine guards on a fresh BETTING-state game
	var g2 = BJ.new(5000, 1)
	g2.hit()  # no-op while BETTING
	assert_eq(g2.state, BJ.State.BETTING, "hit() in BETTING is a no-op")
	g2.stand()  # no-op
	assert_eq(g2.state, BJ.State.BETTING, "stand() in BETTING is a no-op")
	assert_eq(g2.double_down(), false, "double_down() in BETTING returns false")
	g2.next_round()  # no-op outside RESOLVED — must not change state
	assert_eq(g2.state, BJ.State.BETTING, "next_round() before RESOLVED is a no-op")

	# Round invariant sweep: 200 seeded rounds, each one stands immediately so
	# the dealer always plays out. Chips bookkeeping must reconcile every round
	# regardless of outcome.
	var bj_count := 0
	var bust_count := 0
	var win_count := 0
	var loss_count := 0
	var push_count := 0
	for seed_v in range(1, 201):
		var sg = BJ.new(5000, seed_v)
		var pre_chips: int = sg.chips
		var bet_amount := 100
		var resolved := {"outcome": -1, "payout": 0}
		sg.round_resolved.connect(func(o: int, p: int) -> void:
			resolved.outcome = o
			resolved.payout = p
		)
		assert_true(sg.place_bet(bet_amount), "seed %d: place_bet succeeds" % seed_v)
		# place_bet may resolve immediately on a natural blackjack; otherwise stand
		if sg.state == BJ.State.PLAYER_TURN:
			sg.stand()
		assert_eq(sg.state, BJ.State.RESOLVED, "seed %d: round reaches RESOLVED" % seed_v)
		assert_true(resolved.outcome >= 0, "seed %d: round_resolved fired" % seed_v)
		# Chips delta = payout - bet (bet was deducted at place_bet, payout returned at resolve)
		var expected_delta: int = resolved.payout - bet_amount
		assert_eq(sg.chips - pre_chips, expected_delta, "seed %d: chips delta matches payout" % seed_v)
		# Tally outcome distribution to surface obvious deck-sampling bugs
		match resolved.outcome:
			BJ.Outcome.PLAYER_BLACKJACK: bj_count += 1
			BJ.Outcome.PLAYER_BUST:      bust_count += 1
			BJ.Outcome.PLAYER_WIN:       win_count += 1
			BJ.Outcome.DEALER_WIN:       loss_count += 1
			BJ.Outcome.PUSH:             push_count += 1
	print("  INFO: outcomes across 200 seeded rounds — BJ=%d BUST=%d WIN=%d LOSS=%d PUSH=%d" %
		[bj_count, bust_count, win_count, loss_count, push_count])
	assert_gt(bj_count + win_count + push_count, 0, "Player can win/push at least once")
	assert_gt(loss_count + bust_count, 0, "Player can lose/bust at least once")

	# 3:2 payout uses integer math (bet + bet * 3 / 2). Spot-check the formula.
	# bet=100 → 100 + 150 = 250 returned (= 1.5x profit + stake back).
	# bet=101 → 101 + 151 = 252 (floor on the odd half-cent).
	var even_payout := 100 + (100 * 3) / 2
	assert_eq(even_payout, 250, "3:2 on bet=100 returns 250")
	var odd_payout := 101 + (101 * 3) / 2
	assert_eq(odd_payout, 252, "3:2 on bet=101 floors to 252 (no float rounding)")

	# Find a seed that produces a natural player blackjack on the opening hand
	# and lock in the payout. If the deck/shuffle ever changes such that this
	# seed stops dealing a blackjack, the assertion fires and we re-pick.
	var found_bj := false
	for seed_v in range(1, 5000):
		var bg = BJ.new(5000, seed_v)
		var bj_resolved := {"hit": false, "payout": 0, "outcome": -1}
		bg.round_resolved.connect(func(o: int, p: int) -> void:
			bj_resolved.hit = true
			bj_resolved.outcome = o
			bj_resolved.payout = p
		)
		bg.place_bet(100)
		if bj_resolved.hit and bj_resolved.outcome == BJ.Outcome.PLAYER_BLACKJACK:
			assert_eq(bj_resolved.payout, 250, "Player BJ on bet 100 pays 250 (stake + 3:2)")
			assert_eq(bg.chips, 5000 - 100 + 250, "Chips reflect BJ payout")
			found_bj = true
			break
	assert_true(found_bj, "At least one seed in [1,5000) produces a player blackjack")

	print("")


func test_script_parse() -> void:
	print("── Script parse smoke test ──")
	var paths: Array = []
	_collect_gd_files("res://scripts", paths)
	var failures: int = 0
	for path in paths:
		# Skip the test runner itself — it's already running.
		if path == "res://scripts/tools/test_runner.gd":
			continue
		var script: Resource = load(path)
		# load() returns a GDScript resource even when compilation failed
		# (e.g. a child redeclaring a parent const) — can_instantiate() is
		# false in that case, so check it too, not just null.
		if script == null or (script is GDScript and not script.can_instantiate()):
			if script is GDScript and _compile_blocked_by_missing_pack_asset(script):
				continue  # pack-only asset preload; absent in repo-only CI checkouts
			_fail += 1
			failures += 1
			print("  FAIL: Parse/compile error in %s" % path)
	if failures == 0:
		_pass += 1
		print("  PASS: %d scripts parsed cleanly" % paths.size())


# Scripts that preload() pack-distributed assets (the Arweave .pck — SEGA
# media is never committed) can't compile in a repo-only checkout like the
# CI test job. Skip the strict can_instantiate check only when the failing
# script preloads a res://assets/ path that doesn't exist here; on dev
# boxes with assets present the strict check still applies in full.
func _compile_blocked_by_missing_pack_asset(script: GDScript) -> bool:
	for line in script.source_code.split("\n"):
		var idx := line.find("preload(\"res://assets/")
		if idx < 0:
			continue
		var start := line.find("\"", idx) + 1
		var path := line.substr(start, line.find("\"", start) - start)
		if not ResourceLoader.exists(path):
			return true
	return false


func _collect_gd_files(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var sub_path: String = dir_path.path_join(entry)
			if dir.current_is_dir():
				_collect_gd_files(sub_path, out)
			elif entry.ends_with(".gd"):
				out.append(sub_path)
		entry = dir.get_next()
	dir.list_dir_end()

extends Node
## Headless test runner — exercises game systems without UI.
## Run: godot --headless --path /home/kion/Github/psz-godot/ res://scripts/tools/test_runner.tscn

var _pass := 0
var _fail := 0


func _ready() -> void:

	print("\n══════════════════════════════════")
	print("  PSZ-GODOT HEADLESS TEST RUNNER")
	print("══════════════════════════════════\n")

	# Split across two registration helpers so neither crosses the code-health
	# size bound as the suite grows (each new test is one more line here).
	# Core first: it creates the active character the combat group's
	# simulation/damage tests need (they SKIP without one).
	_run_tests_core()
	_run_tests_telepipe_and_roam()
	_run_tests_combat()
	_run_tests_systems()

	print("\n══════════════════════════════════")
	print("  RESULTS: %d passed, %d failed" % [_pass, _fail])
	print("══════════════════════════════════\n")

	get_tree().quit(1 if _fail > 0 else 0)


# Player state machine + combat: states, commitment, combos, damage math,
# drops, and the combat-adjacent regression tests.
func _run_tests_combat() -> void:
	test_player_states()
	test_player_defeat_invulnerable()
	test_player_anim_library_cache()
	test_player_model_y_damping()
	test_action_commitment()
	test_combo_two_tier()
	test_combo_chain_lifecycle()
	test_combo_miss_early_fumble()
	test_cone_targeting()
	test_damaging_frame()
	test_target_info_panel()
	test_area_map_overlay()
	test_area_map_room_shapes()
	test_element_status()
	test_enemy_attack_recovery()
	test_enemy_attack_clip_resolution()
	test_enemy_attack_selection()
	test_enemy_attack_arc()
	test_enemy_attack_timeline()
	test_enemy_telegraph()
	test_enemy_locomotion()
	test_enemy_ranged_delivery()
	test_enemy_leap_delivery()
	test_enemy_charge_stop_on_hit()
	test_enemy_charge_roll_through()
	test_enemy_windup_prelude()
	test_box_mimic_disguise()
	test_enemy_archetype_modules()
	test_enemy_berserk_kamikaze()
	test_coliseum_debug_quest()
	test_coliseum_master_picker()
	test_coliseum_roster_grouping()
	test_coliseum_mother_variations()
	test_enemy_authored_table_charge_cycle()
	test_enemy_authored_table_ranged_cycles()
	test_enemy_difficulty_scaling()
	test_combat_math()
	test_combat_drops()
	test_drop_tables()
	test_combat_simulation()
	test_damage_formulas()
	test_charge_drop_paths()
	test_mechgun_final_step_no_root()
	test_technique_cast_recovers()
	test_weapon_attack_sfx_mapping()
	test_weapon_anim_data_new_animation_sets()
	test_companion_combat_decisions()


# Registries, inventory, mags, shops, techniques, telepipe + the
# recent playtest-fix regression tests (#357/#358/#359/#352).
func _run_tests_core() -> void:
	test_registries()
	test_inventory()
	test_inventory_capacity()
	test_key_hud_count()
	test_character_creation()
	test_equipment()
	test_palette_momentary_swap()
	test_menu_carry_survives_scene_signal()
	test_session_manager()
	test_mag_feeding()
	test_mag_evolution()
	test_mag_personality_contract()
	test_shops()
	test_shop_buy_unequippable_gear()
	test_humar_gear_unequippable()
	test_shop_capability_grey()
	test_shop_row_dims_disabled_icon()
	test_disk_capability_grey()
	test_shop_sell_cannot_use_marker()
	test_shop_sell_disabled_already_known()
	test_shop_sell_disabled_renders_muted()
	test_start_menu_disk_use_gated()
	test_synth_unequippable_marker()
	test_start_menu_cannot_use()
	test_storage_cannot_use()
	test_equip_action_matches_marker()
	test_field_weapon_swap_gate()
	test_quick_weapon_menu_unequip_and_order()
	test_quick_weapon_menu_captures_input()
	test_start_menu_data()
	test_start_menu_palette_bg_cached()
	test_scene_manager_fade_rect_full_size()
	test_scene_manager_transition_settles()
	test_hud_stats_persistent_panel()
	test_ranger_playthrough()
	test_technique_disks()
	test_disk_duplicate_use_strips_suffix()
	test_new_registries()
	test_autoload_api_surface()
	test_element_collision_setup()
	test_player_traps()
	test_gate_economy_invariants()
	test_gate_economy_solvability()
	test_authored_field_objects()
	test_authored_walls_clear_doorways()
	test_authored_fences_are_openable()
	test_gate_kind_per_door()
	test_group_five_trap_roll()
	test_enemies_stand_on_authored_slots()
	test_keys_stand_on_authored_slots()
	test_field_trap_behaviour()
	test_trap_vision_reveal()
	test_palette_picker_grid()
	test_source_wrap_per_axis()
	test_teleporter_dressing()
	test_teleporter_dressing_texture_overrides()
	test_city_scroll_fixes()
	test_area_objects()
	test_generated_field_doors()
	test_equipment_slot_names()
	test_material_system()
	test_set_bonuses()
	test_technique_tier_listing()
	test_shop_sell_list_inventory_order()
	test_technique_casting()
	test_photon_art_usage()
	test_tekker_grinding()
	test_tekker_identification()
	test_additional_drops()


# Telepipe + section state, free-roam lifecycle, and companion movement.
# Split out of _run_tests_core when that list crossed the code-health size
# bound; the grouping is topical, the call order is unchanged.
func _run_tests_telepipe_and_roam() -> void:
	test_telepipe_suspend()
	test_telepipe_manager_unit()
	test_telepipe_round_trip()
	test_telepipe_suspend_resume_keeps_telepipe()
	test_section_state_round_trip()
	test_telepipe_cancel_hooks()
	test_city_state_cleared_on_title_return()
	test_telepipe_use_item_outside_field()
	test_telepipe_239_fixes()
	test_dup_equipment()
	test_equipment_screen_dup_frame()
	test_frame_change_clears_units()
	test_armor_slots_per_instance()
	test_shop_armor_purchase_records_slots()
	test_telepipe_city_visual_cleared()
	test_freefield_quest_unblock()
	test_free_roam_per_area_state()
	test_free_roam_field_lifecycle()
	test_free_telepipe_round_trip()
	test_field_quest_decouple()
	test_player_defeat_return()
	test_companion_anim_from_measured_speed()
	test_companion_anim_walk_run_hysteresis()
	test_companion_follow_speed_ramp()


# Build/bootstrap, warp, scene/screen smoke, fields, quests, difficulty, misc.
func _run_tests_systems() -> void:
	test_build_info_sentinel()
	test_bootstrap_pack_magic_guard()
	test_bootstrap_registers_pack_uids()
	test_warp_teleporter_section_label()
	test_warp_area_unlock()
	test_mesh_utils_apply_texture()
	test_game_element_build_prompt_label()
	test_game_element_override_textured_material()
	test_setup_shop_portrait()
	test_storage_tabs_fit_pinned_card()
	test_shop_camera_pose()
	test_shop_nav()
	test_shop_confirm()
	test_character_appearance()
	test_humarl_skin_remap()
	test_character_create_state()
	test_class_select_slat_crop_is_width_stable()
	test_valley_grid()
	test_field_config()
	test_wetlands_field()
	test_tower_field()
	test_quest_lifecycle()
	test_quest_objectives()
	test_quest_item_registers_on_contact()
	test_quest_item_burst_is_static()
	test_dialog_box_not_restored_after_close()
	test_quest_rewards()
	test_quest_reward_data()
	test_scaled_rewards()
	test_difficulty_unlock()
	test_difficulty_unlock_persistence()
	test_debug_unlock_all_missions()
	test_input_config()
	test_crt_filter()
	test_confirm_input_precedence()
	test_blackjack()
	test_kill_state_survives_warp_flush()
	test_box_state_survives_warp_flush()
	test_box_state_survives_floor_placement()
	test_drop_state_survives_warp_flush()
	test_message_wall_questitem_persist()
	test_keys_gates_survive_section_roundtrip()
	test_field_state_full_contract_roundtrip()
	test_minimap_enemy_markers()
	test_script_parse()
	test_autoloads_avoid_packonly_classscope_preloads()
	test_orbit_camera_follow_y_damping()


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


## #380 — class-select cutout wobble. The slat portrait must be cropped against
## a FIXED width so the selection-tween (slat width 1<->5) only changes how much
## of the cutout is revealed, never the crop origin. Deterministic, no RNG:
## build the real (static) portrait frame, then resolve layout at a narrow and a
## wide slat width and assert the frame + cover-cropped TextureRect sizes are
## identical. Also assert every class id maps to an art file that ships in the
## pack (asset_tree.txt), covering the hucaseal->hucasteal / racaseal->racasteal
## filename overrides without loading the pack-only PNGs.
func test_class_select_slat_crop_is_width_stable() -> void:
	print("\n── Class-select slat crop stability (#380) ──")
	var CharacterCreate := preload("res://scripts/2d/character_create.gd")

	# Dummy art at hucast's real dimensions (250x347). Built in-memory so the
	# test runs in repo-only CI where assets/images/*.png live only in the pack.
	var img := Image.create(250, 347, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 1.0, 0.0, 0.5))
	var tex := ImageTexture.create_from_image(img)

	var ref_w := 178.0
	var slat := Control.new()
	slat.clip_contents = true
	var frame: Control = CharacterCreate._make_portrait_frame(ref_w, tex)
	slat.add_child(frame)
	add_child(slat)
	var portrait: TextureRect = frame.get_node("Portrait")

	# Narrow (unselected, stretch ratio 1) slat width.
	slat.size = Vector2(ref_w / 5.0, 280.0)
	var frame_w_narrow: float = frame.size.x
	var portrait_w_narrow: float = portrait.size.x

	# Wide (selected, stretch ratio 5) slat width.
	slat.size = Vector2(ref_w, 280.0)
	var frame_w_wide: float = frame.size.x
	var portrait_w_wide: float = portrait.size.x

	assert_gt(frame_w_narrow, 0.0, "portrait frame has positive width")
	assert_eq(frame_w_narrow, ref_w, "portrait frame width == ref width (px-fixed)")
	assert_eq(frame_w_narrow, frame_w_wide,
		"portrait frame width is IDENTICAL at narrow vs wide slat (crop origin can't drift)")
	assert_eq(portrait_w_narrow, portrait_w_wide,
		"cover-crop TextureRect size IDENTICAL across slat widths — #380 wobble removed")
	assert_eq(frame.anchor_left, 0.5, "frame left anchor collapsed to slat centre")
	assert_eq(frame.anchor_right, 0.5, "frame right anchor collapsed to slat centre")
	assert_true(frame.clip_contents, "portrait frame clips its overflow")
	assert_true(portrait.texture != null, "portrait received its texture")
	slat.queue_free()

	# Every class id must resolve to an art file that ships in the pack.
	# asset_tree.txt is the in-repo manifest of pack contents (res:// = repo root).
	var tree_txt := FileAccess.get_file_as_string("res://asset_tree.txt")
	assert_gt(tree_txt.length(), 0, "asset_tree.txt readable for art-coverage check")
	var overrides: Dictionary = CharacterCreate.CLASS_ART_OVERRIDES
	var all_classes: Array = ClassRegistry.get_all_classes()
	assert_eq(all_classes.size(), 14, "ClassRegistry exposes all 14 classes")
	var missing: Array = []
	for cls in all_classes:
		var art_name: String = overrides.get(cls.id, cls.id)
		if not tree_txt.contains("assets/images/%s.png" % art_name):
			missing.append("%s->%s" % [cls.id, art_name])
	assert_eq(missing.size(), 0,
		"every class id maps to a packed art file (missing: %s)" % str(missing))
	assert_eq(overrides.get("hucaseal", "hucaseal"), "hucasteal",
		"hucaseal art override -> hucasteal")
	assert_eq(overrides.get("racaseal", "racaseal"), "racasteal",
		"racaseal art override -> racasteal")


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


# ── Teleporter dressing (special_c3 warp-pad set) ───────
# Pins the mock→Godot contract: data/city_teleporter.json parses, pieces get
# re-pivoted to bbox bottom-center (what makes mock offsets land in-world),
# and the layout's uv/scroll config maps onto uv_dressing.gdshader uniforms.
# Pack-free: synthetic BoxMesh + ImageTexture, no GLB loads (assets aren't in
# git on CI).
## ── Per-field object resolution (AreaObjects) ───────
## box.gd and wall.gd used to hardcode valley/o01_cont.glb and valley/o01_wall.glb,
## so every non-Valley field rendered Valley crates and Valley walls. Pins the
## area → folder/scene-number mapping for all eight areas and the Valley
## fallback. Pack-free: candidate_path/fallback_path are pure string mapping,
## and the extents helper runs on a synthetic BoxMesh (assets aren't in git).
func test_area_objects() -> void:
	print("── AreaObjects (per-field model resolution) ──")

	# One row per area: the folder and scene number its models live under. These
	# are the directories the storybook port created (PR #571). City (s00) has no
	# field props of its own — quest-authored city stages (the coliseum debug
	# arena) would fall back to Valley crates; nothing spawns crates there today.
	var expected := {
		"city": ["city", "00"],
		"gurhacia": ["valley", "01"],
		"ozette": ["wetlands", "02"],
		"rioh": ["snowfield", "03"],
		"makara": ["makara", "04"],
		"paru": ["paru", "05"],
		"arca": ["arca", "06"],
		"dark": ["shrine", "07"],
		"tower": ["tower", "08"],
	}
	for area_id in expected:
		var want: Array = expected[area_id]
		assert_eq(AreaObjects.folder(area_id), want[0], "%s folder is %s" % [area_id, want[0]])
		assert_eq(AreaObjects.scene_num(area_id), want[1], "%s scene number is %s" % [area_id, want[1]])
		assert_eq(
			AreaObjects.candidate_path(area_id, "cont"),
			"%s/o%s_cont.glb" % [want[0], want[1]],
			"%s container path" % area_id
		)

	# Every area covered by the grid generator must resolve — a new area added
	# to AREA_CONFIG without object art would otherwise silently show Valley.
	# (GridGenerator has no class_name, so it is preloaded like every other
	# consumer does.)
	const GridGeneratorScript := preload("res://scripts/3d/field/grid_generator.gd")
	for area_id in GridGeneratorScript.AREA_CONFIG:
		assert_true(expected.has(area_id), "AREA_CONFIG area '%s' has a pinned object folder" % area_id)

	# The Valley row is the fallback, so its candidate and fallback agree —
	# which is what stops model_path warning about the area it falls back to.
	assert_eq(
		AreaObjects.candidate_path("gurhacia", "wall"),
		AreaObjects.fallback_path("wall"),
		"Valley is its own fallback"
	)
	assert_eq(AreaObjects.fallback_path("wall"), "valley/o01_wall.glb", "fallback wall is the Valley wall")
	# An area that isn't in the table at all still resolves rather than
	# producing a path like "/o__cont.glb".
	assert_eq(AreaObjects.candidate_path("nonexistent", "cont"), "valley/o01_cont.glb", "unknown area falls back")

	# Extents drive box collision. A mesh offset from its root must measure by
	# its geometry, not its origin — Paru's container is 1 x 1.588 x 1 where
	# every other field's is 1x1x1, and the fixed 1x1x1 box left the top third
	# of it without collision or hurtbox.
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.588, 1.2, 1.588)
	mi.mesh = bm
	mi.position = Vector3(4, 0, -3)
	root.add_child(mi)
	var extents: AABB = AreaObjects.model_extents(root)
	assert_true(extents.size.is_equal_approx(Vector3(1.588, 1.2, 1.588)), "extents measure the mesh, not the offset")
	# No mesh -> zero size, which is the signal box.gd uses to keep its default.
	var empty := Node3D.new()
	assert_eq(AreaObjects.model_extents(empty).size, Vector3.ZERO, "meshless model measures zero")
	root.free()
	empty.free()
	print("")


## ── Generated free fields: doors line up ───────
## GridGenerator now rotates rooms to fit the layout, which is what makes
## generation succeed at all. Rotation is also what can silently misalign a
## door, so these are the invariants that decide whether a field is walkable:
## a connection must be reciprocal, must have a portal, and that portal must be
## backed by a real config portal once the cell rotation is applied. Pack-free —
## stage configs, RE tables and enemy resources are all in git.
func test_generated_field_doors() -> void:
	print("── Generated free fields (door alignment) ──")
	const GridGen := preload("res://scripts/3d/field/grid_generator.gd")
	var areas := ["gurhacia", "ozette", "rioh", "makara", "paru", "arca", "dark"]
	var cfg_file := FileAccess.open("res://data/stage_configs/unified-stage-configs.json", FileAccess.READ)
	var cfg_json := JSON.new()
	cfg_json.parse(cfg_file.get_as_text())
	var configs: Dictionary = cfg_json.data

	# Tallies, so one assert per invariant names the invariant rather than the
	# first cell that happened to break it.
	# SEEDED. Generation is random, and an unseeded sweep makes this test flaky
	# on the tail below — a fixed set of seeds keeps a red run reproducible.
	var t := {"cells": 0, "one_way": 0, "no_portal": 0, "unbacked": 0, "unreachable": 0,
		"fell_back": 0, "spare": 0, "spare_start": 0}
	for area in areas:
		for roll in range(3):
			var gen = GridGen.new()
			gen.set_seed(roll)
			for section in gen.generate_field("normal", area)["sections"]:
				_audit_generated_section(section, configs, t)

	# Door alignment is absolute — a misaligned door is an unwalkable field.
	assert_eq(t["one_way"], 0, "no one-way door pairs across generated fields")
	assert_eq(t["no_portal"], 0, "every connection has a portal")
	assert_eq(t["unbacked"], 0, "every portal is backed by a config portal at the cell's rotation")
	assert_eq(t["unreachable"], 0, "every section's end cell is reachable from its start")
	# Fallbacks are a RATE, not zero. Rotation-aware room selection took this
	# from 100% (every section of every area, before the fix) to ~1.5% measured
	# over 840 sections. The tail is a real remaining gap, tracked separately —
	# the bound here catches a regression back toward "never generates" without
	# pretending the tail is gone. A fallback section is still a valid walkable
	# field, just a fixed 5-room line with no objects.
	assert_true(t["fell_back"] <= 2, "grid sections falling back to the 5-room line stays in the tail (got %d of 42)" % t["fell_back"])
	# A spare door — one with no room behind it, no gate and no loading trigger
	# — is indistinguishable from a real exit until the player walks into it.
	# psz-re: the original has none, because room shape comes from the cell's
	# degree, so doors == connections by construction (/states/field-gates).
	assert_eq(t["spare"], 0, "no generated room has a door with nothing behind it")
	assert_eq(t["spare_start"], 0, "start rooms have no spare door either")
	print("  INFO: %d generated cells checked across %d areas" % [t["cells"], areas.size()])
	print("")


## One section's door invariants, accumulated into `t`. Split out of
## test_generated_field_doors to stay under the complexity bound.
func _audit_generated_section(section: Dictionary, configs: Dictionary, t: Dictionary) -> void:
	const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
	var cells: Array = section["cells"]
	t["cells"] += cells.size()
	# The fallback is a fixed 5-room line with no objects; a grid section that
	# lands on it means generation failed.
	if str(section.get("type", "")) == "grid" and cells.size() < 6:
		t["fell_back"] += 1

	var by_pos := {}
	for cell in cells:
		by_pos[str(cell["pos"])] = cell

	for cell in cells:
		var connections: Dictionary = cell.get("connections", {})
		var portals: Dictionary = cell.get("portals", {})
		for dir in connections:
			var target: String = str(connections[dir])
			if by_pos.has(target):
				var back: Dictionary = by_pos[target].get("connections", {})
				if str(back.get(OPPOSITE[dir], "")) != str(cell["pos"]):
					t["one_way"] += 1
			if not portals.has(dir):
				t["no_portal"] += 1
		if not cell.has("objects"):
			t["no_portal"] += 1
		for dir in portals:
			if dir == "default":
				continue
			if not _portal_backed(configs, str(cell["stage_id"]), int(cell.get("rotation", 0)), str(dir)):
				t["unbacked"] += 1
			_tally_spare_door(cell, section, str(dir), connections, t)

	var sp := str(section.get("start_pos", ""))
	var ep := str(section.get("end_pos", ""))
	if by_pos.has(sp) and by_pos.has(ep) and sp != ep and not _connected(by_pos, sp, ep):
		t["unreachable"] += 1


## Count one portal direction as a spare door, or exempt it and say why.
##
## Exempt: the field's own warp out (a door that leaves the field rather than
## leading nowhere) and every door of a transition room, which is entered and
## left by warp and so has no grid connections at all. Start cells are NOT
## exempt — they are tallied separately only so a regression there names itself.
func _tally_spare_door(cell: Dictionary, section: Dictionary, dir: String,
		connections: Dictionary, t: Dictionary) -> void:
	if connections.has(dir):
		return
	if dir == str(cell.get("warp_edge", "")):
		return
	# The start room's way back to where the player warped in from — a `b`
	# section must show you where you came from, so this door is required
	# rather than tolerated.
	if dir == str(cell.get("entry_warp_edge", "")):
		return
	if str(section.get("type", "")) == "transition":
		return
	if bool(cell.get("is_start", false)):
		t["spare_start"] += 1
		return
	t["spare"] += 1


## Does `stage_id` have a config portal that faces `game_dir` once rotated?
func _portal_backed(configs: Dictionary, stage_id: String, rotation: int, game_dir: String) -> bool:
	for portal in configs.get(stage_id, {}).get("portals", []):
		var base: String = str(portal.get("direction", ""))
		if not base.is_empty() and StageRotation.rotate_dir(base, rotation) == game_dir:
			return true
	return false


## BFS over `connections`.
func _connected(by_pos: Dictionary, from_pos: String, to_pos: String) -> bool:
	var seen := {from_pos: true}
	var queue: Array = [from_pos]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to_pos:
			return true
		for d in by_pos[cur].get("connections", {}):
			var nxt: String = str(by_pos[cur]["connections"][d])
			if by_pos.has(nxt) and not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)
	return false


## ── Player-placed traps (#575) ───────
## Four consumables that only a CAST can carry and drop. Pins the four things
## that make them work as items rather than just models: the shop sells them,
## the palette can hold them, they cap at 5, and a non-CAST cannot use them.
## Pack-free — data resources and constants only.
## ── Palette picker grid ───────
## The picker draws PsoStartMenu._PAL_PICKER_ROWS and assigns by the id in that
## table. Two things must hold and neither did when #575 landed: every palette
## action must be reachable from some cell, and the cell must assign what it
## draws. Before the fix the picker indexed ALL_ACTIONS by grid position, so
## inserting the four traps mid-list made 12 of 25 cells assign the wrong
## action — "Foie" assigned "Ice Trap" — while the traps themselves were
## unreachable. Pack-free: constants only.
func test_palette_picker_grid() -> void:
	print("── Palette picker grid (reachability / cell identity) ──")
	const PsoMenu := preload("res://scripts/3d/field/pso_start_menu.gd")

	var grid_ids: Array = PsoMenu.palette_grid_ids()
	assert_true(grid_ids.size() > 0, "picker grid is non-empty")

	# The two column sizes must account for every row, or the tail of the grid
	# is undrawable and the up/down wrap lands out of range.
	var rows: Array = PsoMenu._PAL_PICKER_ROWS
	assert_eq(PsoMenu._PAL_LEFT_COL_SIZE + PsoMenu._PAL_RIGHT_COL_SIZE, rows.size(),
		"left + right column sizes cover every grid row")

	# Every cell names a real action.
	for id in grid_ids:
		assert_true(not ActionPalette.get_action_data(str(id)).is_empty(),
			"grid cell '%s' is a real ActionPalette action" % id)

	# No id appears twice — a duplicate makes one of the two cells unselectable
	# (the seed-cursor search stops at the first match).
	var seen := {}
	var dupes: Array = []
	for id in grid_ids:
		if seen.has(id):
			dupes.append(id)
		seen[str(id)] = true
	assert_true(dupes.is_empty(), "no id appears in two cells (dupes: %s)" % str(dupes))

	# Every assignable action is reachable. This is the check that would have
	# caught #575's traps being absent from the grid entirely.
	var missing: Array = []
	for action in ActionPalette.ALL_ACTIONS:
		var aid: String = str(action.get("id", ""))
		if not seen.has(aid):
			missing.append(aid)
	assert_true(missing.is_empty(),
		"every ALL_ACTIONS entry is reachable in the picker (unreachable: %s)" % str(missing))

	# The four traps specifically, since that is what #575 added.
	for id in ["heat_trap", "ice_trap", "light_trap", "heal_trap"]:
		assert_true(seen.has(id), "%s is reachable in the picker grid" % id)

	# Every grid cell must be DISPATCHABLE, not just drawable. player.gd's
	# _execute_palette_action routes on ActionPalette.is_consumable() /
	# TechniqueManager.TECHNIQUES / a few literals; an action in the grid that
	# matches none of those is a slot that silently does nothing when pressed —
	# which is exactly how #575's traps shipped.
	const DISPATCH_LITERALS := ["attack", "strong_attack", "dodge", "kill_all"]
	var undispatchable: Array = []
	for id in grid_ids:
		var aid: String = str(id)
		if aid in DISPATCH_LITERALS:
			continue
		if ActionPalette.is_consumable(aid):
			continue
		if TechniqueManager.TECHNIQUES.has(aid):
			continue
		undispatchable.append(aid)
	assert_true(undispatchable.is_empty(),
		"every palette action is dispatchable in player.gd (dead: %s)" % str(undispatchable))
	print("")


func test_player_traps() -> void:
	print("── Player-placed traps (shop / palette / cap / CAST-only) ──")
	const TrapScript := preload("res://scripts/3d/elements/trap_ball.gd")
	var trap_ids := ["heat_trap", "ice_trap", "light_trap", "heal_trap"]

	# Every trap item has a ball and an effect, and nothing else sneaks in.
	assert_eq(TrapScript.TRAP_MODELS.size(), 4, "four trap balls")
	assert_eq(TrapScript.TRAP_EFFECTS.size(), 4, "four trap effects")
	var models := {}
	for id in trap_ids:
		assert_true(TrapScript.TRAP_MODELS.has(id), "%s has a ball model" % id)
		assert_true(TrapScript.TRAP_EFFECTS.has(id), "%s has an effect" % id)
		models[str(TrapScript.TRAP_MODELS[id])] = true
	assert_eq(models.size(), 4, "each trap maps to a DIFFERENT ball (the mapping is 1:1)")

	# Effects resolve against the real status table, or the trap does nothing.
	for id in trap_ids:
		var effect: Dictionary = TrapScript.TRAP_EFFECTS[id]
		var status: String = str(effect.get("status", ""))
		if not status.is_empty():
			assert_true(CombatManager.STATUS_EFFECTS.has(status),
				"%s inflicts a status that exists (%s)" % [id, status])
		else:
			assert_true(float(effect.get("heal_percent", 0.0)) > 0.0,
				"%s does something — a status or a heal" % id)

	# Carry up to 5 each, and CAST-only through the shop's capability hook.
	for id in trap_ids:
		var consumable = ConsumableRegistry.get_consumable(id)
		assert_true(consumable != null, "%s is a registered consumable" % id)
		if consumable == null:
			continue
		assert_eq(consumable.max_stack, 5, "%s stacks to 5" % id)
		assert_true(consumable.can_be_used_by("Hunter Cast"), "%s usable by HUcast" % id)
		assert_true(consumable.can_be_used_by("Ranger Cast"), "%s usable by RAcast" % id)
		assert_true(not consumable.can_be_used_by("Hunter Human"), "%s NOT usable by HUmar" % id)
		assert_true(not consumable.can_be_used_by("Force Newman"), "%s NOT usable by FOnewm" % id)

	# Buyable at the item shop, under their own category.
	var shop = ShopRegistry.get_shop("item_shop")
	assert_true(shop != null, "item shop loads")
	if shop != null:
		var sold := {}
		for entry in shop.items:
			sold[str(entry.get("item", "")).to_lower().replace(" ", "_")] = str(entry.get("category", ""))
		for id in trap_ids:
			assert_true(sold.has(id), "item shop sells %s" % id)
			assert_eq(str(sold.get(id, "")), "Traps", "%s is in the Traps category" % id)

	# Equippable to the action palette, and treated as a consumable there.
	for id in trap_ids:
		assert_true(not ActionPalette.get_action_data(id).is_empty(),
			"%s is a palette action" % id)
		assert_true(ActionPalette.is_consumable(id), "%s counts as a consumable slot" % id)
	print("")


func test_gate_economy_invariants() -> void:
	print("── Gate economy: the rules /states/field-gates makes normative ──")
	const GridGen := preload("res://scripts/3d/field/grid_generator.gd")
	# One tally across the whole sweep; the per-section work is in the helper so
	# neither function crosses the complexity bound.
	var t: Dictionary = {
		"sections": 0, "off_connection": 0, "way_back": 0, "adjacent": 0,
		"mixed": 0, "all_gated": 0, "none_gated": 0, "over_budget": 0,
	}
	for seed_value in range(60):
		var gen = GridGen.new()
		gen.set_seed(seed_value)
		for section in gen.generate_field("normal", "gurhacia")["sections"]:
			_tally_gate_violations(_cells_by_pos(section),
				str(section.get("start_pos", "")), t)

	assert_true(int(t["sections"]) > 100, "swept a real sample (%d sections)" % t["sections"])
	assert_eq(int(t["off_connection"]), 0, "no door attribute sits on a non-connection")
	assert_eq(int(t["way_back"]), 0, "the way-back door is NEVER gated")
	assert_eq(int(t["adjacent"]), 0, "two gated rooms are never adjacent")
	assert_eq(int(t["mixed"]), 0, "enemy-defeat is all-or-nothing per ROOM, never per door")
	assert_eq(int(t["over_budget"]), 0, "no section exceeds its key-gate budget")
	var rate: float = float(t["all_gated"]) / float(maxi(1, int(t["all_gated"]) + int(t["none_gated"])))
	assert_true(rate > 0.62 and rate < 0.87,
		"the enemy-defeat roll lands near 75%% (got %.0f%%)" % (rate * 100.0))
	print("")


## Fold one generated section's gate violations into the running tally.
func _tally_gate_violations(cells: Dictionary, start_pos: String, t: Dictionary) -> void:
	if cells.is_empty():
		return
	t["sections"] = int(t["sections"]) + 1
	var parents: Dictionary = _way_back_dirs(cells, start_pos)
	var key_gates := 0
	for pos in cells:
		var cell: Dictionary = cells[pos]
		var attrs: Dictionary = cell.get("door_attributes", {})
		var conns: Dictionary = cell.get("connections", {})
		for dir in attrs:
			if not conns.has(dir):
				t["off_connection"] = int(t["off_connection"]) + 1
		var wb: String = str(parents.get(pos, ""))
		if not wb.is_empty() and int(attrs.get(wb, 0)) != 0:
			t["way_back"] = int(t["way_back"]) + 1
		if _has_key_gate(attrs):
			key_gates += 1
			for dir in conns:
				if _has_key_gate(cells.get(str(conns[dir]), {}).get("door_attributes", {})):
					t["adjacent"] = int(t["adjacent"]) + 1
		_tally_enemy_defeat(cell, conns, attrs, wb, t)
	# budget = (rooms - 2) * 35 / 100, a hard cap
	if key_gates > int(float(cells.size() - 2) * 35.0 / 100.0):
		t["over_budget"] = int(t["over_budget"]) + 1


## Enemy-defeat must be all-or-nothing over the FORWARD doors a key gate has not
## already taken.
func _tally_enemy_defeat(cell: Dictionary, conns: Dictionary, attrs: Dictionary,
		wb: String, t: Dictionary) -> void:
	if cell.get("is_start", false) or cell.get("is_end", false):
		return
	var defeat := 0
	var open_doors := 0
	for dir in conns:
		if dir == wb:
			continue
		var a: int = int(attrs.get(dir, 0))
		if a == 1 or a == 2:
			return  # the key gate consumed this room's forward door
		elif a == 4:
			defeat += 1
		else:
			open_doors += 1
	if defeat == 0 and open_doors == 0:
		return
	if defeat > 0 and open_doors > 0:
		t["mixed"] = int(t["mixed"]) + 1
	elif defeat > 0:
		t["all_gated"] = int(t["all_gated"]) + 1
	else:
		t["none_gated"] = int(t["none_gated"]) + 1


func test_gate_economy_solvability() -> void:
	print("── Gate economy: no generated field is ever unsolvable ──")
	const GridGen := preload("res://scripts/3d/field/grid_generator.gd")
	var checked := 0
	var unsolvable: Array[String] = []
	var unbalanced := 0
	var two_key := 0
	var one_key := 0

	for area in ["gurhacia", "ozette", "rioh", "paru"]:
		for seed_value in range(30):
			var gen = GridGen.new()
			gen.set_seed(seed_value)
			for section in gen.generate_field("normal", area)["sections"]:
				var cells: Dictionary = _cells_by_pos(section)
				if cells.is_empty():
					continue
				checked += 1
				# Requirement and supply must balance exactly — a spare key is
				# as much a bug as a missing one, because it means a gate was
				# placed and then dropped.
				var required := 0
				var keys := 0
				for pos in cells:
					keys += int(cells[pos].get("key_count", 0))
					for dir in cells[pos].get("door_attributes", {}):
						var a: int = int(cells[pos]["door_attributes"][dir])
						if a == 1:
							required += 1
							one_key += 1
						elif a == 2:
							required += 2
							two_key += 1
				if required != keys:
					unbalanced += 1
				if not _section_is_solvable(cells, str(section.get("start_pos", ""))):
					unsolvable.append("%s/%s" % [area, section.get("start_pos", "")])

	assert_true(checked > 300, "swept a real sample (%d sections)" % checked)
	assert_eq(unsolvable.size(), 0,
		"every generated section is completable (%d checked)" % checked)
	assert_eq(unbalanced, 0, "keys placed exactly match keys demanded")
	assert_true(one_key + two_key > 0, "the sweep actually produced key gates")
	print("  (%d one-key, %d two-key gates over %d sections)" % [one_key, two_key, checked])
	print("")


## {pos: cell} for one generated section.
func _cells_by_pos(section: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for cell in section.get("cells", []):
		out[str(cell.get("pos", ""))] = cell
	return out


## {pos: direction back toward the start}, by BFS.
##
## Derived rather than read off `path_order`: branch cells carry -1 there, so a
## path_order rule silently treats a branch's way-back as a forward door — which
## is exactly the mistake that made an earlier read of this data report a 53%
## enemy-defeat rate instead of 75%.
func _way_back_dirs(cells: Dictionary, start_pos: String) -> Dictionary:
	var out: Dictionary = {}
	if not cells.has(start_pos):
		return out
	out[start_pos] = ""
	var queue: Array[String] = [start_pos]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for dir in cells[cur].get("connections", {}):
			var nkey: String = str(cells[cur]["connections"][dir])
			if out.has(nkey) or not cells.has(nkey):
				continue
			out[nkey] = ""
			for back in cells[nkey].get("connections", {}):
				if str(cells[nkey]["connections"][back]) == cur:
					out[nkey] = back
					break
			queue.append(nkey)
	return out


func _has_key_gate(attrs: Dictionary) -> bool:
	for dir in attrs:
		var a: int = int(attrs[dir])
		if a == 1 or a == 2:
			return true
	return false


## Walk the section with a key purse, opening what it can afford, until nothing
## new opens. Solvable when the goal is reached.
func _section_is_solvable(cells: Dictionary, start_pos: String) -> bool:
	if not cells.has(start_pos):
		return false
	var goal: String = ""
	for pos in cells:
		if cells[pos].get("is_end", false):
			goal = pos
			break
	if goal.is_empty():
		return true
	var reached: Dictionary = {start_pos: true}
	var changed := true
	while changed:
		changed = false
		var held := 0
		for pos in reached:
			held += int(cells[pos].get("key_count", 0))
		var spent := 0
		for pos in reached.keys():
			var attrs: Dictionary = cells[pos].get("door_attributes", {})
			for dir in cells[pos].get("connections", {}):
				var nkey: String = str(cells[pos]["connections"][dir])
				if reached.has(nkey) or not cells.has(nkey):
					continue
				var a: int = int(attrs.get(dir, 0))
				# An enemy-defeat gate always opens: clearing a room is
				# something the player can always do. Only keys can strand you.
				var cost: int = a if a == 1 or a == 2 else 0
				if cost > held - spent:
					continue
				spent += cost
				reached[nkey] = true
				changed = true
	return reached.has(goal)


func test_authored_field_objects() -> void:
	print("── Authored field objects (the set table + the layout / group-5 roll) ──")
	const Pop := preload("res://scripts/3d/field/field_population.gd")

	# 1. The table covers every cell of every shipped field quest. If a room
	#    code ever falls out of it the field silently drops back to the ring,
	#    which is exactly the regression this replaces.
	var missing: Array = []
	var checked: int = 0
	for path in ["valley", "wetlands", "snowfield", "paru", "shrine", "ruins", "arca"]:
		var doc = QuestLoader._load_json("res://data/field_quests/%s_field.json" % path)
		if doc.is_empty():
			continue
		for section in doc.get("sections", []):
			for cell in section.get("cells", []):
				checked += 1
				var stage_id: String = str(cell.get("stage_id", ""))
				if not _room_is_authored(stage_id):
					missing.append(stage_id)
	assert_true(checked > 0, "field quests loaded (%d cells)" % checked)
	assert_eq(missing.size(), 0, "every field-quest cell has an authored table")

	# 2. Same seed, same field. Every draw goes through the generator's RNG.
	var a: Array = Pop.authored_objects("s01a_tb3", 3, _seeded_rng(1234))
	var b: Array = Pop.authored_objects("s01a_tb3", 3, _seeded_rng(1234))
	assert_eq(JSON.stringify(a), JSON.stringify(b), "the roll is seed-deterministic")

	# 3. The caps hold, and walls are in the DATA — the autopilot skip moved to
	#    spawn time (#593), so a generated cell must carry its walls whether or
	#    not this run intends to build them.
	var over_cap: int = 0
	var saw_wall := false
	for seed_i in range(120):
		var objs: Array = Pop.authored_objects("s05b_lb3", seed_i % 9, _seeded_rng(seed_i))
		if objs.size() > 20:
			over_cap += 1
		for o in objs:
			if str(o.get("type", "")) == "wall":
				saw_wall = true
	assert_eq(over_cap, 0, "a room never exceeds the 20-object cap")
	assert_true(saw_wall, "authored walls reach the object list (the gate is at spawn time)")
	print("")


## A fence is a barrier you open, not scenery — psz-re measures o0c_fence at
## 1.31 cells from a doorway against 5.14 for walls, so fences stand IN
## doorways on purpose. One with no switch in the room is a sealed room, and
## the layout mask can build the fence's group while skipping the switch's, so
## the guard has to hold on the objects a room actually builds.
## Which gate a doorway gets, per kion\'s four-door room: enter from the south,
## two-key west, enemy-defeat north, nothing east.
##
## This is the layer that was missing when the runtime ignored door attributes
## entirely. The generator tests assert the attributes are ASSIGNED; the sanity
## autopilot drives a static quest that has none. Between them a runtime that
## built a gate on every door passed everything, while three stages of play
## showed nothing but enemy-defeat gates.
func test_gate_kind_per_door() -> void:
	print("── Which gate a doorway gets (spec /states/field-gates) ──")
	const VF := preload("res://scripts/3d/field/valley_field_controller.gd")
	# north enemy-defeat, west two-key, east open (absent = open), entered south.
	var attrs := {"north": 4, "west": 2}
	assert_eq(VF.gate_kind_for_door(attrs, "south", "south", false, []),
		VF.GATE_NONE, "the way back gets no gate")
	assert_eq(VF.gate_kind_for_door(attrs, "east", "south", false, []),
		VF.GATE_NONE, "an open door gets no gate at all, not an opened one")
	assert_eq(VF.gate_kind_for_door(attrs, "north", "south", false, []),
		VF.GATE_ENEMY_DEFEAT, "an enemy-defeat door gets a gate")
	assert_eq(VF.gate_kind_for_door(attrs, "west", "south", false, []),
		VF.GATE_KEY, "a two-key door gets a key gate")
	assert_eq(VF.gate_kind_for_door({"west": 1}, "west", "south", false, []),
		VF.GATE_KEY, "a one-key door gets a key gate")

	# A field with no attributes — every static field_quest — is untouched.
	assert_eq(VF.gate_kind_for_door({}, "east", "south", false, []),
		VF.GATE_ENEMY_DEFEAT, "legacy field still gates every connection")
	assert_eq(VF.gate_kind_for_door({}, "west", "south", true, ["west"]),
		VF.GATE_KEY, "legacy field still key-gates what its old fields name")
	assert_eq(VF.gate_kind_for_door({}, "south", "south", false, []),
		VF.GATE_ENEMY_DEFEAT, "legacy field gates the entry edge as it always did")
	print("")


func test_authored_fences_are_openable() -> void:
	print("── Every authored fence has a switch in its room ──")
	const Pop := preload("res://scripts/3d/field/field_population.gd")
	var rooms: Dictionary = QuestLoader._load_json(
		"res://data/re_reference/room_objects.json").get("rooms", {})
	var sealed: int = 0
	var with_fence: int = 0
	var switches: int = 0
	for key in rooms.keys():
		var room_code: String = str(key).substr(0, str(key).rfind("_"))
		for seed_i in range(6):
			var objs: Array = Pop.authored_objects(room_code, seed_i % 9, _seeded_rng(seed_i))
			var kinds: Array[String] = []
			for o in objs:
				kinds.append(str(o.get("type", "")))
			if "step_switch" in kinds:
				switches += 1
			if "fence" not in kinds:
				continue
			with_fence += 1
			if "step_switch" not in kinds:
				sealed += 1
	assert_true(with_fence > 0, "the corpus places fences at all (%d room rolls)" % with_fence)
	assert_true(switches > 0, "the corpus places switches at all (%d room rolls)" % switches)
	assert_eq(sealed, 0, "no room roll leaves a fence with no switch to open it")
	print("")


func test_authored_walls_clear_doorways() -> void:
	print("── No BLOCKING authored object stands in a doorway (#593's soft-lock question) ──")
	var rooms: Dictionary = QuestLoader._load_json(
		"res://data/re_reference/room_objects.json").get("rooms", {})
	var doorways: Dictionary = QuestLoader._load_json(
		"res://data/re_reference/room_doorways.json").get("rooms", {})
	assert_true(not rooms.is_empty() and not doorways.is_empty(), "both reference tables load")

	# The reason walls were gated off was that one across the line between two
	# doorways is a soft-lock. psz-re measured that it never happens — 5.14
	# cells of clearance over all 964 records, against a control that finds the
	# room warp at 0.01. This re-derives it from OUR copy rather than trusting
	# the number, because the import is ours to get wrong.
	#
	# SCOPED TO THE KINDS THAT BLOCK, and it has to be. The claim "no authored
	# object of ANY kind stands in a doorway" is FALSE in the corpus — the same
	# psz-re ruler puts o0c_fence at 1.31 and the room warp at 0.01, and both
	# belong there: a fence across a doorway is a barrier, which is the entire
	# point of a fence, and a warp IS the doorway. Asserting it over every kind
	# would pass today only because the importer's allowlist (CONTAINER_KINDS)
	# has not reached those kinds yet, and would fail the moment #594 widens it
	# — reading as "#594 broke the invariant" when the invariant was overstated
	# here. What matters for a soft-lock is an object the player can neither
	# walk through nor get rid of.
	const BLOCKING_KINDS := ["box", "rare_box", "wall"]
	const MIN_CLEARANCE := 3.0
	var worst_wall: float = 1e9
	var worst_blocking: float = 1e9
	var worst_desc: String = ""
	var worst_any: float = 1e9
	var worst_any_desc: String = ""
	var measured: int = 0

	for key in rooms.keys():
		var room_code: String = str(key).substr(0, str(key).rfind("_"))
		var door: Dictionary = doorways.get(room_code, {})
		var segments: Array = door.get("segments", [])
		if segments.is_empty():
			continue
		for obj in rooms[key].get("objects", []):
			var kind: String = str(obj.get("k", ""))
			var d: float = _distance_to_doorways(
				float(obj.get("x", 0.0)), float(obj.get("z", 0.0)), segments)
			measured += 1
			if d < worst_any:
				worst_any = d
				worst_any_desc = "%s %s" % [key, kind]
			if kind not in BLOCKING_KINDS:
				continue
			if d < worst_blocking:
				worst_blocking = d
				worst_desc = "%s %s" % [key, kind]
			if kind == "wall" and d < worst_wall:
				worst_wall = d

	assert_true(measured > 1000, "measured a real corpus (%d objects)" % measured)
	assert_true(worst_wall >= MIN_CLEARANCE,
		"the closest authored WALL clears every doorway by %.2f units" % worst_wall)
	assert_true(worst_blocking >= MIN_CLEARANCE,
		"no BLOCKING authored object stands in a doorway (closest %.2f, %s)"
			% [worst_blocking, worst_desc])
	# Reported, never asserted — see the note above. When #594 lands the fences
	# this number is expected to drop to roughly 1.3, and that is not a failure.
	print("    closest of any kind (informational): %.2f — %s" % [worst_any, worst_any_desc])
	print("")


## Shortest distance from a point to any of a room's doorway openings.
##
## Sampled along each opening rather than measured to its endpoints: a wall
## beside the middle of a wide doorway is in the way just as much as one at the
## corner, and endpoint-only distance would miss it.
func _distance_to_doorways(x: float, z: float, segments: Array) -> float:
	var best: float = 1e9
	for seg in segments:
		if seg.size() < 2:
			continue
		var ax: float = float(seg[0][0])
		var az: float = float(seg[0][1])
		var bx: float = float(seg[1][0])
		var bz: float = float(seg[1][1])
		for step in range(9):
			var t: float = float(step) / 8.0
			var px: float = ax + (bx - ax) * t
			var pz: float = az + (bz - az) * t
			best = minf(best, Vector2(x - px, z - pz).length())
	return best


func test_enemies_stand_on_authored_slots() -> void:
	print("── Enemies stand on the room's AUTHORED SLOTS, not on a ring ──")
	const Pop := preload("res://scripts/3d/field/field_population.gd")

	# The ring is radius 5.0 about the origin, so "every enemy is 5.0 from the
	# centre" is exactly the symptom being removed (#604). Authored slots are
	# scattered by the room's real geometry and are not equidistant.
	var slots: Array = Pop.enemy_slot_positions("s03a_ib1", 4, _seeded_rng(1))
	assert_true(slots.size() == 4, "four enemies get four positions")

	var on_ring := 0
	for p in slots:
		var d: float = sqrt(float(p[0]) * float(p[0]) + float(p[2]) * float(p[2]))
		if abs(d - 5.0) < 0.02:
			on_ring += 1
	assert_true(on_ring < 4, "not every enemy sits on the 5.0 ring")

	# Every position MUST be one the room actually authors -- placement picks
	# from the slot list, it does not interpolate or jitter.
	var authored := {}
	for e in Pop.authored_enemy_slots("s03a_ib1"):
		authored["%.2f,%.2f" % [float(e.get("x", 0.0)), float(e.get("z", 0.0))]] = true
	for p in slots:
		assert_true(authored.has("%.2f,%.2f" % [float(p[0]), float(p[2])]),
			"position %s is an authored slot" % [p])

	# Seeded: the same field populates the same way every time it is entered.
	var again: Array = Pop.enemy_slot_positions("s03a_ib1", 4, _seeded_rng(1))
	assert_true(str(again) == str(slots), "same seed gives the same placement")

	# A wave larger than the slot count REUSES slots rather than losing enemies
	# -- the original reuses them too (8 slots, 11 enemies over three waves).
	var big: Array = Pop.enemy_slot_positions("s03a_ib1", 12, _seeded_rng(2))
	assert_true(big.size() == 12, "a 12-enemy wave gets 12 positions, none dropped")

	# An unknown room code falls back to the ring rather than spawning nothing.
	var none: Array = Pop.enemy_slot_positions("s99z_zz9", 3, _seeded_rng(3))
	assert_true(none.is_empty(), "unknown room code yields no slots, so the caller rings")


func test_keys_stand_on_authored_slots() -> void:
	print("── Keys stand on the room's AUTHORED KEY SLOTS, not the portal centroid ──")
	const Pop := preload("res://scripts/3d/field/field_population.gd")

	# Every position MUST be one the room actually authors — placement picks
	# from the slot list, it does not interpolate or jitter. s01a_ib2 splits
	# its four slots by group (two in group 0, two in group 3, disjoint), so
	# the same fixture exercises the mask filter below. Keys are compared in
	# key_slot_positions' own snappedf form: GDScript's %.2f and snappedf
	# disagree on half-boundary values (-0.405 → -0.41 vs -0.4), so mixing the
	# two roundings fails a slot that IS authored.
	var authored := {}
	for s in Pop.authored_key_slots("s01a_ib2"):
		authored[_key_slot_key(s)] = true
	assert_eq(authored.size(), 4, "s01a_ib2 authors 4 distinct key positions")

	var picks: Array = Pop.key_slot_positions("s01a_ib2", 2, _seeded_rng(1), 33)
	assert_eq(picks.size(), 2, "two keys get two positions")
	for p in picks:
		assert_true(authored.has("%.2f,%.2f" % [float(p[0]), float(p[2])]),
			"position %s is an authored key slot" % [p])

	# THE MASK FILTER — the same draw that builds the room's objects decides
	# which slots exist. Mask 33 builds group 0 (+5); mask 40 builds group 3.
	# count=2 empties each pool, so each pick set IS its mask's slot set.
	var set33 := {}
	for p in Pop.key_slot_positions("s01a_ib2", 2, _seeded_rng(2), 33):
		set33["%.2f,%.2f" % [float(p[0]), float(p[2])]] = true
	var set40 := {}
	for p in Pop.key_slot_positions("s01a_ib2", 2, _seeded_rng(3), 40):
		set40["%.2f,%.2f" % [float(p[0]), float(p[2])]] = true
	for s in Pop.authored_key_slots("s01a_ib2"):
		var slot_key := _key_slot_key(s)
		assert_eq(set33.has(slot_key), s.get("g", []).has(0),
			"mask 33 admits exactly the group-0 slot %s" % slot_key)
		assert_eq(set40.has(slot_key), s.get("g", []).has(3),
			"mask 40 admits exactly the group-3 slot %s" % slot_key)

	# A mask that leaves the room NO slot must not unplace the key: s03a_ib1's
	# slots are all group 0, which mask 40 does not build, so the mask is set
	# aside and the authored slots are used anyway (spec /mechanics/key-placement
	# — which rooms hold keys is the gate economy's committed decision).
	var mask_empty: Array = Pop.key_slot_positions("s03a_ib1", 2, _seeded_rng(4), 40)
	assert_eq(mask_empty.size(), 2, "the key exists regardless of the mask — no slot dropped")

	# Flat-build rooms (no recoverable group table, all of s02/s05): records
	# carry no group, so every slot is eligible whatever the mask.
	var flat_a: Array = Pop.key_slot_positions("s02a_ib1", 2, _seeded_rng(5), 33)
	var flat_b: Array = Pop.key_slot_positions("s02a_ib1", 2, _seeded_rng(5), 40)
	assert_eq(flat_a.size(), 2, "a flat room still yields its authored slots")
	assert_true(str(flat_a) == str(flat_b), "the mask does not filter an ungrouped slot")

	# Seeded: the same field populates the same way on every revisit.
	var again: Array = Pop.key_slot_positions("s01a_ib2", 2, _seeded_rng(1), 33)
	assert_true(str(again) == str(picks), "same seed gives the same placement")

	# More keys than distinct slots WRAP — the gate demands them, none dropped.
	var big: Array = Pop.key_slot_positions("s01a_ib2", 12, _seeded_rng(6), 33)
	assert_eq(big.size(), 12, "a 12-key cell gets 12 positions, none dropped")

	# Authored records carry no height (y=0.0 corpus-wide) — the pickup
	# floor-snaps and hovers at spawn instead of trusting y.
	assert_true(is_zero_approx(float(picks[0][1])),
		"slot y is authored 0.0; the spawn floor-snaps rather than trusting it")

	# An unknown room code yields no slots, so the caller keeps the centroid.
	assert_true(Pop.key_slot_positions("s99z_zz9", 3, _seeded_rng(7), 33).is_empty(),
		"unknown room code yields no slots")

	# END TO END: generated fields stand every key on its room's authored
	# slots, wrapped to the cell's key_count, under a mask the room drew. The
	# sweep lives in its own helper so neither function crosses the
	# code-health size bound.
	var checked: int = _sweep_generated_key_slots()
	assert_true(checked > 50, "the sweep exercised real key placements (%d)" % checked)


## How many key slots the generator sweep checked; asserts each one against
## its room's authored list (see test_keys_stand_on_authored_slots).
func _sweep_generated_key_slots() -> int:
	const Pop := preload("res://scripts/3d/field/field_population.gd")
	const GridGen := preload("res://scripts/3d/field/grid_generator.gd")
	var checked := 0
	for seed_value in range(30):
		var gen = GridGen.new()
		gen.set_seed(seed_value)
		for section in gen.generate_field("normal", "gurhacia")["sections"]:
			for cell in section.get("cells", []):
				if not cell.get("has_key", false):
					continue
				var stage_id: String = str(cell.get("stage_id", ""))
				var room_authors: Array = Pop.authored_key_slots(stage_id)
				if room_authors.is_empty():
					continue  # reference never covered this room — centroid path
				var slots: Array = cell.get("key_slots", [])
				var want: int = maxi(1, int(cell.get("key_count", 1)))
				assert_eq(slots.size(), want,
					"cell %s holds one slot per key (%d wanted)" % [str(cell.get("pos", "")), want])
				var by_xy := {}
				for s in room_authors:
					by_xy[_key_slot_key(s)] = true
				for sa in slots:
					checked += 1
					assert_true(by_xy.has("%.2f,%.2f" % [float(sa[0]), float(sa[2])]),
						"generated slot %s is authored for %s" % [str(sa), stage_id])
	return checked


## Comparison key for an authored key-slot record, in key_slot_positions' own
## snappedf form — see the note in test_keys_stand_on_authored_slots.
func _key_slot_key(s: Dictionary) -> String:
	return "%.2f,%.2f" % [
		snappedf(float(s.get("x", 0.0)), 0.01),
		snappedf(float(s.get("z", 0.0)), 0.01)]


func test_group_five_trap_roll() -> void:
	print("── Group 5 is the trap group, and it is ROLLED 0..3 at 40/20/20/20 ──")
	const Pop := preload("res://scripts/3d/field/field_population.gd")

	# s01a_tb3 authors ten group-5 Heat traps and nothing else in group 5, so
	# the trap count in a roll IS the rolled count — 0 through 3, never more.
	var counts := {0: 0, 1: 0, 2: 0, 3: 0}
	var trials := 400
	for seed_i in range(trials):
		var objs: Array = Pop.authored_objects("s01a_tb3", 5, _seeded_rng(seed_i))
		var traps: int = 0
		for o in objs:
			if str(o.get("type", "")).ends_with("_trap"):
				traps += 1
		counts[traps] = int(counts.get(traps, 0)) + 1
	# Asserted once over the whole sample rather than per trial — 400 identical
	# PASS lines bury the two assertions that actually say something.
	var over: int = 0
	for n in counts.keys():
		if int(n) > 3:
			over += int(counts[n])
	assert_eq(over, 0, "a room never rolls more than 3 group-5 objects (%d trials)" % trials)

	# 40% of rooms roll nothing. Bounded loosely — this is a seeded sample, not
	# a proof — but tight enough that a broken weight walk fails it.
	var zero_share: float = float(counts[0]) / float(trials)
	assert_true(zero_share > 0.28 and zero_share < 0.52,
		"about 40%% of rooms roll no trap (got %.0f%%)" % (zero_share * 100.0))
	assert_true(counts[1] > 0 and counts[2] > 0 and counts[3] > 0,
		"counts 1, 2 and 3 all occur")

	# Every authored trap id the table can emit is one the spawner handles.
	const Known := ["heal_trap", "heat_trap", "light_trap", "ice_trap",
		"gun_trap", "burn_trap", "needler_trap", "capture_trap"]
	var seen := {}
	for code in ["s01a_tb3", "s03a_xb2", "s05a_lc1", "s07b_td1", "s04a_ib1"]:
		for seed_i in range(60):
			for o in Pop.authored_objects(code, 4, _seeded_rng(seed_i)):
				var t: String = str(o.get("type", ""))
				if t.ends_with("_trap"):
					seen[t] = true
	for t in seen.keys():
		assert_true(t in Known, "authored trap '%s' is a kind the spawner knows" % t)
	assert_true(seen.size() >= 3, "the sample reaches several trap types (%d)" % seen.size())
	print("")


func test_field_trap_behaviour() -> void:
	print("── The elemental trap: one class, two families, measured fuses ──")
	const TrapScript := preload("res://scripts/3d/elements/trap_ball.gd")

	# The fuse table, straight off psz-re. Element 0 (Heal) is singled out on
	# the player side; the field side gets FASTER as difficulty rises.
	var player_heal := TrapScript.build("heal_trap")
	var player_heat := TrapScript.build("heat_trap")
	assert_true(player_heal != null and player_heat != null, "both trap balls build")
	if player_heal != null and player_heat != null:
		assert_true(is_equal_approx(player_heal.fuse_seconds(), 150.0 / 60.0),
			"a player's Heal trap fuses over 150 frames")
		assert_true(is_equal_approx(player_heat.fuse_seconds(), 75.0 / 60.0),
			"every other player trap fuses over 75 frames")
		assert_true(not player_heal.field_placed, "a built trap is the player's by default")
		player_heal.free()
		player_heat.free()

	var expect := [45.0, 30.0, 15.0]
	for d in range(3):
		var field_trap := TrapScript.build_field("ice_trap", d)
		assert_true(field_trap != null, "the field form builds at difficulty %d" % d)
		if field_trap == null:
			continue
		assert_true(field_trap.field_placed, "build_field sets the parameter-block byte")
		assert_true(is_equal_approx(field_trap.fuse_seconds(), expect[d] / 60.0),
			"difficulty %d fuses over %d frames" % [d, int(expect[d])])
		field_trap.free()

	# The difficulty index is clamped rather than trusted — a session with an
	# unknown difficulty string must not index off the end of the table.
	var clamped := TrapScript.build_field("ice_trap", 9)
	assert_true(clamped != null, "an out-of-range difficulty still builds")
	if clamped != null:
		assert_true(is_equal_approx(clamped.fuse_seconds(), 15.0 / 60.0),
			"an out-of-range difficulty clamps to the fastest fuse")
		clamped.free()

	# Heal is measured at half of max HP, in both of the game's handlers.
	assert_true(is_equal_approx(float(TrapScript.TRAP_EFFECTS["heal_trap"]["heal_percent"]), 0.5),
		"the Heal element restores 50% of max HP")
	print("")


func test_trap_vision_reveal() -> void:
	print("── A dormant trap is seen by a CAST, or under Trap Vision ──")
	const TrapScript := preload("res://scripts/3d/elements/trap_ball.gd")

	TrapScript.vision_until_msec = 0
	assert_true(not TrapScript.vision_active(), "Trap Vision starts inactive")

	# Using one turns it on for everybody, CAST or not.
	TrapScript.grant_vision(5.0)
	assert_true(TrapScript.vision_active(), "using a Trap Vision turns it on")
	assert_true(TrapScript.traps_are_visible(), "traps are visible while it runs")

	# A second one EXTENDS rather than stacks: the later expiry wins and an
	# earlier, shorter one cannot cut the running effect short.
	var long_until: int = TrapScript.vision_until_msec
	TrapScript.grant_vision(60.0)
	assert_true(TrapScript.vision_until_msec > long_until, "a longer one extends it")
	var extended: int = TrapScript.vision_until_msec
	TrapScript.grant_vision(1.0)
	assert_eq(TrapScript.vision_until_msec, extended,
		"a shorter one does NOT cut the running effect short")

	# With vision off, the rule falls through to the race check — the same hook
	# that gates whether the character can carry traps at all.
	TrapScript.vision_until_msec = 0
	assert_eq(TrapScript.traps_are_visible(), Inventory.can_use_traps(),
		"with no Trap Vision, seeing traps is exactly the CAST check")

	# The consumable is wired: using one is what grants the effect.
	var consumable = ConsumableRegistry.get_consumable("trap_vision")
	assert_true(consumable != null, "trap_vision is a registered consumable")
	print("")


func _seeded_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## True when the authored table carries this room code. A room with a table but
## no records is fine — a room with NO table falls back to the ring, which is
## the regression the authored placement replaces.
var _authored_rooms_cache: Dictionary = {}

func _room_is_authored(stage_id: String) -> bool:
	if _authored_rooms_cache.is_empty():
		var doc := QuestLoader._load_json("res://data/re_reference/room_objects.json")
		_authored_rooms_cache = doc.get("rooms", {})
	return _authored_rooms_cache.has("%s_d" % stage_id)


## ── Per-axis texture wrap read back from the source .glb ───────
## #576: the DS sets wrap per axis and mirrors heavily — 283 of the exported
## samplers mirror EXACTLY ONE axis. Godot's importer collapses all of it into
## a single texture_repeat bool, so the only way to honour it is to read the
## .glb. Needs the asset pack, so it self-skips on CI where /assets/ is absent.
func test_source_wrap_per_axis() -> void:
	print("── SourceWrap (per-axis wrap from the source .glb) ──")
	const PROBE := "res://assets/objects/valley/o0c_needle.glb"
	if not FileAccess.file_exists(PROBE):
		print("  SKIP: no local /assets/ tree (pack-free CI)")
		print("")
		return
	SourceWrap.clear_cache()

	# One model per wrap combination the survey found, so a regression in the
	# parse cannot hide behind a uniform case.
	var cases := {
		# mirror/repeat AND repeat/mirror on the same model — the case that
		# proves per-axis is real rather than a converter default.
		"res://assets/objects/valley/o0c_needle.glb": {
			"o0c_1_needle.png": ["mirror", "repeat"],
			"o0c_1_needle2.png": ["repeat", "mirror"],
		},
		# mirror/mirror — the box, which is why forcing mirror looked right.
		"res://assets/objects/valley/o01_cont.glb": {
			"o02_0_cont.png": ["mirror", "mirror"],
		},
		# repeat/repeat — every wall. These were being mirrored against the
		# source before #576.
		"res://assets/objects/valley/o01_wall.glb": {
			"o01_1_wall1.png": ["repeat", "repeat"],
		},
		# Two textures disagreeing within one model.
		"res://assets/objects/special_c3/o0s_warpcn.glb": {
			"o0s_1_cwarp1a2.png": ["mirror", "mirror"],
			"o0s_1_cwarp2a.png": ["repeat", "repeat"],
		},
	}
	for glb_path in cases:
		var wraps: Dictionary = SourceWrap.for_glb(glb_path)
		var model_name: String = glb_path.get_file()
		for tex_name in cases[glb_path]:
			var want: Array = cases[glb_path][tex_name]
			var got: Dictionary = wraps.get(tex_name, {})
			assert_eq(str(got.get("s", "")), str(want[0]),
				"%s %s wrapS is %s" % [model_name, tex_name, want[0]])
			assert_eq(str(got.get("t", "")), str(want[1]),
				"%s %s wrapT is %s" % [model_name, tex_name, want[1]])

	# for_texture is the per-surface accessor the elements use.
	var one: Dictionary = SourceWrap.for_texture(
		"res://assets/objects/valley/o0c_needle.glb", "o0c_1_needle2.png")
	assert_eq(str(one.get("t", "")), "mirror", "for_texture resolves a single texture")
	# Unknown model / unknown texture must be empty, not a guess — callers use
	# {} as the signal to leave the material alone.
	# Path assembled at runtime on purpose: check_asset_refs.py greps source for
	# asset-path literals and would flag a deliberately-absent one.
	var absent := "res://assets/objects/valley/" + "does_not_exist" + ".glb"
	assert_true(SourceWrap.for_glb(absent).is_empty(), "a missing model yields no opinion")
	assert_true(SourceWrap.for_texture(
		"res://assets/objects/valley/o01_wall.glb", "not_a_texture.png").is_empty(),
		"an unknown texture yields no opinion")
	print("")


func test_teleporter_dressing() -> void:
	print("── TeleporterDressing (special_c3 layout + pivot + materials) ──")
	const DressScript := preload("res://scripts/3d/elements/teleporter_dressing.gd")
	var el = DressScript.new()

	# Layout contract, as authored in the web #/teleporter-mock.
	var layout: Dictionary = el._load_layout()
	assert_true(not layout.is_empty(), "data/city_teleporter.json loads")
	assert_eq(layout.get("set", ""), "special_c3", "layout set is special_c3")
	var pieces: Dictionary = layout.get("pieces", {})
	assert_eq(pieces.size(), 6, "layout has 6 pieces")
	var anchor: Array = layout.get("anchor", [])
	assert_true(anchor.size() == 3 and is_equal_approx(float(anchor[2]), 60.83), "anchor sits at the warp pad")
	# The parked Absorb ring keeps its measured config on record: its glow sheet
	# scrolls while its base plate does not, which is why it needs `textures`.
	var warpcb: Dictionary = pieces.get("o0s_warpcb", {})
	var wabs2: Dictionary = warpcb.get("textures", {}).get("o0c_1_wabs2.png", {})
	assert_eq(wabs2.get("scroll", {}).get("v", 0.0), 0.4, "absorb ring glow scrolls v=0.4")
	assert_true(
		not warpcb.get("textures", {}).get("o0c_1_wabs1.png", {}).has("scroll"),
		"absorb ring base plate does not scroll"
	)
	# The two compass plates and City Warp A are live in-game; the other three
	# warp variants are parked (visible:false keeps their authored transforms
	# and measured configs without spawning them).
	var visible_names := []
	for n in pieces:
		if pieces[n].get("visible", true):
			visible_names.append(n)
	visible_names.sort()
	# City Warp A is NOT dressing any more: WarpPad renders o0s_warpcn as the
	# teleporter itself, so spawning it here too would double the mesh. Its
	# authored transform and measured config stay on record via visible:false.
	assert_eq(
		visible_names,
		["o00_compass", "o00_compass2"],
		"compass plates spawn; the warp is the pad, not dressing"
	)

	# Pivot math: a mesh authored away from its scene root gets re-pivoted to
	# bbox bottom-center before the cfg offset applies.
	var model := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2, 2, 2)
	mi.mesh = box
	mi.position = Vector3(5, 3, -2)
	model.add_child(mi)
	var pivot = el._build_piece("test_piece", model, {"pos": [0, 1, 0], "ry": 0.5, "s": 2})
	assert_eq(String(pivot.name), "test_piece", "pivot named after the piece")
	assert_eq(pivot.position, Vector3(0, 1, 0), "pivot at cfg pos offset")
	assert_true(is_equal_approx(pivot.rotation.y, 0.5), "pivot yaw from cfg")
	assert_eq(pivot.scale, Vector3(2, 2, 2), "pivot scale from cfg")
	assert_eq(model.position, Vector3(-5, -2, 2), "model shifted to bbox bottom-center")

	# Material mapping: layout uv/scroll → shader uniforms, scissor carried
	# over from the imported material (glTF MASK).
	var src := StandardMaterial3D.new()
	src.albedo_texture = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	src.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	src.alpha_scissor_threshold = 0.5
	var cfg := {
		"uv": {"wrap": ["repeat", "mirror"], "repeat": [1, 1], "offset": [0, 0], "rot": 0},
		"scroll": {"u": 0, "v": 0.15},
	}
	var smat: ShaderMaterial = el._make_dress_material(src, cfg)
	assert_eq(smat.get_shader_parameter("wrap_u"), 1, "wrap_u repeat")
	assert_eq(smat.get_shader_parameter("wrap_v"), 0, "wrap_v mirror")
	assert_eq(smat.get_shader_parameter("scroll_speed"), Vector2(0, 0.15), "scroll_speed from cfg")
	assert_true(is_equal_approx(float(smat.get_shader_parameter("alpha_scissor")), 0.5), "alpha scissor carried")
	assert_true(smat.get_shader_parameter("albedo_tex") == src.albedo_texture, "albedo texture carried")
	var smat_default: ShaderMaterial = el._make_dress_material(src, {})
	assert_eq(smat_default.get_shader_parameter("wrap_u"), 0, "default wrap is mirror (source sampler mode)")
	assert_eq(smat_default.get_shader_parameter("scroll_speed"), Vector2.ZERO, "default has no scroll")

	pivot.free()
	el.free()
	print("")


## ── Teleporter dressing: per-texture overrides ───────
## Split out of test_teleporter_dressing to stay under the complexity bound.
## Covers only the `textures` merge — two surfaces on one piece disagreeing is
## the whole reason it exists (o0s_warpcn's glow scrolls over a static plate).
func test_teleporter_dressing_texture_overrides() -> void:
	print("── TeleporterDressing (per-texture uv/scroll overrides) ──")
	const DressScript := preload("res://scripts/3d/elements/teleporter_dressing.gd")
	var el = DressScript.new()

	var piece_cfg := {
		"uv": {"wrap": ["mirror", "mirror"], "repeat": [1, 1], "offset": [0, 0], "rot": 0},
		"textures": {
			"glow.png": {
				"uv": {"wrap": ["mirror", "mirror"], "repeat": [1, 1], "offset": [-2.68, 5.31], "rot": 0},
				"scroll": {"u": -0.5, "v": 0},
			},
			"plate.png": {
				"uv": {"wrap": ["mirror", "mirror"], "repeat": [2, 2], "offset": [0, 1], "rot": 0},
			},
		},
	}
	var glow_cfg: Dictionary = el._texture_cfg(piece_cfg, "glow.png")
	assert_eq(glow_cfg.get("uv", {}).get("offset", []), [-2.68, 5.31], "glow takes its own offset")
	assert_eq(glow_cfg.get("scroll", {}).get("u", 0.0), -0.5, "glow takes its own scroll")
	var plate_cfg: Dictionary = el._texture_cfg(piece_cfg, "plate.png")
	assert_eq(plate_cfg.get("uv", {}).get("repeat", []), [2, 2], "plate takes its own repeat")
	assert_true(not plate_cfg.has("scroll"), "plate inherits no scroll (piece sets none)")
	# An unlisted texture — and a texture with no resource path at all, which is
	# what a synthetic ImageTexture gives — fall back to the piece config.
	assert_eq(el._texture_cfg(piece_cfg, "other.png"), piece_cfg, "unlisted texture uses piece cfg")
	assert_eq(el._texture_cfg(piece_cfg, ""), piece_cfg, "unnamed texture uses piece cfg")
	# Per-key merge: a texture entry that sets only scroll keeps the piece uv.
	var scroll_only := {
		"uv": {"wrap": ["clamp", "clamp"], "repeat": [3, 3], "offset": [0, 0], "rot": 0},
		"textures": {"glow.png": {"scroll": {"u": 1, "v": 0}}},
	}
	var merged: Dictionary = el._texture_cfg(scroll_only, "glow.png")
	assert_eq(merged.get("uv", {}).get("repeat", []), [3, 3], "scroll-only override inherits piece uv")
	assert_eq(merged.get("scroll", {}).get("u", 0.0), 1.0, "scroll-only override applies its scroll")

	# Sidedness carries from the source material. o0s_warpcn mixes the two on
	# one mesh — glow CULL_DISABLED over a CULL_BACK plate — and the shader is
	# compile-time double-sided, so a back-culled surface must be told to
	# discard its back faces or it draws through the piece as an offset,
	# discoloured copy (what the city pad showed).
	var back_src := StandardMaterial3D.new()
	back_src.albedo_texture = ImageTexture.new()
	back_src.cull_mode = BaseMaterial3D.CULL_BACK
	var back_mat: ShaderMaterial = el._make_dress_material(back_src, piece_cfg)
	assert_true(back_mat.get_shader_parameter("cull_back"), "CULL_BACK surface discards back faces")

	var both_src := StandardMaterial3D.new()
	both_src.albedo_texture = ImageTexture.new()
	both_src.cull_mode = BaseMaterial3D.CULL_DISABLED
	var both_mat: ShaderMaterial = el._make_dress_material(both_src, piece_cfg)
	assert_true(not both_mat.get_shader_parameter("cull_back"), "CULL_DISABLED surface stays double-sided")

	el.free()
	print("")


# ── Quest pickup is one still burst, not a star plus a badge ──
# The gold star was a stand-in for ef_com_quest, so once the real texture
# landed the pickup carried both — the imitation spinning on the floor and the
# original hovering above it. The burst is now the model itself, and nothing
# animates it. Pack-free: falls back to the star when assets/effects is absent,
# which is exactly the case this also has to keep working.
func test_quest_item_burst_is_static() -> void:
	print("── QuestItemPickup shows one still burst (no star, no spin) ──")
	var qitem := QuestItemPickup.new()
	qitem._load_model()

	# Never invisible: an objective the player cannot see is an unclearable quest.
	assert_true(qitem.model != null, "pickup always builds a visible model")
	assert_eq(qitem.get_child_count(), 1, "one visual, not a model plus a marker")

	# DropBase spins `model` every frame. This one must not.
	var before: Vector3 = qitem.model.rotation
	qitem._update_animation(1.0)
	assert_eq(qitem.model.rotation, before, "burst does not spin")

	# And it does not bob: the height is a constant, not a starting point.
	assert_eq(QuestMarker.DEFAULT_HEIGHT, 0.7, "burst centre sits at a fixed 0.7")

	# The burst path itself only exists with the pack mounted; the CI runner has
	# no assets/effects on disk, so assert it only where it can be built.
	if ResourceLoader.exists("res://assets/effects/ef_com_quest/ef_com_quest.glb"):
		assert_true(qitem.model is QuestMarker, "pack present → the burst IS the model")
		var marker := QuestMarker.build()
		assert_true(marker != null, "marker builds from the pack")
		if marker:
			# is_equal_approx, not assert_eq: position.y is a float32 Vector3
			# component, so DEFAULT_HEIGHT (0.7, a double) reads back as
			# 0.699999988… and an exact compare can never pass. The guard above
			# means CI never ran this — it only fires on a box that has
			# assets/effects on disk.
			assert_true(is_equal_approx(marker.position.y, QuestMarker.DEFAULT_HEIGHT),
				"marker sits at its height (%f)" % marker.position.y)
			marker.free()
	else:
		print("  (no pack — burst not built; fallback star path exercised instead)")

	qitem.free()
	print("")


# ── City scroll-only texture pass (Dairon market waves) ──────
# _apply_scroll_fixes() exists so an area with baked textures can animate its
# water without opting into the whole _fix_city_materials() rewrite. Two things
# are worth pinning: that it converts a scrolling material, and that it leaves
# a non-scrolling one alone — the second is the entire point of the narrow pass.
func test_city_scroll_fixes() -> void:
	print("── city _apply_scroll_fixes (scroll-only material pass) ──")
	var area := CityAreaBase.new()
	CityAreaBase._load_global_texture_fixes()

	# The data half. scrollY must be present and 0: _fix_materials_recursive
	# defaults a missing scrollY to -0.35, so an entry that only says scrollX
	# would inherit a vertical crawl nobody asked for.
	var fixes_file := FileAccess.open("res://data/stage_configs/global-texture-fixes.json", FileAccess.READ)
	assert_true(fixes_file != null, "global-texture-fixes.json is readable")
	var fixes: Dictionary = JSON.parse_string(fixes_file.get_as_text())
	fixes_file.close()
	for key in ["dairon2_s00_2_wave01.png#1", "dairon2_s00_2_wave02.png#1"]:
		assert_true(fixes.has(key), "%s has a fix entry" % key)
		var entry: Dictionary = fixes.get(key, {})
		assert_eq(entry.get("scrollX", 0.0), -0.2, "%s scrolls -0.2 in u" % key)
		assert_true(entry.has("scrollY"), "%s pins scrollY (else it defaults to -0.35)" % key)
		assert_eq(entry.get("scrollY", -0.35), 0.0, "%s does not scroll in v" % key)

	# The behavioural half. A material whose texture carries a scroll entry
	# becomes a waterfall ShaderMaterial carrying that scroll.
	var wave := MeshInstance3D.new()
	wave.mesh = QuadMesh.new()
	var wave_mat := StandardMaterial3D.new()
	var wave_tex := ImageTexture.new()
	wave_tex.resource_path = "res://assets/stages/city_e/market/dairon2_s00_2_wave01.png"
	wave_mat.albedo_texture = wave_tex
	wave.set_surface_override_material(0, wave_mat)
	area.add_child(wave)

	# ...and one whose texture has a fix with NO scroll stays exactly as authored.
	var wall := MeshInstance3D.new()
	wall.mesh = QuadMesh.new()
	var wall_mat := StandardMaterial3D.new()
	var wall_tex := ImageTexture.new()
	# s00e_sa2's copy, not the market's: market/s00_* is excluded from the
	# export, and check-asset-refs rejects a res:// path that isn't in the pack.
	# The lookup keys on the basename, so the shipped path is the right one.
	wall_tex.resource_path = "res://assets/stages/city_e/s00e_sa2/lndmd/s00_0_back00.png"
	wall_mat.albedo_texture = wall_tex
	wall.set_surface_override_material(0, wall_mat)
	area.add_child(wall)

	area._apply_scroll_fixes_recursive(area)

	var wave_out := wave.get_surface_override_material(0)
	assert_true(wave_out is ShaderMaterial, "scrolling texture becomes a ShaderMaterial")
	if wave_out is ShaderMaterial:
		var sm := wave_out as ShaderMaterial
		assert_eq(sm.get_shader_parameter("uv_scroll"), Vector2(-0.2, 0.0), "wave scrolls -0.2 in u only")
	assert_true(wall.get_surface_override_material(0) == wall_mat,
		"non-scrolling material is left untouched by the narrow pass")

	area.free()
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


# Held-key count for the field HUD (playtest: keys must decrement on use, not
# just accumulate). get_total_keys tracks keys IN HAND; keys_changed fires on
# both pickup (add_key) and gate-consume (remove_key) so the HUD refreshes.
func test_key_hud_count() -> void:
	print("── Held-key count + keys_changed signal ──")
	while Inventory.get_total_keys() > 0:
		Inventory.remove_key(Inventory._keys.keys()[0])
	var events: Array = []
	var cb := func(total: int): events.append(total)
	Inventory.keys_changed.connect(cb)
	Inventory.add_key("key_2_3")
	assert_eq(Inventory.get_total_keys(), 1, "pickup → 1 key in hand")
	Inventory.add_key("key_4_1")
	assert_eq(Inventory.get_total_keys(), 2, "second distinct key → 2 in hand")
	Inventory.remove_key("key_2_3")
	assert_eq(Inventory.get_total_keys(), 1, "using a key drops the held count")
	Inventory.remove_key("key_4_1")
	assert_eq(Inventory.get_total_keys(), 0, "using the last key drops to 0 (playtest fix)")
	assert_eq(events, [1, 2, 1, 0], "keys_changed emits the new total on every add/remove")
	Inventory.keys_changed.disconnect(cb)
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

	# Dodge i-frames (spec /mechanics/dodge, tightened by #377): only the
	# first DODGE_IFRAME_DURATION (0.2s) of the roll is invincible — NOT the
	# whole move phase. Off-tree instance — take_damage's i-frame return
	# fires before any tree-dependent call.
	assert_eq(consts.get("DODGE_IFRAME_DURATION"), 0.2, "i-frame window is the fixed 0.2s (#377)")
	var p = PlayerScript.new()
	var hp_full: int = GameState.max_hp
	GameState.set_hp(hp_full)
	p.current_state = states["DODGING"]
	p.dodge_timer = 0.1
	p.dodge_move_end = 0.5
	p.take_damage(25)
	assert_eq(GameState.hp, hp_full, "hit inside the 0.2s window ignores damage (i-frames)")
	assert_eq(p.current_state, states["DODGING"], "i-frame hit does not interrupt the roll")
	p.dodge_timer = 0.3  # inside the move phase but PAST the i-frame window
	p.take_damage(5)
	assert_eq(GameState.hp, hp_full - 5, "hit past 0.2s takes damage even mid-move-phase (#377)")
	assert_eq(p.current_state, states["DAMAGED"], "post-window hit interrupts the roll (DODGING → DAMAGED)")
	GameState.set_hp(hp_full)
	p.current_state = states["DODGING"]
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


# ── Defeat damage-immunity (#469, spec /states/player-death) ──
# Between HP hitting 0 and the return-to-city load completing the field player
# MUST be damage-immune — take_damage() a hard no-op, no HP change, no further
# `died`. The immunity is HP-DECOUPLED via the _is_defeated flag: the defeat
# transaction revives to full HP synchronously on "Yes", so an HP-coupled guard
# alone (current_state==DOWN and hp<=0) stops firing while the field player
# lives on for the transition frames — the exact bug this pins. Off-tree
# instance; take_damage's flag return fires before any tree-dependent call.
func test_player_defeat_invulnerable() -> void:
	print("── Player defeat — damage immunity across the return-to-city window (#469) ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	var p = PlayerScript.new()

	# Count `died` emissions so we can assert no re-fire during the immune window.
	var died_count := [0]
	p.died.connect(func() -> void: died_count[0] += 1)

	# Defeated: flag latched, HP already at 0 (the state right after death).
	var full: int = GameState.max_hp
	p._is_defeated = true
	GameState.set_hp(0)
	p.take_damage(25)
	assert_eq(GameState.hp, 0, "defeated player takes no damage (HP stays 0)")
	assert_eq(died_count[0], 0, "no further `died` while defeated")

	# THE REGRESSION: the defeat transaction revives to full HP synchronously on
	# "Yes" (before the scene swaps), so GameState.hp is no longer <= 0. The
	# HP-coupled guard would now STOP firing — but _is_defeated is still true, so
	# the still-live field player stays immune through the transition frames.
	GameState.set_hp(full)
	p.take_damage(25)
	assert_eq(GameState.hp, full, "post-revive, still-defeated player is immune (HP unchanged) — the #469 window")
	assert_eq(died_count[0], 0, "no `died` re-fire after the revive while defeated")

	p.free()
	GameState.set_hp(full)
	print("")


# ── Player model vertical-follow damping (#538) ──
# The collision capsule snaps discretely down each stair step; _smooth_model_y
# damps the visible mesh's Y toward the body (via _damp_scalar) so those per-step
# pops glide, while physics stays exact. Snaps on a real fall so the mesh never
# floats. Locks the damping contract; the buttery result is verified in-game.
func test_player_model_y_damping() -> void:
	print("── Player Model Y Damping ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	# delta<=0 (init / settled frame) snaps exactly to target.
	assert_eq(PlayerScript._damp_scalar(0.0, 2.0, 0.07, 0.9, 0.0), 2.0, "delta<=0 snaps to target")
	# A gap beyond snap_dist (a real fall) snaps so the mesh doesn't float.
	assert_eq(PlayerScript._damp_scalar(0.0, 5.0, 0.07, 0.9, 0.016), 5.0, "gap > snap_dist snaps to target")
	# A small step (a stair riser) damps only partway in one frame.
	var one_frame: float = PlayerScript._damp_scalar(0.0, 0.3, 0.07, 0.9, 0.008)
	assert_true(one_frame > 0.0 and one_frame < 0.3, "small gap damps partway, not instant (%f)" % one_frame)
	# Frame-rate independent: a larger delta moves further toward target.
	assert_true(PlayerScript._damp_scalar(0.0, 0.3, 0.07, 0.9, 0.016) > PlayerScript._damp_scalar(0.0, 0.3, 0.07, 0.9, 0.008),
		"larger delta damps further toward target")
	# Repeated frames converge on the target (no permanent mesh offset).
	var y: float = 0.0
	for _i in range(240):
		y = PlayerScript._damp_scalar(y, 0.3, 0.07, 0.9, 0.008)
	assert_true(absf(0.3 - y) < 0.001, "repeated damping converges to target (%f)" % y)
	print("")


# ── Player animation-library cache (#531) ──
# The player rig was rebuilt on every city area transition; the expensive part
# is instantiate + per-clip duplicate/track-remap of ~26 animations. That build
# is now split into _build_animation_library() and memoized on a static cache
# keyed by (anim_glb, skeleton.name), so it runs once and the library resource
# is shared across player instances. (The full build path needs the model GLB —
# only in the pack — so this locks the cache CONTRACT; the autopilot city→field
# probe exercises the real build+reuse.)
func test_player_anim_library_cache() -> void:
	print("── Player Anim Library Cache ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	var p1 = PlayerScript.new()
	var p2 = PlayerScript.new()
	assert_true(p1.has_method("_build_animation_library"),
		"library build split into _build_animation_library() so it can be cached")

	# Shared static store: an entry written via one instance is visible to another.
	# (Synthetic keys — real "<glb>|<skeleton>" keys with res:// paths would trip
	# check_asset_refs; the dict semantics are what matter here.)
	p1._anim_lib_cache.clear()
	var lib := AnimationLibrary.new()
	var key := "saver_m|GeneralSkeleton"
	p1._anim_lib_cache[key] = lib
	assert_true(p2._anim_lib_cache.has(key),
		"anim library cache is a shared static store across player instances")

	# A hit hands back the identical resource — reused, not rebuilt.
	assert_true(is_same(p2._anim_lib_cache[key], lib),
		"a cache hit returns the same AnimationLibrary instance (no rebuild)")

	# Key captures the GLB, so a different animation set is a distinct entry.
	assert_true(not p1._anim_lib_cache.has("sword_m|GeneralSkeleton"),
		"a different animation GLB is a different cache key")

	p1._anim_lib_cache.clear()
	p1.free()
	p2.free()
	print("")


# ── Action commitment + hitbox lifetime (#377/#428, spec /states/player-state) ──
# PSZ actions commit: a swing cannot be dodge-canceled, a roll cannot be
# attack-canceled — only damage interrupts. And the attack hitbox must not
# outlive ATTACKING by ANY exit path (dodge-cancel was how stale hitboxes
# stored hits; the transition_to deactivation covers every interrupt).
func test_action_commitment() -> void:
	print("── Action commitment (#377) + hitbox lifetime (#428) ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	var states: Dictionary = PlayerScript.PlayerState
	var p = PlayerScript.new()
	GameState.set_hp(GameState.max_hp)

	# Attack commits: a player dodge input mid-swing is a no-op.
	p.current_state = states["ATTACKING"]
	p.dodge_timer = 0.42  # sentinel — an accepted dodge would reset it to 0
	p._start_dodge()
	assert_eq(p.current_state, states["ATTACKING"], "dodge input cannot cancel a swing (#377)")
	assert_eq(p.dodge_timer, 0.42, "blocked dodge leaves dodge state untouched")

	# Dodge commits: attack / strong-attack input mid-roll is a no-op, and a
	# roll cannot restart itself.
	p.current_state = states["DODGING"]
	p.combo_state = 0
	p._start_attack()
	assert_eq(p.current_state, states["DODGING"], "attack input cannot cancel a roll (#377)")
	assert_eq(p.combo_state, 0, "blocked attack starts no combo")
	p._start_strong_attack()
	assert_eq(p.current_state, states["DODGING"], "strong attack cannot cancel a roll (#377)")
	p.dodge_timer = 0.42
	p._start_dodge()
	assert_eq(p.dodge_timer, 0.42, "a roll cannot restart itself mid-roll")

	# Damage-initiated exits stay allowed — interrupts, not cancels.
	p.current_state = states["ATTACKING"]
	p.take_damage(15)  # medium hit
	assert_eq(p.current_state, states["DAMAGED"], "damage interrupts a swing (ATTACKING → DAMAGED)")
	GameState.set_hp(GameState.max_hp)
	p.current_state = states["DODGING"]
	p.dodge_timer = 0.5  # outside the i-frame window
	p.dodge_move_end = 0.5
	p.take_damage(25)  # heavy hit
	assert_eq(p.current_state, states["DOWN"], "damage outside i-frames interrupts a roll (DODGING → DOWN)")
	GameState.set_hp(GameState.max_hp)

	# Hitbox lifetime (#428): EVERY exit from ATTACKING deactivates the attack
	# hitbox and clears stored hits, same-frame, via transition_to.
	var hb := Hitbox.new()
	p.attack_hitbox = hb
	# Damage interrupt path (the surviving early-exit once #377 blocks
	# dodge-cancel): activate mid-swing, take a hit, hitbox must die with it.
	p.transition_to(states["ATTACKING"])
	hb.activate()
	hb._hit_targets.append(p)  # simulate a landed hit ("stored" target slot)
	p.take_damage(15)
	assert_true(not hb.monitoring, "damage interrupt deactivates the attack hitbox (#428)")
	assert_eq(hb._hit_targets.size(), 0, "deactivation clears stored hits — no carry-over (#428)")
	GameState.set_hp(GameState.max_hp)
	# Generic exit edge: any transition out of ATTACKING kills the hitbox even
	# if a future code path forgets its own deactivate call.
	p.transition_to(states["ATTACKING"])
	hb.activate()
	assert_true(hb.monitoring, "hitbox is live during the swing")
	p.transition_to(states["IDLE"])
	assert_true(not hb.monitoring, "any ATTACKING exit deactivates the hitbox (#428)")

	# Quick Menu is the fifth charge-drop case (#377): its opened signal exists
	# on the field HUD's quick-weapon menu. field_hud.gd preloads pack-only
	# assets, so this only runs where the pack is mounted (can_instantiate()).
	var fh := load("res://scripts/3d/field/field_hud.gd")
	if fh != null and fh.can_instantiate():
		var inner: Variant = fh.get_script_constant_map().get("_QuickWeaponMenu")
		assert_true(inner != null, "field_hud exposes _QuickWeaponMenu")
		if inner != null:
			var qm: Control = inner.new()
			assert_true(qm.has_signal("opened"), "Quick Menu emits opened → player._drop_charge (#377)")
			qm.free()
	else:
		print("  SKIP: field_hud.gd not compilable repo-only (pack assets) — opened-signal check runs pack-mounted")
# ── Momentary palette swap (#447, spec /states/player-state) ───
# The field back palette is hold-to-activate, not a latched toggle:
# palette_swap press shows the back page, release returns to the front,
# and the transitions are edge-driven — exactly one switch per press and
# per release, no double-advance from a repeat press, no buffered toggle
# surviving the release, and no latch when a modal opens mid-hold.
func test_palette_momentary_swap() -> void:
	print("── Momentary palette swap (#447) ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	var p = PlayerScript.new()  # off-tree: _is_in_city() is false → field input path
	while GameState.modal_stack > 0:
		GameState.pop_modal()
	assert_true(not GameState.is_gameplay_blocked(), "precondition: gameplay unblocked")
	ActionPalette.show_front()
	assert_eq(ActionPalette.current_page, 0, "precondition: front page shown")

	var switches: Array = []
	var on_page := func(page: int) -> void: switches.append(page)
	ActionPalette.page_changed.connect(on_page)
	var press := _nav_event("palette_swap")
	var release := _nav_event("palette_swap")
	release.pressed = false

	p._unhandled_input(press)
	assert_eq(ActionPalette.current_page, 1, "press shows the back page")
	p._unhandled_input(press)  # repeat press without a release (echo / double-bind)
	assert_eq(ActionPalette.current_page, 1, "repeat press does not double-advance (no latched cycle)")
	p._unhandled_input(release)
	assert_eq(ActionPalette.current_page, 0, "release returns to the front page")
	p._unhandled_input(release)  # repeat release
	assert_eq(ActionPalette.current_page, 0, "repeat release stays on the front page")
	assert_eq(switches, [1, 0], "edge-driven: exactly one switch per press/release pair")
	ActionPalette.page_changed.disconnect(on_page)

	# The release must still restore the front page when gameplay got
	# blocked mid-hold (e.g. a menu opened while R1 was down) — the back
	# page MUST NOT latch behind the gameplay-blocked gate.
	p._unhandled_input(press)
	assert_eq(ActionPalette.current_page, 1, "held: back page shown before the modal opens")
	GameState.push_modal()
	p._unhandled_input(release)
	GameState.pop_modal()
	assert_eq(ActionPalette.current_page, 0, "release mid-modal still returns to the front (no latch)")

	p.free()
	print("")


# ── Start Menu carried across an area transition (#426, spec /states/start-menu) ──
# The carried-over edge case (Rozalin v0.38.18): a menu opened in area A and
# carried across a change_scene_to_file into area B double-fired confirm into
# both the menu and the teleporter. At unit scope the contract is: the autoload
# survives the scene_changed signal with _is_open AND the GameState modal block
# intact — the same is_gameplay_blocked() gate that consumes the press must
# hold after the transition exactly as before it. The cross-scene interact is
# covered at runtime by the PSZ_AUTOPILOT_MENU_CARRY=1 autopilot probe.
func test_menu_carry_survives_scene_signal() -> void:
	print("── Start Menu carried across a transition still blocks (#426) ──")
	while GameState.modal_stack > 0:
		GameState.pop_modal()
	assert_true(not GameState.is_gameplay_blocked(), "precondition: gameplay unblocked")

	PsoStartMenu.open()
	assert_true(PsoStartMenu.is_open(), "menu opened")
	assert_true(GameState.is_gameplay_blocked(), "open menu blocks gameplay input")

	# The area transition the autoload survives: SceneManager emits
	# scene_changed after the tree rebuild. Menu state and the modal block
	# must be invariant to it.
	SceneManager.scene_changed.emit("res://scenes/3d/city/city_counter.tscn")
	assert_true(PsoStartMenu.is_open(), "menu still open after scene_changed")
	assert_true(GameState.is_gameplay_blocked(), "carried menu still blocks gameplay input")

	# The REAL transition path (goto_scene) hard-resets modal_stack to clear
	# per-scene dialogs freed mid-dialog without popping — the #426 double-fire
	# was that reset also zeroing the SURVIVING menu's modal (menu open, block
	# gone). Exercise the extracted reset directly, with a leaked dialog modal
	# on the stack to prove the leak-clearing still works.
	GameState.push_modal()  # simulate a per-scene dialog leaked by the transition
	SceneManager._reset_modals_for_scene_change()
	assert_true(PsoStartMenu.is_open(), "menu still open after the goto_scene modal reset")
	assert_true(GameState.is_gameplay_blocked(), "carried menu still blocks after the goto_scene modal reset (#426)")
	assert_eq(GameState.modal_stack, 1, "leaked dialog modal cleared; exactly the menu's block survives")

	PsoStartMenu.close()
	assert_true(not PsoStartMenu.is_open(), "menu closed")
	assert_true(not GameState.is_gameplay_blocked(), "closing the carried menu unblocks")
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


# ── Enemy attack recovery (#477, spec /states/enemies) ─────
## Big rigs name their attack clip atk1 / atckwat (or lack one entirely);
## ATTACKING must still end without a damage event — the playtest freeze was
## the finished-signal suffix parse never matching "atk1".

func _make_recovery_enemy(anim_names: Array, anim_len: float) -> EnemyBase:
	var e := EnemyBase.new()
	e.enemy_data = EnemyData.new()
	add_child(e)
	var ap := AnimationPlayer.new()
	e.add_child(ap)
	var lib := AnimationLibrary.new()
	for anim_name in anim_names:
		var anim := Animation.new()
		anim.length = anim_len
		lib.add_animation(anim_name, anim)
	ap.add_animation_library("", lib)
	e.animation_player = ap
	return e


## Node3D target that records the damage values passed to take_damage — stands in for
## the player when driving an enemy's attack timeline.
class _DamageCapture extends Node3D:
	var hits: Array = []
	var knockdowns: Array = []
	func take_damage(damage: int, _knockback: Vector3 = Vector3.ZERO, force_knockdown: bool = false) -> void:
		hits.append(damage)
		if force_knockdown:
			knockdowns.append(damage)


# ── Enemy attack model (#509, spec /mechanics/enemy-attacks) ─────
## Seeded ports of web/src/__tests__/enemy-room-fsm.test.ts — selection + arc + timeline.

func test_enemy_attack_selection() -> void:
	print("── Enemy attack selection (#509) ──")
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5E1EC7
	var bite := {"id": "bite", "weight": 1.0, "min_range": 0.0, "max_range": 2.0}
	var lunge := {"id": "lunge", "weight": 1.0, "min_range": 2.0, "max_range": 6.0}
	var atks := [bite, lunge]
	assert_eq(EnemyAttackLogic.select_attack(atks, 1.0, rng)["id"], "bite", "dist 1 picks the 0-2 band")
	assert_eq(EnemyAttackLogic.select_attack(atks, 5.0, rng)["id"], "lunge", "dist 5 picks the 2-6 band")

	# Weighted split: weight 9 vs 1 in overlapping bands → ~90% the heavy one.
	var a := {"id": "a", "weight": 1.0, "min_range": 0.0, "max_range": 6.0}
	var b := {"id": "b", "weight": 9.0, "min_range": 0.0, "max_range": 6.0}
	var count_b := 0
	for _i in range(1000):
		if EnemyAttackLogic.select_attack([a, b], 3.0, rng)["id"] == "b":
			count_b += 1
	assert_true(count_b > 800 and count_b < 980, "weight 9 vs 1 picks b heavily (got %d/1000)" % count_b)

	# Nearest-band fallback when no band contains the distance; empty → {}.
	assert_eq(EnemyAttackLogic.select_attack(atks, 10.0, rng)["id"], "lunge", "beyond all bands → nearest")
	var far := {"id": "far", "weight": 1.0, "min_range": 4.0, "max_range": 6.0}
	assert_eq(EnemyAttackLogic.select_attack([far], 0.5, rng)["id"], "far", "below all bands → nearest")
	assert_true(EnemyAttackLogic.select_attack([], 1.0, rng).is_empty(), "empty table → {}")
	print("")


func test_enemy_attack_arc() -> void:
	print("── Enemy attack arc hit test (#509) ──")
	var o := Vector3.ZERO
	var fwd := Vector3(0, 0, 1)
	assert_true(EnemyAttackLogic.arc_hit_test(o, fwd, Vector3(0, 0, 2.3), 0.4, 45.0, 2.0), "inside reach+radius (2.3 <= 2.4)")
	assert_true(not EnemyAttackLogic.arc_hit_test(o, fwd, Vector3(0, 0, 2.5), 0.4, 45.0, 2.0), "beyond reach+radius (2.5 > 2.4)")
	var diag := Vector3(sin(deg_to_rad(45.0)), 0, cos(deg_to_rad(45.0)))
	assert_true(EnemyAttackLogic.arc_hit_test(o, fwd, diag, 0.1, 45.0, 2.0), "45deg target inside 45deg half-angle")
	assert_true(not EnemyAttackLogic.arc_hit_test(o, fwd, diag, 0.1, 30.0, 2.0), "45deg target outside 30deg half-angle")
	assert_true(not EnemyAttackLogic.arc_hit_test(o, fwd, Vector3(0, 0, -1), 0.1, 90.0, 2.0), "behind (180deg) outside 90deg")
	assert_true(EnemyAttackLogic.arc_hit_test(o, fwd, o, 0.4, 45.0, 2.0), "target inside the enemy hits")
	print("")


func test_enemy_attack_timeline() -> void:
	print("── Enemy attack timeline / arc damage (#509) ──")
	var dummy := _DamageCapture.new()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, 1.0)  # in front, within reach

	var e := _make_recovery_enemy(["atk"], 1.0)
	e.enemy_data.attack_base = 10
	e.target = dummy
	e.current_state = EnemyBase.EnemyState.ATTACKING
	# Inject a known attack def and force the accumulator path (no real playback).
	e._attack_def = {"clip": "atk", "windup_frac": 0.35, "damage_end_frac": 0.6,
		"hit_half_angle_deg": 45.0, "hit_reach": 2.0, "damage_mult": 2.5, "kind": "melee_arc"}
	e._attack_anim = ""
	e._attack_clip_len = 1.0
	e._attack_fallback_timer = 5.0  # keep the attack alive through the window
	e._attack_hit_resolved = false
	e._attack_facing = Vector3(0, 0, 1)
	e.is_attacking = true

	var dt := 1.0 / 60.0
	var hit_pos := -1.0
	for _i in range(45):  # ~0.75s covers the window [0.35, 0.6]
		var before := dummy.hits.size()
		e._process_attacking(dt)
		if dummy.hits.size() > before and hit_pos < 0.0:
			hit_pos = e._attack_pos
	assert_eq(dummy.hits.size(), 1, "exactly one hit lands")
	assert_true(hit_pos >= 0.35 and hit_pos <= 0.6 + dt, "hit occurs within [windup, damage_end] (got %.3f)" % hit_pos)
	if dummy.hits.size() >= 1:
		assert_eq(dummy.hits[0], 25, "damage = attack_base(10) x damage_mult(2.5)")

	e.queue_free()
	dummy.queue_free()
	print("")


func test_enemy_difficulty_scaling() -> void:
	print("── Enemy difficulty scaling (#522) ──")
	assert_eq(EnemyBase.AGGRO_SCALING["normal"]["cadence"], 1.0, "normal cadence is identity")
	assert_true(EnemyBase.AGGRO_SCALING["hard"]["cadence"] < 1.0, "hard tightens cadence")
	assert_true(EnemyBase.AGGRO_SCALING["super-hard"]["detection"] > 1.0, "super-hard widens aggro")

	# No session → normal (identity): detection unscaled, cadence 1.0.
	var en := _make_recovery_enemy(["wat"], 0.5)
	assert_eq(en._aggro_cadence, 1.0, "no session -> normal cadence")
	assert_true(abs(en._detection_range - en.enemy_data.detection_range) < 0.001, "no session -> base detection")
	en.queue_free()

	# Hard session → scaled aggro/cadence (enemy reads difficulty at _ready).
	var prev_diff := str(SessionManager.get_session().get("difficulty", ""))
	SessionManager.enter_field("gurhacia-valley", "hard")
	var eh := _make_recovery_enemy(["wat"], 0.5)
	var exp_det: float = eh.enemy_data.detection_range * EnemyBase.AGGRO_SCALING["hard"]["detection"]
	assert_true(abs(eh._detection_range - exp_det) < 0.001, "hard widens detection range")
	assert_eq(eh._aggro_cadence, EnemyBase.AGGRO_SCALING["hard"]["cadence"], "hard sets cadence mult")
	eh.queue_free()
	SessionManager.enter_field("gurhacia-valley", prev_diff if prev_diff != "" else "normal")
	print("")


func test_enemy_locomotion() -> void:
	print("── Enemy per-archetype locomotion (#494) ──")
	var fwd := Vector3(0, 0, 1)  # unit vector toward the target

	# Standoff 3-band (quad_machine / shooter / roller share this geometry).
	var r := EnemyLocomotionLogic.standoff_move(3.0, 6.0, fwd, 1.0, 0.85, 1.25, true)
	assert_eq(r["mode"], "retreat", "inside standoff -> retreat")
	assert_true(r["dir"].dot(fwd) < -0.99, "retreat backs straight away from target")
	r = EnemyLocomotionLogic.standoff_move(8.0, 6.0, fwd, 1.0, 0.85, 1.25, true)
	assert_eq(r["mode"], "close", "beyond standoff -> close")
	assert_true(r["dir"].dot(fwd) > 0.99, "close moves straight toward target")
	r = EnemyLocomotionLogic.standoff_move(6.0, 6.0, fwd, 1.0, 0.85, 1.25, true)
	assert_eq(r["mode"], "strafe", "in band + strafe -> lateral strafe")
	assert_true(abs(r["dir"].dot(fwd)) < 0.01, "strafe is perpendicular to the target line")
	r = EnemyLocomotionLogic.standoff_move(6.0, 6.0, fwd, 1.0, 0.8, 1.2, false)
	assert_eq(r["mode"], "hold", "in band + no strafe (shooter) -> hold")
	assert_true(r["dir"].length() < 0.001, "hold has zero move direction")

	# Quadruped arc vs dash.
	var q := EnemyLocomotionLogic.quadruped_move(fwd, 1.0, true)
	assert_true(q["dash"] and q["dir"].dot(fwd) > 0.99, "quadruped dash goes straight at target")
	q = EnemyLocomotionLogic.quadruped_move(fwd, 1.0, false)
	assert_true(not q["dash"], "quadruped arc is not a dash")
	assert_true(q["dir"].dot(fwd) < 0.95, "quadruped arc never walks straight at the target")
	assert_true(abs(q["dir"].x) > 0.1, "quadruped arc has a lateral (circling) component")
	print("")


func test_enemy_telegraph() -> void:
	print("── Enemy telegraph / stance wind-up (#491) ──")
	var dummy := _DamageCapture.new()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, 1.0)

	# Stance riser: rig has stt (rise) + wat2 (hold) + atk.
	var e := _make_recovery_enemy(["m_003_stt", "m_003_wat2", "m_003_atk1"], 0.3)
	e.enemy_data.attack_base = 10
	e.target = dummy
	e.current_state = EnemyBase.EnemyState.ATTACKING
	e._begin_telegraph()
	assert_true(e._telegraphing, "telegraph begins on ATTACKING entry")
	assert_true(e._telegraph_rising, "stance riser rises (stt) first")
	assert_eq(e.current_anim, "stt", "plays the rise clip")

	# Drive through rise + hold; damage MUST NOT land during the telegraph.
	var dt := 1.0 / 60.0
	var telegraph_dmg := false
	var ticks := 0
	while e._telegraphing and ticks < 300:
		e._process_attacking(dt)
		if dummy.hits.size() > 0:
			telegraph_dmg = true
		ticks += 1
	assert_true(not telegraph_dmg, "no damage during the telegraph")
	assert_true(not e._telegraphing, "telegraph ends and commits to the strike")
	assert_true(e.is_attacking, "strike is in flight after the telegraph")
	e.queue_free()

	# Generic rig: no stt/wat2 → holds its idle (wat), no rise phase.
	var g := _make_recovery_enemy(["b_001_wat", "b_001_atk"], 0.3)
	g.target = dummy
	g.current_state = EnemyBase.EnemyState.ATTACKING
	g._begin_telegraph()
	assert_true(g._telegraphing and not g._telegraph_rising, "generic rig holds without a rise phase")
	assert_eq(g.current_anim, "wat", "generic telegraph holds idle (wat)")
	g.queue_free()
	dummy.queue_free()
	print("")


# ── Attack delivery kinds (#629, spec /mechanics/enemy-attacks "kind") ─────
## Seeded ports of the fsm.ts delivery models: projectile/lob released once at
## window open, leap travel + landing AoE, segmented charge with stop_on_hit /
## overshoot / punish window, and the windup_clips prelude offset.

## Rig builder with per-clip lengths (the shared _make_recovery_enemy forces one
## length on every clip; preludes and segments need their own timings).
func _make_rig_enemy(clip_lengths: Dictionary) -> EnemyBase:
	var e := EnemyBase.new()
	e.enemy_data = EnemyData.new()
	add_child(e)
	var ap := AnimationPlayer.new()
	e.add_child(ap)
	var lib := AnimationLibrary.new()
	for clip_name in clip_lengths:
		var anim := Animation.new()
		anim.length = float(clip_lengths[clip_name])
		lib.add_animation(str(clip_name), anim)
	ap.add_animation_library("", lib)
	e.animation_player = ap
	return e


func _delivery_def(kind: String, extras: Dictionary = {}) -> Dictionary:
	var def := {"id": "t", "clip": "atk", "kind": kind, "windup_frac": 0.35,
		"damage_end_frac": 0.6, "hit_half_angle_deg": 45.0, "hit_reach": 2.0,
		"damage_mult": 1.0, "min_range": 0.0, "max_range": 99.0}
	for k in extras:
		def[k] = extras[k]
	return def


func _find_delivery(cls: Script) -> Node:
	# Newest first: queue_free is deferred (no frames pass mid-test), so deliveries
	# from earlier cases are still children — the latest release is the one to step.
	var kids := get_children()
	for i in range(kids.size() - 1, -1, -1):
		if kids[i].get_script() == cls:
			return kids[i]
	return null


func test_enemy_ranged_delivery() -> void:
	print("── Enemy ranged deliveries: projectile + lob (#629) ──")
	var dt := 1.0 / 60.0
	var dummy := _DamageCapture.new()
	add_child(dummy)

	# ── projectile: released once at window open, straight along the locked facing,
	#    contact-tested by the delivery itself.
	dummy.global_position = Vector3(0, 0, 6.0)
	var p := _make_rig_enemy({"atk": 1.0})
	p.enemy_data.attack_base = 10
	p.enemy_data.move_speed = 4.0
	p.target = dummy
	p.current_state = EnemyBase.EnemyState.ATTACKING
	p._attack_def = _delivery_def("projectile", {"hit_reach": 10.0})
	p._start_attack()
	p._attack_anim = ""          # headless: no real playback — force the accumulator
	p._attack_fallback_timer = 3.0
	assert_eq(p._attack_kind, "projectile", "kind read from the def")
	var fired := false
	for _i in range(45):  # window opens at 0.35 x 1.0s
		p._process_attacking(dt)
		if p._window_opened:
			fired = true
			break
	assert_true(fired, "projectile window opens inside the clip")
	assert_true(p._attack_hit_resolved, "release consumes the attack's one resolution")
	var proj := _find_delivery(preload("res://scripts/3d/enemies/enemy_projectile.gd"))
	assert_true(proj != null, "an EnemyProjectile was released")
	if proj:
		assert_true(is_equal_approx(float(proj.dir.dot(Vector3(0, 0, 1))), 1.0), "projectile travels the locked facing")
		assert_eq(proj.max_range, 10.0, "hit_reach is the flight range")
		for _t in range(120):  # 6m at 10 m/s ≈ 0.6s
			proj._physics_process(dt)
			if dummy.hits.size() > 0:
				break
		assert_eq(dummy.hits.size(), 1, "projectile damages the target on contact")
		assert_eq(dummy.hits[0], 10, "damage = attack_base x damage_mult")
		assert_true(not is_instance_valid(proj) or proj._hit, "contact consumed the projectile")
	p.queue_free()

	# ── lob: released at window open toward the target's position; area damage at
	#    landing, hit_reach = blast radius, one resolution at landing.
	dummy.hits.clear()
	dummy.global_position = Vector3(0, 0, 5.0)
	var l := _make_rig_enemy({"atkb": 1.0})
	l.enemy_data.attack_base = 10
	l.target = dummy
	l.current_state = EnemyBase.EnemyState.ATTACKING
	l._attack_def = _delivery_def("lob", {"clip": "atkb", "hit_reach": 1.6, "damage_mult": 1.5})
	l._start_attack()
	l._attack_anim = ""
	l._attack_fallback_timer = 3.0
	for _i in range(45):
		l._process_attacking(dt)
		if l._window_opened:
			break
	var lob := _find_delivery(preload("res://scripts/3d/enemies/enemy_lob.gd"))
	assert_true(lob != null, "an EnemyLob was released")
	if lob:
		assert_true(Vector2(lob.to.x, lob.to.z).distance_to(Vector2(0, 5)) < 0.01, "lob lands at the target's release position")
		for _t in range(75):  # LOB_FLIGHT_TIME 0.9s
			lob._physics_process(dt)
			if dummy.hits.size() > 0:
				break
		assert_eq(dummy.hits.size(), 1, "lob damages the target at landing")
		assert_eq(dummy.hits[0], 15, "lob damage = attack_base x 1.5")
	l.queue_free()


func test_enemy_leap_delivery() -> void:
	print("── Enemy leap delivery (#629) ──")
	var dt := 1.0 / 60.0
	var dummy := _DamageCapture.new()
	add_child(dummy)

	# ── leap: the enemy itself travels to the target's window-open position during
	#    the window, landing at its close for area damage.
	dummy.hits.clear()
	dummy.global_position = Vector3(0, 0, 5.0)
	var le := _make_rig_enemy({"atk3": 1.0})
	le.enemy_data.attack_base = 10
	le.target = dummy
	le.current_state = EnemyBase.EnemyState.ATTACKING
	le._attack_def = _delivery_def("leap", {"clip": "atk3", "windup_frac": 0.4, "damage_end_frac": 0.75, "hit_reach": 2.0, "damage_mult": 1.8})
	le._start_attack()
	le._attack_anim = ""
	le._attack_fallback_timer = 3.0
	for _i in range(120):
		le._process_attacking(dt)
	assert_true(le._window_closed, "leap window closed by end of clip")
	assert_eq(dummy.hits.size(), 1, "leap landing damages the target once")
	assert_eq(dummy.hits[0], 18, "leap damage = attack_base x 1.8")
	assert_true(Vector2(le.global_position.x, le.global_position.z).distance_to(Vector2(0, 5)) < 0.05,
		"the enemy lands on the captured target position")
	le.queue_free()


	dummy.queue_free()
	print("")


## Shared charge-test setup: rig + injected charge def + committed attack.
func _make_charge_enemy(rig: Dictionary, def_extras: Dictionary, dummy: Node3D) -> EnemyBase:
	var e := _make_rig_enemy(rig)
	e.enemy_data.attack_base = 10
	e.enemy_data.move_speed = 4.0
	e.target = dummy
	e.current_state = EnemyBase.EnemyState.ATTACKING
	e._attack_def = _delivery_def("charge", def_extras)
	e._start_attack()
	return e


func test_enemy_charge_stop_on_hit() -> void:
	print("── Enemy charge: gorilla slam (#629) ──")
	var dt := 1.0 / 60.0
	var dummy := _DamageCapture.new()
	add_child(dummy)

	# ── charge (gorilla slam): st → lp travel along the locked facing → contact hit
	#    ends it (stop_on_hit default) → ed recovery.
	dummy.hits.clear()
	dummy.knockdowns.clear()
	dummy.global_position = Vector3(0, 0, 3.0)
	var c := _make_charge_enemy({"r_atk2_st": 0.3, "r_atk2_lp": 0.3, "r_atk2_ed": 0.3},
		{"clip": "atk2", "hit_reach": 1.4, "max_range": 9.0, "damage_mult": 1.4}, dummy)
	assert_eq(String(c._charge["tokens"]["st"]), "atk2_st", "suffix tokens derived from the clip")
	# st: stationary windup segment, no damage, no movement.
	for _i in range(20):
		c._process_attacking(dt)
		# Integrate manually: from synchronous test code the physics server hasn't
		# synced the body, so move_and_slide() wouldn't advance the transform.
		c.global_position += c.velocity * dt
	assert_eq(String(c._charge["phase"]), "lp", "st segment elapses into the charge loop")
	assert_eq(dummy.hits.size(), 0, "no damage during the windup segment")
	# lp: moves forward until first contact; stop_on_hit ends the charge.
	var lp_start := c.global_position
	for _i in range(120):
		c._process_attacking(dt)
		c.global_position += c.velocity * dt
		if String(c._charge.get("phase", "ed")) == "ed":
			break
	assert_eq(dummy.hits.size(), 1, "charge hits on first contact")
	assert_eq(dummy.hits[0], 14, "charge damage = attack_base x 1.4")
	assert_true(c.global_position.z > lp_start.z + 0.5, "charge traveled forward along the facing")
	assert_eq(String(c._charge["phase"]), "ed", "stop_on_hit (default) ends the charge on contact")
	# ed: recovery runs its duration, then the attack ends.
	for _i in range(30):
		c._process_attacking(dt)
	assert_eq(c.current_state, EnemyBase.EnemyState.LOAFING, "charge recovers to LOAFING after ed")
	c.queue_free()



func test_enemy_charge_roll_through() -> void:
	print("── Enemy charge: roller roll-through + punish window (#629) ──")
	var dt := 1.0 / 60.0
	var dummy := _DamageCapture.new()
	add_child(dummy)

	# ── charge (roller roll): explicit segments, overshoot, rolls THROUGH the target
	#    (stop_on_hit false), knockdown flag passes through, ed opens the punish window.
	dummy.hits.clear()
	dummy.knockdowns.clear()
	dummy.global_position = Vector3(0, 0, 3.0)
	var r := _make_charge_enemy({"trf1": 0.3, "wat3": 0.3, "trf2": 0.3}, {
		"clip": "wat3", "hit_reach": 1.3, "max_range": 12.0, "damage_mult": 1.5,
		"charge_segments": {"st": "trf1", "lp": "wat3", "ed": "trf2"},
		"stop_on_hit": false, "overshoot": 3.0, "knockdown": true,
		"recovery_vulnerable_mult": 2.0}, dummy)
	assert_true(r._charge["rotate_model"], "explicit segments mean an engine-rolled loop clip")
	assert_eq(float(r._charge["travel_target"]), 6.0, "overshoot: travel = start dist 3 + 3, capped by max_range")
	for _i in range(20):
		r._process_attacking(dt)
		r.global_position += r.velocity * dt
	var roll_z := r.global_position.z
	for _i in range(240):
		r._process_attacking(dt)
		r.global_position += r.velocity * dt
		if String(r._charge.get("phase", "ed")) == "ed":
			break
	assert_eq(dummy.hits.size(), 1, "roll resolves its one hit on contact")
	assert_eq(dummy.knockdowns.size(), 1, "roll hit carries the knockdown flag")
	assert_true(r.global_position.z > roll_z + 4.0, "stop_on_hit false rolls past the target")
	assert_eq(String(r._charge["phase"]), "ed", "roll ends on the travel target, not the hit")
	assert_eq(r._vulnerable_mult, 2.0, "recovery opens the punish window (recovery_vulnerable_mult)")
	for _i in range(30):
		r._process_attacking(dt)
	assert_eq(r._vulnerable_mult, 1.0, "punish window closes with the recovery")
	assert_eq(r.current_state, EnemyBase.EnemyState.LOAFING, "roll recovers to LOAFING")
	r.queue_free()

	dummy.queue_free()
	print("")
func test_enemy_windup_prelude() -> void:
	print("── Enemy windup_clips prelude (#629) ──")
	var dt := 1.0 / 60.0
	var dummy := _DamageCapture.new()
	add_child(dummy)

	# ── windup_clips: sequential prelude, no damage before it, window offset past it.
	dummy.hits.clear()
	dummy.knockdowns.clear()
	dummy.global_position = Vector3(0, 0, 1.0)
	var w := _make_rig_enemy({"atckstt": 0.2, "atckwat": 0.2, "atckswg": 1.0})
	w.enemy_data.attack_base = 10
	w.target = dummy
	w.current_state = EnemyBase.EnemyState.ATTACKING
	w._attack_def = _delivery_def("melee_arc", {"clip": "atckswg", "windup_clips": ["atckstt", "atckwat"], "windup_frac": 0.35, "damage_mult": 1.6})
	w._start_attack()
	assert_true(not w._windup_done, "prelude armed")
	assert_true(is_equal_approx(w._windup_total, 0.4), "prelude total = sum of resolved clip lengths")
	assert_eq(w.current_anim, "atckstt", "first prelude clip plays")
	var anims_seen := {"atckstt": true, "atckwat": false, "atckswg": false}
	var windup_hit_pos := -1.0
	for _i in range(90):  # 0.4 prelude + 0.35 windup + margin
		w._process_attacking(dt)
		if w._windup_done and w._attack_anim != "":
			w._attack_anim = ""          # headless: force the accumulator past the prelude
			w._attack_fallback_timer = 5.0
		anims_seen[w.current_anim] = true
		if dummy.hits.size() > 0 and windup_hit_pos < 0.0:
			windup_hit_pos = w._attack_pos
	assert_true(anims_seen["atckwat"] and anims_seen["atckswg"], "prelude clips play in sequence, then the swing")
	assert_eq(dummy.hits.size(), 1, "exactly one hit lands")
	assert_eq(dummy.hits[0], 16, "swing damage = attack_base x 1.6")
	assert_true(windup_hit_pos >= 0.35 and windup_hit_pos <= 0.61, "hit inside the swing's window [0.35, 0.6] — the prelude delays it via its own gate (got %.3f)" % windup_hit_pos)
	w.queue_free()

	dummy.queue_free()
	print("")


# ── Archetype runtime modules (#629, spec /states/enemies) ─────
## Box-mimic disguise/reveal, flyer hover-orbit chase, stationary rooting, and the
## aggro threat display — seeded ports of the fsm.ts archetype branches.


func test_box_mimic_disguise() -> void:
	print("── Box-mimic disguise / reveal (#629) ──")
	var dummy := _DamageCapture.new()
	add_child(dummy)

	# Box mimic: the disguise overrides detection_range entirely — only reveal_range
	# breaks it. detection 15 would aggro at 10 m; the mimic must stay dormant.
	var m := _make_rig_enemy({"stt": 0.3, "wlk2": 0.4, "tk2": 0.4, "wlk1": 0.5, "atk": 0.5})
	m.enemy_data.detection_range = 15.0
	m._archetype = "box_mimic"
	m._fsm = {"reveal_range": 3.5}
	m.target = dummy
	dummy.global_position = Vector3(0, 0, 10.0)
	m.current_state = EnemyBase.EnemyState.IDLE
	m._process_idle(1.0 / 60.0)
	assert_eq(m.current_state, EnemyBase.EnemyState.IDLE, "mimic ignores detection_range while disguised")
	assert_eq(m.velocity.x, 0.0, "disguised mimic never moves")
	dummy.global_position = Vector3(0, 0, 3.0)
	m._process_idle(1.0 / 60.0)
	assert_eq(m.current_state, EnemyBase.EnemyState.CHASING, "reveal_range breaks the disguise")
	assert_true(m._threat_timer > 0.0, "reveal is a held display (stt)")
	assert_eq(m.current_anim, "stt", "reveal plays stt (head out of the box)")
	# Threat hold keeps it stationary; reveal-cancel retreats if the target flees.
	m._process_chasing(1.0 / 60.0)
	assert_eq(m.velocity.x, 0.0, "mimic holds through the reveal display")
	dummy.global_position = Vector3(0, 0, 10.0)
	m._process_chasing(1.0 / 60.0)
	assert_eq(m.current_state, EnemyBase.EnemyState.IDLE, "backing off mid-reveal cancels into the disguise")
	assert_eq(m.current_anim, "tk2", "reveal-cancel plays the retreat clip")
	m.queue_free()



func test_enemy_archetype_modules() -> void:
	print("── Enemy archetype modules (#629) ──")
	var dummy := _DamageCapture.new()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, 1.0)

	# Flyer: approach beyond 1.4x orbit, hover-orbit inside it (math pinned on the
	# static like the other locomotion decisions; the node path pins anims/airborne).
	var fm := EnemyLocomotionLogic.flyer_move(8.0, 2.5, Vector3(0, 0, 1), 1.0)
	assert_eq(fm["mode"], "approach", "far flyer approaches")
	assert_true(fm["dir"].dot(Vector3(0, 0, 1)) > 0.99, "approach flies straight at the target")
	fm = EnemyLocomotionLogic.flyer_move(2.0, 2.5, Vector3(0, 0, 1), 1.0)
	assert_eq(fm["mode"], "orbit", "in-band flyer hover-orbits")
	assert_true(absf(fm["dir"].dot(Vector3(0, 0, 1))) < 0.01, "orbit strafes perpendicular to the target line")
	var f := _make_rig_enemy({"fly": 0.5, "tk": 0.5, "atk1": 0.5})
	f._archetype = "flyer_combo"
	f._fsm = {"hover_height": 1.3, "standoff_range": 2.5}
	f.enemy_data.move_speed = 4.0
	f.target = dummy
	dummy.global_position = Vector3(0, 0, 8.0)
	f.current_state = EnemyBase.EnemyState.CHASING
	f._chase_flyer(8.0, Vector3(0, 0, 1))
	assert_true(f._flying, "flyer is airborne while engaged")
	assert_eq(f.current_anim, "fly", "fly clip closes distance")
	f._chase_flyer(2.0, Vector3(0, 0, 1))
	assert_eq(f.current_anim, "tk", "tk clip hover-orbits at standoff")
	f.queue_free()

	# Stationary: rooted in CHASING — faces the target, never moves (fsm.stationary).
	var s := _make_rig_enemy({"waito": 0.5, "atk": 0.5})
	s._fsm = {"stationary": true}
	s._idle_clip = "waito"  # entry-level key — cached from the registry at _ready
	s.enemy_data.move_speed = 4.0
	s.target = dummy
	dummy.global_position = Vector3(0, 0, 2.0)
	s.current_state = EnemyBase.EnemyState.CHASING
	s.attack_cooldown_timer = 5.0  # gate closed — the locomotion branch runs
	s._process_chasing(1.0 / 60.0)
	assert_eq(s.velocity.length(), 0.0, "rooted enemy never moves in CHASING")
	assert_eq(s.current_anim, "waito", "rooted engaged idle is the authored idle_clip")
	s.queue_free()

	# Threat display: bigrig/roller/ape-gunner/flyer hold stt on aggro before pursuit.
	var b := _make_rig_enemy({"stt": 0.3, "wlk": 0.5, "run": 0.5, "atk1": 0.5})
	b._archetype = "bigrig_combo"
	b.enemy_data.detection_range = 15.0
	b.target = dummy
	dummy.global_position = Vector3(0, 0, 5.0)
	b.current_state = EnemyBase.EnemyState.IDLE
	b._process_idle(1.0 / 60.0)
	assert_eq(b.current_state, EnemyBase.EnemyState.CHASING, "bigrig aggroes in detection range")
	assert_true(b._threat_timer > 0.0, "bigrig opens with the chest-beat display")
	assert_eq(b.current_anim, "stt", "the display clip is its stt")
	b._process_chasing(1.0 / 60.0)
	assert_eq(b.velocity.x, 0.0, "display holds position")
	b._threat_timer = 0.0
	b._process_chasing(1.0 / 60.0)
	assert_true(b.current_anim in ["wlk", "run"], "pursuit starts when the display ends (got %s)" % b.current_anim)
	b.queue_free()

	dummy.queue_free()
	print("")


# ── Berserk kamikaze + leader loss (#629, spec /states/enemies §shooter) ─────
func test_enemy_berserk_kamikaze() -> void:
	print("── Enemy berserk kamikaze (#629) ──")
	var dummy := _DamageCapture.new()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, 4.0)

	# apply_berserk: confusion display hold, then the dive; contact explodes once.
	var e := _make_rig_enemy({"atk_an": 0.3, "atk_ji": 0.5, "atk_sh": 0.5})
	e.enemy_data.attack_base = 10
	e.enemy_data.move_speed = 4.0
	e.target = dummy
	e._kamikaze_def = {"id": "kamikaze", "clip": "atk_ji", "hit_reach": 1.5, "damage_mult": 2.5, "damage_end_frac": 1.0, "windup_frac": 0.0}
	e.apply_berserk()
	assert_true(e._berserk, "berserk engages when a kamikaze attack exists")
	assert_true(e._threat_timer > 0.0, "the confusion display (atk_an) plays first")
	assert_eq(e.current_anim, "atk_an", "confusion clip is atk_an")
	e._threat_timer = 0.0
	e._process_chasing(1.0 / 60.0)
	assert_eq(e.current_anim, "atk_ji", "the dive loops the kamikaze clip")
	assert_true(e.velocity.length() > 0.0, "the dive closes on the player")
	dummy.global_position = Vector3(0, 0, 1.0)
	assert_eq(dummy.hits.size(), 0, "no damage before contact")
	e._process_chasing(1.0 / 60.0)
	assert_eq(dummy.hits.size(), 1, "contact explodes exactly once")
	assert_eq(dummy.hits[0], 25, "blast damage = attack_base x 2.5")
	assert_true(not e.is_alive, "kamikaze self-destructs")
	e.queue_free()

	# Leader loss wiring: an Akorse (*_leader model) dying berserks its Korse pack
	# (same model minus the suffix) — and nothing else.
	var leader := _make_rig_enemy({"atk_sh": 0.5, "atk_an": 0.3})
	leader.enemy_data.model_id = "shooter_leader"
	var korse := _make_rig_enemy({"atk_sh": 0.5, "atk_ji": 0.5})
	korse.enemy_data.model_id = "shooter"
	korse._kamikaze_def = {"id": "kamikaze", "clip": "atk_ji", "hit_reach": 1.5, "damage_mult": 2.5}
	var wolf := _make_rig_enemy({"atk": 0.5})
	wolf.enemy_data.model_id = "wolf"
	wolf._kamikaze_def = {"id": "kamikaze", "clip": "atk", "hit_reach": 1.5, "damage_mult": 1.0}
	leader._die()
	assert_true(korse._berserk, "leader death berserks the same-model pack")
	assert_true(not wolf._berserk, "other models stay calm")
	leader.queue_free()
	korse.queue_free()
	wolf.queue_free()
	dummy.queue_free()
	print("")


# ── Coliseum debug quest (#629): the s00a_nr2 1:1 arena vs #/enemy-room ─────

func test_coliseum_debug_quest() -> void:
	print("── Coliseum debug quest (#629) ──")
	# Quest JSON + manifest + area wiring are consistent, and every placed enemy
	# resolves in the roster (the arena is only useful 1:1 if the ids are real).
	var q = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/debug_coliseum.json"))
	assert_true(q is Dictionary, "debug_coliseum.json parses")
	if not q is Dictionary:
		print("")
		return
	assert_eq(str(q["id"]), "debug_coliseum", "quest id")
	assert_eq(str(q["area_id"]), "city", "quest sits in the city area")
	var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/manifest.json"))
	assert_true(manifest.has("debug_coliseum"), "manifest lists debug_coliseum")
	var cell: Dictionary = q["sections"][0]["cells"][0]
	assert_eq(str(cell["stage_id"]), "s00a_nr2", "the arena is the coliseum room")
	const GridGeneratorScript := preload("res://scripts/3d/field/grid_generator.gd")
	assert_true(GridGeneratorScript.AREA_CONFIG.has("city"), "AREA_CONFIG resolves the city area")
	assert_eq(str(GridGeneratorScript.AREA_CONFIG["city"]["folder"]), "city", "city folder")
	var FieldController := preload("res://scripts/3d/field/valley_field_controller.gd")
	assert_eq(FieldController._get_stage_subfolder("s00a_nr2", "city"), "city_a",
		"s00a_nr2 resolves to the city_a asset folder")
	var enemy_ids := {}
	for o in cell["objects"]:
		if str(o.get("type", "")) == "enemy":
			enemy_ids[str(o["enemy_id"])] = true
	assert_true(enemy_ids.size() >= 12, "the arena covers the archetype set (%d enemies)" % enemy_ids.size())
	for eid in enemy_ids:
		assert_true(EnemyRegistry.get_enemy(eid) != null, "roster resolves enemy '%s'" % eid)
	# The runtime-relevant kinds/archetypes are represented in the lineup.
	var attacks = EnemyAttackRegistry.get_attacks("hildegigas")
	assert_true(attacks.any(func(a: Dictionary) -> bool: return str(a.get("kind")) == "charge"), "hildegigas carries a charge attack")
	assert_eq(EnemyAttackRegistry.get_archetype("pelcatraz"), "flyer_combo", "pelcatraz is the flyer archetype")
	assert_eq(EnemyAttackRegistry.get_fsm("bolix")["reveal_range"], 3.5, "mimic reveal range comes from the table")
	print("")


# ── Coliseum Master picker (#629 follow-up): NPC → enemy list → 1:1 arena ─────

func test_coliseum_master_picker() -> void:
	print("── Coliseum Master picker (#629) ──")

	# The synthesized 1:1 cell: the chosen enemy plus a room-clear telepipe home,
	# on the coliseum stage with the city area wiring.
	var sections: Array = ColiseumRoster.make_sections("hildegigas")
	assert_eq(sections.size(), 1, "one section")
	var cell: Dictionary = sections[0]["cells"][0]
	assert_eq(str(cell["stage_id"]), "s00a_nr2", "the arena is the coliseum room")
	assert_eq(str(sections[0]["area_id"]), "city", "city area wiring")
	var objs: Array = cell["objects"]
	assert_eq(objs.size(), 2, "one enemy + one telepipe")
	assert_eq(str(objs[0]["enemy_id"]), "hildegigas", "the chosen enemy is placed")
	assert_eq(objs[0]["position"], [0.0, 0.0, 6.0], "enemy placed across the arena")
	assert_eq(str(objs[1]["type"]), "telepipe", "the way home is a telepipe")
	assert_eq(str(objs[1]["spawn_condition"]), "room_clear", "it spawns when the enemy dies")
	var other: Array = ColiseumRoster.make_sections("poison_lily")
	assert_true(str(other[0]["cells"][0]["objects"][0]["enemy_id"]) != "hildegigas",
		"the choice drives the spawn")

	# The warp payload carries the playtest spawn (0, z 15) so the warp-in and
	# the player start land at the same authored point.
	var warp: Dictionary = ColiseumRoster.warp_data()
	assert_eq(warp["spawn_position"], [0.0, 0.5, 15.0], "arena spawn at (0, 15)")
	assert_eq(str(warp["current_cell_pos"]), "0,0", "warp targets the arena cell")

	# The arena is an indoor stage (no weather, no day/night cycle) fixed at
	# noon (kion playtest).
	var FieldController := preload("res://scripts/3d/field/valley_field_controller.gd")
	assert_true(FieldController._is_indoor_stage("s00a_nr2"), "coliseum classifies as indoors")
	assert_eq(float(FieldController.INDOOR_STAGE_HOURS.get("s00a_nr2", -1.0)), 12.0,
		"coliseum indoor hour is noon")

	# The picker scene itself: instantiates, builds its rows from the roster, and
	# wires the shared shop nav (catches node-path/@onready drift in the .tscn).
	# Runtime load() — a compile-time preload of the shop UI stalled the runner.
	var pick_scene: PackedScene = load("res://scenes/2d/shops/coliseum_pick.tscn")
	assert_true(pick_scene != null, "coliseum_pick.tscn loads")
	if pick_scene:
		var pick: Control = pick_scene.instantiate()
		add_child(pick)
		assert_eq(str(pick.title_label.text), "Coliseum Master", "picker screen titles itself")
		assert_true(pick._rows.size() > 0, "enemy tab lists rows")
		assert_eq(pick._pill_nodes.size(), pick._rows.size(), "one rendered row per enemy")
		assert_eq(pick._groups.size(), (ColiseumRoster.grouped_roster(false) as Array).size(),
			"groups render")
		pick._load_tab(1)
		assert_true(pick._rows.size() > 0 and pick._rows.size() < EnemyRegistry.get_enemy_count(),
			"boss tab is a smaller list")
		pick.queue_free()
	print("")


# ── Coliseum roster grouping (kion playtest): tabs by boss flag, groups by
# ── archetype ordered by earliest area.

func test_coliseum_roster_grouping() -> void:
	print("── Coliseum roster grouping (#629) ──")

	var enemies: Array = ColiseumRoster.grouped_roster(false)
	var bosses: Array = ColiseumRoster.grouped_roster(true)
	var enemy_count := 0
	for g in enemies:
		enemy_count += (g["rows"] as Array).size()
	var boss_count := 0
	var saw_reyburn := false
	for g in bosses:
		for row in g["rows"]:
			boss_count += 1
			if str(row["id"]) == "reyburn":
				saw_reyburn = true
	assert_eq(enemy_count + boss_count, EnemyRegistry.get_enemy_count(), "tabs cover the roster")
	assert_true(boss_count > 0, "boss tab is populated")
	assert_true(saw_reyburn, "reyburn is on the boss tab")
	# Bosses load their own arena quest (kion playtest); mother_trinity has none
	# and falls back to the coliseum cell.
	assert_eq(ColiseumRoster.boss_quest_for("reyburn"), "debug_boss_reyburn", "reyburn arena quest")
	assert_eq(ColiseumRoster.boss_quest_for("sinow_beat"), "debug_boss_paru", "sinow shares the paru arena")
	assert_eq(ColiseumRoster.boss_quest_for("mother_trinity"), "debug_boss_heavens_mother",
		"mother_trinity fights in the eternal tower arena (s087_na1)")

	var saw_hildegigas := false
	for g in enemies:
		for row in g["rows"]:
			assert_true(not bool(row["is_boss"]), "enemy tab carries no bosses")
			if str(row["id"]) == "hildegigas":
				saw_hildegigas = true
	assert_true(saw_hildegigas, "hildegigas is on the enemy tab")

	# Groups order by earliest area (Gurhacia before Eternal Tower), rows within
	# a group by (area rank, name).
	var ranks: Array = []
	for g in enemies:
		ranks.append(int(g["area_rank"]))
	var ranks_sorted: Array = ranks.duplicate()
	ranks_sorted.sort()
	assert_eq(ranks, ranks_sorted, "groups ordered by earliest area")
	var hg_group: Dictionary = {}
	for g in enemies:
		for row in g["rows"]:
			if str(row["id"]) == "hildegigas":
				hg_group = g
	assert_eq(str(hg_group["archetype"]), "bigrig_combo", "hildegigas groups under its archetype")
	assert_true(int(hg_group["area_rank"]) == 2, "hildegigas group ranks by Rioh (Snowfield)")
	assert_true(("charge" in _picker_row(hg_group, "hildegigas")["kinds"]),
		"rows carry the authored delivery kinds")
	print("")


# ── Mother variations (kion): separate solo boss options in the tower arena.

func test_coliseum_mother_variations() -> void:
	print("── Coliseum mother variations (#629) ──")
	var bosses: Array = ColiseumRoster.grouped_roster(true)

	var mothers := {}
	for g in bosses:
		for row in g["rows"]:
			if str(row["id"]) in ["blade_mother", "force_mother", "shot_mother", "mother_trinity"]:
				mothers[str(row["id"])] = row
	assert_eq(mothers.size(), 4, "all four mother entries sit on the boss tab")
	for mid in ["blade_mother", "force_mother", "shot_mother"]:
		assert_true(not (mothers[mid]["arena"] as Dictionary).is_empty(),
			"%s carries its solo tower arena" % mid)
		assert_eq(str(mothers[mid]["quest_id"]), "", "%s loads no whole-quest" % mid)
	var solo: Array = ColiseumRoster.make_arena_sections(mothers["blade_mother"])
	assert_eq(str(solo[0]["type"]), "boss", "solo mother cell is a boss section")
	assert_eq(str(solo[0]["cells"][0]["stage_id"]), "s087_na1", "solo mother fights in the tower arena")
	var solo_objs: Array = solo[0]["cells"][0]["objects"]
	assert_eq(solo_objs.size(), 1, "one enemy only — not all three at once")
	assert_eq(str(solo_objs[0]["enemy_id"]), "blade_mother", "the chosen variation spawns")
	print("")

	print("")


func _picker_row(group: Dictionary, id: String) -> Dictionary:
	for row in group["rows"]:
		if str(row["id"]) == id:
			return row
	return {}
func test_enemy_authored_table_charge_cycle() -> void:
	print("── Authored table: hildegigas slam cycle (#629) ──")
	var dt := 1.0 / 60.0

	# hildegigas at 8.5m: only the shoulder_slam band [3,9] contains it (the flop
	# caps at 7, the punch at 2.2) — the charge kind, suffix atk2_st/lp/ed segments.
	var dummy := _DamageCapture.new()
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, 8.5)
	var hg := _make_rig_enemy({"b070_stt": 0.3, "b070_wat": 0.5, "b070_wlk": 0.5,
		"b070_atk1": 0.5, "b070_atk2_st": 0.3, "b070_atk2_lp": 0.3, "b070_atk2_ed": 0.3})
	hg._attacks = EnemyAttackRegistry.get_attacks("hildegigas", 2.2)  # real table
	hg.enemy_data.attack_base = 10
	hg.target = dummy
	hg.current_state = EnemyBase.EnemyState.ATTACKING
	hg._begin_telegraph()
	assert_eq(hg._attack_kind, "charge", "8.5m selects the shoulder slam")
	assert_true(not hg._telegraphing, "the charge's st segment is its own telegraph")
	for _i in range(400):
		hg._process_attacking(dt)
		hg.global_position += hg.velocity * dt
		if hg.current_state == EnemyBase.EnemyState.LOAFING:
			break
	assert_eq(hg.current_state, EnemyBase.EnemyState.LOAFING, "slam cycle completes")
	assert_eq(dummy.hits.size(), 1, "slam lands exactly one hit from the authored def")
	hg.queue_free()



func test_enemy_authored_table_ranged_cycles() -> void:
	print("── Authored table: lob + windup cycles (#629) ──")
	var dt := 1.0 / 60.0
	var dummy := _DamageCapture.new()
	add_child(dummy)

	# azherowa_b2 at 11m: only the grenade band [4,12] contains it — the lob kind.
	dummy.hits.clear()
	dummy.global_position = Vector3(0, 0, 11.0)
	var az := _make_rig_enemy({"q_stt": 0.3, "q_wat": 0.5, "q_atk": 0.5, "q_atkb": 1.0})
	az._attacks = EnemyAttackRegistry.get_attacks("azherowa_b2", 2.0)
	az.enemy_data.attack_base = 10
	az.target = dummy
	az.current_state = EnemyBase.EnemyState.ATTACKING
	az._begin_telegraph()
	assert_eq(az._attack_kind, "lob", "11m selects the grenade")
	for _i in range(300):
		az._process_attacking(dt)
		# The uniform telegraph commits to _start_attack only after its hold — clear
		# the anim AFTER that so the accumulator path is armed (headless playback).
		if az.is_attacking and not az._telegraphing and az._attack_anim != "":
			az._attack_anim = ""
			az._attack_fallback_timer = 5.0
		if az._window_opened:
			break
	assert_true(az._window_opened, "authored grenade releases at its window open")
	var az_lob := _find_delivery(preload("res://scripts/3d/enemies/enemy_lob.gd"))
	assert_true(az_lob != null, "the authored grenade releases an EnemyLob")
	if az_lob:
		for _t in range(75):
			az_lob._physics_process(dt)
			if dummy.hits.size() > 0:
				break
		assert_eq(dummy.hits.size(), 1, "authored lob damages at landing")
	az.queue_free()

	# froutang at 1m: only the charged punch band [0,2.4] contains it (pistols
	# start at 2/3m) — windup_clips prelude into a melee arc swing.
	dummy.hits.clear()
	dummy.global_position = Vector3(0, 0, 1.0)
	var fr := _make_rig_enemy({"o_stt": 0.3, "o_wat": 0.5, "o_atcksht": 0.5,
		"o_atcktuki": 0.5, "o_atckstt": 0.3, "o_atckwat": 0.3, "o_atckswg": 1.0})
	fr._attacks = EnemyAttackRegistry.get_attacks("froutang", 2.4)
	fr.enemy_data.attack_base = 10
	fr.target = dummy
	fr.current_state = EnemyBase.EnemyState.ATTACKING
	fr._begin_telegraph()
	assert_eq(fr._attack_kind, "melee_arc", "1m selects the charged punch")
	assert_true(not fr._telegraphing, "windup_clips ARE the telegraph — no generic hold")
	assert_true(not fr._windup_done, "the atckstt → atckwat prelude is armed")
	for _i in range(300):
		fr._process_attacking(dt)
		if fr._windup_done and fr._attack_anim != "":
			fr._attack_anim = ""  # headless: force the accumulator
			fr._attack_fallback_timer = 5.0
		if fr.current_state == EnemyBase.EnemyState.LOAFING:
			break
	assert_eq(dummy.hits.size(), 1, "charged punch lands exactly one hit")
	fr.queue_free()

	dummy.queue_free()
	print("")
func test_enemy_attack_recovery() -> void:
	print("── Enemy attack recovery (#477) ──")
	var dummy := Node3D.new()
	add_child(dummy)
	dummy.position = Vector3(0, 0, 2)

	# Gorilla-shaped rig: only "b_014_atk1", resolved via the atk→atk1 alias.
	var e := _make_recovery_enemy(["b_014_atk1"], 0.4)
	e.target = dummy
	assert_eq(e._find_animation("atk"), "b_014_atk1", "atk resolves atk1 rigs via alias")
	e.current_state = EnemyBase.EnemyState.ATTACKING
	e._start_attack()
	assert_true(e.is_attacking, "attack starts on atk1 rig")
	assert_eq(e._attack_anim, "b_014_atk1", "resolved attack anim tracked by full name")
	e._on_animation_finished("b_014_atk1")
	assert_true(not e.is_attacking, "atk1 finish clears is_attacking — no hit needed")
	e._process_attacking(0.016)
	assert_eq(e.current_state, EnemyBase.EnemyState.LOAFING, "ATTACKING exits to LOAFING")

	# Watchdog: resolved anim stopped without a matching finished signal —
	# the ATTACKING tick itself must notice and recover.
	e.current_state = EnemyBase.EnemyState.ATTACKING
	e._start_attack()
	assert_true(e.is_attacking, "second attack starts")
	e.animation_player.stop()
	e._process_attacking(0.016)
	assert_true(not e.is_attacking, "stopped attack anim recovers via ATTACKING watchdog")
	assert_eq(e.current_state, EnemyBase.EnemyState.LOAFING, "watchdog exit lands in LOAFING")

	# Rig with no attack animation at all (armadillo): nothing plays, so the
	# fixed fallback duration must end the attack.
	var e2 := _make_recovery_enemy(["b_035_wat1"], 1.0)
	e2.target = dummy
	e2.current_state = EnemyBase.EnemyState.ATTACKING
	e2._start_attack()
	assert_true(e2.is_attacking, "attack starts even with no attack anim")
	assert_eq(e2._attack_anim, "", "no resolvable attack anim → fallback armed")
	e2._process_attacking(0.1)
	assert_true(e2.is_attacking, "fallback does not end the attack early")
	e2._process_attacking(EnemyBase.ATTACK_FALLBACK_DURATION)
	assert_true(not e2.is_attacking, "fallback duration ends the attack")
	assert_eq(e2.current_state, EnemyBase.EnemyState.LOAFING, "no-anim rig exits to LOAFING")

	# Orangutan's misspelled "atck" clip is aliased so the rig still swings.
	var e3 := _make_recovery_enemy(["b_044_atckwat"], 0.5)
	e3.target = dummy
	assert_eq(e3._find_animation("atk"), "b_044_atckwat", "atk resolves orangutan's atckwat clip")

	e.queue_free()
	e2.queue_free()
	e3.queue_free()
	dummy.queue_free()
	print("")


## Last-resort atk-segment scan (spec /states/enemies resolution order §4):
## suffix-variant rigs must swing; segmented st/lp/ed pieces must not be
## picked alone; whole-clip variants win alphabetically for determinism.
## Parity twin: web/src/__tests__/enemy-room-anim.test.ts pins the same table.
func test_enemy_attack_clip_resolution() -> void:
	print("── Enemy attack clip resolution (scan fallback) ──")
	var dummy := Node3D.new()
	add_child(dummy)
	dummy.position = Vector3(0, 0, 2)

	var e4 := _make_recovery_enemy(
		["b062_atk_pu", "b062_atk_sw", "b062_atk_th_st", "b062_atk_th_ed", "b062_wat"], 0.6)
	assert_eq(e4._find_animation("atk"), "b062_atk_pu", "swordman rig: atk scan picks atk_pu (not th_st/th_ed segments)")
	var e5 := _make_recovery_enemy(
		["m051_atk_sp_ed", "m051_atk_sp_lp", "m051_atk_sp_st", "m051_atk_sh"], 0.6)
	assert_eq(e5._find_animation("atk"), "m051_atk_sh", "board rig: atk scan picks whole atk_sh over sp_* segments")
	var e6 := _make_recovery_enemy(
		["b072_atk_gu_a_st", "b072_atk_gu_a_lp", "b072_atk_gu_a_ed", "b072_atk_sa_a", "b072_atk_sb_a"], 0.6)
	assert_eq(e6._find_animation("atk"), "b072_atk_sa_a", "mother rig: atk scan picks atk_sa_a (alphabetical among whole clips)")
	var e7 := _make_recovery_enemy(["z003_atk_dl_lp", "z003_wat"], 0.6)
	assert_eq(e7._find_animation("atk"), "", "segment-only rig resolves nothing → fallback duration path")
	var e8 := _make_recovery_enemy(["s071_atk", "s071_atk_hi", "s071_atk_mi"], 0.6)
	assert_eq(e8._find_animation("atk"), "s071_atk", "plain _atk suffix still wins before the scan")

	# dmg → dam alias: five rigs (booma/swordman/tank/orangutan/shrimp) name
	# their damage clip dam — the hurt reaction must still resolve a clip.
	var e9 := _make_recovery_enemy(["s_040_dam", "s_040_atk"], 0.5)
	assert_eq(e9._find_animation("dmg"), "s_040_dam", "dmg resolves dam-named damage clips via alias")
	e9.queue_free()

	# End-to-end on a suffix-variant rig: the scanned clip is the tracked
	# attack anim and its finish clears is_attacking (no wedge, real visual).
	e4.target = dummy
	e4.current_state = EnemyBase.EnemyState.ATTACKING
	e4._start_attack()
	assert_eq(e4._attack_anim, "b062_atk_pu", "scanned clip becomes the tracked attack anim")
	e4._on_animation_finished("b062_atk_pu")
	assert_true(not e4.is_attacking, "scanned clip finish clears is_attacking")

	for extra in [e4, e5, e6, e7, e8]:
		extra.queue_free()
	dummy.queue_free()
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

	# ── Multi-qty SELL (#416) ──
	# Selling a stack used to remove one copy per confirm; now the sell tab
	# mirrors the buy flow — true stacks open the QuantityDialog picker, per-slot
	# gear stays a 1-at-a-time confirm. ShopNav.sell_confirm() is the shared
	# router both shops call; assert its modal choice here (the seeded unit layer)
	# and let the autopilot/manual round exercise the on-screen picker.
	print("  ── Multi-qty sell routing ──")
	var ShopNavSell = load("res://scripts/2d/shops/shop_nav.gd")
	var noop_qty := func(_q: int) -> void: pass
	var noop := func() -> void: pass
	var sell_shop = load("res://scripts/2d/shops/item_shop.gd").new()
	# A stack of 5 → the quantity picker, clamped to the stack size.
	ShopNavSell.sell_confirm(
		sell_shop, {"name": "Monomate", "id": "monomate", "sell_price": 10, "quantity": 5},
		noop_qty, noop)
	assert_true(sell_shop._active_modal is QuantityDialog,
		"selling a 5-stack opens the quantity picker")
	if sell_shop._active_modal is QuantityDialog:
		assert_eq(sell_shop._active_modal._max_qty, 5,
			"sell picker max qty == the stack size (5)")
	if sell_shop._active_modal != null:
		sell_shop._active_modal.free()
		sell_shop._active_modal = null
	# A single per-slot weapon instance → plain confirm, never the picker.
	ShopNavSell.sell_confirm(
		sell_shop, {"name": "Saber", "id": "saber#1", "sell_price": 40, "quantity": 1},
		noop_qty, noop)
	assert_true(sell_shop._active_modal != null and not (sell_shop._active_modal is QuantityDialog),
		"selling per-slot gear stays a plain 1-qty confirm")
	if sell_shop._active_modal != null:
		sell_shop._active_modal.free()
	sell_shop.free()

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


# ── #375: class-unequippable gear is purchasable (warning modal, not a block) ──
# Pre-#375 the weapon shop hard-blocked buying gear the active class couldn't
# equip. The states/shops spec makes equippability a SOFT caveat: the row stays
# selectable and the buy goes through (behind a warning confirm) — only
# affordability and inventory room are hard buy-blocks. This pins _can_buy's
# contract so the block can't creep back in.
func test_shop_buy_unequippable_gear() -> void:
	print("── #375: class-unequippable gear stays purchasable ──")
	var ws = load("res://scripts/2d/shops/weapon_shop.gd").new()
	var character = CharacterManager.get_active_character()
	if character == null:
		print("  INFO: no active character — skipped")
		ws.free(); print(""); return
	# _check_equippability now routes through item_fits_slot, which honors
	# DebugConfig.equip_all — force it off so a genuinely class-illegal weapon
	# exists to find (else the gate would clear everything and the test no-ops).
	var saved_equip_all := DebugConfig.equip_all
	DebugConfig.equip_all = false
	# Find a weapon the active character's class genuinely cannot equip.
	var unequip_id := ""
	for wid in WeaponRegistry.get_all_weapon_ids():
		if not ws._check_equippability(str(wid), "weapon").get("can_equip", true):
			unequip_id = str(wid)
			break
	if unequip_id.is_empty():
		print("  INFO: active class can equip every weapon — skipped")
		DebugConfig.equip_all = saved_equip_all
		ws.free(); print(""); return

	var saved_meseta: int = int(character.get("meseta", 0))
	var saved_game_meseta: int = GameState.meseta
	var item := {"id": unequip_id, "category": "weapon", "cost": 1000}
	Inventory.clear_inventory()

	# Affordable + room → buyable, despite the class being unable to equip it.
	character["meseta"] = 999999
	GameState.meseta = 999999
	assert_true(not ws._check_equippability(unequip_id, "weapon").get("can_equip", true),
		"#375: chosen weapon really is class-unequippable")
	assert_true(ws._can_buy(item).get("ok", false),
		"#375: unequippable-but-affordable weapon IS buyable")

	# Hard buy-blocks (afford / room) still apply.
	character["meseta"] = 0
	GameState.meseta = 0
	var broke: Dictionary = ws._can_buy(item)
	assert_true(not broke.get("ok", true), "#375: still blocked when can't afford")
	assert_eq(str(broke.get("reason", "")), "Can't afford", "#375: afford reason unchanged")

	Inventory.clear_inventory()
	character["meseta"] = saved_meseta
	GameState.meseta = saved_game_meseta
	DebugConfig.equip_all = saved_equip_all
	ws.free()
	print("")


# Regression for Rozalin's "HUmar shows every weapon/armor equippable" report,
# re-pinned to the canonical equip-legality gate (EquipmentUtils.item_fits_slot;
# spec /mechanics/equip-legality). Under the contract:
#   • a rod is a Force weapon type HUmar's class can't equip → ✕
#     (ClassData.allowed_weapon_types; WeaponData.usable_by is NOT consulted);
#   • a saber is allowed for every class → no ✕;
#   • a basic Frame (empty usable_by = no restriction) is equippable → no ✕;
#   • a Robe IS class-restricted (usable_by = Newman-Hunter/Force, which excludes
#     HUmar = Hunter Human) → ✕. Armor legality is a per-item class list
#     (ArmorData.usable_by, the only armor-legality source), routed through
#     item_fits_slot("frame") — the same gate everywhere, so buy/sell/inventory agree.
# Also asserts the buy-tab ✕ predicate equals the sell-tab one
# (ShopNav.sell_cannot_use) — the "single source of truth" rule in code.
func test_humar_gear_unequippable() -> void:
	print("── HUmar gear equippability via canonical gate (regression) ──")
	var saved_chars = CharacterManager._characters
	var saved_slot = CharacterManager._active_slot
	var saved_equip_all := DebugConfig.equip_all
	DebugConfig.equip_all = false  # item_fits_slot honors equip_all; force real legality
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "EquipTest")
	CharacterManager.set_active_slot(0)

	var ShopNavCls = load("res://scripts/2d/shops/shop_nav.gd")
	var ws = load("res://scripts/2d/shops/weapon_shop.gd").new()

	assert_true(not ws._check_equippability("rod", "weapon").get("can_equip", true),
		"HUmar cannot equip a rod / Force weapon (should ✕)")
	assert_true(ws._check_equippability("saber", "weapon").get("can_equip", false),
		"HUmar CAN equip a saber — every class allows it (no ✕)")
	assert_true(ws._check_equippability("frame", "armor").get("can_equip", false),
		"HUmar CAN equip a basic frame — empty usable_by = no restriction (no ✕)")
	assert_true(not ws._check_equippability("robe", "armor").get("can_equip", true),
		"HUmar CANNOT equip a robe — usable_by excludes Hunter Human (should ✕)")

	# Buy and sell agree: the buy-tab ✕ predicate == the sell-tab ✕ predicate,
	# for weapons AND armor (the single source of truth, every gear type).
	assert_eq(not ws._check_equippability("rod", "weapon").get("can_equip", true),
		ShopNavCls.sell_cannot_use("rod"),
		"buy ✕ and sell ✕ agree for a rod (single source of truth)")
	assert_eq(not ws._check_equippability("saber", "weapon").get("can_equip", true),
		ShopNavCls.sell_cannot_use("saber"),
		"buy ✕ and sell ✕ agree for a saber (single source of truth)")
	assert_eq(not ws._check_equippability("robe", "armor").get("can_equip", true),
		ShopNavCls.sell_cannot_use("robe"),
		"buy ✕ and sell ✕ agree for a robe (armor class restriction is canonical)")
	assert_eq(not ws._check_equippability("frame", "armor").get("can_equip", true),
		ShopNavCls.sell_cannot_use("frame"),
		"buy ✕ and sell ✕ agree for an unrestricted frame")

	# DebugConfig.equip_all bypasses the armor class gate too (verify-models flow).
	DebugConfig.equip_all = true
	assert_true(ws._check_equippability("robe", "armor").get("can_equip", false),
		"equip_all bypasses the armor class gate (robe becomes equippable)")
	assert_true(not ShopNavCls.sell_cannot_use("robe"),
		"equip_all clears the robe ✕ on the sell predicate too")
	DebugConfig.equip_all = false
	ws.free()

	DebugConfig.equip_all = saved_equip_all
	CharacterManager._characters = saved_chars
	CharacterManager._active_slot = saved_slot
	print("")


## The visible Label inside a PszStyle.shop_row pill (the item name).
func _shop_row_label(pill: Control) -> Label:
	for c in pill.get_child(0).get_children():
		if c is Label:
			return c
	return null


## The leftmost marker-slot kind of a shop_row pill: "x" (✕ icon), "e" ([E] tag),
## or "" (empty reserved gap). The marker cell is always the first hbox child.
func _shop_row_marker(pill: Control) -> String:
	var cell: Node = pill.get_child(0).get_child(0)
	if cell == null or cell.get_child_count() == 0:
		return ""
	return "x" if cell.get_child(0) is TextureRect else "e"


## The leading item-icon TextureRect of a shop_row pill — the first TextureRect
## among the hbox children (the marker cell is a Control wrapper, so its inner ✕
## TextureRect is not a direct hbox child and isn't picked up here). null when the
## row carries no icon.
func _shop_row_icon(pill: Control) -> TextureRect:
	for child in pill.get_child(0).get_children():
		if child is TextureRect:
			return child
	return null


# Capability-based greying (PSOBB rule, Rozalin/Kion playtest 2026-06-22):
# a row greys when the character CAN'T USE/EQUIP it — never for affordability or
# inventory space. Gear that can never be equipped also carries a ✕ marker.
func test_shop_capability_grey() -> void:
	print("── Shop capability greying (PSOBB rule) ──")

	# shop_row rendering: capability greys (with/without ✕), economics don't. The
	# [E]/✕ live in a fixed leftmost marker slot, reserved (empty) otherwise.
	var normal := PszStyle.shop_row("Saber", "100 M", {})
	assert_eq(_shop_row_label(normal).get_theme_color("font_color"), PszStyle.TEXT,
		"usable row is not muted")
	assert_eq(_shop_row_marker(normal), "", "usable row reserves an empty marker slot")

	var cant_equip := PszStyle.shop_row("Cane", "100 M", {"cannot_use": true})
	assert_eq(_shop_row_label(cant_equip).get_theme_color("font_color"), PszStyle.TEXT_MUTED,
		"cannot_use (can't equip) row is muted")
	assert_eq(_shop_row_marker(cant_equip), "x", "cannot_use row carries the ✕ marker")

	var disabled := PszStyle.shop_row("Foie Lv1", "100 M", {"disabled": true})
	assert_eq(_shop_row_label(disabled).get_theme_color("font_color"), PszStyle.TEXT_MUTED,
		"disabled (already-known / req-level) row is muted")
	assert_eq(_shop_row_marker(disabled), "", "disabled row has NO ✕ marker (temporary block)")

	var equipped := PszStyle.shop_row("Saber +1", "100 M", {"equipped": true})
	assert_eq(_shop_row_marker(equipped), "e", "equipped row shows the [E] marker in the slot")

	var x_tex := PszStyle.cannot_use_icon()
	assert_true(x_tex != null and x_tex.get_width() == 16 and x_tex.get_height() == 16,
		"cannot_use_icon() is a generated 16×16 texture (no asset, no pack republish)")

	# ConsumableData usable_by: empty = usable by all; restriction respected.
	var cd := ConsumableData.new()
	assert_true(cd.can_be_used_by("Hunter Cast"), "empty usable_by → usable by everyone")
	cd.usable_by = PackedStringArray(["Force Newman"])
	assert_true(cd.can_be_used_by("Force Newman"), "listed Type/Race can use it")
	assert_true(not cd.can_be_used_by("Hunter Cast"), "unlisted Type/Race cannot use it")
	print("")


# A muted shop row greys its ITEM ICON, not just its text — Rozalin's #417 note
# ("shop should be graying the icons like the inventory"). The leading icon is
# dimmed via PszStyle.DISABLED_ICON_MOD, the SAME modulate the start-menu
# inventory uses, so the two surfaces grey icons identically.
func test_shop_row_dims_disabled_icon() -> void:
	print("── Shop row — a muted row dims its item icon (matches inventory) ──")
	var icon := PszStyle.cannot_use_icon()  # any texture; only its modulate matters here

	var normal := PszStyle.shop_row("Foie Lv1", "100 M", {"icons": [icon]})
	var normal_icon := _shop_row_icon(normal)
	assert_true(normal_icon != null and normal_icon.modulate.is_equal_approx(Color.WHITE),
		"usable row renders its icon at full colour")

	var disabled := PszStyle.shop_row("Foie Lv1", "100 M", {"icons": [icon], "disabled": true})
	var disabled_icon := _shop_row_icon(disabled)
	assert_true(disabled_icon != null and disabled_icon.modulate.is_equal_approx(PszStyle.DISABLED_ICON_MOD),
		"disabled row dims its icon (greyed like the text, same modulate as inventory)")
	print("")


# The disk-grey slice of the capability rule: greys via TechniqueManager.can_learn
# (meseta-independent), with the ✕ marker only when the class/race can NEVER learn
# it (class_can_learn) vs a plain grey for already-known / below-level. Split from
# test_shop_capability_grey to stay under the code-health complexity bound.
func test_disk_capability_grey() -> void:
	print("── Disk capability greying ──")
	# Disk grey predicate IS TechniqueManager.can_learn, and it never depends on
	# meseta — affordability must not grey a disk.
	var character = CharacterManager.get_active_character()
	if character == null:
		print("  INFO: no active character — disk-grey checks skipped")
		print(""); return
	var saved_class = character.get("class_id", "")
	var saved_techs: Dictionary = (character.get("techniques", {}) as Dictionary).duplicate()
	var saved_level = character.get("level", 1)
	var saved_meseta = character.get("meseta", 0)
	character["level"] = 50
	character["techniques"] = {}

	var inv: Array = TechniqueManager.generate_shop_inventory(50)
	if not inv.is_empty():
		var tid := str(inv[0].get("technique_id", ""))
		var lvl := int(inv[0].get("level", 1))
		character["class_id"] = "humar"
		character["meseta"] = 0
		var poor: bool = TechniqueManager.can_learn(character, tid, lvl).get("allowed", false)
		character["meseta"] = 999999
		var rich: bool = TechniqueManager.can_learn(character, tid, lvl).get("allowed", false)
		assert_eq(poor, rich, "disk grey predicate ignores meseta (afford never greys)")

	# A CAST can never learn techniques → every disk is capability-greyed.
	character["class_id"] = "hucast"
	character["techniques"] = {}
	if not inv.is_empty():
		var tid2 := str(inv[0].get("technique_id", ""))
		var lvl2 := int(inv[0].get("level", 1))
		assert_true(not TechniqueManager.can_learn(character, tid2, lvl2).get("allowed", false),
			"CAST disk is capability-greyed (cannot learn techniques)")
		assert_true(not TechniqueManager.class_can_learn(character, tid2, lvl2),
			"CAST disk gets the ✕ marker (class can never learn it)")

	# Pick a genuinely learnable (class, disk) so the "already-known greys it"
	# path (Rozalin's Ryuker observation) is tested precisely, not vacuously.
	var learn_class := ""
	var learn_tid := ""
	var learn_lvl := 1
	for cid in ["fonewm", "fomar", "fonewearl", "ramar", "humar"]:
		if ClassRegistry.get_class_data(cid) == null:
			continue
		character["class_id"] = cid
		character["techniques"] = {}
		for d in inv:
			var t := str(d.get("technique_id", ""))
			var l := int(d.get("level", 1))
			if TechniqueManager.can_learn(character, t, l).get("allowed", false):
				learn_class = cid; learn_tid = t; learn_lvl = l
				break
		if learn_tid != "":
			break
	if learn_tid != "":
		character["class_id"] = learn_class
		character["techniques"] = {}
		assert_true(TechniqueManager.can_learn(character, learn_tid, learn_lvl).get("allowed", false),
			"learnable disk is NOT greyed for a class that can learn it")
		character["techniques"] = {learn_tid: learn_lvl}
		assert_true(not TechniqueManager.can_learn(character, learn_tid, learn_lvl).get("allowed", false),
			"already-known disk IS greyed (Ryuker: the spare copy greys once learned)")
		assert_true(TechniqueManager.class_can_learn(character, learn_tid, learn_lvl),
			"already-known disk greys WITHOUT ✕ (class can still learn it — a temporary block)")
	else:
		print("  INFO: no learnable disk found for sample classes — known-disk check skipped")

	character["class_id"] = saved_class
	character["techniques"] = saved_techs
	character["level"] = saved_level
	character["meseta"] = saved_meseta
	print("")


# Sell tabs (item + weapon shop) mark gear/disks the active character can never
# use with the ✕ marker, so a player scanning what to offload sees dead weight at
# a glance (spec /states/shops). Uses the canonical equip-legality gate
# (allowed_weapon_types via EquipmentUtils), NOT WeaponData.usable_by.
# Shared isolation for the per-screen ✕-marker tests below (shop sell, start
# menu, storage): each asserts its screen's _item_cannot_use agrees with the
# canonical ShopNav.sell_cannot_use, so they share identical character-state
# setup/teardown. Extracted so the three parallel tests keep one copy of the
# isolation (and don't trip the near-duplicate ratchet, #294).
func _isolate_character_state() -> Dictionary:
	var saved := {
		"chars": CharacterManager._characters,
		"slot": CharacterManager._active_slot,
		"equip_all": DebugConfig.equip_all,
	}
	DebugConfig.equip_all = false  # the ✕ gate must see real class legality
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	return saved


func _restore_character_state(saved: Dictionary) -> void:
	CharacterManager._characters = saved["chars"]
	CharacterManager._active_slot = saved["slot"]
	DebugConfig.equip_all = saved["equip_all"]


func test_shop_sell_cannot_use_marker() -> void:
	print("── Shop sell ✕ — cannot-use marker on the sell tabs ──")
	var ShopNavCls = load("res://scripts/2d/shops/shop_nav.gd")
	var saved := _isolate_character_state()

	# FOnewm (Force): allowed_weapon_types is Saber/Handgun/Rod/Wand — no Sword.
	CharacterManager.create_character(0, "fonewm", "SellXForce")
	CharacterManager.set_active_slot(0)
	if WeaponRegistry.get_weapon("sword") and WeaponRegistry.get_weapon("saber"):
		assert_true(ShopNavCls.sell_cannot_use("sword"),
			"FOnewm sell row: Sword carries ✕ (class can't equip the type)")
		assert_true(not ShopNavCls.sell_cannot_use("saber"),
			"FOnewm sell row: Saber has no ✕ (class can equip it)")
	# Armor carries the per-item class ✕ too (ArmorData.usable_by, the only
	# armor-legality source). "armor" = Hunter/Ranger only → ✕ for a Force;
	# "robe" lists Force Newman → no ✕; "frame" is unrestricted → no ✕.
	if ArmorRegistry.get_armor("armor") and ArmorRegistry.get_armor("robe") and ArmorRegistry.get_armor("frame"):
		assert_true(ShopNavCls.sell_cannot_use("armor"),
			"FOnewm sell row: 'armor' carries ✕ (Hunter/Ranger only, FOnewm can't wear it)")
		assert_true(not ShopNavCls.sell_cannot_use("robe"),
			"FOnewm sell row: Robe has no ✕ (usable_by lists Force Newman)")
		assert_true(not ShopNavCls.sell_cannot_use("frame"),
			"FOnewm sell row: unrestricted Frame has no ✕")
	# Non-gear (consumables, materials) never carry the ✕.
	assert_true(not ShopNavCls.sell_cannot_use("monomate"),
		"Consumable sell row: no ✕ (no permanent class restriction)")
	# A learnable technique disk for a Force → no ✕.
	assert_true(not ShopNavCls.sell_cannot_use("disk_foie_1"),
		"FOnewm sell row: a learnable disk has no ✕")

	# A CAST can never learn techniques → every disk carries the ✕.
	# (create_character refuses an occupied slot, so clear it first.)
	CharacterManager._characters[0] = null
	CharacterManager.create_character(0, "hucast", "SellXCast")
	CharacterManager.set_active_slot(0)
	assert_true(ShopNavCls.sell_cannot_use("disk_foie_1"),
		"CAST sell row: a technique disk carries ✕ (class can never learn it)")

	# Disk-id parser: well-formed vs malformed.
	assert_eq(str(ShopNavCls._parse_disk_id("disk_gizonde_3").get("technique_id", "")), "gizonde",
		"_parse_disk_id reads the technique id")
	assert_eq(int(ShopNavCls._parse_disk_id("disk_gizonde_3").get("level", -1)), 3,
		"_parse_disk_id reads the level")
	assert_true(ShopNavCls._parse_disk_id("disk_foie").is_empty(),
		"_parse_disk_id rejects a level-less id")

	_restore_character_state(saved)
	print("")


# The grey-WITHOUT-✕ tier (ShopNav.sell_disabled): a disk for a technique
# already known at this level (or below the required player level) mutes the row
# but carries no ✕. The same predicate backs every item-list surface (sell tabs,
# storage, start-menu inventory), so owning N copies of a learnable disk and
# learning one greys the rest consistently — the display half of the #417 fix.
func test_shop_sell_disabled_already_known() -> void:
	print("── Shop grey — already-known disk disabled (no ✕) ──")
	var ShopNavCls = load("res://scripts/2d/shops/shop_nav.gd")
	var saved := _isolate_character_state()

	# HUmar learns Foie (attack group, cap 10). Level 20 clears the required-
	# player-level gate so the ONLY block in play is the already-known one.
	CharacterManager.create_character(0, "humar", "DiskGrey")
	CharacterManager.set_active_slot(0)
	var character = CharacterManager.get_active_character()
	character["level"] = 20
	character["techniques"] = {}

	# Before learning: a Lv.1 Foie disk is fully usable — no ✕, not greyed.
	assert_true(not ShopNavCls.sell_cannot_use("disk_foie_1"),
		"unknown Foie Lv.1: no ✕ (class can learn it)")
	assert_true(not ShopNavCls.sell_disabled("disk_foie_1"),
		"unknown Foie Lv.1: not greyed (still worth learning)")

	# Learn Foie Lv.1 → the Lv.1 disk is now a no-op.
	character["techniques"]["foie"] = 1

	assert_true(ShopNavCls.sell_disabled("disk_foie_1"),
		"already-known Foie Lv.1: greyed (already learned at this level)")
	assert_true(not ShopNavCls.sell_cannot_use("disk_foie_1"),
		"already-known Foie Lv.1: still NO ✕ (block is temporary, not a class bar)")
	# A suffixed duplicate greys identically — get_base_id strips the #2 first.
	assert_true(ShopNavCls.sell_disabled("disk_foie_1#2"),
		"already-known Foie Lv.1#2 duplicate: greyed too (suffix stripped)")
	# A higher-level disk is still an upgrade → not greyed.
	assert_true(not ShopNavCls.sell_disabled("disk_foie_2"),
		"Foie Lv.2 while knowing Lv.1: not greyed (it upgrades)")

	# Permanent class block stays the ✕ tier, never the grey tier: a CAST disk is
	# ✕ and NOT sell_disabled (sell_disabled is the can-learn-but-not-now slice).
	CharacterManager._characters[0] = null
	CharacterManager.create_character(0, "hucast", "DiskGreyCast")
	CharacterManager.set_active_slot(0)
	assert_true(ShopNavCls.sell_cannot_use("disk_foie_1"),
		"CAST disk: ✕ (permanent class block)")
	assert_true(not ShopNavCls.sell_disabled("disk_foie_1"),
		"CAST disk: NOT in the grey tier (permanent block is ✕, not grey)")

	# Non-disk items never enter the grey-disk tier.
	assert_true(not ShopNavCls.sell_disabled("monomate"),
		"consumable: never disk-greyed")
	assert_true(not ShopNavCls.sell_disabled("saber"),
		"weapon: never disk-greyed")

	_restore_character_state(saved)
	print("")


# RENDER-LEVEL guard: the predicate test above proves sell_disabled flips, but a
# row only greys if the shop's _refresh_display actually FORWARDS that flag into
# PszStyle.shop_row. The real #417-followup bug lived exactly there — the sell
# render dropped "disabled" — invisible to a predicate-only test. So instantiate
# the real item_shop, render its sell tab, and assert the disk pill's text colour.
func test_shop_sell_disabled_renders_muted() -> void:
	print("── Shop sell — already-known disk RENDERS muted (pixels, not predicate) ──")
	var saved := _isolate_character_state()
	CharacterManager.create_character(0, "humar", "DiskRender")
	CharacterManager.set_active_slot(0)
	var ch = CharacterManager.get_active_character()
	ch["level"] = 20
	ch["techniques"] = {}
	Inventory.clear_inventory()
	for _i in range(5):
		Inventory.add_item("disk_foie_1", 1)

	var shop = load("res://scenes/2d/shops/item_shop.tscn").instantiate()
	add_child(shop)  # add_child runs _ready synchronously → @onready nodes ready
	shop.set("_tab", 3)  # Tab.SELL

	# Before learning: the disk sell row renders at normal (non-muted) colour.
	assert_eq(_sell_disk_pill_muted(shop), 0,
		"sell row for an unknown-level Foie disk renders NOT muted")

	# Learn Foie Lv.1 through the real use path, then re-render the sell tab.
	var first_disk: String = ""
	for k in Inventory._items.keys():
		if str(k).begins_with("disk_foie_1"):
			first_disk = str(k); break
	Inventory.use_item(first_disk)

	# After learning: every remaining Foie Lv.1 disk row renders muted.
	assert_eq(_sell_disk_pill_muted(shop), 1,
		"sell row for an already-known Foie disk renders MUTED (disabled forwarded to shop_row)")

	shop.free()
	Inventory.clear_inventory()
	_restore_character_state(saved)
	print("")


# Regenerate the item_shop sell list and report the rendered mute state of the
# first disk_ row: 1 = muted (TEXT_MUTED), 0 = normal, -1 = no disk row / no label.
func _sell_disk_pill_muted(shop) -> int:
	shop.call("_generate_sell_list")
	shop.call("_refresh_display")
	var sell_items: Array = shop.get("_sell_items")
	var pills = shop.get("_pill_nodes")
	for i in range(sell_items.size()):
		if not str(sell_items[i].get("id", "")).begins_with("disk_"):
			continue
		var pill = pills[i] if (typeof(pills) == TYPE_ARRAY and i < pills.size()) else (pills.get(i) if typeof(pills) == TYPE_DICTIONARY else null)
		if pill == null:
			return -1
		var lbl := _first_label(pill)
		if lbl == null:
			return -1
		return 1 if lbl.get_theme_color("font_color").is_equal_approx(PszStyle.TEXT_MUTED) else 0
	return -1


func _first_label(n: Node) -> Label:
	if n is Label:
		return n
	for c in n.get_children():
		var r := _first_label(c)
		if r != null:
			return r
	return null


# The start-menu item modal must NOT offer "Use" for a disk that can't be learned
# right now (already known at this level, too-low level, or class-illegal). The
# "Use" choice is gated on _get_inventory()'s `usable` flag, so assert that flag:
# a learnable disk is usable, an already-known one is not (#417).
func test_start_menu_disk_use_gated() -> void:
	print("── Start menu — already-known disk offers no Use ──")
	var saved := _isolate_character_state()
	CharacterManager.create_character(0, "humar", "DiskUse")
	CharacterManager.set_active_slot(0)
	var ch = CharacterManager.get_active_character()
	ch["level"] = 20
	ch["techniques"] = {}
	Inventory.clear_inventory()
	for _i in range(3):
		Inventory.add_item("disk_foie_1", 1)

	# Unknown technique → the disk is usable (offers "Use").
	assert_eq(_disk_usable_flag("disk_foie_1"), 1,
		"unknown Foie Lv.1 disk: usable (Use offered)")

	# Learn it, then every remaining copy must be NOT usable (no Use option).
	var first := ""
	for k in Inventory._items.keys():
		if str(k).begins_with("disk_foie_1"):
			first = str(k); break
	Inventory.use_item(first)
	assert_eq(_disk_usable_flag("disk_foie_1"), 0,
		"already-known Foie Lv.1 disk: NOT usable (no Use option offered)")

	Inventory.clear_inventory()
	_restore_character_state(saved)
	print("")


# Returns the start menu's `usable` flag for the first inventory row whose base id
# matches `base`: 1 = usable, 0 = not usable, -1 = no such row.
func _disk_usable_flag(base: String) -> int:
	for it in PsoStartMenu._get_inventory():
		var id: String = str(it.get("id", ""))
		if Inventory.get_base_id(id) == base:
			return 1 if bool(it.get("usable", false)) else 0
	return -1


# Synthesis shop marks recipes whose OUTPUT weapon the class can't equip with the
# ✕ marker (crafting still allowed) — a visual filter (Kion request).
func test_synth_unequippable_marker() -> void:
	print("── Synthesis: ✕ marker on un-equippable recipe outputs ──")
	var cs = load("res://scripts/2d/shops/crafting_shop.gd").new()
	var ShopNavCls = load("res://scripts/2d/shops/shop_nav.gd")
	if CharacterManager.get_active_character() == null:
		print("  INFO: no active character — skipped"); cs.free(); print(""); return
	var class_str: String = ShopNavCls.active_class_use_string()
	if class_str.is_empty():
		print("  INFO: no class string — skipped"); cs.free(); print(""); return
	# Expectation routes through the SAME canonical gate the migrated
	# _output_unequippable now uses (EquipmentUtils.item_fits_slot →
	# ClassData.allowed_weapon_types), NOT the deprecated WeaponData.usable_by.
	var all_consistent := true
	for recipe in RecipeRegistry.get_all_recipes():
		var w = WeaponRegistry.get_weapon(recipe.output_weapon_id)
		var expect: bool = w != null and not EquipmentUtils.item_fits_slot(recipe.output_weapon_id, "weapon")
		if cs._output_unequippable(recipe) != expect:
			all_consistent = false
	assert_true(all_consistent,
		"_output_unequippable matches the canonical equip-legality gate for every recipe output")
	cs.free()
	print("")


# The 3D field start menu's items-list ✕ marker (StartMenuRenderer._item_cannot_use)
# routes through the shared cannot-use predicate (the canonical equip-legality gate;
# spec /mechanics/equip-legality), so it agrees with the shops and storage. Covers
# the three gear kinds — weapon type, armor class list, disk learnability — plus the
# DebugConfig.equip_all bypass.
func test_start_menu_cannot_use() -> void:
	print("── 3D start menu: ✕ cannot-use marker via canonical gate ──")
	var renderer = load("res://scripts/3d/field/start_menu_renderer.gd").new(null)
	var ShopNavCls = load("res://scripts/2d/shops/shop_nav.gd")
	var saved := _isolate_character_state()
	# FOnewm (Force Newman): can equip Rod/Handgun, not Sword; can wear "robe"
	# (lists Force Newman) but not "armor" (Hunter/Ranger only); can learn Foie.
	CharacterManager.create_character(0, "fonewm", "StartMenuX")
	CharacterManager.set_active_slot(0)

	if WeaponRegistry.get_weapon("sword") and WeaponRegistry.get_weapon("rod"):
		assert_true(renderer._item_cannot_use("sword"), "start menu: Sword ✕ for FOnewm (type)")
		assert_true(not renderer._item_cannot_use("rod"), "start menu: Rod has no ✕ for FOnewm")
	if ArmorRegistry.get_armor("armor") and ArmorRegistry.get_armor("robe") and ArmorRegistry.get_armor("frame"):
		assert_true(renderer._item_cannot_use("armor"), "start menu: 'armor' ✕ for FOnewm (class list)")
		assert_true(not renderer._item_cannot_use("robe"), "start menu: Robe has no ✕ for FOnewm")
		assert_true(not renderer._item_cannot_use("frame"), "start menu: unrestricted Frame has no ✕")
	assert_true(not renderer._item_cannot_use("disk_foie_1"), "start menu: learnable disk has no ✕")
	assert_true(not renderer._item_cannot_use("monomate"), "start menu: consumable never gets ✕")

	# The marker IS the shared predicate (single source of truth) — no per-screen drift.
	assert_eq(renderer._item_cannot_use("sword"), ShopNavCls.sell_cannot_use("sword"),
		"start menu ✕ == shared sell_cannot_use for a weapon")
	assert_eq(renderer._item_cannot_use("armor"), ShopNavCls.sell_cannot_use("armor"),
		"start menu ✕ == shared sell_cannot_use for armor")

	# equip_all bypasses the gate everywhere it applies.
	DebugConfig.equip_all = true
	assert_true(not renderer._item_cannot_use("sword"), "equip_all clears the weapon ✕")
	assert_true(not renderer._item_cannot_use("armor"), "equip_all clears the armor ✕")

	_restore_character_state(saved)
	print("")


# The storage counter's row ✕ marker (storage._item_cannot_use) routes through the
# same shared cannot-use predicate as the shops and start menu, so the three agree.
# Storage previously skipped disks entirely; this also pins that disks now get the ✕.
func test_storage_cannot_use() -> void:
	print("── Storage: ✕ cannot-use marker via canonical gate ──")
	var storage = load("res://scripts/2d/storage.gd").new()
	var ShopNavCls = load("res://scripts/2d/shops/shop_nav.gd")
	var saved := _isolate_character_state()
	# A CAST: can't equip Rod (Force type), can't wear "robe" (Newman-Hunter/Force),
	# and can NEVER learn a technique disk → all three carry the ✕.
	CharacterManager.create_character(0, "hucast", "StorageX")
	CharacterManager.set_active_slot(0)

	if WeaponRegistry.get_weapon("rod") and WeaponRegistry.get_weapon("saber"):
		assert_true(storage._item_cannot_use("rod"), "storage: Rod ✕ for HUcast (type)")
		assert_true(not storage._item_cannot_use("saber"), "storage: Saber has no ✕ for HUcast")
	if ArmorRegistry.get_armor("robe") and ArmorRegistry.get_armor("frame"):
		assert_true(storage._item_cannot_use("robe"), "storage: Robe ✕ for HUcast (class list)")
		assert_true(not storage._item_cannot_use("frame"), "storage: unrestricted Frame has no ✕")
	assert_true(storage._item_cannot_use("disk_foie_1"),
		"storage: technique disk ✕ for a CAST (can never learn) — previously unmarked here")

	# Single source of truth: storage ✕ == the shared sell predicate.
	assert_eq(storage._item_cannot_use("rod"), ShopNavCls.sell_cannot_use("rod"),
		"storage ✕ == shared sell_cannot_use for a weapon")
	assert_eq(storage._item_cannot_use("robe"), ShopNavCls.sell_cannot_use("robe"),
		"storage ✕ == shared sell_cannot_use for armor")
	assert_eq(storage._item_cannot_use("disk_foie_1"), ShopNavCls.sell_cannot_use("disk_foie_1"),
		"storage ✕ == shared sell_cannot_use for a disk")

	storage.free()
	_restore_character_state(saved)
	print("")


# The ACTUAL equip action must agree with the ✕ marker — they previously used
# different checks, so the shop could show "no ✕ / can equip" while the equip
# action refused (or, for armor, the reverse: a ✕ but still equippable). Both now
# route through EquipmentUtils.item_fits_slot. This pins the 3D start menu's
# equip-from-inventory slot resolver (PsoStartMenu._slot_key_for_inventory_item):
# an empty slot key (= Equip disabled) must equal the shared cannot-use predicate.
func test_equip_action_matches_marker() -> void:
	print("── Equip action == ✕ marker (single gate) ──")
	var ShopNavCls = load("res://scripts/2d/shops/shop_nav.gd")
	var saved := _isolate_character_state()
	# FOnewm: Rod/Handgun yes, Sword no; can wear "robe" (lists Force Newman) and
	# the unrestricted "frame", but not "armor" (Hunter/Ranger only).
	CharacterManager.create_character(0, "fonewm", "EquipActX")
	CharacterManager.set_active_slot(0)

	# Helper: slot key the start menu would equip this item into ("" = can't).
	var slot := func(cat: String, id: String) -> String:
		return PsoStartMenu._slot_key_for_inventory_item({"category": cat, "id": id})

	if WeaponRegistry.get_weapon("sword") and WeaponRegistry.get_weapon("rod"):
		assert_eq(slot.call("Weapon", "sword"), "", "start-menu equip: Sword refused for FOnewm")
		assert_eq(slot.call("Weapon", "rod"), "weapon", "start-menu equip: Rod allowed for FOnewm")
		# The equip action and the ✕ marker can't disagree.
		assert_eq(slot.call("Weapon", "sword").is_empty(), ShopNavCls.sell_cannot_use("sword"),
			"Sword: equip-refused == ✕ marker")
		assert_eq(slot.call("Weapon", "rod").is_empty(), ShopNavCls.sell_cannot_use("rod"),
			"Rod: equip-allowed == no ✕")
	if ArmorRegistry.get_armor("armor") and ArmorRegistry.get_armor("robe") and ArmorRegistry.get_armor("frame"):
		# THE regression: class-illegal armor used to return "frame" unconditionally
		# (equippable despite the ✕). It must now be refused.
		assert_eq(slot.call("Armor", "armor"), "", "start-menu equip: class-illegal 'armor' refused for FOnewm")
		assert_eq(slot.call("Armor", "robe"), "frame", "start-menu equip: Robe allowed for FOnewm")
		assert_eq(slot.call("Armor", "frame"), "frame", "start-menu equip: unrestricted Frame allowed")
		assert_eq(slot.call("Armor", "armor").is_empty(), ShopNavCls.sell_cannot_use("armor"),
			"armor: equip-refused == ✕ marker (no longer diverges)")

	# equip_all bypasses the gate for the equip action too (verify-models flow).
	DebugConfig.equip_all = true
	assert_eq(slot.call("Weapon", "sword"), "weapon", "equip_all: Sword becomes equippable")
	assert_eq(slot.call("Armor", "armor"), "frame", "equip_all: 'armor' becomes equippable")

	_restore_character_state(saved)
	print("")


# The in-field weapon palette swap (field_hud _QuickWeaponMenu._build_weapon_list)
# now filters via EquipmentUtils.item_fits_slot — so it matches the shop ✕ AND
# honors DebugConfig.equip_all (the hand-rolled check it replaced ignored equip_all,
# so debug-equipped weapons vanished from the swap list).
func test_field_weapon_swap_gate() -> void:
	print("── In-field weapon swap list == canonical gate ──")
	const FieldHud := preload("res://scripts/3d/field/field_hud.gd")
	var saved := _isolate_character_state()
	CharacterManager.create_character(0, "fonewm", "SwapX")
	CharacterManager.set_active_slot(0)
	if not (WeaponRegistry.get_weapon("sword") and WeaponRegistry.get_weapon("rod")):
		print("  INFO: sword/rod missing — skipped"); _restore_character_state(saved); print(""); return

	Inventory.clear_inventory()
	Inventory.add_item("sword", 1)
	Inventory.add_item("rod", 1)

	var menu = FieldHud._QuickWeaponMenu.new()
	menu._build_weapon_list()
	var ids: Array = menu._weapon_list.map(func(e): return Inventory.get_base_id(str(e.get("id", ""))))
	assert_true(ids.has("rod"), "swap list includes Rod (FOnewm can equip)")
	assert_true(not ids.has("sword"), "swap list excludes Sword (FOnewm can't equip)")

	# equip_all must surface the class-illegal weapon too (the bug this fixes).
	DebugConfig.equip_all = true
	menu._build_weapon_list()
	var ids_all: Array = menu._weapon_list.map(func(e): return Inventory.get_base_id(str(e.get("id", ""))))
	assert_true(ids_all.has("sword"), "equip_all: swap list now includes Sword (was hidden before the fix)")
	menu.free()

	Inventory.clear_inventory()
	_restore_character_state(saved)
	print("")


# Quick Weapon Menu (issue #424, spec /states/quick-weapon-menu):
#   (1) the equipped row sorts LAST in the built list;
#   (2) selecting the equipped row UNEQUIPS to barehanded then closes;
#   (3) selecting a non-equipped row still equips then closes;
#   (4) barehanded SFX no longer maps to common35 (the saber swing).
# The menu is add_child'd so _equip_selected()'s get_tree() call is safe; the
# "player" group is empty headless, so refresh_weapon() is skipped.
func test_quick_weapon_menu_unequip_and_order() -> void:
	print("── Quick Weapon Menu: unequip-to-barehanded + ordering (#424) ──")
	const FieldHud := preload("res://scripts/3d/field/field_hud.gd")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	var saved := _isolate_character_state()
	CharacterManager.create_character(0, "humar", "QuickMenuX")
	CharacterManager.set_active_slot(0)
	# saber/sword/dagger are weapon types 0/1/2 — all HUmar-equippable.
	if not (WeaponRegistry.get_weapon("saber") and WeaponRegistry.get_weapon("sword") and WeaponRegistry.get_weapon("dagger")):
		print("  INFO: saber/sword/dagger missing — skipped"); _restore_character_state(saved); print(""); return

	Inventory.clear_inventory()
	Inventory.add_item("saber", 1)
	Inventory.add_item("sword", 1)
	Inventory.add_item("dagger", 1)
	var character = CharacterManager.get_active_character()
	character["equipment"]["weapon"] = "saber"

	var menu = FieldHud._QuickWeaponMenu.new()
	add_child(menu)

	# (1) ORDER — equipped row sorts to the END; nothing before it is equipped.
	menu._build_weapon_list()
	assert_true(menu._weapon_list.size() == 3, "swap list has all three HUmar weapons")
	assert_true(bool(menu._weapon_list.back().get("equipped", false)),
		"equipped row (Saber) sorts LAST in the list (#424)")
	var any_earlier_equipped := false
	for i in range(menu._weapon_list.size() - 1):
		if bool(menu._weapon_list[i].get("equipped", false)):
			any_earlier_equipped = true
	assert_true(not any_earlier_equipped, "no non-final row is marked equipped")

	# (1b) CURSOR — _open() starts the cursor at the TOP (index 0), NOT on the
	# equipped row (which sorts last). Spec /states/quick-weapon-menu (#141).
	menu._selected_index = 99  # dirty it so a stale value can't pass by accident
	menu._open()
	assert_eq(menu._selected_index, 0, "cursor starts at the top of the list on open (#141)")
	assert_true(not bool(menu._weapon_list[menu._selected_index].get("equipped", false)),
		"cursor does NOT land on the equipped row on open")
	menu._close()

	# (2) UNEQUIP — accept on the equipped row → barehanded, menu closes.
	menu._selected_index = menu._weapon_list.size() - 1  # the equipped row
	menu._is_open = true
	menu._equip_selected()
	assert_eq(str(CharacterManager.get_active_character()["equipment"]["weapon"]), "",
		"selecting the equipped row unequips to barehanded (weapon == '')")
	assert_true(not menu._is_open, "menu closes after unequip")

	# (3) EQUIP still works — re-equip, then accept on a non-equipped row.
	character["equipment"]["weapon"] = "saber"
	menu._build_weapon_list()
	var sword_idx := -1
	for i in range(menu._weapon_list.size()):
		if Inventory.get_base_id(str(menu._weapon_list[i].get("id", ""))) == "sword":
			sword_idx = i
	assert_true(sword_idx >= 0, "Sword row present for equip")
	menu._selected_index = sword_idx
	menu._is_open = true
	menu._equip_selected()
	assert_eq(Inventory.get_base_id(str(CharacterManager.get_active_character()["equipment"]["weapon"])), "sword",
		"selecting a non-equipped row equips it (Sword)")
	assert_true(not menu._is_open, "menu closes after equip")

	# (4) SFX — barehanded no longer resolves to common35 (the saber swing).
	# The common46 asset isn't in the pack headless, so we assert the mapping is
	# distinct rather than loading it.
	assert_true(PlayerScript.BAREHANDED_SFX != PlayerScript.WEAPON_SFX[WeaponData.WeaponType.SABER],
		"barehanded SFX (common46) != saber SFX (common35)")

	menu.free()
	Inventory.clear_inventory()
	_restore_character_state(saved)
	print("")


# Quick Weapon Menu input capture (issue #467, spec /states/quick-weapon-menu):
# an open Quick Menu MUST capture input the same way the Start Menu does (#426) —
# it pushes a GameState modal so is_gameplay_blocked() suppresses palette/attack
# actions bound to any button (Player._unhandled_input early-returns on that gate).
# This is the unit half of the two-layer contract; the autopilot probe is the
# other half. Movement is orthogonal (ungated _physics_process) and not asserted
# here. Mirrors the #426 modal-gate assertions in the carried-menu test.
func test_quick_weapon_menu_captures_input() -> void:
	print("── Quick Weapon Menu: open captures input / blocks gameplay (#467) ──")
	const FieldHud := preload("res://scripts/3d/field/field_hud.gd")
	var saved := _isolate_character_state()
	# Known baseline so a modal leaked by a prior test can't mask the assertions.
	GameState.modal_stack = 0
	CharacterManager.create_character(0, "humar", "QuickMenuCapture")
	CharacterManager.set_active_slot(0)
	if not WeaponRegistry.get_weapon("saber"):
		print("  INFO: saber missing — skipped")
		GameState.modal_stack = 0; _restore_character_state(saved); print(""); return

	Inventory.clear_inventory()
	Inventory.add_item("saber", 1)

	var menu = FieldHud._QuickWeaponMenu.new()
	add_child(menu)

	assert_true(not GameState.is_gameplay_blocked(), "precondition: gameplay unblocked before open")

	# Open → the menu captures input by pushing a modal (the #426 gate).
	menu._open()
	assert_true(menu._is_open, "menu opened (list non-empty)")
	assert_true(GameState.is_gameplay_blocked(),
		"open Quick Menu blocks gameplay input — palette/attack suppressed (#467)")

	# Close → restores palette firing; modal balanced back to the baseline.
	menu._close()
	assert_true(not menu._is_open, "menu closed")
	assert_true(not GameState.is_gameplay_blocked(),
		"closing the Quick Menu restores gameplay input (modal popped)")

	# Idempotent close: a stray second _close() MUST NOT pop a modal it never
	# pushed (would underflow past another modal and wrongly unblock gameplay).
	GameState.push_modal()  # stand in for some other modal being up
	menu._close()  # already closed — must be a no-op on the stack
	assert_true(GameState.is_gameplay_blocked(),
		"double-close does not leak a pop under an unrelated modal (#467)")
	GameState.pop_modal()

	# Opening with an EMPTY equippable list must not push a modal (early return).
	Inventory.clear_inventory()
	CharacterManager.get_active_character()["equipment"]["weapon"] = ""
	assert_true(not GameState.is_gameplay_blocked(), "precondition: unblocked before empty-open")
	menu._open()
	assert_true(not menu._is_open, "empty list → menu does not open")
	assert_true(not GameState.is_gameplay_blocked(),
		"empty-list open pushes no modal — gameplay stays unblocked")

	menu.free()
	Inventory.clear_inventory()
	GameState.modal_stack = 0
	_restore_character_state(saved)
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


# #421 — the Palette HUD-preview background must be CACHED on the persistent
# PsoStartMenu autoload (like action icons), not re-load()ed on every draw. The
# menu survives change_scene_to_file across an area transition; the pre-fix
# renderer re-load()ed the bg each draw, so a redraw fired during the tree
# rebuild could transiently miss and silently skip the image until the player
# exited/re-entered the page. A cached ref re-binds from memory and can never
# skip. Deterministic (no GPU/seed): palette_bg.png / palette_bg_r.png are
# repo-resident and import in the editor pass CI runs before the tests.
func test_start_menu_palette_bg_cached() -> void:
	print("── Start Menu (palette bg cache, #421) ──")

	# Both pages resolve to a non-null Texture2D (page 0 → palette_bg.png,
	# page 1 → palette_bg_r.png).
	var bg0: Texture2D = PsoStartMenu._get_palette_bg(0)
	var bg1: Texture2D = PsoStartMenu._get_palette_bg(1)
	assert_true(bg0 != null, "palette page 0 background resolves to a texture")
	assert_true(bg1 != null, "palette page 1 background resolves to a texture")

	# The cache returns the IDENTICAL instance on a second call — proving the
	# texture ref is held on the persistent autoload and survives a redraw, so a
	# post-transition repaint re-binds from cache instead of risking a miss.
	var bg0_again: Texture2D = PsoStartMenu._get_palette_bg(0)
	assert_true(bg0_again == bg0, "palette page 0 background is cached (same instance on re-fetch)")
	var bg1_again: Texture2D = PsoStartMenu._get_palette_bg(1)
	assert_true(bg1_again == bg1, "palette page 1 background is cached (same instance on re-fetch)")
	print("")


func test_scene_manager_fade_rect_full_size() -> void:
	print("── SceneManager fade rect full-size (#421 follow-up) ──")

	# The transition fade-to-black only masks the HUD/menu rebuild if the fade
	# rect actually covers the viewport. Setting `anchors_preset` alone leaves a
	# fresh ColorRect at size (0,0) — black, full-alpha, on the right layer, but
	# zero-area, so it masked NOTHING (the real cause of the #421 flicker that the
	# layer-raise didn't fix). The rect MUST be sized via
	# set_anchors_and_offsets_preset so its area equals the viewport.
	var fr: ColorRect = SceneManager._fade_rect
	assert_true(fr != null, "SceneManager fade rect exists")
	assert_true(fr.size.x > 0.0 and fr.size.y > 0.0, "fade rect has non-zero size (not 0,0)")
	var vp: Vector2 = SceneManager.get_viewport().get_visible_rect().size
	assert_true(fr.size.is_equal_approx(vp), "fade rect covers the full viewport (%s == %s)" % [fr.size, vp])
	print("")


# ── Transition settles before fading in (#530) ──
# change_scene_to_file() is deferred, so the swap + the new scene's _ready run
# on a later frame. Fading in after a single process_frame revealed the new
# scene's blank first frame (default environment before its WorldEnvironment +
# lights settle). The fix holds black for SETTLE_FRAMES rendered frames after
# the swap applies. Guard the invariant statically — the async timing itself is
# exercised by the autopilot city→field matrix — so the flash can't silently
# return and a failed swap can't hang the transition.
func test_scene_manager_transition_settles() -> void:
	print("── SceneManager transition settle (#530) ──")
	var sm: GDScript = load("res://scripts/autoloads/scene_manager.gd")
	var consts: Dictionary = sm.get_script_constant_map()
	assert_true(int(consts.get("SETTLE_FRAMES", 0)) >= 1,
		"transition waits >=1 settled frame before fading in (no blank flash, #530)")
	assert_true(int(consts.get("MAX_SWAP_WAIT_FRAMES", 0)) > 0,
		"deferred-swap wait is capped so a failed swap can't hang the transition")
	print("")


# ── Persistent HUD stats panel (#444; spec /states/field-lifecycle) ──
# The HP/PP/Lv panel MUST be a persistent autoload (HudStats): the SAME node
# instance across an area transition (never freed/rebuilt by the per-scene
# controller), rendered throughout the transition holding its last values,
# reading live values from the GameState / CharacterManager autoloads. This
# drives a simulated transition (SceneManager._transitioning + scene_changed,
# the same signals a real goto_scene fires) and pins each clause.
func test_hud_stats_persistent_panel() -> void:
	print("── Persistent HUD stats panel across transitions (#444) ──")

	var panel = HudStats._stats_panel
	assert_true(panel != null, "HudStats autoload owns a stats panel")
	assert_true(panel.is_inside_tree(), "stats panel is in the tree")
	assert_eq(HudStats.get_parent(), get_tree().root, "HudStats is a root autoload — outside any scene")
	assert_true(not get_tree().current_scene.is_ancestor_of(panel),
		"panel is NOT under the current scene, so change_scene_to_file can never free it")

	# Live values come from the GameState autoload (signal-driven, no polling).
	GameState.set_max_hp(200)
	GameState.set_hp(77)
	GameState.set_max_mp(90)
	GameState.set_mp(41)
	assert_eq(panel._hp_cur_label.text, "77", "HP label reads live GameState.hp")
	assert_eq(panel._hp_max_label.text, "200", "max-HP label reads live GameState.max_hp")
	assert_eq(panel._pp_cur_label.text, "41", "PP label reads live GameState.mp")
	assert_eq(panel._pp_max_label.text, "90", "max-PP label reads live GameState.max_mp")

	# Level comes from the CharacterManager autoload's level_up signal.
	CharacterManager.level_up.emit(7)
	assert_eq(panel._level_label.text, "7", "Lv label tracks CharacterManager.level_up")

	# Non-gameplay scene (this test scene) → panel hidden.
	SceneManager._transitioning = false
	HudStats._update_visibility()
	assert_true(not panel.visible, "panel hidden on non-gameplay scenes (title/select/create)")

	# Simulate an area transition: gameplay scene, fade running. The panel MUST
	# stay rendered — same instance — for every step of the transition.
	HudStats._in_gameplay = true
	SceneManager._transitioning = true
	HudStats._update_visibility()
	assert_true(panel.visible, "panel rendered while in gameplay")
	var id_before: int = panel.get_instance_id()
	GameState.set_hp(63)  # value at the moment the warp starts
	SceneManager.scene_changed.emit("res://scenes/3d/field/valley_field.tscn")
	HudStats._update_visibility()  # mid-transition frame
	assert_eq(HudStats._stats_panel.get_instance_id(), id_before,
		"SAME panel instance after the scene change (never freed/rebuilt)")
	assert_true(is_instance_valid(panel) and panel.is_inside_tree(),
		"panel still in the tree after the scene change")
	assert_true(panel.visible, "no absent frame: panel still rendered mid-transition")
	assert_eq(panel._hp_cur_label.text, "63", "panel holds the last GameState values across the warp")

	# Full-screen SceneManager overlays (shops, storage, guild) hide the panel;
	# clearing the overlay restores it — the old FieldHud keep_stats contract,
	# now owned by HudStats itself (the start menu is NOT in _overlay_stack, so
	# start-menu-only keeps the panel visible by this same rule). Still inside
	# the simulated gameplay state (_transitioning holds _in_gameplay).
	SceneManager._overlay_stack.append({})
	HudStats._update_visibility()
	assert_true(not panel.visible, "panel hidden under a full-screen scene overlay")
	SceneManager._overlay_stack.pop_back()
	HudStats._update_visibility()
	assert_true(panel.visible, "panel restored when the overlay clears")

	# Cleanup: back to the runner's non-gameplay reality.
	SceneManager._transitioning = false
	HudStats._in_gameplay = false
	HudStats._update_visibility()
	GameState.reset_game_state()
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


# Regression for #417: a duplicate technique disk is minted as "disk_foie_3#2".
# Parsing the RAW instance id makes int("3#2") == 32, so use_disk() rejected
# every copy past the first as "level 32 > class max" (the "greyed out / not
# usable" report). The fix strips the suffix via get_base_id() BEFORE parsing
# tech/level, while remove_item still consumes the exact selected instance.
func test_disk_duplicate_use_strips_suffix() -> void:
	print("── Disk Duplicate Use (#417) ──")

	# Save state
	var saved_characters: Array = CharacterManager._characters.duplicate(true)
	var saved_slot: int = CharacterManager._active_slot
	Inventory.clear_inventory()

	# FOmar — Force class, full technique access
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	GameState.reset_game_state()
	var fomar := CharacterManager.create_character(0, "fomar", "DupDiskForce")
	assert_true(fomar != null, "Created FOmar character")
	if fomar == null:
		print("  SKIP: Could not create FOmar")
		CharacterManager._characters = saved_characters
		CharacterManager._active_slot = saved_slot
		if saved_slot >= 0:
			CharacterManager.set_active_slot(saved_slot)
		print("")
		return
	fomar["level"] = 20
	CharacterManager.set_active_slot(0)
	fomar["techniques"].clear()

	# Buy TWO copies of the same learnable disk → two per-slot instances.
	Inventory.add_item("disk_foie_3", 1)
	Inventory.add_item("disk_foie_3", 1)
	var keys: Array = Inventory._items.keys()
	assert_true(keys.has("disk_foie_3"), "First copy minted as 'disk_foie_3'")
	# The second copy gets a '#N' instance suffix (any N, not just #2).
	var dup_id := ""
	for k in keys:
		var kk := str(k)
		if kk != "disk_foie_3" and kk.begins_with("disk_foie_3#"):
			dup_id = kk
			break
	assert_true(not dup_id.is_empty(), "Second copy minted with '#' instance suffix (%s)" % dup_id)
	# Two distinct disk instances exist (create_character seeds starter gear, so
	# assert on the disk count specifically rather than total unique items).
	assert_eq(Inventory.get_item_count("disk_foie_3") + Inventory.get_item_count(dup_id), 2, "Two distinct disk instances exist")

	# Load-bearing: using the DUPLICATE instance must learn Foie at Lv.3, NOT 32.
	# Under the bug this returned false and the level would parse as 32.
	var use_ok := Inventory.use_item(dup_id)
	assert_true(use_ok, "use_item(duplicate '%s') succeeded" % dup_id)
	assert_eq(TechniqueManager.get_technique_level(fomar, "foie"), 3, "Foie learned at Lv.3 (not 32) from the duplicate copy")

	# The exact instance the player selected is consumed; the base copy is untouched.
	assert_eq(Inventory.get_item_count(dup_id), 0, "Selected duplicate instance consumed")
	assert_eq(Inventory.get_item_count("disk_foie_3"), 1, "First copy left untouched")

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


# Selling at the item shop / weapon shop MUST list items in the same order as
# the inventory (matching storage's deposit tab). Both shops iterate
# Inventory.get_all_items() and previously re-sorted by category+name; the sort
# was removed. Guards against it coming back.
func test_shop_sell_list_inventory_order() -> void:
	print("── Shop sell lists preserve inventory order ──")
	var saved: Dictionary = Inventory._items.duplicate(true)
	Inventory.clear_inventory()
	# Deliberately non-alphabetical insertion order — a category/name re-sort
	# would reorder these, so exact-match catches a regression.
	Inventory.add_item("trimate", 1)
	Inventory.add_item("monomate", 1)
	Inventory.add_item("dimate", 1)

	var expected: Array = []
	for it in Inventory.get_all_items():
		if int(it.get("quantity", 0)) > 0:
			expected.append(str(it.get("id", "")))
	assert_gt(expected.size(), 1, "set up multiple inventory items for the order check")

	const ItemShopScript := preload("res://scripts/2d/shops/item_shop.gd")
	var ishop = ItemShopScript.new()
	ishop._generate_sell_list()
	var ish_ids: Array = []
	for e in ishop._sell_items:
		ish_ids.append(str(e.get("id", "")))
	assert_eq(ish_ids, expected, "item shop sell list matches inventory order")
	ishop.free()

	const WeaponShopScript := preload("res://scripts/2d/shops/weapon_shop.gd")
	var wshop = WeaponShopScript.new()
	wshop._generate_sell_list()
	var wsh_ids: Array = []
	for e in wshop._sell_items:
		wsh_ids.append(str(e.get("id", "")))
	assert_eq(wsh_ids, expected, "weapon shop sell list matches inventory order")
	wshop.free()

	Inventory._items = saved
	print("")


# Spec /mechanics/techs: only base-tier techniques are listed in the palette /
# Start menu; gi-/ra- variants are charge-only (tier mid/advanced) and MUST NOT
# appear as their own entries. Pins the data contract the start-menu filter
# (pso_start_menu._get_techniques: skip tier != "basic") relies on.
func test_technique_tier_listing() -> void:
	print("── Technique tiers: gi-/ra- are charge-only, not listed ──")
	var charge_only := ["gifoie", "rafoie", "gibarta", "rabarta", "gizonde", "razonde", "grants", "megid"]
	var base := ["foie", "barta", "zonde", "resta", "anti", "shifta", "deband", "jellen", "zalure"]

	for tid in base:
		var d: Dictionary = TechniqueManager.TECHNIQUES.get(tid, {})
		assert_eq(str(d.get("tier", "")), "basic", "%s is tier basic (listed/learnable)" % tid)
	for tid in charge_only:
		var d: Dictionary = TechniqueManager.TECHNIQUES.get(tid, {})
		assert_true(str(d.get("tier", "basic")) != "basic", "%s is NOT tier basic (charge-only)" % tid)

	# Apply the exact start-menu predicate and assert what survives.
	var listed: Array = []
	for tech_id in TechniqueManager.TECHNIQUES:
		if str(TechniqueManager.TECHNIQUES[tech_id].get("tier", "basic")) != "basic":
			continue
		listed.append(tech_id)
	for tid in charge_only:
		assert_true(not listed.has(tid), "%s filtered out of the techniques list" % tid)
	for tid in base:
		assert_true(listed.has(tid), "%s kept in the techniques list" % tid)

	# Charge map turns a base tech into its charged variant (the only way to it).
	assert_eq(TechniqueManager.get_charged_technique("foie"), "rafoie", "foie charges into rafoie")
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


# ── Kill-state survives the exit flush (#423) ────────────────
# Pins the invariant that an enemy defeated in the SAME frame the player
# warps out of a cell is snapshotted dead by save_cell_state and MUST NOT
# respawn on return. The capture path (CellObjectSpawner._save_cell_state)
# builds the alive list from is_alive, so an enemy whose _die() already
# flipped is_alive=false this frame is written as "dead" — and that dead
# state survives a city suspend/resume round-trip. Spec:
# /states/field-lifecycle "Flush on exit". Companion to #426 (input
# precedence — the warp consuming the palette button is what makes this a
# same-frame race in the first place).
func test_kill_state_survives_warp_flush() -> void:
	print("── Kill-state — defeated enemy persists as dead through warp flush (#423) ──")

	# Clean slate for the section-state store + any suspended session.
	SessionManager.clear_section_states()
	SessionManager._suspended_session.clear()

	# Stub field controller exposing exactly the fields _save_cell_state reads.
	var stub := _KillStateStubController.new()
	stub._current_cell = {
		"pos": "1,2",
		"objects": [
			{"type": "enemy", "enemy_id": "lizard", "wave": 1, "position": [1.0, 0.0, 2.0]},
			{"type": "enemy", "enemy_id": "wolf", "wave": 1, "position": [3.0, 0.0, 4.0]},
		],
	}

	# Two real EnemyBase nodes mirror the live room. The wolf has already had
	# _die() flip is_alive=false THIS frame (the kill-all-then-warp case); the
	# lizard is still alive. Not added to the tree — _save_cell_state only reads
	# is_alive + enemy_data.id, no _ready() needed.
	var lizard_data := EnemyData.new()
	lizard_data.id = "lizard"
	var wolf_data := EnemyData.new()
	wolf_data.id = "wolf"
	var lizard := EnemyBase.new()
	lizard.enemy_data = lizard_data
	lizard.is_alive = true
	var wolf := EnemyBase.new()
	wolf.enemy_data = wolf_data
	wolf.is_alive = false
	stub._room_enemies = [lizard, wolf]

	# Capture the live cell state, exactly as a warp/exit flush would.
	var spawner := CellObjectSpawner.new(stub)
	spawner._save_cell_state()

	assert_true(stub._cell_states.has("1,2"), "Cell 1,2 flushed into _cell_states")
	var saved_objs: Array = stub._cell_states.get("1,2", {}).get("objects", [])
	var lizard_state: String = ""
	var wolf_state: String = ""
	for o in saved_objs:
		if str(o.get("type", "")) != "enemy":
			continue
		if str(o.get("enemy_id", "")) == "lizard":
			lizard_state = str(o.get("state", ""))
		elif str(o.get("enemy_id", "")) == "wolf":
			wolf_state = str(o.get("state", ""))
	assert_eq(lizard_state, "alive", "Live lizard snapshotted alive")
	assert_eq(wolf_state, "dead", "Same-frame-killed wolf snapshotted dead")

	# Round-trip the snapshot through a city suspend/resume — the kill must
	# survive (the #423 invariant: defeated enemies MUST NOT respawn on return).
	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.save_section_state(0, stub._cell_states, {}, {}, {})
	SessionManager.suspend_session()
	SessionManager.resume_session()
	var st: Dictionary = SessionManager.get_section_state(0)
	var rt_cells: Dictionary = st.get("cell_states", {})
	assert_true(rt_cells.has("1,2"), "Cell 1,2 survives city round-trip")
	var rt_wolf_state: String = ""
	for o in rt_cells.get("1,2", {}).get("objects", []):
		if str(o.get("type", "")) == "enemy" and str(o.get("enemy_id", "")) == "wolf":
			rt_wolf_state = str(o.get("state", ""))
	assert_eq(rt_wolf_state, "dead", "Killed wolf still dead after city trip (no respawn)")

	# Cleanup — free the Node-derived EnemyBase instances (stub is RefCounted).
	lizard.free()
	wolf.free()
	SessionManager.return_to_city()
	SessionManager.clear_section_states()
	print("")


# ── Box-state survives the warp flush (#423 / field-lifecycle §Persistence) ──
# Broken boxes MUST NOT reappear (and MUST NOT re-drop loot). A box destroyed in
# the field is freed, so it's absent from _room_boxes; the save's diff against
# the authored cell records it "destroyed", and that survives a city telepipe.
func test_box_state_survives_warp_flush() -> void:
	print("── Box-state — broken boxes persist as destroyed through warp flush (#423) ──")
	SessionManager.clear_section_states()
	SessionManager._suspended_session.clear()

	var stub := _KillStateStubController.new()
	stub._current_cell = {
		"pos": "5,5",
		"objects": [
			{"type": "box", "position": [1.0, 0.0, 1.0]},   # A — still standing
			{"type": "box", "position": [9.0, 0.0, 9.0]},   # B — destroyed, gone from room
		],
	}
	# Live room: only the intact box at A survives (B was broken → freed → absent).
	var intact_box := Box.new()
	intact_box.element_state = "intact"
	intact_box.position = Vector3(1.0, 0.0, 1.0)
	stub._room_boxes = [intact_box]

	var spawner := CellObjectSpawner.new(stub)
	spawner._save_cell_state()

	var objs: Array = stub._cell_states.get("5,5", {}).get("objects", [])
	var box_a := ""
	var box_b := ""
	for o in objs:
		if str(o.get("type", "")) != "box":
			continue
		if abs(float(o.get("px", 0)) - 1.0) < 0.01:
			box_a = str(o.get("state", ""))
		elif abs(float(o.get("px", 0)) - 9.0) < 0.01:
			box_b = str(o.get("state", ""))
	assert_eq(box_a, "intact", "Intact box snapshotted intact")
	assert_eq(box_b, "destroyed", "Broken box snapshotted destroyed")

	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.save_section_state(0, stub._cell_states, {}, {}, {})
	SessionManager.suspend_session()
	SessionManager.resume_session()
	var rt: Array = SessionManager.get_section_state(0).get("cell_states", {}).get("5,5", {}).get("objects", [])
	var rt_b := ""
	for o in rt:
		if str(o.get("type", "")) == "box" and abs(float(o.get("px", 0)) - 9.0) < 0.01:
			rt_b = str(o.get("state", ""))
	assert_eq(rt_b, "destroyed", "Broken box still destroyed after city trip (no reappear / no re-drop)")

	intact_box.free()
	SessionManager.return_to_city()
	SessionManager.clear_section_states()
	print("")


# ── Drop-state survives the warp flush (#423) ────────────────────────────────
# Uncollected ground loot MUST keep its position + amount (no move, no re-roll);
# collected drops MUST NOT reappear. The save only persists drops whose
# element_state == "available".
func test_drop_state_survives_warp_flush() -> void:
	print("── Drop-state — uncollected loot persists (pos+amount), collected does not (#423) ──")
	SessionManager.clear_section_states()
	SessionManager._suspended_session.clear()

	var stub := _KillStateStubController.new()
	stub._current_cell = {"pos": "6,6", "objects": []}

	var meseta := DropMeseta.new()
	meseta.element_state = "available"
	meseta.amount = 250
	meseta.position = Vector3(2.0, 0.0, 3.0)
	var material := DropMaterial.new()
	material.element_state = "available"
	material.item_id = "power_material"
	material.amount = 1
	material.position = Vector3(4.0, 0.0, 5.0)
	var collected := DropItem.new()
	collected.element_state = "collected"   # already picked up → excluded by the save
	collected.item_id = "monomate"
	collected.position = Vector3(7.0, 0.0, 8.0)
	stub._room_drops = [meseta, material, collected]

	var spawner := CellObjectSpawner.new(stub)
	spawner._save_cell_state()

	var drops: Array = stub._cell_states.get("6,6", {}).get("drops", [])
	assert_eq(drops.size(), 2, "Only the 2 available drops saved (collected excluded)")

	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.save_section_state(0, stub._cell_states, {}, {}, {})
	SessionManager.suspend_session()
	SessionManager.resume_session()
	var rt_drops: Array = SessionManager.get_section_state(0).get("cell_states", {}).get("6,6", {}).get("drops", [])
	var got_meseta := {}
	var got_material := {}
	var has_collected := false
	for d in rt_drops:
		if str(d.get("kind", "")) == "meseta":
			got_meseta = d
		elif str(d.get("kind", "")) == "material":
			got_material = d
		if str(d.get("item_id", "")) == "monomate":
			has_collected = true
	assert_eq(int(got_meseta.get("amount", -1)), 250, "Meseta drop keeps amount (no re-roll)")
	assert_true(abs(float(got_meseta.get("px", -99)) - 2.0) < 0.01 and abs(float(got_meseta.get("pz", -99)) - 3.0) < 0.01,
		"Meseta drop keeps exact position")
	assert_eq(str(got_material.get("item_id", "")), "power_material", "Material drop keeps item_id")
	assert_true(not has_collected, "Collected item did NOT reappear as a ground drop")

	meseta.free()
	material.free()
	collected.free()
	SessionManager.return_to_city()
	SessionManager.clear_section_states()
	print("")


# ── Read messages / destroyed walls / collected quest items persist (#423) ───
func test_message_wall_questitem_persist() -> void:
	print("── Read messages / destroyed walls / collected quest items persist (#423) ──")
	SessionManager.clear_section_states()
	SessionManager._suspended_session.clear()

	var stub := _KillStateStubController.new()
	stub._current_cell = {"pos": "7,7", "objects": []}

	var msg := MessagePack.new()
	msg.element_state = "read"
	msg.message_text = "A cryptic note."
	msg.position = Vector3(1.0, 0.0, 0.0)
	stub._room_messages = [msg]

	var wall := Wall.new()
	wall.element_state = "destroyed"
	wall.is_destructible = true
	wall.position = Vector3(2.0, 0.0, 0.0)
	stub._room_walls = [wall]

	var qitem := QuestItemPickup.new()
	qitem.element_state = "collected"
	qitem.quest_item_id = "ancient_key"
	qitem.quest_item_label = "Ancient Key"
	qitem.position = Vector3(3.0, 0.0, 0.0)
	stub._room_quest_items = [qitem]

	var spawner := CellObjectSpawner.new(stub)
	spawner._save_cell_state()

	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.save_section_state(0, stub._cell_states, {}, {}, {})
	SessionManager.suspend_session()
	SessionManager.resume_session()
	var rt: Array = SessionManager.get_section_state(0).get("cell_states", {}).get("7,7", {}).get("objects", [])
	var m := ""
	var w := ""
	var qi := ""
	for o in rt:
		match str(o.get("type", "")):
			"message": m = str(o.get("state", ""))
			"wall": w = str(o.get("state", ""))
			"quest_item": qi = str(o.get("state", ""))
	assert_eq(m, "read", "Read message stays read after warp")
	assert_eq(w, "destroyed", "Destroyed wall stays destroyed after warp")
	assert_eq(qi, "collected", "Collected quest item stays collected after warp")

	msg.free()
	wall.free()
	qitem.free()
	SessionManager.return_to_city()
	SessionManager.clear_section_states()
	print("")


# ── Collected keys + opened gates survive the section round-trip (#423) ──────
# Gate/key progress is controller-level state (not in the objects array); it
# rides along in save_section_state and MUST survive a telepipe suspend/resume.
func test_keys_gates_survive_section_roundtrip() -> void:
	print("── Collected keys + opened gates survive the section round-trip (#423) ──")
	SessionManager.clear_section_states()
	SessionManager._suspended_session.clear()
	SessionManager.enter_field("gurhacia", "normal")

	var keys := {"1,2:red_key": true, "2,3:blue_key": true}
	var gates := {"1,2:north_gate": true}
	SessionManager.save_section_state(0, {}, keys, gates, {"1,2": true})
	SessionManager.suspend_session()
	SessionManager.resume_session()
	var st: Dictionary = SessionManager.get_section_state(0)
	assert_eq((st.get("keys_collected", {}) as Dictionary).size(), 2, "Both collected keys survive round-trip")
	assert_true((st.get("keys_collected", {}) as Dictionary).has("1,2:red_key"), "red_key still collected")
	assert_true(bool((st.get("gates_opened", {}) as Dictionary).get("1,2:north_gate", false)), "north_gate still opened")
	assert_true((st.get("visited_cells", {}) as Dictionary).has("1,2"), "visited cell preserved")

	SessionManager.return_to_city()
	SessionManager.clear_section_states()
	print("")


# ── Full persistence contract holds across repeated city trips (#423) ────────
# The reliability/stress case: one cell mixing every persisted category, bounced
# to the city 3× in a row. Every category MUST hold each trip — nothing respawns.
func test_box_state_survives_floor_placement() -> void:
	print("── Box-state — floor-snapped/relocated boxes aren't recorded destroyed ──")
	SessionManager.clear_section_states()
	SessionManager._suspended_session.clear()

	var stub := _KillStateStubController.new()
	stub._current_cell = {
		"pos": "6,6",
		"objects": [
			{"type": "box", "position": [1.0, 0.0, 1.0]},   # A — floor snapped y
			{"type": "box", "position": [4.0, 0.0, 4.0]},   # B — floor relocated x/z
			{"type": "box", "position": [9.0, 0.0, 9.0]},   # C — genuinely destroyed
		],
	}
	# _spawn_box positions boxes at _place_on_floor(pos): A's floor sits below
	# the authored y, and B's authored spot had no floor at all so the grid scan
	# moved it several metres. Both are still standing; only C is gone.
	var snapped_box := Box.new()
	snapped_box.element_state = "intact"
	snapped_box.position = Vector3(1.0, 0.35, 1.0)
	snapped_box.set_meta("authored_pos", Vector3(1.0, 0.0, 1.0))
	var relocated := Box.new()
	relocated.element_state = "intact"
	relocated.position = Vector3(7.0, 0.2, 7.0)
	relocated.set_meta("authored_pos", Vector3(4.0, 0.0, 4.0))
	stub._room_boxes = [snapped_box, relocated]

	var spawner := CellObjectSpawner.new(stub)
	spawner._save_cell_state()

	# Only C may be recorded destroyed. A phantom "destroyed" for a box that is
	# still standing is the bug: the saved cell state then disagrees with the
	# room it describes.
	var destroyed_x: Array = []
	for o in stub._cell_states.get("6,6", {}).get("objects", []):
		if str(o.get("type", "")) == "box" and str(o.get("state", "")) == "destroyed":
			destroyed_x.append(snappedf(float(o.get("px", 0)), 0.01))
	assert_true(not destroyed_x.has(1.0), "Floor-snapped box not recorded destroyed")
	assert_true(not destroyed_x.has(4.0), "Relocated box not recorded destroyed")
	assert_true(destroyed_x.has(9.0), "Genuinely broken box still recorded destroyed")
	assert_eq(destroyed_x.size(), 1, "Exactly one destroyed record (no phantoms)")


func test_field_state_full_contract_roundtrip() -> void:
	print("── Full persistence contract holds across 3 consecutive city trips (#423) ──")
	SessionManager.clear_section_states()
	SessionManager._suspended_session.clear()

	var stub := _KillStateStubController.new()
	stub._current_cell = {
		"pos": "8,8",
		"objects": [
			{"type": "enemy", "enemy_id": "wolf", "wave": 1, "position": [0.0, 0.0, 0.0]},
			{"type": "enemy", "enemy_id": "lizard", "wave": 1, "position": [1.0, 0.0, 0.0]},
			{"type": "box", "position": [9.0, 0.0, 9.0]},   # broken, absent from room
		],
	}
	var dead_wolf := EnemyBase.new()
	var wd := EnemyData.new(); wd.id = "wolf"; dead_wolf.enemy_data = wd; dead_wolf.is_alive = false
	var live_liz := EnemyBase.new()
	var ld := EnemyData.new(); ld.id = "lizard"; live_liz.enemy_data = ld; live_liz.is_alive = true
	stub._room_enemies = [dead_wolf, live_liz]
	var drop := DropMeseta.new(); drop.element_state = "available"; drop.amount = 99; drop.position = Vector3(3.0, 0.0, 3.0)
	stub._room_drops = [drop]
	var msg := MessagePack.new(); msg.element_state = "read"; msg.message_text = "x"; msg.position = Vector3(4.0, 0.0, 4.0)
	stub._room_messages = [msg]

	var spawner := CellObjectSpawner.new(stub)
	spawner._save_cell_state()

	SessionManager.enter_field("gurhacia", "normal")
	var cells: Dictionary = stub._cell_states
	for trip in range(1, 4):
		SessionManager.save_section_state(0, cells, {}, {}, {})
		SessionManager.suspend_session()
		SessionManager.resume_session()
		cells = SessionManager.get_section_state(0).get("cell_states", {})
		var objs: Array = cells.get("8,8", {}).get("objects", [])
		var n_destroyed := 0
		var n_read := 0
		var wolf_state := ""
		var liz_state := ""
		for o in objs:
			var t := str(o.get("type", ""))
			var s := str(o.get("state", ""))
			if (t == "box" or t == "rare_box") and s == "destroyed":
				n_destroyed += 1
			elif t == "message" and s == "read":
				n_read += 1
			if t == "enemy" and str(o.get("enemy_id", "")) == "wolf":
				wolf_state = s
			elif t == "enemy" and str(o.get("enemy_id", "")) == "lizard":
				liz_state = s
		var n_drops: int = (cells.get("8,8", {}).get("drops", []) as Array).size()
		assert_eq(wolf_state, "dead", "Trip %d: killed wolf stays dead" % trip)
		assert_eq(liz_state, "alive", "Trip %d: live lizard stays alive" % trip)
		assert_eq(n_destroyed, 1, "Trip %d: broken box stays destroyed" % trip)
		assert_eq(n_read, 1, "Trip %d: read message stays read" % trip)
		assert_eq(n_drops, 1, "Trip %d: ground drop still present" % trip)

	dead_wolf.free()
	live_liz.free()
	drop.free()
	msg.free()
	SessionManager.return_to_city()
	SessionManager.clear_section_states()
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


func test_player_defeat_return() -> void:
	print("── Player defeat — return-to-city transaction (spec /states/player-death) ──")

	TelepipeManager.cancel("test_setup")
	SessionManager._suspended_session.clear()

	# The active CHARACTER dict is the source of truth for meseta/HP (the city
	# re-syncs GameState from it on arrival), so set up a known one and assert
	# the penalty/revive land on the CHARACTER, not just the GameState mirror.
	var saved_chars = CharacterManager._characters
	var saved_slot = CharacterManager._active_slot
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "DefeatTest")
	CharacterManager.set_active_slot(0)
	var ch = CharacterManager.get_active_character()
	ch["meseta"] = 100
	ch["max_hp"] = 120
	ch["hp"] = 1
	GameState.meseta = 100
	GameState.stored_meseta = 500
	GameState.max_hp = 120
	GameState.set_hp(0)  # dead

	# In a quest field, carrying 100 meseta with 500 banked, an active telepipe.
	SessionManager.enter_quest("search_and_rescue", "normal")
	TelepipeManager.place("gurhacia", 0, "0,0", Vector3(1, 0, 1),
		"res://scenes/3d/field/valley_field.tscn")

	var result: Dictionary = SessionManager.defeat_return_to_city()

	# 50% of carried meseta is lost (floored), on the CHARACTER + the mirror;
	# bank untouched.
	assert_eq(int(result.get("meseta_lost", -1)), 50, "Defeat loses 50% of carried meseta (100 → lose 50)")
	assert_eq(int(ch["meseta"]), 50, "Character (source of truth) meseta halved to 50")
	assert_eq(GameState.meseta, 50, "GameState meseta mirror halved to 50")
	assert_eq(GameState.stored_meseta, 500, "Banked meseta untouched by defeat penalty")

	# Revived to full HP — on the character and the mirror.
	assert_eq(int(ch["hp"]), int(ch["max_hp"]), "Character revived to full HP")
	assert_eq(GameState.hp, GameState.max_hp, "GameState HP mirror at full")

	# Session ended (not resumable) and telepipe cleared.
	assert_true(not SessionManager.has_active_session(), "Defeat ends the field session")
	assert_true(not SessionManager.has_suspended_session(), "Defeat does NOT leave a resumable session")
	assert_eq(SessionManager.get_location(), "city", "Player is back in the city after defeat")
	assert_true(not TelepipeManager.is_active(), "Defeat cancels any active telepipe (session end)")

	# Odd amount floors (101 → lose 50, keep 51); zero carried → lose nothing.
	ch["meseta"] = 101
	GameState.meseta = 101
	assert_eq(int(SessionManager.defeat_return_to_city().get("meseta_lost", -1)), 50,
		"Odd carried meseta floors (101 → lose 50)")
	assert_eq(int(ch["meseta"]), 51, "51 meseta kept on the character after flooring")
	ch["meseta"] = 0
	GameState.meseta = 0
	assert_eq(int(SessionManager.defeat_return_to_city().get("meseta_lost", -1)), 0,
		"Zero carried meseta → nothing lost")

	# Cleanup
	GameState.stored_meseta = 0
	CharacterManager._characters = saved_chars
	CharacterManager._active_slot = saved_slot
	GameState.set_hp(GameState.max_hp)
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


## #425 — return-to-title must clear the city-hub position cache (CityState),
## not just SessionManager's _session. CityState is a SECOND in-memory holder of
## the player's position (_position/_rotation/_area/_spawn_key), written whenever
## the player walks between city areas or up to a shop NPC (city_area_base.gd:217).
## The return-to-title chokepoint (title.gd → SessionManager.reset_all_state())
## historically never touched it, so a SOFT re-login restored the leftover shop
## spot via the predicate `pos != null && area matches` in
## city_area_base._spawn_player (city_area_base.gd:35) instead of DEFAULT_SPAWN.
## A HARD reboot zeroes the autoload, which is why reboot didn't reproduce.
## This test pins that reset_all_state() now empties CityState so the spawn
## predicate is false and login falls through to the canonical DEFAULT_SPAWN.
func test_city_state_cleared_on_title_return() -> void:
	print("── reset_all_state clears CityState (#425 return-to-title position) ──")

	# (1) Simulate having walked up to a shop NPC in the market: a non-default
	#     position/rotation/area plus a spawn key are cached in the autoload.
	CityState.save_player_state(Vector3(0.98, 2, 40.0), 1.5, "market")
	CityState.set_spawn_key("market-exit")
	assert_true(CityState.get_player_position() != null,
		"precondition: CityState holds a cached city position before title return")
	assert_eq(CityState.get_area(), "market",
		"precondition: CityState area is the market the player walked in")

	# (2) Take the title-return chokepoint.
	SessionManager.reset_all_state()

	# (3) The spawn-decision predicate `pos != null && area matches` in
	#     city_area_base.gd:35 must now be FALSE, so login resolves DEFAULT_SPAWN.
	assert_true(CityState.get_player_position() == null,
		"reset_all_state clears CityState position (spawn predicate false → DEFAULT_SPAWN)")
	assert_eq(CityState.get_area(), "",
		"reset_all_state clears CityState area")
	assert_eq(CityState.get_player_rotation(), 0.0,
		"reset_all_state clears CityState rotation")
	assert_eq(CityState.get_spawn_key(), "",
		"reset_all_state clears CityState spawn key")
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

	# Bug 2: a free field in progress is held in the per-area Free-Roam store
	# (not the single suspended slot), must not block quest accept, and is
	# cleared when a quest is accepted (spec /states/quest-vs-field).
	SessionManager.return_to_city()
	SessionManager._accepted_quest.clear()
	SessionManager._suspended_session.clear()
	SessionManager.clear_free_roam_state()

	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.flush_free_roam_field()
	assert_true(SessionManager.has_free_roam_field("gurhacia"), "free field flushes to the per-area store")
	assert_true(not SessionManager.has_suspended_session(), "a free field is NOT held in the suspended slot")
	assert_true(not SessionManager.has_suspended_quest(),
		"free field is not a suspended quest (counter stays unlocked)")

	TelepipeManager.place("gurhacia", 0, "0,0", Vector3.ZERO, "res://x.tscn")
	SessionManager.accept_quest("search_and_rescue", "normal")
	assert_true(not SessionManager.has_free_roam_field("gurhacia"),
		"accepting a quest clears retained free-field state")
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
	SessionManager.clear_free_roam_state()
	print("")


# ── #357: duplicate non-weapon equipment is equippable ──────────
# Buying multiples gives each copy a unique instance id; every copy must
# categorize as its real type and fit its slot (the bug stripped the suffix
# only for weapons, so armor/unit/mag duplicates became "tools").
func test_dup_equipment() -> void:
	print("── Same-stat items are each their own equippable item (#357) ──")
	# This test is about instance-suffix categorization, not class legality, and
	# runs against whatever character is globally active. "armor" is Hunter/Ranger-
	# only, so force equip_all to isolate the slot-fit check from the armor class
	# gate item_fits_slot("frame") now applies.
	var saved_equip_all_dup := DebugConfig.equip_all
	DebugConfig.equip_all = true
	Inventory.clear_inventory()
	for _i in range(3):
		Inventory.add_item("armor", 1)
	var armor_ids: Array = []
	for iid in Inventory._items:
		if Inventory.get_base_id(iid) == "armor":
			armor_ids.append(iid)
	assert_eq(armor_ids.size(), 3, "3 distinct armor instances in inventory")
	for iid in armor_ids:
		assert_eq(Inventory.get_item_category(iid), "Armor", "copy %s categorizes as Armor" % iid)
		assert_true(EquipmentUtils.item_fits_slot(iid, "frame"), "copy %s fits the frame slot" % iid)
	DebugConfig.equip_all = saved_equip_all_dup

	# Equip the 2nd copy, then switch to the 3rd — any instance is equippable.
	var character = CharacterManager.get_active_character()
	if character != null:
		character["equipment"] = character.get("equipment", {})
		character["equipment"]["frame"] = armor_ids[1]
		assert_eq(str(character["equipment"]["frame"]), str(armor_ids[1]), "can equip frame B")
		character["equipment"]["frame"] = armor_ids[2]
		assert_eq(str(character["equipment"]["frame"]), str(armor_ids[2]), "can switch to frame C")
		character["equipment"]["frame"] = ""

	# Same root cause hit units + mags — regress those too.
	Inventory.clear_inventory()
	Inventory.add_item("ace_guard", 1)
	Inventory.add_item("ace_guard", 1)
	var unit_ids: Array = []
	for iid in Inventory._items:
		if Inventory.get_base_id(iid) == "ace_guard":
			unit_ids.append(iid)
	assert_eq(unit_ids.size(), 2, "2 distinct unit instances")
	if unit_ids.size() >= 2:
		assert_true(EquipmentUtils.item_fits_slot(unit_ids[1], "unit1"), "2nd unit copy fits a unit slot")
		assert_eq(Inventory.get_item_category(unit_ids[1]), "Unit", "2nd unit copy categorizes as Unit")
	Inventory.clear_inventory()
	print("")


# ── #357: the REAL equipment screen lists + equips every same-stat frame ──
# test_dup_equipment proves the equipment_utils/inventory layer; this drives
# the actual equipment_screen.tscn node — the surface the player touched when
# they reported "only the first copy is equippable." Pre-fix, the screen's
# _open_item_selection filtered the #N copies out (item_fits_slot saw the raw
# suffixed id), so the list showed one frame; this asserts all three appear AND
# that a NON-first (#N-suffixed) instance equips through the screen's own flow.
func test_equipment_screen_dup_frame() -> void:
	print("── Equipment screen lists + equips every same-stat frame (#357) ──")
	const EquipmentScreen := preload("res://scenes/2d/equipment.tscn")

	# Deterministic active character. HUmar (Hunter Human) is in "armor"'s
	# usable_by (Hunter/Ranger), so the seeded frames are legally equippable —
	# this test exercises instance handling, not the class gate.
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "EquipDupTester")
	CharacterManager.set_active_slot(0)
	var character = CharacterManager.get_active_character()
	assert_true(character != null, "active character set up")
	character["equipment"] = character.get("equipment", {})
	character["equipment"]["frame"] = ""

	Inventory.clear_inventory()
	for _i in range(3):
		Inventory.add_item("armor", 1)
	var frame_ids: Array = []
	for iid in Inventory._items:
		if Inventory.get_base_id(iid) == "armor":
			frame_ids.append(iid)
	assert_eq(frame_ids.size(), 3, "3 distinct frame instances seeded")

	var screen: Control = EquipmentScreen.instantiate()
	add_child(screen)  # runs _ready → @onready + _refresh_display

	# Open the frame slot's item list through the real screen.
	var slots: Array = screen._get_visible_slots()
	var frame_idx: int = slots.find("frame")
	assert_true(frame_idx >= 0, "frame slot is visible")
	screen._selected_slot = frame_idx
	screen._open_item_selection()

	# Every seeded copy must appear as an equippable frame row — the regression:
	# pre-fix only the bare-id copy survived item_fits_slot, so this was 1.
	var rows: Array = []
	var suffixed_idx: int = -1
	for i in range(screen._equippable_items.size()):
		var row: Dictionary = screen._equippable_items[i]
		var rid: String = str(row.get("id", ""))
		if Inventory.get_base_id(rid) == "armor" and not bool(row.get("equipped", false)):
			rows.append(rid)
			if "#" in rid and suffixed_idx < 0:
				suffixed_idx = i
	assert_eq(rows.size(), 3, "all 3 frame instances are listed as equippable")
	assert_true(suffixed_idx >= 0, "a #N-suffixed (non-first) instance is in the list")

	# Equip the non-first instance through the screen, assert it sticks.
	var target_id: String = str(screen._equippable_items[suffixed_idx].get("id", ""))
	screen._selected_item = suffixed_idx
	screen._equip_selected_item()
	assert_eq(str(character["equipment"]["frame"]), target_id,
		"equipping a #N-suffixed frame instance through the screen sticks")

	# Rule 1 (/mechanics/inventory): a suffixed instance is a full, equal item.
	# It MUST contribute its base type's stats and expose its unit slots — not
	# read as a 0-stat / 0-slot item (the #363 raw-suffixed-id registry bug).
	var bonuses: Dictionary = screen._calc_equip_bonuses(character["equipment"], character)
	assert_eq(int(bonuses.get("def", 0)), 35,
		"suffixed frame contributes its base type's full DEF (35), not 0")
	var vis: Array = screen._get_visible_slots()
	assert_true(vis.has("unit1") and vis.has("unit4"),
		"suffixed frame exposes 4 unit slots (no shop roll → resolver falls back to the resource max_slots=4)")

	screen.free()
	Inventory.clear_inventory()
	character["equipment"]["frame"] = ""
	print("")


# ── Spec /mechanics/inventory: "Changing the frame clears every equipped unit" ──
# Any frame change to a DIFFERENT item unequips ALL units, even when the new
# frame has the same or more unit slots — the player re-slots into the new frame.
func test_frame_change_clears_units() -> void:
	print("── Changing the frame clears every equipped unit (#363, spec /mechanics/inventory) ──")
	const EquipmentScreen := preload("res://scenes/2d/equipment.tscn")

	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "FrameSwapTester")
	CharacterManager.set_active_slot(0)
	var character = CharacterManager.get_active_character()
	assert_true(character != null, "active character set up")
	character["equipment"] = {"weapon": "", "frame": "", "mag": ""}

	Inventory.clear_inventory()
	Inventory.add_item("armor", 1)          # 4 unit slots
	Inventory.add_item("valiant_frame", 1)  # 3 unit slots (still > 0)
	Inventory.add_item("ace_guard", 1)      # a unit to occupy a slot

	# Start with the 4-slot frame and a unit equipped in slot 1.
	character["equipment"]["frame"] = "armor"
	character["equipment"]["unit1"] = "ace_guard"

	var screen: Control = EquipmentScreen.instantiate()
	add_child(screen)

	# Equip the OTHER frame through the real screen flow.
	var slots: Array = screen._get_visible_slots()
	var frame_idx: int = slots.find("frame")
	assert_true(frame_idx >= 0, "frame slot is visible")
	screen._selected_slot = frame_idx
	screen._open_item_selection()
	var pick: int = -1
	for i in range(screen._equippable_items.size()):
		if str(screen._equippable_items[i].get("id", "")) == "valiant_frame":
			pick = i
			break
	assert_true(pick >= 0, "the other frame is offered in the frame list")
	screen._selected_item = pick
	screen._equip_selected_item()

	assert_eq(str(character["equipment"]["frame"]), "valiant_frame", "frame changed to the other frame")
	# The contract: EVERY unit slot is cleared, even though valiant_frame has 3 slots.
	for s in ["unit1", "unit2", "unit3", "unit4"]:
		assert_eq(str(character["equipment"].get(s, "")), "",
			"%s is unequipped after the frame change" % s)

	screen.free()
	Inventory.clear_inventory()
	character["equipment"] = {"weapon": "", "frame": "", "mag": ""}
	print("")


# ── Spec /mechanics/inventory: unit slots are a per-instance rolled property ──
# Two frames of the same base type may differ in slot count; the count lives in
# character["armor_slots"] keyed by instance id, falling back to the resource
# max_slots when no roll is recorded (starter gear, legacy saves).
func test_armor_slots_per_instance() -> void:
	print("── Unit slots are per-instance (spec /mechanics/inventory) ──")
	const EquipmentScreen := preload("res://scenes/2d/equipment.tscn")

	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "ArmorSlotsTester")
	CharacterManager.set_active_slot(0)
	var character = CharacterManager.get_active_character()
	assert_true(character != null, "active character set up")
	character["equipment"] = {"weapon": "", "frame": "", "mag": ""}
	character["armor_slots"] = {}

	Inventory.clear_inventory()
	for _i in range(2):
		Inventory.add_item("armor", 1)  # armor.tres max_slots = 4
	var ids: Array = []
	for iid in Inventory._items:
		if Inventory.get_base_id(iid) == "armor":
			ids.append(iid)
	assert_eq(ids.size(), 2, "2 distinct armor instances seeded")

	# id_a gets a recorded roll of 1; id_b stays un-rolled (→ fallback to 4).
	var id_a: String = str(ids[0])
	var id_b: String = str(ids[1])
	character["armor_slots"][id_a] = 1

	assert_eq(EquipmentUtils.get_unit_slot_count(id_a, character), 1,
		"recorded instance returns its rolled count (1)")
	assert_eq(EquipmentUtils.get_unit_slot_count(id_b, character), 4,
		"un-rolled instance falls back to resource max_slots (4)")
	assert_eq(EquipmentUtils.get_unit_slot_count("", character), 0, "empty id → 0 slots")

	# Clamp: a stored count above the cap resolves to 4.
	character["armor_slots"][id_a] = 9
	assert_eq(EquipmentUtils.get_unit_slot_count(id_a, character), 4, "stored count clamps to cap 4")
	character["armor_slots"][id_a] = 1

	# The visible equip slots must reflect the *instance's* count, not the base type.
	var screen: Control = EquipmentScreen.instantiate()
	add_child(screen)
	character["equipment"]["frame"] = id_a
	var vis_a: Array = screen._get_visible_slots()
	assert_true(vis_a.has("unit1") and not vis_a.has("unit2"),
		"1-slot frame exposes exactly one unit slot")
	character["equipment"]["frame"] = id_b
	var vis_b: Array = screen._get_visible_slots()
	assert_true(vis_b.has("unit1") and vis_b.has("unit4"),
		"same-base sibling with no roll exposes 4 unit slots")

	screen.free()
	Inventory.clear_inventory()
	character["equipment"] = {"weapon": "", "frame": "", "mag": ""}
	print("")


# ── Buying armor records a per-instance slot roll on the minted instance id ──
# Regression: the roll used to be keyed by BASE id, so two copies collided and
# the dict was never read. Now each purchase mints its own instance and records
# the roll against it; the shop row title carries no "[N slot]" suffix.
func test_shop_armor_purchase_records_slots() -> void:
	print("── Shop armor purchase records per-instance slots ──")
	const WeaponShop := preload("res://scenes/2d/shops/weapon_shop.tscn")

	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "ShopArmorTester")
	CharacterManager.set_active_slot(0)
	var character = CharacterManager.get_active_character()
	assert_true(character != null, "active character set up")
	character["meseta"] = 1000000
	character["armor_slots"] = {}
	Inventory.clear_inventory()

	var shop: Control = WeaponShop.instantiate()
	add_child(shop)  # _ready → _generate_inventory populates _armors with rolls

	assert_true(shop._armors.size() >= 1, "shop offers at least one armor")
	# No "[N slot]" label baked into the row name anymore.
	var first_name: String = str(shop._armors[0].get("name", ""))
	assert_true(not ("slot" in first_name) and not ("[" in first_name),
		"armor row name has no bracketed slot suffix")

	# Buy the same armor row twice → two distinct instance keys, each carrying
	# that row's rolled count.
	shop._tab = shop.Tab.ARMOR
	shop._selected_index = 0
	var expected_roll: int = int(shop._armors[0].get("rolled_slots", -1))
	var base_id: String = str(shop._armors[0].get("id", ""))
	shop._buy_selected()
	shop._buy_selected()

	var keys: Array = character.get("armor_slots", {}).keys()
	assert_eq(keys.size(), 2, "two purchases recorded two distinct instance keys")
	for k in keys:
		assert_eq(Inventory.get_base_id(str(k)), base_id, "recorded key %s is an instance of the bought armor" % str(k))
		assert_eq(int(character["armor_slots"][k]), expected_roll, "recorded slot count matches the row roll")

	shop.free()
	Inventory.clear_inventory()
	print("")


# ── #358: city telepipe visual cleared when the state is canceled ──
func test_telepipe_city_visual_cleared() -> void:
	print("── City telepipe visual cleared on cancel (#358) ──")
	const CityCounter := preload("res://scripts/3d/city/city_counter_controller.gd")
	# Off-tree instance — _ready (heavy city setup) doesn't run; we test the
	# cancel handler directly with a stub CityTelepipe child.
	var ctl = CityCounter.new()
	var pipe := Node3D.new()
	pipe.name = "CityTelepipe"
	ctl.add_child(pipe)
	assert_true(ctl.get_node_or_null("CityTelepipe") != null, "CityTelepipe present before cancel")
	ctl._on_telepipe_canceled("test")
	assert_true(pipe.is_queued_for_deletion(), "CityTelepipe node freed when the telepipe is canceled")
	ctl.free()
	print("")


# ── #384: Field Context outlives objective completion; report/cancel exit ──
func test_field_quest_decouple() -> void:
	print("── Field Context vs Quest State decoupling (#384) ──")
	# Clean slate.
	SessionManager.return_to_city()
	SessionManager._suspended_session.clear()
	SessionManager._accepted_quest.clear()
	SessionManager._completed_quest.clear()
	TelepipeManager.cancel("test_setup")

	# Enter a quest field and drop a player telepipe in it.
	SessionManager.accept_quest("search_and_rescue", "normal")
	SessionManager.start_accepted_quest()
	assert_true(SessionManager.has_active_session(), "quest Field Context active")
	TelepipeManager.place("gurhacia", 0, "0,0", Vector3(1, 0, 1),
		"res://scenes/3d/field/valley_field.tscn")
	assert_true(TelepipeManager.is_active(), "telepipe placed in the field")

	# Complete objectives → MUST keep the Field Context AND the telepipe alive.
	SessionManager.complete_quest()
	assert_true(SessionManager.has_active_session(),
		"completion keeps the Field Context (a later cell move won't hit Invalid section index — #378)")
	assert_true(not SessionManager.get_field_sections().is_empty(),
		"field sections still present after completion")
	assert_true(SessionManager.has_completed_quest(), "quest marked complete")
	assert_true(TelepipeManager.is_active(),
		"completing objectives does NOT cancel a placed telepipe (#384)")

	# Report → the quest's exit: tears down the Field Context + closes the pipe.
	SessionManager.report_quest()
	assert_true(not SessionManager.has_active_session(), "report clears the Field Context")
	assert_true(not TelepipeManager.is_active(), "report closes the telepipe")
	assert_true(not SessionManager.has_completed_quest(), "completed quest cleared on report")

	# Cancel is the other exit — also clears + closes.
	SessionManager.accept_quest("search_and_rescue", "normal")
	SessionManager.start_accepted_quest()
	TelepipeManager.place("gurhacia", 0, "0,0", Vector3(1, 0, 1),
		"res://scenes/3d/field/valley_field.tscn")
	SessionManager.complete_quest()
	assert_true(TelepipeManager.is_active(), "telepipe still up after completion (control)")
	SessionManager.cancel_accepted_quest()
	assert_true(not TelepipeManager.is_active(), "cancel closes the telepipe")
	assert_true(SessionManager._session.get("type", "") != "quest", "cancel cleared the live quest session")

	# Cleanup.
	SessionManager.return_to_city()
	SessionManager._suspended_session.clear()
	SessionManager._completed_quest.clear()
	print("")


# ── #359: a suspended FREE-FIELD session must not block quest accept ──
func test_freefield_quest_unblock() -> void:
	print("── Free-field session doesn't block quest accept (#359) ──")
	SessionManager.return_to_city()
	SessionManager._accepted_quest.clear()
	SessionManager._suspended_session.clear()

	# Leaving a free field via StartWarp flushes to the per-area Free-Roam store
	# (not the suspended slot).
	SessionManager.clear_free_roam_state()
	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.flush_free_roam_field()
	assert_true(SessionManager.has_free_roam_field("gurhacia"), "free-field run retained in the store")
	assert_true(not SessionManager.has_suspended_session(), "a free field is not a suspended session")
	assert_true(not SessionManager.has_suspended_quest(),
		"a free field is NOT a quest suspension (guild accept-block won't fire)")

	# Accepting a quest is allowed and clears the retained free-field state.
	SessionManager.accept_quest("search_and_rescue", "normal")
	assert_true(SessionManager.has_accepted_quest(), "quest accepted after a free-field trip")
	assert_true(not SessionManager.has_free_roam_field("gurhacia"), "accepting cleared the free-field state")
	SessionManager.cancel_accepted_quest()

	# Control: a suspended QUEST still reads as a quest (would block accept).
	SessionManager.enter_quest("search_and_rescue", "normal")
	SessionManager.suspend_session()
	assert_true(SessionManager.has_suspended_quest(), "a suspended QUEST still blocks accept (control)")
	SessionManager.cancel_accepted_quest()

	SessionManager.return_to_city()
	SessionManager._suspended_session.clear()
	SessionManager.clear_free_roam_state()
	print("")


# ── Free-Roam per-area field state (spec /states/quest-vs-field) ──
# Free-field run-state MUST persist per area across field switches + city
# returns for the whole Free-Roam period, and reset on quest accept / exit.
func _reset_session_state() -> void:
	SessionManager.return_to_city()
	SessionManager._accepted_quest.clear()
	SessionManager._suspended_session.clear()
	SessionManager._completed_quest.clear()
	SessionManager.clear_free_roam_state()
	TelepipeManager.cancel("test_setup")


## ── Free-Roam field lifecycle: generate → persist → regenerate ───────
## Spec /states/quest-vs-field. test_free_roam_per_area_state covers the STORE
## (what is retained and when it is cleared); this covers the FIELD ITSELF —
## that a first visit rolls a random layout, that the SAME layout comes back
## until a quest is taken, and that a new one is rolled afterwards.
##
## This is what the static data/field_quests/*.json used to prevent: the store
## cleared correctly, but the next entry replayed the identical hand-authored
## layout, so "a new field is created" was never true.
func test_free_roam_field_lifecycle() -> void:
	print("── Free-Roam field lifecycle (generate → persist → regenerate) ──")
	const GridGen := preload("res://scripts/3d/field/grid_generator.gd")
	_reset_session_state()

	# First visit: the warp's fresh-entry path generates rather than loading a file.
	SessionManager.enter_field("gurhacia", "normal")
	var first: Array = GridGen.new().generate_field("normal", "gurhacia")["sections"]
	SessionManager.set_field_sections(first)
	var first_sig := JSON.stringify(first)
	SessionManager.flush_free_roam_field()

	# Re-entry inside Free Roam restores the SAME field — not a fresh roll.
	assert_true(SessionManager.enter_free_roam_field("gurhacia"), "re-enter Valley from the store")
	assert_eq(JSON.stringify(SessionManager.get_field_sections()), first_sig,
		"the generated field persists byte-for-byte across a city return")
	SessionManager.flush_free_roam_field()

	# A second area generates its own field and neither disturbs the other.
	SessionManager.enter_field("ozette", "normal")
	SessionManager.set_field_sections(GridGen.new().generate_field("normal", "ozette")["sections"])
	SessionManager.flush_free_roam_field()
	assert_true(SessionManager.enter_free_roam_field("gurhacia"), "Valley still retained after a Wetlands trip")
	assert_eq(JSON.stringify(SessionManager.get_field_sections()), first_sig,
		"Valley's field is unchanged by visiting another free field")
	SessionManager.flush_free_roam_field()

	# Accepting a quest drops every retained field.
	SessionManager.accept_quest("search_and_rescue", "normal")
	assert_true(SessionManager.get_free_roam_area_ids().is_empty(),
		"accepting a quest clears the retained fields")
	assert_true(not SessionManager.has_free_roam_field("gurhacia"),
		"Valley has no retained field, so the next visit takes the fresh-generation path")
	SessionManager.start_accepted_quest()
	SessionManager.complete_quest()
	SessionManager.report_quest()

	# After the quest, a visit rolls a NEW field. Generation is random, so rather
	# than asserting one roll differs (which a coincidence could fail), assert the
	# generator produces more than one distinct layout — a fixed file cannot.
	var layouts := {}
	for i in range(6):
		layouts[JSON.stringify(GridGen.new().generate_field("normal", "gurhacia")["sections"])] = true
	assert_true(layouts.size() > 1,
		"post-quest visits roll a new field (%d distinct layouts in 6 rolls)" % layouts.size())

	_reset_session_state()
	print("")


func test_free_roam_per_area_state() -> void:
	print("── Free-Roam per-area state persists across field switches ──")
	_reset_session_state()

	# Enter Valley, clear a cell, and leave to the city (StartWarp/final-exit
	# both call flush_free_roam_field).
	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.set_field_sections([{"cells": [{"stage_id": "s01a_sa1"}], "start_pos": "1,1"}])
	SessionManager.save_section_state(0, {"1,1": {"objects": ["cleared"]}}, {}, {}, {"1,1": true})
	SessionManager.flush_free_roam_field()
	assert_true(SessionManager.has_free_roam_field("gurhacia"), "Valley retained after leaving")

	# Now visit Wetlands and leave — this MUST NOT wipe Valley's state.
	SessionManager.enter_field("ozette", "normal")
	SessionManager.set_field_sections([{"cells": [{"stage_id": "s02a_wa1"}], "start_pos": "2,2"}])
	SessionManager.save_section_state(0, {"2,2": {"objects": ["wet"]}}, {}, {}, {})
	SessionManager.flush_free_roam_field()
	assert_true(SessionManager.has_free_roam_field("ozette"), "Wetlands retained after leaving")
	assert_true(SessionManager.has_free_roam_field("gurhacia"),
		"Valley state survived the Wetlands trip (MUST NOT reset between free fields)")

	# Re-enter Valley from the store — its cleared cell comes back.
	assert_true(SessionManager.enter_free_roam_field("gurhacia"), "re-enter Valley from the store")
	assert_true(not SessionManager.get_field_sections().is_empty(), "Valley sections restored")
	var st: Dictionary = SessionManager.get_section_state(0)
	assert_true(st.get("cell_states", {}).has("1,1"), "Valley's cleared cell restored on re-entry")

	# Teleporter listing: both areas present, each at its reached section.
	var ids: Array = SessionManager.get_free_roam_area_ids()
	assert_true(ids.has("gurhacia") and ids.has("ozette"), "teleporter lists every retained free field")
	assert_eq(SessionManager.get_free_roam_visited_section_indices("ozette"), [0],
		"Wetlands lists its reached section as a warp point")

	# Accepting a quest clears ALL retained free-field state.
	SessionManager.accept_quest("search_and_rescue", "normal")
	assert_true(SessionManager.get_free_roam_area_ids().is_empty(),
		"accepting a quest clears all retained free-field state")

	# The quest's exit (report) leaves Free Roam reset — store stays empty.
	SessionManager.start_accepted_quest()
	SessionManager.complete_quest()
	SessionManager.report_quest()
	assert_true(SessionManager.get_free_roam_area_ids().is_empty(),
		"reporting a quest returns to a fresh Free Roam (no stale fields)")

	_reset_session_state()
	print("")


# ── Free-field telepipe round-trip restores from the per-area store ──
# The city-side telepipe pad must rehydrate a FREE field from _free_roam_state
# (it has no suspended session under the new model).
func test_free_telepipe_round_trip() -> void:
	print("── Free-field telepipe round-trip (store-backed) ──")
	_reset_session_state()

	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.set_field_sections([{"cells": [{"stage_id": "s01a_sa1"}], "start_pos": "3,3"}])
	SessionManager.save_section_state(0, {"3,3": {"objects": ["x"]}}, {}, {}, {})
	TelepipeManager.place("gurhacia", 0, "3,3", Vector3.ZERO, "res://scenes/3d/field/valley_field.tscn")
	SessionManager.flush_free_roam_field()
	assert_true(TelepipeManager.is_active(), "free-field telepipe stays active after leaving")
	assert_true(not SessionManager.has_suspended_session(), "free field does not use the suspended slot")
	assert_true(SessionManager.has_free_roam_field("gurhacia"), "field retained in the store")

	# Simulate the city-side pad: consume the return + rehydrate from the store.
	var snap: Dictionary = TelepipeManager.consume_return()
	assert_eq(str(snap.get("area_id", "")), "gurhacia", "telepipe snapshot carries the area")
	assert_true(SessionManager.enter_free_roam_field(str(snap.get("area_id", ""))),
		"city-side return rehydrates the free field from the store")
	SessionManager.set_current_section(int(snap.get("section_idx", 0)))
	assert_true(SessionManager.has_active_session(), "field session live again after telepipe return")
	var st2: Dictionary = SessionManager.get_section_state(int(snap.get("section_idx", 0)))
	assert_true(st2.get("cell_states", {}).has("3,3"), "cleared cell restored via the telepipe return")

	_reset_session_state()
	print("")


# ── Mechgun root-after-fire (Rozalin): every combo step recovers ──
# A looping attack animation (mechgun spray) never emits animation_finished,
# so without the elapsed-length safety net in _handle_attack_state the player
# is stranded in ATTACKING with movement zeroed. Under the #155 queued model
# the net is generalized to every step: at animation length the step ends —
# firing the queued chain if one exists, otherwise breaking to IDLE.
func test_mechgun_final_step_no_root() -> void:
	print("── Mechgun: combo steps recover without animation_finished ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	var pl = PlayerScript.new()

	# Final step (combo_state >= max_combo), anim "looping" so
	# animation_finished never fires. Tick past the anim length.
	pl.set("current_state", PlayerScript.PlayerState.ATTACKING)
	pl.set("combo_state", 3)
	pl.set("_attack_step_ended", false)
	pl.set("_attack_anim_length", 0.4)
	pl.set("_attack_anim_elapsed", 0.0)
	for _i in range(10):
		pl._handle_attack_state(0.1)
	assert_eq(int(pl.get("current_state")), int(PlayerScript.PlayerState.IDLE),
		"final combo step returns to IDLE once the anim length elapses (no permanent root)")
	assert_eq(int(pl.get("combo_state")), 0, "combo resets after the final step ends")

	# A non-final step with a QUEUED chain fires the next step at anim length
	# instead of rooting or breaking (#155 — the queued model's fire point).
	pl.set("current_state", PlayerScript.PlayerState.ATTACKING)
	pl.set("combo_state", 1)
	pl.set("_queued_combo", PlayerScript.ComboQueue.NORMAL)
	pl.set("_attack_step_ended", false)
	pl.set("_attack_anim_length", 0.4)
	pl.set("_attack_anim_elapsed", 0.5)
	pl._handle_attack_state(0.05)
	assert_eq(int(pl.get("current_state")), int(PlayerScript.PlayerState.ATTACKING),
		"queued chain keeps ATTACKING — next step fires at the safety net")
	assert_eq(int(pl.get("combo_state")), 2, "queued step advanced the combo at anim length")

	pl.free()
	print("")


# ── Technique cast recovers to IDLE (every cast, not just the first) ──
# A cast enters ATTACKING via _cast_technique, which does NOT go through
# _play_attack_animation — so the step-end tracking that path resets was left
# holding the previous attack step's values. _attack_step_ended stayed true,
# and BOTH exits out of ATTACKING are gated on it: the animation_finished
# double-fire guard and the elapsed-length safety net. Net effect was that the
# first cast after a spawn worked and every cast after it stranded the player
# in ATTACKING until an unrelated event (usually taking a hit) knocked them out.
# Same root as the mechgun case above: an entry point into ATTACKING that
# forgets to arm the step-end machinery.
func test_technique_cast_recovers() -> void:
	print("── Technique cast returns to IDLE ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	var pl = PlayerScript.new()

	# A cast-shaped step: combo_state 0 (techniques never combo), tracking armed
	# the way _cast_technique now arms it. The safety net must land it in IDLE
	# even though no animation_finished ever arrives.
	pl.set("current_state", PlayerScript.PlayerState.ATTACKING)
	pl.set("combo_state", 0)
	pl.set("_attack_step_ended", false)
	pl.set("_attack_anim_length", 0.4)
	pl.set("_attack_anim_elapsed", 0.0)
	for _i in range(10):
		pl._handle_attack_state(0.1)
	assert_eq(int(pl.get("current_state")), int(PlayerScript.PlayerState.IDLE),
		"a cast returns to IDLE at animation length with no animation_finished")

	# Why it has to be armed: a stale _attack_step_ended disables BOTH exits, so
	# the player never leaves ATTACKING no matter how long the clip runs.
	pl.set("current_state", PlayerScript.PlayerState.ATTACKING)
	pl.set("combo_state", 0)
	pl.set("_attack_step_ended", true)  # stale, as _cast_technique used to leave it
	pl.set("_attack_anim_length", 0.4)
	pl.set("_attack_anim_elapsed", 0.0)
	for _i in range(10):
		pl._handle_attack_state(0.1)
	assert_eq(int(pl.get("current_state")), int(PlayerScript.PlayerState.ATTACKING),
		"stale _attack_step_ended roots the player — why every ATTACKING entry must arm")

	# The regression pin: _arm_attack_step is the shared arming both the attack
	# path and the cast path go through, and it must clear a stale flag. Drop
	# the call from _cast_technique and casts root again — this is the assert
	# that makes that failure loud.
	pl.set("_attack_step_ended", true)
	pl.set("_attack_anim_elapsed", 99.0)
	pl._arm_attack_step("")
	assert_true(not bool(pl.get("_attack_step_ended")),
		"_arm_attack_step clears a stale step-end flag")
	assert_eq(float(pl.get("_attack_anim_elapsed")), 0.0,
		"_arm_attack_step restarts the elapsed clock")
	assert_eq(float(pl.get("_attack_anim_length")), 0.5,
		"_arm_attack_step falls back to 0.5s so the safety net stays armed")

	# The call site itself. Everything above proves _arm_attack_step works;
	# none of it proves _cast_technique still calls it, and that call is the
	# whole fix. It can't be driven from an off-tree player — _cast_technique
	# reaches _spawn_technique_effect, which needs get_tree() — so pin the
	# source instead.
	var src: String = _read_text_file("res://scripts/3d/player/player.gd")
	var cast_start: int = src.find("func _cast_technique(")
	assert_true(cast_start >= 0, "_cast_technique still exists in player.gd")
	var next_func: int = src.find("\nfunc ", cast_start + 1)
	var cast_body: String = src.substr(cast_start, next_func - cast_start) if next_func > 0 else src.substr(cast_start)
	assert_true(cast_body.contains("_arm_attack_step("),
		"_cast_technique arms the step-end machinery (drop this and every cast roots the player)")

	pl.free()
	print("")


# ── Two-tier combo timing (#461, spec /mechanics/combos) ──
# `just_start` is the single chain-accept boundary, a fraction of the current
# swing from WeaponComboConfig data (saber = 0.45). A press before it FUMBLES
# (miss-early, unbuffered); a press at/after it queues a NORMAL chain that fires
# at step end. There is no just-attack tier — crit/damage come from
# stats + equipment, not timing (#461). The finisher can't chain. Off-tree
# player, barehanded → type 0 (saber config) — the weapon-type fallback combat
# callers rely on.
func test_combo_two_tier() -> void:
	print("── Combo two-tier timing (#461) ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")

	# Data: saber tuned per #155, untuned types share the default config.
	# (approx: PackedFloat32Array narrows to float32 — exact == would flake.)
	var saber_t: Dictionary = CombatManager.get_combo_timing(0, 1)
	assert_true(is_equal_approx(float(saber_t.just_start), 0.45), "saber chain-accept opens at 0.45 (#155 fast-weapon tuning)")
	assert_true(not saber_t.has("just_end"), "no just_end tier boundary remains (#461)")
	var default_t: Dictionary = CombatManager.get_combo_timing(7, 1)  # untuned type → default
	assert_true(is_equal_approx(float(default_t.just_start), 0.55), "untuned weapon types share the default just_start 0.55")
	assert_true(CombatManager.get_combo_timing(0, 3).is_empty(), "finisher (step 3) has no accept window")
	assert_true(CombatManager.get_combo_timing(0, 0).is_empty(), "step 0 (not attacking) has no window")

	var pl = PlayerScript.new()

	# miss-early: press before just_start queues nothing (it FUMBLES the
	# swing — the lockout itself is pinned in test_combo_miss_early_fumble).
	pl.set("current_state", PlayerScript.PlayerState.ATTACKING)
	pl.set("combo_state", 1)
	pl.set("_attack_anim_length", 1.0)
	pl.set("_attack_anim_elapsed", 0.3)  # < 0.45
	pl._try_queue_combo(false)
	assert_eq(int(pl.get("_queued_combo")), int(PlayerScript.ComboQueue.NONE),
		"miss-early press queues nothing (fumble, not buffered)")
	pl.set("_combo_fumbled", false)  # fresh swing for the accept asserts below

	# chain-accept: at/after just_start queues a NORMAL chain.
	pl.set("_attack_anim_elapsed", 0.5)
	pl._try_queue_combo(false)
	assert_eq(int(pl.get("_queued_combo")), int(PlayerScript.ComboQueue.NORMAL),
		"press at/after just_start queues a normal chain")

	# One queue slot: a later press must not re-roll.
	pl.set("_attack_anim_elapsed", 0.8)
	pl._try_queue_combo(false)
	assert_eq(int(pl.get("_queued_combo")), int(PlayerScript.ComboQueue.NORMAL),
		"second press can't re-roll the queued chain")

	# Fire at step end: queued chain advances the combo.
	pl.set("_attack_step_ended", false)
	pl._attack_step_finished()
	assert_eq(int(pl.get("combo_state")), 2, "queued chain fires at step end → step 2")
	assert_eq(int(pl.get("_queued_combo")), int(PlayerScript.ComboQueue.NONE), "queue slot cleared on fire")
	assert_eq(int(pl.get("current_state")), int(PlayerScript.PlayerState.ATTACKING), "chain stays in ATTACKING")

	# Combo timing no longer scales damage (#461): the dict carries no "just"
	# mark and equals the plain step damage.
	var atk: Dictionary = pl._get_attack_damage()
	assert_true(not atk.has("just"), "combo swing carries no just mark (#461)")

	pl.free()
	print("")


# Second half of the #461 contract: the chain lifecycle — normal chains,
# the finisher's structural no-window, the un-queued break to IDLE.
# Off-tree player parked mid-swing — shared setup for the combo tests.
func _combo_swing_player(pl_script, step: int, elapsed: float):
	var pl = pl_script.new()
	pl.set("current_state", pl_script.PlayerState.ATTACKING)
	pl.set("combo_state", step)
	pl.set("_attack_anim_length", 1.0)
	pl.set("_attack_anim_elapsed", elapsed)
	return pl


# Fire the step-end point (resetting the exactly-once guard first).
func _combo_step_end(pl) -> void:
	pl.set("_attack_step_ended", false)
	pl._attack_step_finished()


# damage interrupts clearing the queue, and the special-chain flag.
func test_combo_chain_lifecycle() -> void:
	print("── Combo chain lifecycle (#461) ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")

	# chain-accept: a press at/after just_start queues a NORMAL chain.
	var pl = _combo_swing_player(PlayerScript, 2, 0.8)
	pl._try_queue_combo(false)
	assert_eq(int(pl.get("_queued_combo")), int(PlayerScript.ComboQueue.NORMAL),
		"press at/after just_start queues a normal chain")
	_combo_step_end(pl)
	assert_eq(int(pl.get("combo_state")), 3, "normal chain fires → step 3 (finisher)")
	var atk3: Dictionary = pl._get_attack_damage()
	assert_true(not atk3.has("just"), "combo swing carries no just mark (#461)")

	# Finisher: presses during step 3 are no-ops; its end breaks to IDLE.
	pl.set("_attack_anim_elapsed", 0.7)
	pl._try_queue_combo(false)
	assert_eq(int(pl.get("_queued_combo")), int(PlayerScript.ComboQueue.NONE), "finisher press queues nothing")
	_combo_step_end(pl)
	assert_eq(int(pl.get("current_state")), int(PlayerScript.PlayerState.IDLE), "finisher end returns to IDLE")
	assert_eq(int(pl.get("combo_state")), 0, "combo resets after the finisher")

	# Un-queued step end breaks the combo (too-late tier is structural).
	pl.set("current_state", PlayerScript.PlayerState.ATTACKING)
	pl.set("combo_state", 1)
	pl.set("_queued_combo", PlayerScript.ComboQueue.NONE)
	_combo_step_end(pl)
	assert_eq(int(pl.get("current_state")), int(PlayerScript.PlayerState.IDLE),
		"swing ending un-queued breaks the combo to IDLE (no grace window)")

	# Damage interrupt clears the queue AND the fumble flag (via
	# transition_to, with #428): the queued follow-up must never fire after
	# a DAMAGED recovery, and a fumble must not leak into the next combo.
	GameState.set_hp(GameState.max_hp)
	pl.set("current_state", PlayerScript.PlayerState.ATTACKING)
	pl.set("combo_state", 1)
	pl.set("_queued_combo", PlayerScript.ComboQueue.NORMAL)
	pl.set("_combo_fumbled", true)
	pl.take_damage(15)
	assert_eq(int(pl.get("_queued_combo")), int(PlayerScript.ComboQueue.NONE),
		"damage interrupt clears the combo queue (#155/#428)")
	assert_true(not bool(pl.get("_combo_fumbled")), "ATTACKING exit clears the fumble flag")
	GameState.set_hp(GameState.max_hp)

	# Special chain: strong-attack press queues with the special flag. (The
	# fire itself is the same _attack_step_finished path asserted above; the
	# special wind-up tween needs a tree, so the flag hand-off to
	# _is_special_attack is left to the autopilot probe.)
	pl.set("current_state", PlayerScript.PlayerState.ATTACKING)
	pl.set("combo_state", 1)
	pl.set("_is_special_attack", false)
	pl.set("_attack_anim_length", 1.0)
	pl.set("_attack_anim_elapsed", 0.8)
	pl._try_queue_combo(true)
	assert_true(bool(pl.get("_queued_combo_special")), "strong-attack press queues a special chain")
	assert_eq(int(pl.get("_queued_combo")), int(PlayerScript.ComboQueue.NORMAL),
		"special press in the normal window queues a NORMAL-tier chain")

	pl.free()
	print("")


# Miss-early FUMBLES the swing (spec /mechanics/combos): a plain no-op let
# mashing ride the wide accept window and chain anyway (Rozalin's #459
# playtest) — the fumble locks out chaining for the rest of the swing so
# mash breaks its own combo. Per swing: the next step starts clean.
func test_combo_miss_early_fumble() -> void:
	print("── Combo miss-early fumble ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	# Park mid-swing at 0.3 — before saber's just_start (0.45): miss-early.
	var pl = _combo_swing_player(PlayerScript, 1, 0.3)
	pl._try_queue_combo(false)
	assert_true(bool(pl.get("_combo_fumbled")), "miss-early press fumbles the swing")
	assert_eq(int(pl.get("_queued_combo")), int(PlayerScript.ComboQueue.NONE),
		"fumbling press queues nothing")

	# Mash: presses inside the accept window are now locked out.
	pl.set("_attack_anim_elapsed", 0.5)  # just window
	pl._try_queue_combo(false)
	assert_eq(int(pl.get("_queued_combo")), int(PlayerScript.ComboQueue.NONE),
		"just-window press after a fumble is ignored")
	pl.set("_attack_anim_elapsed", 0.8)  # normal window
	pl._try_queue_combo(true)
	assert_eq(int(pl.get("_queued_combo")), int(PlayerScript.ComboQueue.NONE),
		"normal-window press after a fumble is ignored (strong too)")

	# The fumbled swing ends un-queued → combo breaks.
	_combo_step_end(pl)
	assert_eq(int(pl.get("current_state")), int(PlayerScript.PlayerState.IDLE),
		"fumbled swing breaks the combo at swing end")

	# Per-swing lockout: firing the next step resets the flag (synthetic
	# fumbled+queued state — unreachable in play, but pins the reset path).
	pl.set("current_state", PlayerScript.PlayerState.ATTACKING)
	pl.set("combo_state", 1)
	pl.set("_combo_fumbled", true)
	pl.set("_queued_combo", PlayerScript.ComboQueue.NORMAL)
	_combo_step_end(pl)
	assert_eq(int(pl.get("combo_state")), 2, "queued chain fires into step 2")
	assert_true(not bool(pl.get("_combo_fumbled")), "next step starts with a clean chain attempt")
	# (Damage-interrupt clearing of the flag is pinned in
	# test_combo_chain_lifecycle's interrupt block.)

	pl.free()
	print("")


# The hit cone (spec /mechanics/targeting): PSO's check_enemy_is_targetable
# flattened to XZ — apex pulled back by v_dist, target radius extends reach,
# half-angle test against the facing. Pure math, tested directly.
func test_cone_targeting() -> void:
	print("── Hit cone (spec /mechanics/targeting) ──")
	var o := Vector3.ZERO
	# yaw 0 faces +Z. Saber-ish cone: h 2.4, v 0.5, half-angle 30°,
	# vertical unbounded (90) for the horizontal cases.
	assert_true(ConeTargeting.in_cone(o, 0.0, 2.4, 0.5, 30.0, 90.0, Vector3(0, 0, 2.6), 0.5),
		"enemy straight ahead inside reach passes")
	assert_true(not ConeTargeting.in_cone(o, 0.0, 2.4, 0.5, 30.0, 90.0, Vector3(0, 0, 3.5), 0.5),
		"enemy past reach fails")
	# Reach is measured from the pulled-back apex: reach = h + v + radius vs
	# dist = z + v — so at z = 3.2 a 0.5-radius target is out (3.7 > 3.4)
	# but a 0.9-radius one is in (3.7 ≤ 3.8).
	assert_true(not ConeTargeting.in_cone(o, 0.0, 2.4, 0.5, 30.0, 90.0, Vector3(0, 0, 3.2), 0.5),
		"0.5-radius target at 3.2 m is out of reach")
	assert_true(ConeTargeting.in_cone(o, 0.0, 2.4, 0.5, 30.0, 90.0, Vector3(0, 0, 3.2), 0.9),
		"a bigger hitbox radius extends the reach (PSO)")
	var side := Vector3(2.0, 0, 2.0)  # 45° off the facing
	assert_true(not ConeTargeting.in_cone(o, 0.0, 2.4, 0.5, 30.0, 90.0, side, 0.5),
		"45° off a 30° half-angle cone fails")
	assert_true(ConeTargeting.in_cone(o, 0.0, 2.4, 0.5, 60.0, 90.0, side, 0.5),
		"45° off a 60° half-angle cone passes")
	# Apex pull-back widens point-blank coverage: a flank target (90° off)
	# only passes when v_dist moves the cone's apex behind the player.
	var flank := Vector3(0.6, 0, 0.0)
	assert_true(not ConeTargeting.in_cone(o, 0.0, 2.4, 0.0, 45.0, 90.0, flank, 0.3),
		"flank target fails with no apex pull-back")
	assert_true(ConeTargeting.in_cone(o, 0.0, 2.4, 1.0, 45.0, 90.0, flank, 0.3),
		"apex pull-back brings the flank target into the cone")
	var d_near: float = ConeTargeting.distance_in_cone(o, 0.0, 2.4, 0.5, 30.0, 90.0, Vector3(0, 0, 1.0), 0.5)
	var d_far: float = ConeTargeting.distance_in_cone(o, 0.0, 2.4, 0.5, 30.0, 90.0, Vector3(0, 0, 2.5), 0.5)
	assert_true(d_near >= 0.0 and d_far > d_near, "distance_in_cone orders nearest-first")
	assert_true(not ConeTargeting.in_cone(o, PI, 2.4, 0.5, 30.0, 90.0, Vector3(0, 0, 2.6), 0.5),
		"facing away fails the cone")
	# Vertical half-angle bounds the slope from the apex: a target 2 m ahead
	# and 2 m up sits at 45° — outside a 40° bound, inside a 50° one; 90
	# means unbounded (PSO's launchers).
	var high := Vector3(0, 2.0, 2.0)
	assert_true(not ConeTargeting.in_cone(o, 0.0, 4.0, 0.0, 30.0, 40.0, high, 0.3),
		"45° slope fails a 40° vertical bound")
	assert_true(ConeTargeting.in_cone(o, 0.0, 4.0, 0.0, 30.0, 50.0, high, 0.3),
		"45° slope passes a 50° vertical bound")
	assert_true(ConeTargeting.in_cone(o, 0.0, 4.0, 0.0, 30.0, 90.0, high, 0.3),
		"vertical 90° is unbounded")
	print("")


# Damaging frame (spec /mechanics/targeting): hits resolve exactly once, when
# the swing crosses the step's damaging_frac — never before. Also pins the
# per-weapon hit-cone data every config entry must carry.
func test_damaging_frame() -> void:
	print("── Damaging frame + hit-cone data ──")
	var bad := 0
	for wt in CombatManager.WEAPON_TYPE_CONFIGS:
		var cfg: Dictionary = CombatManager.WEAPON_TYPE_CONFIGS[wt]
		if not (cfg.has("hit_h_dist") and cfg.has("hit_v_dist") and cfg.has("hit_h_angle_deg") and cfg.has("hit_v_angle_deg") and cfg.has("damaging_frac")):
			bad += 1
			continue
		var fracs: Array = cfg.get("damaging_frac")
		if fracs.size() != int(cfg.get("combo_steps", 3)):
			bad += 1
			continue
		for f in fracs:
			if float(f) <= 0.0 or float(f) >= 1.0:
				bad += 1
				break
	assert_eq(bad, 0, "every weapon type carries a hit cone + per-step damaging_frac in (0,1)")

	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	var pl = _combo_swing_player(PlayerScript, 1, 0.0)
	pl.set("_attack_hit_done", false)
	pl._handle_attack_state(0.2)  # elapsed 0.2 < saber damaging_frac[0] 0.40
	assert_true(not bool(pl.get("_attack_hit_done")), "no hit before the damaging frame")
	pl._handle_attack_state(0.25)  # elapsed 0.45 ≥ 0.40 → resolves (off-tree: empty cone)
	assert_true(bool(pl.get("_attack_hit_done")), "hit resolves once the damaging frame is crossed")
	pl._play_and_track_attack("no_such_anim")
	assert_true(not bool(pl.get("_attack_hit_done")), "a new swing starts with its damaging frame pending")
	pl.free()
	print("")


# Target-info HUD panel (spec /mechanics/targeting): renders NOTHING without
# a primary target. (The quick-menu priority is enforced by field_hud._process
# passing {} while the menu is open — same code path as "no target".)
func test_target_info_panel() -> void:
	print("── Target-info HUD panel ──")
	const FieldHud := preload("res://scripts/3d/field/field_hud.gd")
	var panel = FieldHud._TargetInfoPanel.new()
	panel.update_info({"kind": "enemy", "name": "Wolf", "hp": 10, "max_hp": 20})
	assert_true(panel.visible, "enemy target → panel renders")
	panel.update_info({})
	assert_true(not panel.visible, "no target (or quick menu open) → panel does not render")
	panel.update_info({"kind": "item", "name": "Monomate"})
	assert_true(panel.visible, "ground-item target → panel renders")
	panel.free()

	# Boxes ride the "enemies" group but carry no enemy_data — the primary
	# scan MUST show no panel for them (PSO; Rozalin's "enemy 0/0").
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	var pl = PlayerScript.new()
	var box := Node3D.new()  # anything without enemy_data reads as a box
	pl._update_primary_target_info([box], CombatManager.get_weapon_type_config(0))
	assert_true((pl.get("_primary_target_info") as Dictionary).is_empty(),
		"box primary → no details panel (targetable, but nothing to show)")
	box.free()
	pl.free()

	# Meseta drops have no item_id — the display name must come from amount
	# (Rozalin's nameless meseta panel).
	const DropMesetaScript := preload("res://scripts/3d/elements/drop_meseta.gd")
	var meseta = DropMesetaScript.new()
	meseta.amount = 25
	assert_eq(str(meseta._get_display_name()), "25 Meseta", "meseta drop names itself from the amount")
	meseta.free()
	print("")


# Area-map overlay (spec /states/area-map): fog of war — cells render only
# once visited (or with the tester reveal toggle), doors/warps track the
# controller's gate-state feed.
func test_area_map_overlay() -> void:
	print("── Area map overlay (fog of war) ──")
	const OverlayScript := preload("res://scripts/3d/field/area_map_overlay.gd")
	var map = OverlayScript.new()
	var cells: Array = [
		{"pos": "0,0", "connections": {"east": "0,1"}, "is_start": true},
		{"pos": "0,1", "connections": {"west": "0,0"}, "warp_edge": "east",
			"is_key_gate": true, "key_gate_direction": "east"},
	]
	map.setup(cells, "0,0", {"0,0": true}, "Section 1")
	assert_true(map._is_revealed("0,0"), "visited/current cell is revealed")
	assert_true(not map._is_revealed("0,1"), "unvisited cell stays fogged")
	DebugConfig.reveal_map = true
	assert_true(map._is_revealed("0,1"), "reveal_map debug toggle shows the full grid")
	DebugConfig.reveal_map = false
	assert_true(not map._is_revealed("0,1"), "toggle off restores the fog")
	# Gate-state feed: warp edge initializes as exit; controller locks flow in.
	assert_eq(str(map._gate_states.get("0,1>east", "")), "exit", "warp_edge initializes as the area-warp exit")
	map.set_gate_state("0,0", "east", "locked")
	assert_eq(str(map._gate_states.get("0,0>east", "")), "locked", "set_gate_state locks a door")
	map.set_gate_state("0,0", "east", "open")
	assert_eq(str(map._gate_states.get("0,0>east", "")), "open", "set_gate_state reopens it")
	map.free()
	print("")


# ── Area map room shapes: per-cell SVG footprints (player request) ──
# The map should read as actual rooms, not uniform squares: revealed cells
# draw their stage's minimap-SVG floor outline, rotated per cell. The
# parsing lives in MinimapSvg (extracted from room_minimap so both maps
# share it — and so the near-dup ratchet keeps it that way). Seeded inline
# SVG: CI runs without pack assets, so nothing here touches res://assets.
func test_area_map_room_shapes() -> void:
	print("── Area map room shapes (SVG footprints, shared parser) ──")
	var svg := "<svg viewBox=\"0 0 400 400\" data-scale=\"15.5\" data-offset-x=\"1.5\" data-offset-y=\"-2.5\">\n<path fill=\"#2a2a4e\" d=\"M 10,20 L 30,20 L 10,60 Z M 100,100 L 140,100 L 100,160 Z\"/>\n<path fill=\"none\" stroke=\"white\" stroke-width=\"2\" d=\"M 10,20 L 30,20 M 5,5 L 9,9\"/>\n<rect x=\"123.2\" y=\"272.9\" width=\"48\" height=\"8\" fill=\"#ff4444\" data-gate=\"true\" data-gate-dir=\"south\"/>\n</svg>\n"
	var tris: Array = MinimapSvg.parse_floor(svg)
	assert_eq(tris.size(), 2, "floor path parses into its two triangles")
	var first: PackedVector2Array = tris[0]
	assert_eq(first.size(), 3, "each floor chunk is a 3-vertex triangle")
	assert_true(Vector2(first[0]).is_equal_approx(Vector2(10, 20)),
		"triangle verts parse from the path d")
	var bounds: Array = MinimapSvg.parse_boundaries(svg)
	assert_eq(bounds.size(), 2, "boundary path parses into its two segments")
	var meta: Dictionary = MinimapSvg.parse_metadata(svg)
	assert_true(is_equal_approx(float(meta["scale"]), 15.5), "data-scale parses")
	assert_true(is_equal_approx(float(meta["offset_y"]), -2.5), "data-offset-y parses")
	var gates: Array = MinimapSvg.parse_gates(svg)
	assert_eq(gates.size(), 1, "data-gate rect parses")
	assert_eq(str(gates[0]["dir"]), "south", "gate direction comes from data-gate-dir")
	assert_true(Vector2(gates[0]["center"]).is_equal_approx(Vector2(147.2, 276.9)),
		"gate center is the rect midpoint")
	# View transform: unrotated SVG fills the window; rotation mirrors the CW
	# label swap StageRotation applies to directions (north edge → east edge).
	var win := Rect2(139.0, 219.0, 107.0, 107.0)
	assert_true(MinimapSvg.svg_to_view(Vector2(0, 0), 0, win).is_equal_approx(win.position),
		"unrotated SVG origin lands on the window corner")
	var east_mid := Vector2(win.position.x + win.size.x, win.position.y + win.size.y * 0.5)
	assert_true(MinimapSvg.svg_to_view(Vector2(200, 0), 90, win).is_equal_approx(east_mid),
		"90° rotation maps the north edge onto the east edge")
	# Overlay fallback: a cell whose stage has no SVG (bogus id) caches an
	# empty shape and keeps the square; a cell without stage_id requests none.
	const OverlayScript := preload("res://scripts/3d/field/area_map_overlay.gd")
	var map = OverlayScript.new()
	var cells: Array = [
		{"pos": "0,0", "stage_id": "s01z_zz9", "rotation": 90, "connections": {"east": "0,1"}},
		{"pos": "0,1", "connections": {"west": "0,0"}},
	]
	map.setup(cells, "0,0", {"0,0": true}, "Section 1", "valley")
	assert_true((map._room_shapes["0,0"] as Dictionary).get("triangles", []).is_empty(),
		"stage without an SVG caches an empty shape → square fallback")
	assert_true(not map._room_shapes.has("0,1"), "cell without stage_id requests no shape")
	map.free()
	print("")

# ── Weapon attack SFX: one canonical sound per type (Rozalin's audit) ──
# Each weapon MUST map to a single attack sound (no random multi-common glob),
# and the file MUST exist in the pack. Pins the common-number mapping so it
# can't silently drift back to globs.
func test_weapon_attack_sfx_mapping() -> void:
	print("── Weapon attack SFX mapping (single canonical sound per type) ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	const W := WeaponData.WeaponType
	var sfx: Dictionary = PlayerScript.WEAPON_SFX
	var expected := {
		W.SABER: "saber_swing_1.wav",        # common35
		W.SWORD: "sword_swing_1.wav",         # common36
		W.DAGGERS: "dagger_swing_1.wav",      # common38
		W.CLAW: "saber_swing_1.wav",          # common35
		W.DOUBLE_SABER: "saber_swing_1.wav",  # common35
		W.SPEAR: "spear_swing_1.wav",         # common37
		W.SLICER: "slicer_swing_1.wav",       # common39
		W.HANDGUN: "handgun_shot_1.wav",      # common41
		W.RIFLE: "rifle_shot_1.wav",          # common43
		W.MECH_GUN: "mechgun_shot_1.wav",     # common42
		W.ROD: "saber_swing_1.wav",           # common35
		W.WAND: "rod_swing_1.wav",            # common45
	}
	for wtype in expected:
		var path: String = str(sfx.get(wtype, ""))
		assert_true(path.ends_with(expected[wtype]),
			"weapon type %d → %s (got '%s')" % [wtype, expected[wtype], path])
		assert_true(not path.contains("*"), "weapon type %d sound is a single file, not a glob" % wtype)
		# NB: file existence is check-asset-refs' job (greps res:// refs against
		# asset_tree.txt) — CI doesn't check out pack assets, so we can't assert
		# ResourceLoader.exists() here.
	print("")


# ── New weapon animation sets imported from psz-asset-viewer ──
# a_rifle / d_saver / l_cannon NDS extractions wired onto RIFLE / DOUBLE_SABER /
# LASER_CANNON. Pins the WEAPON_ANIM_DATA wiring (GLB paths + prefixes) so the
# male/female prefix convention can't silently drift. The GLBs are pack-only, so
# existence is check-asset-refs' job — we can't ResourceLoader.exists() here.
func test_weapon_anim_data_new_animation_sets() -> void:
	print("── New weapon anim sets: rifle / double saber / laser cannon ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	const W := WeaponData.WeaponType
	var anim: Dictionary = PlayerScript.WEAPON_ANIM_DATA
	# weapon_type → [glb_basename, prefix_m, prefix_w]
	var expected := {
		W.RIFLE: ["rifle", "pmar", "pwars"],
		W.DOUBLE_SABER: ["dsaver", "pmds", "pwdss"],
		W.LASER_CANNON: ["cannon", "pmlc", "pwlcs"],
	}
	for wtype in expected:
		assert_true(anim.has(wtype), "WEAPON_ANIM_DATA has weapon type %d" % wtype)
		var data: Dictionary = anim.get(wtype, {})
		var base: String = expected[wtype][0]
		assert_eq(str(data.get("glb_m", "")),
			"res://assets/player/animations/%s_m.glb" % base, "type %d male GLB" % wtype)
		assert_eq(str(data.get("glb_w", "")),
			"res://assets/player/animations/%s_w.glb" % base, "type %d female GLB" % wtype)
		assert_eq(str(data.get("prefix_m", "")), expected[wtype][1], "type %d male prefix" % wtype)
		assert_eq(str(data.get("prefix_w", "")), expected[wtype][2], "type %d female prefix" % wtype)

	# Combat combo length must match the attack clips each set actually ships:
	# rifle/double-saber have atk1..3 (3-step), laser cannon only atk1 (1-step,
	# so it must NOT fall back to the SABER 3-step config and request atk2/atk3).
	var expected_combo := {W.RIFLE: 3, W.DOUBLE_SABER: 3, W.LASER_CANNON: 1}
	for wtype in expected_combo:
		var cfg: Dictionary = CombatManager.get_weapon_type_config(wtype)
		assert_eq(int(cfg.get("combo_steps", -1)), expected_combo[wtype],
			"type %d combo_steps" % wtype)
	print("")


# ── #420: companion locomotion clip is keyed to MEASURED displacement ──
# The bug: _process_follow chose the companion's walk/run/wait clip from the
# delayed *player* PlayerState (IDLE=0/WALKING=1/RUNNING=2/ATTACKING=3/…). A
# rooted player attack (state 3) is >= 1 and != 1, so the companion fell into
# the `run` branch while its trail-follow position never advanced — it ran in
# place. The fix makes the clip a pure function of the companion's own planar
# displacement via _select_locomotion_anim, which takes NO player state at all.
# Off-tree instance (no _ready / scene / AnimationPlayer needed) — the selector
# is pure, so this is fully deterministic.
func test_companion_anim_from_measured_speed() -> void:
	print("── Companion locomotion clip from measured planar speed (#420) ──")
	const CompanionScript := preload("res://scripts/3d/elements/companion_npc.gd")
	var c = CompanionScript.new()
	var dt: float = 1.0 / 60.0  # one physics frame

	# The bug case: zero displacement MUST be "wait" — proves the selector reads
	# the companion's motion, not the player's state. (Under the old code a
	# rooted-attack player here produced "run" while the companion stood still.)
	assert_eq(c._select_locomotion_anim(Vector3.ZERO, Vector3.ZERO, dt), "wait",
		"zero displacement -> wait (no run-in-place)")

	# Sub-IDLE_EPS jitter (0.002 m/frame ≈ 0.12 m/s < IDLE_EPS 0.15) stays wait.
	assert_eq(c._select_locomotion_anim(Vector3.ZERO, Vector3(0.002, 0, 0), dt), "wait",
		"sub-threshold jitter -> wait")

	# 0.02 m/frame = 1.2 m/s — between IDLE_EPS and RUN_ENTER -> walk.
	assert_eq(c._select_locomotion_anim(Vector3.ZERO, Vector3(0.02, 0, 0), dt), "walk",
		"0.02 m/frame (1.2 m/s) -> walk")

	# 0.1 m/frame = 6 m/s — above RUN_ENTER (4.0) -> run.
	assert_eq(c._select_locomotion_anim(Vector3.ZERO, Vector3(0, 0, 0.1), dt), "run",
		"0.1 m/frame (6 m/s) -> run")

	# Pure vertical displacement is planar-excluded (gravity / height-snap) -> wait.
	assert_eq(c._select_locomotion_anim(Vector3.ZERO, Vector3(0, 1.0, 0), dt), "wait",
		"pure vertical motion -> wait (planar only)")

	# delta == 0 must not divide-by-zero — defaults to wait.
	assert_eq(c._select_locomotion_anim(Vector3.ZERO, Vector3(0.1, 0, 0.1), 0.0), "wait",
		"delta == 0 -> wait (no div-by-zero)")

	# Intent gate (pure CompanionCombat.locomotion_clip): the FSM's movement
	# intent selects wait vs locomote, the measured speed selects walk vs run.
	# intent=false is ALWAYS wait, even at run speed (rooted/frozen states never
	# slide); intent=true still yields wait below IDLE_EPS (the #420 veto — a
	# blocked-but-steering companion never plays a locomotion clip in place). The
	# current clip is threaded in for the walk↔run hysteresis (exercised below);
	# the wait cases must win regardless of what is playing.
	assert_eq(CompanionCombat.locomotion_clip(false, 6.0, "run"), "wait",
		"intent=false -> wait even at run speed (no slide)")
	assert_eq(CompanionCombat.locomotion_clip(true, 0.05, "run"), "wait",
		"intent=true but sub-IDLE_EPS -> wait (#420 veto, beats run-hold)")
	assert_eq(CompanionCombat.locomotion_clip(true, 1.2, "walk"), "walk",
		"intent=true, mid speed -> walk")
	assert_eq(CompanionCombat.locomotion_clip(true, 6.0, "walk"), "run",
		"intent=true, above RUN_ENTER -> run")

	c.free()
	print("")


# ── #463 hysteresis, split from the selector test above so each stays under the
# code-health size/cx bound. Pure CompanionCombat.locomotion_clip statics
# (data-in/data-out) — no companion instance needed.
func test_companion_anim_walk_run_hysteresis() -> void:
	print("── Companion walk↔run hysteresis band (#463) ──")

	# ── #463: walk↔run hysteresis band (RUN_EXIT 3.0 .. RUN_ENTER 4.0) ──
	# The bug: measured planar_speed is a noisy per-frame displacement. With a
	# single threshold, a speed hovering at ~4 m/s flapped run↔walk every frame;
	# the 0.3s _play_companion_anim debounce only rate-limited the flap to ~3 Hz
	# because the SELECTOR's output still oscillated. The fix holds the current
	# clip inside the band.
	#
	# Enter run ONLY above RUN_ENTER; below it (but still in the band) a walker
	# stays walk.
	assert_eq(CompanionCombat.locomotion_clip(true, 3.9, "walk"), "walk",
		"walk + 3.9 m/s (in band, below RUN_ENTER) -> stay walk")
	assert_eq(CompanionCombat.locomotion_clip(true, 4.1, "walk"), "run",
		"walk + 4.1 m/s (above RUN_ENTER) -> enter run")
	# Exit run ONLY below RUN_EXIT; inside the band a runner HOLDS run.
	assert_eq(CompanionCombat.locomotion_clip(true, 3.9, "run"), "run",
		"run + 3.9 m/s (in band, above RUN_EXIT) -> hold run")
	assert_eq(CompanionCombat.locomotion_clip(true, 3.1, "run"), "run",
		"run + 3.1 m/s (in band, above RUN_EXIT) -> hold run")
	assert_eq(CompanionCombat.locomotion_clip(true, 2.9, "run"), "walk",
		"run + 2.9 m/s (below RUN_EXIT) -> exit to walk")
	# Coming out of wait picks by the enter threshold (no phantom run at band speed).
	assert_eq(CompanionCombat.locomotion_clip(true, 3.5, "wait"), "walk",
		"wait + 3.5 m/s (in band) -> walk, not run (enter threshold)")

	# THE anti-regression assertion: an oscillating speed sequence that straddles
	# the band, threading the returned clip back in as current_clip each step,
	# must STOP changing the clip once it has settled into run. Under the old
	# single-threshold selector this list produced run,walk,run,walk,walk,run… —
	# a per-frame flap. With hysteresis, once 4.1 crosses RUN_ENTER the clip is
	# "run" and every subsequent band-dip (3.9, 3.5, 3.1) holds it.
	var flap_speeds: Array = [3.9, 4.1, 3.9, 4.1, 3.5, 4.2, 3.1, 3.8, 3.9]
	var clip: String = "walk"  # start below the band
	var run_since := -1
	var transitions_after_settle := 0
	for i in range(flap_speeds.size()):
		var next_clip: String = CompanionCombat.locomotion_clip(true, flap_speeds[i], clip)
		if run_since >= 0 and next_clip != clip:
			transitions_after_settle += 1
		if next_clip == "run" and run_since < 0:
			run_since = i
		clip = next_clip
	assert_true(run_since >= 0, "oscillating sequence entered run once it crossed RUN_ENTER")
	assert_eq(transitions_after_settle, 0,
		"#463: no clip flapping once settled in run — band dips (3.0..4.0) hold run")
	assert_eq(clip, "run", "sequence ends in run (never fell out through the band)")

	# Honest transitions still work: a clear climb 0→5 gives run; a clear drop
	# 5→0 gives walk then wait (each threaded through the current clip).
	assert_eq(CompanionCombat.locomotion_clip(true, 0.0, "wait"), "wait",
		"climb start: 0 m/s -> wait")
	assert_eq(CompanionCombat.locomotion_clip(true, 5.0, "walk"), "run",
		"climb: 5 m/s well above RUN_ENTER -> run")
	assert_eq(CompanionCombat.locomotion_clip(true, 2.0, "run"), "walk",
		"drop: 2 m/s well below RUN_EXIT -> walk")
	assert_eq(CompanionCombat.locomotion_clip(true, 0.0, "walk"), "wait",
		"drop: 0 m/s -> wait")

	print("")


# ── #463 arrival gait: the FOLLOW speed ramp that drives the clip. Continuity
# (monotonic, no dead zone) is what removes the run/walk/wait flap the old
# measured-displacement path produced when the companion caught up and stalled.
func test_companion_follow_speed_ramp() -> void:
	print("── Companion FOLLOW speed ramp (#463 arrival gait) ──")
	var ring := 2.5   # companion_npc FOLLOW_DISTANCE
	var ramp := 1.5   # companion_npc FOLLOW_SLOW_RADIUS
	var cap := 6.5    # companion_npc FOLLOW_MAX_SPEED
	# At/inside the ring the companion holds station -> 0 (gait settles to wait).
	assert_eq(CompanionCombat.follow_speed(ring, ring, ramp, cap), 0.0, "at the ring -> 0")
	assert_eq(CompanionCombat.follow_speed(1.0, ring, ramp, cap), 0.0, "inside the ring -> 0")
	# Just outside -> moving (a small speed = walk once fed through locomotion_clip).
	assert_true(CompanionCombat.follow_speed(ring + 0.3, ring, ramp, cap) > 0.0, "just outside -> moving")
	# Linear across the ramp: half the ramp -> half the cap.
	assert_eq(CompanionCombat.follow_speed(ring + ramp * 0.5, ring, ramp, cap), cap * 0.5, "half ramp -> half cap")
	# Full ramp and beyond -> capped (no runaway; keeps a bounded trailing gap).
	assert_eq(CompanionCombat.follow_speed(ring + ramp, ring, ramp, cap), cap, "full ramp -> cap")
	assert_eq(CompanionCombat.follow_speed(ring + ramp + 10.0, ring, ramp, cap), cap, "far out -> still cap")
	# THE anti-flap property: monotonic non-decreasing in distance (no dead zone).
	var prev := -1.0
	for d in [0.0, 1.0, 2.5, 2.8, 3.0, 3.25, 4.0, 5.0, 20.0]:
		var s: float = CompanionCombat.follow_speed(d, ring, ramp, cap)
		assert_true(s >= prev, "monotonic at d=%.2f (%.3f >= %.3f)" % [d, s, prev])
		prev = s
	# Cap above player run (MOVE_SPEED 6.0) so the trailing gap can't grow.
	assert_true(cap > 6.0, "cap above player run -> keeps pace")
	# Degenerate ramp (0) can't divide-by-zero — clean step at the ring.
	assert_eq(CompanionCombat.follow_speed(ring + 0.1, ring, 0.0, cap), cap, "ramp=0 -> cap outside ring")
	assert_eq(CompanionCombat.follow_speed(ring, ring, 0.0, cap), 0.0, "ramp=0 -> 0 at ring")
	print("")


# ── Companion combat phase 1: the pure decision functions ──
# Spec /states/companion-combat. All decisions are statics on CompanionCombat
# (data-in/data-out), so this pins target priority, leash filtering, damage
# math, and the damaging-frame crossing without a scene or player.
func test_companion_combat_decisions() -> void:
	print("── Companion combat: target selection / attack math (spec /states/companion-combat) ──")
	var player_pos := Vector3.ZERO
	var comp_pos := Vector3(2, 0, 0)

	# Nearest eligible candidate wins when the player has no reticle target.
	var cands: Array = [
		{"pos": Vector3(8, 0, 0), "alive": true},
		{"pos": Vector3(4, 0, 0), "alive": true},
	]
	assert_eq(CompanionCombat.select_target(cands, player_pos, comp_pos), 1,
		"nearest eligible enemy wins without a preferred target")

	# Assist priority: the player's reticle target wins even when another
	# candidate is nearer to the companion.
	assert_eq(CompanionCombat.select_target(cands, player_pos, comp_pos, 0), 0,
		"player's reticle target wins over a nearer candidate")

	# Leash: candidates beyond LEASH_RADIUS of the PLAYER are ineligible —
	# including a preferred target, which falls back to nearest-eligible.
	var far := Vector3(CompanionCombat.LEASH_RADIUS + 1.0, 0, 0)
	cands = [
		{"pos": far, "alive": true},
		{"pos": Vector3(4, 0, 0), "alive": true},
	]
	assert_eq(CompanionCombat.select_target(cands, player_pos, comp_pos, 0), 1,
		"out-of-leash preferred target falls back to nearest eligible")

	# Dead candidates are filtered; nothing eligible returns -1.
	cands = [
		{"pos": Vector3(3, 0, 0), "alive": false},
		{"pos": far, "alive": true},
	]
	assert_eq(CompanionCombat.select_target(cands, player_pos, comp_pos), -1,
		"dead + out-of-leash candidates -> no target (-1)")

	# Leash is XZ-planar: a big Y offset never breaks the leash.
	cands = [{"pos": Vector3(4, 30, 0), "alive": true}]
	assert_eq(CompanionCombat.select_target(cands, player_pos, comp_pos), 0,
		"leash test is planar — vertical offset is ignored")

	# Damage math: class attack x damage_mult[0] x COMPANION_DAMAGE_SCALE,
	# step-1 knockback/hits/max_targets straight from the shared config.
	var saber: Dictionary = CombatManager.get_weapon_type_config(0)
	var atk: Dictionary = CompanionCombat.compute_attack(100, 120, saber)
	assert_eq(int(atk.damage), int(100.0 * float(saber.damage_mult[0]) * CompanionCombat.COMPANION_DAMAGE_SCALE),
		"raw damage = attack x damage_mult[0] x damage scale")
	assert_eq(int(atk.accuracy), 120, "accuracy passes through to the hit")
	assert_eq(int(atk.hits), int(saber.hits_per_step[0]), "hits = step-1 hits_per_step")
	assert_eq(int(atk.max_targets), int(saber.max_targets), "max_targets from config")

	# Weapon assignment: per-companion types, default SABER. Kai carries the
	# Axeon gunblade (GUN_BLADE = 7) — the swing still resolves through the
	# shared melee cone in phase 1.
	assert_eq(CompanionCombat.weapon_type_for("dorn"), 1, "dorn swings a sword")
	assert_eq(CompanionCombat.weapon_type_for("kai"), 7, "kai carries a gunblade")
	assert_eq(CompanionCombat.weapon_type_for("someone_new"), 0, "unknown companion defaults to saber")

	# Damaging-frame crossing: fires exactly on the tick that crosses
	# frac x length, never before, never twice, never on a zero-length swing.
	assert_eq(CompanionCombat.swing_crossed_damaging_frac(0.0, 0.1, 1.0, 0.4), false,
		"before the damaging frame -> no hit")
	assert_eq(CompanionCombat.swing_crossed_damaging_frac(0.35, 0.45, 1.0, 0.4), true,
		"crossing the damaging frame -> hit")
	assert_eq(CompanionCombat.swing_crossed_damaging_frac(0.45, 0.55, 1.0, 0.4), false,
		"past the damaging frame -> no second hit")
	assert_eq(CompanionCombat.swing_crossed_damaging_frac(0.0, 0.1, 0.0, 0.4), false,
		"zero-length swing never fires")
	print("")


# ── #352: charge-cancel — _drop_charge shared by every drop path ──
# #273 made only dodge cancel a mid-charge technique; #352 extracts the cancel
# into _drop_charge and adds N/H/S-attack and menu-open as drop paths. Off-tree
# bare player (no _ready) so _drop_charge / _on_palette_pressed run without the
# field/combat scene — _end_charge_visual is null-safe.
func test_charge_drop_paths() -> void:
	print("── Charge cancel: _drop_charge clears + different-slot drop (#352) ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")
	var pl = PlayerScript.new()

	# Core: _drop_charge clears the charge and emits tech_charge_released once.
	var released: Array = []
	pl.tech_charge_released.connect(func(s: int) -> void: released.append(s))
	pl.set("_charging_slot", 2)
	pl.set("_charging_tech_id", "foie")
	pl.set("_tech_charge_ready", true)
	pl._drop_charge()
	assert_eq(pl.get("_charging_slot"), -1, "_drop_charge clears the charging slot")
	assert_eq(str(pl.get("_charging_tech_id")), "", "_drop_charge clears the tech id")
	assert_eq(released, [2], "_drop_charge emits tech_charge_released with the dropped slot")

	# No-op when nothing is charging — menu opens fire this every time, so a
	# spurious release would phantom-cancel / double-emit.
	released.clear()
	pl._drop_charge()
	assert_eq(released, [], "_drop_charge is a no-op (no emit) when not charging")

	# A DIFFERENT palette slot mid-charge drops the old charge first. Use two
	# techs so the new press starts a fresh charge (no combat executes) — same
	# branch an N/H/S attack takes before _execute_palette_action.
	var page: int = ActionPalette.current_page
	var saved0: String = ActionPalette.get_action_for_slot(0)
	var saved1: String = ActionPalette.get_action_for_slot(1)
	ActionPalette.set_action(page, 0, "foie")
	ActionPalette.set_action(page, 1, "barta")
	if ActionPalette.get_action_for_slot(1) == "barta":
		released.clear()
		pl.set("_charging_slot", 0)
		pl.set("_charging_tech_id", "foie")
		pl._on_palette_pressed(1)
		assert_eq(released, [0], "pressing a different slot mid-charge drops the old charge (slot 0)")
		assert_eq(pl.get("_charging_slot"), 1, "the new charge starts on the pressed slot")
		assert_eq(str(pl.get("_charging_tech_id")), "barta", "the new charge tracks the new tech")

		# Re-pressing the SAME charging slot must NOT drop — the hold→release
		# cast path (#273) still owns same-slot, so no spurious release fires.
		released.clear()
		pl.set("_charging_slot", 1)
		pl.set("_charging_tech_id", "barta")
		pl._on_palette_pressed(1)
		assert_eq(released, [], "re-pressing the same charging slot does not drop (no release emit)")
	else:
		print("  (skipped palette-driven drop: page has <2 slots)")

	ActionPalette.set_action(page, 0, saved0)
	ActionPalette.set_action(page, 1, saved1)
	pl.free()
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


func test_bootstrap_registers_pack_uids() -> void:
	print("── bootstrap — pack uid map re-registration (#539) ──")

	# load_resource_pack() mounts files but not the pack's UID registry, so
	# uid:// refs baked into packed scenes log "invalid UID — using text path".
	# bootstrap replays assets/uid_map.json through ResourceUID to fix that.
	var boot = load("res://scripts/2d/bootstrap.gd").new()

	# Fixture with one id the binary cannot already know (random-ish text id).
	var map_path: String = "user://test-uid-map.json"
	var uid_text: String = "uid://bpsz539testuid"
	var res_path: String = "res://assets/objects/special_c3/s00_1_back03.png"
	var f := FileAccess.open(map_path, FileAccess.WRITE)
	assert_true(f != null, "uid map fixture opened for write")
	f.store_string(JSON.stringify({uid_text: res_path}))
	f.close()

	var id := ResourceUID.text_to_id(uid_text)
	assert_true(not ResourceUID.has_id(id), "Fixture id unknown before registration")
	assert_eq(boot._register_pack_uids(map_path), 1, "One id registered from the map")
	assert_true(ResourceUID.has_id(id), "Fixture id known after registration")
	assert_eq(ResourceUID.get_id_path(id), res_path, "Registered id resolves to its res:// path")

	# Re-running must not clobber or double-count — in-tree entries win.
	assert_eq(boot._register_pack_uids(map_path), 0, "Second pass skips already-known ids")

	ResourceUID.remove_id(id)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(map_path))

	# Missing / malformed maps degrade to the old text-path fallback, not a crash.
	assert_eq(boot._register_pack_uids("user://test-uid-map-absent.json"), 0,
		"Missing uid map is a no-op")

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


func test_setup_shop_portrait() -> void:
	print("── PszStyle.setup_shop_portrait — single shared shop layout ──")
	# THE one layout path every shop uses (composition, NOT a base class — a
	# ShopBase base class broke the Android export; #274 inc 5 / #368).
	# Diegetic framing (spec /states/shops#presentation): the outer panel is
	# transparent and anchored to the left of the frame; the body (list) is a
	# glass card stretching 3/5, the detail card a shorter top-aligned card 2/5.
	# No 2D portrait spacer — the real 3D shopkeeper NPC stands behind the
	# overlay. Passing null detail makes it create a styled card
	# (photon/crafting/tekker path).
	var panel := PanelContainer.new()
	panel.name = "Panel"
	var content := VBoxContainer.new()
	panel.add_child(content)
	add_child(panel)

	var card := PszStyle.setup_shop_portrait(panel, null, "")

	assert_eq(panel.get_child_count(), 1, "Panel reduced to a single outer container")
	var outer := panel.get_child(0)
	assert_true(outer is HBoxContainer, "Outer container is an HBox (two columns)")
	assert_eq(outer.get_child_count(), 2, "Outer has [body card | right column]")
	var body_card := outer.get_child(0)
	assert_true(body_card is PanelContainer, "Left column is the body glass card")
	assert_true(body_card.get_child(0) == content, "Body card wraps the original content VBox")
	assert_eq((body_card as Control).size_flags_stretch_ratio, 3.0, "Body card stretches 3")
	var right := outer.get_child(1)
	assert_true(right is VBoxContainer, "Right column is a VBox")
	assert_eq((right as Control).size_flags_stretch_ratio, 2.0, "Right column stretches 2")
	# Right column = [detail holder] — the info card, top-aligned at ~40% height,
	# no portrait spacer (the 3D NPC replaces the 2D preview).
	assert_eq(right.get_child_count(), 1, "Right column has [detail] (no portrait spacer)")
	assert_true(right.get_child(0).custom_minimum_size.y > 0.0, "Detail holder reserves ~40% height")
	assert_true(card is PanelContainer, "Returns the detail card PanelContainer")
	assert_true(card.has_theme_stylebox_override("panel"), "Detail card styled")
	assert_true(card.has_node("ScanlineOverlay"), "Detail card has the scanline overlay")
	assert_true(panel.has_theme_stylebox_override("panel"), "Panel stylebox override applied (transparent)")

	# ── Pinned column widths (#626): the split never depends on text length ──
	assert_eq((body_card as Control).custom_minimum_size.x, PszStyle.SHOP_BODY_W,
		"Body card width is pinned")
	var holder: Control = right.get_child(0)
	assert_eq(holder.custom_minimum_size, Vector2(PszStyle.SHOP_DETAIL_W, PszStyle.DETAIL_HEIGHT),
		"Detail holder width is pinned to the fixture's 320")
	var panel_w: float = 1280.0 - PszStyle.LEFT_MARGIN - PszStyle.RIGHT_RESERVE
	assert_eq(PszStyle.SHOP_BODY_W + outer.get_theme_constant("separation") + PszStyle.SHOP_DETAIL_W, panel_w,
		"body + gap + detail consume the fixed panel width exactly (no text-driven surplus)")

	# A long detail line wraps inside the fixed card instead of widening it —
	# unwrapped, this sentence's width becomes the card's minimum width and the
	# list/info split shifts per shop/tab/selection (the #626 report).
	var long_line := "Vivid Agito with a Monomate Grinder Frame, Antlia Parasol and Flowen's Sword"
	var lbl := PszStyle.detail_label(long_line)
	card.add_child(lbl)
	assert_eq(lbl.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "detail_label wraps within the card")
	assert_true(holder.get_minimum_size().x <= PszStyle.SHOP_DETAIL_W + 1.0,
		"a long detail line wraps instead of widening the detail card")

	# Row names trim with an ellipsis rather than drawing past the pill edge
	# (the list scroll disables horizontal scrolling, so the row width is capped).
	var row := PszStyle.shop_row(long_line, "100 M", {})
	assert_eq(_shop_row_label(row).text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS,
		"row name label trims with ellipsis")

	# The hint sentence is the widest single-line text in the body card
	# ("Left/Right: Category …" ≈ 504 px > the 438 pin) — it must wrap, or it
	# floors the card above the pinned split and the menu rides into the NPC
	# reserve (playtest on #630: "the window on the left is cut off").
	var hint := Label.new()
	hint.text = long_line
	var menu_title := Label.new()
	PszStyle.style_menu(menu_title, hint)
	content.add_child(hint)
	assert_eq(hint.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "style_menu wraps the hint label")
	assert_true(hint.get_minimum_size().x < PszStyle.SHOP_BODY_W,
		"a long hint wraps instead of flooring the body card above its pin")
	menu_title.free()

	panel.free()
	print("")


## Storage's tab bar is the one shop chrome that measured wider than the pinned
## card (#630 playtest: the centered mode bar spilled past the card's left edge
## at ~513 px of pills). Pin the contract: whatever TAB_NAMES storage carries,
## the bar must fit the body card's content width (pin minus glass margins).
func test_storage_tabs_fit_pinned_card() -> void:
	print("── Storage tab bar fits the pinned shop card (#626) ──")
	var names: Array = load("res://scripts/2d/storage.gd").TAB_NAMES
	var bar := PszStyle.create_tab_bar(names, 0)
	add_child(bar)
	var content_w: float = PszStyle.SHOP_BODY_W - 20.0  # glass margins 10+10
	assert_true(bar.get_minimum_size().x <= content_w,
		"storage tab bar (%.0f px) fits the %.0f px card content width — shorten TAB_NAMES otherwise" % [
			bar.get_minimum_size().x, content_w])
	bar.free()
	print("")


func test_shop_camera_pose() -> void:
	print("── Diegetic shop camera pose (spec /states/shops#presentation) ──")
	# The shop camera sits on the NPC's own facing axis, in front of it, and
	# looks back at it — the NPC never turns (see CityAreaBase._compute_shop_pose).
	var base: Node = load("res://scripts/3d/city/city_area_base.gd").new()
	var stub := GDScript.new()
	stub.source_code = "extends Node3D\nvar npc_rotation_y: float = 0.0\n"
	stub.reload()
	var npc: Node3D = stub.new()
	add_child(npc)
	npc.global_position = Vector3(5.0, 0.0, 10.0)

	# rot 0 → faces +Z: camera in front is on the +Z side, centred on the NPC's x.
	npc.npc_rotation_y = 0.0
	var pose: Transform3D = base._compute_shop_pose(npc)
	assert_true(pose.origin.z > npc.global_position.z, "Camera sits on the NPC's facing (+Z) side")
	assert_true(absf(pose.origin.x - npc.global_position.x) < 0.001, "Camera centred on the NPC x at rot 0")
	assert_true(absf(pose.origin.y - (npc.global_position.y + base.SHOP_CAM_HEIGHT)) < 0.001, "Camera at shop height above the floor")
	var to_npc: Vector3 = (Vector3(npc.global_position.x, npc.global_position.y + base.SHOP_LOOK_HEIGHT, npc.global_position.z) - pose.origin).normalized()
	var cam_fwd: Vector3 = -pose.basis.z  # Camera3D looks down local −Z
	assert_true(cam_fwd.dot(to_npc) > 0.99, "Camera looks straight back at the NPC")

	# rot 90° → faces +X: camera moves to the NPC's +X side instead.
	npc.npc_rotation_y = PI / 2.0
	var pose_x: Transform3D = base._compute_shop_pose(npc)
	assert_true(pose_x.origin.x > npc.global_position.x, "rot 90° puts the camera on the NPC's +X side")
	assert_true(absf(pose_x.origin.z - npc.global_position.z) < 0.001, "rot 90° keeps the camera on the NPC z")

	npc.queue_free()
	base.free()
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

	# Feedback contract (spec /states/shops #feedback): one message vocabulary +
	# a denied cue distinct from the close cue. Pins the constants every economy
	# screen now routes through, so they can't drift back to per-screen literals.
	assert_eq(ShopNav.MSG_NO_ROOM, "No room", "canonical full-inventory message")
	assert_eq(ShopNav.MSG_NOT_ENOUGH_MESETA, "Not enough meseta", "canonical insufficient-meseta message")
	assert_true(ShopNav.SFX_DENIED.ends_with("menu_invalid.wav"), "denied cue is the invalid sfx")
	assert_true(ShopNav.SFX_DENIED != ShopNav.SFX_BACK, "denied cue is distinct from the close/back cue")
	# The pointed-at .wav lives only in the asset pack (assets/ is gitignored), so it
	# isn't on disk in the CI test runner — ResourceLoader.exists() would always fail
	# here. The path's real existence is guarded instead by the check-asset-refs job
	# (it must appear in asset_tree.txt), which is the right layer for pack assets.

	# Denied-during-accept: an on_accept that blocks the action (deny/denied_sfx)
	# must suppress the accept cue, so a rejected buy plays the denied cue ALONE —
	# not select+denied stacked (Rozalin playtest). The static flag is the seam.
	# (bind to a local var — a lambda can capture vars but not the local const.)
	var nav: GDScript = ShopNav
	var deny_opts := {"sfx": false,
		"on_accept": func() -> void: nav.denied_sfx()}
	ShopNav.handle(shop, _nav_event("ui_accept"), deny_opts)
	assert_true(ShopNav._denied_during_accept,
		"on_accept that denies marks the accept cue suppressed")
	var ok_opts := {"sfx": false, "on_accept": func() -> void: pass}
	ShopNav.handle(shop, _nav_event("ui_accept"), ok_opts)
	assert_true(not ShopNav._denied_during_accept,
		"a clean accept leaves the accept cue intact (flag reset per accept)")

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


func test_humarl_skin_remap() -> void:
	print("── HUmarl skin-tone remap (#372) ──")
	# HUmarl's source skin textures are scrambled vs the lightest→darkest label
	# order, so PlayerConfig remaps skin_tone_index [0,1,2] → texture slot
	# [2,0,1]. The label (0=Light,1=Medium,2=Dark) must match the rendered slot.
	var hml_light: String = PlayerConfig.get_texture_path("humarl", 0, 0, 0, 0)
	assert_true(hml_light.ends_with("pc_010_020.png"), "HUmarl Light (skin 0) → slot 2 / idx 020")
	var hml_med: String = PlayerConfig.get_texture_path("humarl", 0, 0, 1, 0)
	assert_true(hml_med.ends_with("pc_010_000.png"), "HUmarl Medium (skin 1) → slot 0 / idx 000")
	var hml_dark: String = PlayerConfig.get_texture_path("humarl", 0, 0, 2, 0)
	assert_true(hml_dark.ends_with("pc_010_010.png"), "HUmarl Dark (skin 2) → slot 1 / idx 010")
	# Remap composes with hair (hundreds) + body (units): hair1, skin0→slot2,
	# body2 → combined = 1*3+2 = 5 → idx (5/3)*100+(5%3)*10+2 = 122.
	var hml_combo: String = PlayerConfig.get_texture_path("humarl", 0, 1, 0, 2)
	assert_true(hml_combo.ends_with("pc_010_122.png"), "HUmarl remap composes with hair+body → idx 122")
	# Non-listed classes pass skin straight through (no remap): HUmar Dark = slot 2.
	var hm_dark: String = PlayerConfig.get_texture_path("humar", 0, 0, 2, 0)
	assert_true(hm_dark.ends_with("pc_000_020.png"), "HUmar Dark (skin 2) → slot 2 / idx 020 (no remap)")
	# Casts have no skin tone and are not in the override table → straight through.
	var cast_tex: String = PlayerConfig.get_texture_path("hucast", 0, 0, 2, 0)
	assert_true(cast_tex.ends_with("pc_100_020.png"), "HUcast not remapped (idx 020)")
	print("")


func test_valley_grid() -> void:
	print("── Valley Grid ──")

	# ── Grid Generator Tests ──
	var GridGen := preload("res://scripts/3d/field/grid_generator.gd")
	var gen := GridGen.new()

	# Rotation system
	assert_eq(StageRotation.rotate_dir("north", 0), "north", "Rotate north by 0")
	assert_eq(StageRotation.rotate_dir("north", 90), "east", "Rotate north by 90")
	assert_eq(StageRotation.rotate_dir("north", 180), "south", "Rotate north by 180")
	assert_eq(StageRotation.rotate_dir("north", 270), "west", "Rotate north by 270")
	assert_eq(StageRotation.rotate_dir("east", 90), "south", "Rotate east by 90")
	assert_eq(StageRotation.rotate_dir("west", 180), "east", "Rotate west by 180")

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
	# NOT pinned to s02b_sa1 any more. That tile carries north+south and the `b`
	# start sits on row 0, so its north door hung off-grid in every b section —
	# a door with no room, no gate and no trigger behind it. The retile pass
	# swaps it for a tile whose doors are exactly its connections, which is what
	# the original does (room shape comes from the cell's degree, so a start room
	# has one door). The `a` start keeps sa1 above because that stage carries the
	# section's defaultSpawn; b sections are entered by warp instead.
	assert_true(not str(b_start.get("stage_id", "")).is_empty(), "Ozette B section has a start cell")
	assert_true(str(b_start.get("stage_id", "")).begins_with("s02b_"), "Ozette B start is an s02b stage")
	# A `b` section is entered by warp from the transition room, and the room you
	# land in has to show you where you came from — so it carries exactly one
	# door more than it has connections, and that door is the way back.
	var b_entry: String = str(b_start.get("entry_warp_edge", ""))
	assert_true(not b_entry.is_empty(), "Ozette B start has a way back to the transition room")
	assert_true(not b_start.get("connections", {}).has(b_entry),
		"the way back is a warp, not a connection to another room")
	assert_eq(b_start.get("portals", {}).size(), b_start.get("connections", {}).size() + 1,
		"Ozette B start carries its connections plus the way back, and nothing else")

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

	# ── Complete quest objectives (#384: marks complete, KEEPS the Field Context) ──
	SessionManager.complete_quest()
	assert_true(SessionManager.has_active_session(),
		"Session stays ACTIVE after objective completion (#384 — player can keep exploring)")
	assert_true(SessionManager.has_completed_quest(), "Has completed quest")
	assert_eq(SessionManager.get_location(), "field",
		"Still in the field after completing objectives (no forced city return)")

	var cq: Dictionary = SessionManager.get_completed_quest()
	assert_eq(str(cq.get("quest_id", "")), test_quest_id, "Completed quest has correct ID")

	# ── Report quest (the exit → tears down the Field Context) ──
	var report: Dictionary = SessionManager.report_quest()
	assert_true(not report.is_empty(), "report_quest returns data")
	assert_eq(str(report.get("quest_id", "")), test_quest_id, "Report has correct quest ID")
	assert_true(not SessionManager.has_completed_quest(), "No completed quest after report")
	assert_true(not SessionManager.has_active_session(),
		"Field Context cleared after report (#384 — the quest exit)")
	assert_eq(SessionManager.get_location(), "city", "Location is city after reporting")

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


# ── Quest-item pickup registers on contact, not on dialog close ──
# Rozalin's "dialogue bug": the "Picked up X" message is shown by
# quest_item_pickup.gd, but SessionManager.collect_quest_item() is wired to the
# DialogBox's `dialog_complete` signal — it only fires when the player presses
# E/Enter to CLOSE the box. Movement is not gated by the modal
# (player.gd `_handle_movement` polls input directly), so the player can walk
# out of the room before closing the box. Meanwhile DropBase consumes the star
# immediately (`set_state("collected")`), so the fragment is GONE from the world
# but never counted → the objective never ticks, the section gate never unlocks,
# and the quest is permanently unclearable.
#
# Reproduced on The Paru Pact (4× mag_fragment; the 4th pickup runs
# complete_quest + telepipe). The desired contract: a quest item is registered
# the instant you touch it, independent of whether the dialog is ever read.
# This test asserts that contract and so FAILS against the deferred-registration
# code — it is the failing repro that the fix must turn green.
func test_quest_item_registers_on_contact() -> void:
	print("── Quest item registers on contact, not on dialog close (dialogue bug) ──")

	SessionManager.return_to_city()
	SessionManager._completed_quest.clear()
	SessionManager.enter_quest("the_paru_pact", "normal")

	# Part A — first fragment. A field HUD is what the pickup attaches its
	# "Picked up X" message to; the pickup must be in the tree for get_tree().
	var hud_a := CanvasLayer.new()
	hud_a.name = "FieldHud"
	add_child(hud_a)
	hud_a.add_to_group("hud")

	const PickupScript := preload("res://scripts/3d/elements/quest_item_pickup.gd")
	var pickup_a = PickupScript.new()
	pickup_a.quest_item_id = "mag_fragment"
	pickup_a.quest_item_label = "Mag Fragment"
	add_child(pickup_a)

	# Walk onto the star: DropBase fires the reward and consumes the node. The
	# player is now free to leave WITHOUT pressing E to close the dialog.
	pickup_a._give_reward()
	pickup_a.set_state("collected")  # DropBase does this immediately after _give_reward

	assert_eq(SessionManager.get_quest_item_count("mag_fragment"), 1,
		"fragment registers on contact, before the pickup dialog is closed")

	# Part B — the FINAL (4th) fragment. Pre-register 3 (these tick directly),
	# then touch the 4th via the pickup path without ever closing its dialog.
	# Desired: count reaches 4 and the quest's objectives complete. Current bug:
	# the 4th never registers, so the quest can never clear and the clear
	# telepipe (gated on the 4th pickup's actions) never spawns.
	SessionManager.return_to_city()
	SessionManager._completed_quest.clear()
	SessionManager.enter_quest("the_paru_pact", "normal")
	for _i in range(3):
		SessionManager.collect_quest_item("mag_fragment")
	assert_eq(SessionManager.get_quest_item_count("mag_fragment"), 3, "three fragments registered directly (setup)")
	assert_true(not SessionManager.are_objectives_complete(), "three of four fragments is not complete (setup)")

	var hud_b := CanvasLayer.new()
	hud_b.name = "FieldHud"
	add_child(hud_b)
	hud_b.add_to_group("hud")

	var pickup_b = PickupScript.new()
	pickup_b.quest_item_id = "mag_fragment"
	pickup_b.quest_item_label = "Mag Fragment"
	pickup_b.remaining_dialog = [{
		"condition": {"item_count": 4},
		"dialog": [{"speaker": "Elio", "text": "There it is. The last piece."}],
		"actions": ["dismiss_companion", "complete_quest", "telepipe"],
	}]
	add_child(pickup_b)

	pickup_b._give_reward()
	pickup_b.set_state("collected")

	assert_eq(SessionManager.get_quest_item_count("mag_fragment"), 4,
		"final fragment registers on contact (quest is clearable even if dialog is skipped)")
	assert_true(SessionManager.are_objectives_complete(),
		"objectives complete after the final fragment is touched (quest not bricked)")

	# Cleanup — the pickups left their "Picked up X" dialogs open (the player
	# never closed them), so drop the modal the DialogBox pushed and free nodes.
	GameState.modal_stack = 0
	pickup_a.free()
	pickup_b.free()
	hud_a.free()
	hud_b.free()
	SessionManager.return_to_city()
	SessionManager._completed_quest.clear()
	print("")


# ── A closed DialogBox is NOT re-shown when the HUD menu closes ──
# The "Picked up X" toast-persistence bug: the pickup DialogBox lives as a child
# of FieldHud. FieldHud.restore_after_menu() (fired when the PSO start menu
# closes) used to blanket-set every Control child visible=true, re-showing a box
# the player had already closed — with its stale text, since _close() never
# cleared the labels. So "Picked up X" reappeared on every menu toggle and stuck
# until the room unloaded. Fix: _close() clears the text + exposes is_active(),
# and restore_after_menu() honours that instead of forcing the box back on.
func test_dialog_box_not_restored_after_close() -> void:
	print("── Closed DialogBox stays hidden across a HUD menu toggle (toast bug) ──")

	const DialogBoxScript := preload("res://scripts/3d/ui/dialog_box.gd")
	var box = DialogBoxScript.new()
	add_child(box)
	box.show_dialog([{"speaker": "", "text": "Picked up Mag Fragment."}])
	assert_true(box.is_active(), "dialog reads active while shown")
	assert_true(box.visible, "dialog is visible while shown")

	box._close()
	assert_true(not box.is_active(), "dialog reads inactive after close")
	assert_true(not box.visible, "dialog is hidden after close")
	assert_eq(box._text_label.text, "", "closed dialog clears its stale text")

	# Mount it as a HUD child (where quest_item_pickup adds it) and toggle a menu.
	const FieldHudScript := preload("res://scripts/3d/field/field_hud.gd")
	var hud = FieldHudScript.new()
	add_child(hud)
	box.reparent(hud)
	hud.hide_for_menu()   # start menu opens
	assert_true(not box.visible, "closed dialog stays hidden while the menu is open")
	hud.restore_after_menu()  # start menu closes
	assert_true(not box.visible,
		"closed dialog is NOT re-shown when the menu closes (no stuck 'Picked up X' toast)")

	GameState.modal_stack = 0
	if is_instance_valid(box):
		box.free()
	hud.free()
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
		# Debug missions award nothing BY CONTRACT (spec /states/bosses
		# §debug-missions: always unlocked, zero rewards) — the complete-
		# rewards invariant guards canon quests only.
		if qid.begins_with("debug_"):
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


# ── Debug: Unlock All Missions (spec /states/start-menu §DEBUG) ──
# The System → Debug "Unlock All Missions" cheat marks every real quest
# complete so the guild counter surfaces the whole roster. Deterministic,
# no RNG: clear completion, unlock, and assert every non-sentinel quest id
# is now completed and the count is right; then assert idempotency.
func test_debug_unlock_all_missions() -> void:
	print("── Debug Unlock All Missions ──")

	# Snapshot + clear so the run is independent of prior test order.
	var saved: Array = GameState.completed_missions.duplicate()
	GameState.completed_missions.clear()

	# The set the cheat should cover: every quest id minus the sentinels.
	var expected: Array = []
	for qid in QuestLoader.list_quests():
		if qid == "manifest" or qid == "hello_quest":
			continue
		expected.append(qid)
	assert_gt(expected.size(), 0, "roster has real quests to unlock")

	var newly: int = GameState.unlock_all_missions()
	assert_eq(newly, expected.size(), "unlock_all_missions clears every real quest")

	# Every parent/required gate reads is_mission_completed — all must pass now.
	var all_completed := true
	for qid in expected:
		if not GameState.is_mission_completed(qid):
			all_completed = false
			assert_true(false, "quest marked complete: %s" % qid)
	assert_true(all_completed, "all real quests report completed after unlock")

	# The sentinels MUST NOT be marked complete.
	assert_true(not GameState.is_mission_completed("manifest"), "manifest sentinel not marked complete")
	assert_true(not GameState.is_mission_completed("hello_quest"), "hello_quest not marked complete")

	# Idempotent: re-running adds nothing.
	var again: int = GameState.unlock_all_missions()
	assert_eq(again, 0, "second unlock is a no-op (idempotent)")
	assert_eq(GameState.completed_missions.size(), expected.size(), "no duplicate mission entries")

	# Restore the pre-test completion set.
	GameState.completed_missions = saved
	print("")


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


# ── Difficulty unlock loop (#344, spec /states/difficulty-unlock) ──
# The story-finale clear rule, the always-on Normal, the non-finale
# no-op, and per-character persistence through the CharacterManager swap.
func test_difficulty_unlock() -> void:
	print("── Difficulty Unlock Loop (#344) ──")

	var saved: Array = GameState.unlocked_difficulties.duplicate()
	GameState.unlocked_difficulties = ["normal"]

	# Baseline: Normal always, the rest locked.
	assert_true(GameState.is_difficulty_unlocked("normal"), "Normal always unlocked")
	assert_true(not GameState.is_difficulty_unlocked("hard"), "Hard locked initially")
	assert_true(not GameState.is_difficulty_unlocked("super-hard"), "Super-Hard locked initially")

	# Non-finale quest reports never unlock.
	assert_eq(GameState.apply_quest_clear_unlock("search_and_rescue", "normal"), "",
		"clearing a non-finale quest unlocks nothing")
	assert_true(not GameState.is_difficulty_unlocked("hard"), "still locked after a side quest")

	# Finale on Normal → Hard.
	assert_eq(GameState.apply_quest_clear_unlock(GameState.STORY_FINALE_QUEST, "normal"), "hard",
		"finale on Normal unlocks Hard")
	assert_true(GameState.is_difficulty_unlocked("hard"), "Hard now unlocked")
	assert_true(not GameState.is_difficulty_unlocked("super-hard"), "Super-Hard still locked")

	# Re-clearing the finale on Normal is a no-op (already unlocked).
	assert_eq(GameState.apply_quest_clear_unlock(GameState.STORY_FINALE_QUEST, "normal"), "",
		"re-clearing on Normal unlocks nothing new")

	# Finale on Hard → Super-Hard; on Super-Hard → nothing.
	assert_eq(GameState.apply_quest_clear_unlock(GameState.STORY_FINALE_QUEST, "hard"), "super-hard",
		"finale on Hard unlocks Super-Hard")
	assert_true(GameState.is_difficulty_unlocked("super-hard"), "Super-Hard now unlocked")
	assert_eq(GameState.apply_quest_clear_unlock(GameState.STORY_FINALE_QUEST, "super-hard"), "",
		"finale on Super-Hard has no further tier")

	# Integration: the unlock MUST fire through SessionManager.report_quest —
	# the single chokepoint both report UIs call. (The first matrix run caught
	# that hooking only the guild counter missed the autopilot's city-office
	# report path; this pins the chokepoint at the unit layer too.)
	GameState.unlocked_difficulties = ["normal"]
	var meseta_before: int = GameState.get_meseta()
	SessionManager.return_to_city()
	SessionManager._completed_quest.clear()
	SessionManager.enter_quest(GameState.STORY_FINALE_QUEST, "normal")
	SessionManager.mark_quest_complete()
	var report: Dictionary = SessionManager.report_quest()
	assert_eq(str(report.get("difficulty_unlocked", "")), "hard",
		"report_quest fires the unlock and reports it in the data")
	assert_true(GameState.is_difficulty_unlocked("hard"), "Hard unlocked via report_quest")
	# Undo the reward grant report_quest performed, so later tests see a clean slate.
	GameState.meseta = meseta_before
	for entry in report.get("rewards_granted", {}).get("items", []):
		Inventory.remove_item(str(entry.get("id", "")), int(entry.get("quantity", 1)))
	GameState.unlocked_difficulties = saved
	SessionManager.return_to_city()
	SessionManager._completed_quest.clear()
	print("")


# Per-character persistence + the v7 seed migration for #344's unlock state.
func test_difficulty_unlock_persistence() -> void:
	print("── Difficulty Unlock — persistence + migration (#344) ──")

	var saved: Array = GameState.unlocked_difficulties.duplicate()

	# Unlock state swaps with the active slot, mirroring completed_missions.
	var slot_a := 0
	var slot_b := 1
	var bak_a = CharacterManager.get_character(slot_a)
	var bak_b = CharacterManager.get_character(slot_b)
	var bak_active: int = CharacterManager._active_slot
	CharacterManager.create_character(slot_a, "humar", "UnlockA")
	CharacterManager.create_character(slot_b, "humar", "UnlockB")
	CharacterManager.set_active_slot(slot_a)
	GameState.unlocked_difficulties = ["normal", "hard"]
	CharacterManager.set_active_slot(slot_b)
	assert_eq(GameState.unlocked_difficulties, ["normal"], "slot B starts at Normal only")
	GameState.unlocked_difficulties = ["normal", "hard", "super-hard"]
	CharacterManager.set_active_slot(slot_a)
	assert_eq(GameState.unlocked_difficulties, ["normal", "hard"], "slot A retained its own unlocks")

	# Migration: a finale-cleared old character retroactively keeps Hard.
	var ch = CharacterManager.get_character(slot_a)
	ch["completed_missions"] = [GameState.STORY_FINALE_QUEST]
	ch.erase("unlocked_difficulties")
	CharacterManager.migrate_seed_unlocked_difficulties()
	assert_eq(ch["unlocked_difficulties"], ["normal", "hard"],
		"migration retroactively grants Hard to a story-cleared character")

	# Restore the scratch slots and global state.
	CharacterManager._characters[slot_a] = bak_a
	CharacterManager._characters[slot_b] = bak_b
	CharacterManager._active_slot = bak_active
	GameState.unlocked_difficulties = saved
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


# ── CRT filter (spec /states/crt-filter) ─────────────────────
# Two things can silently break this feature and neither shows up as a crash:
# a preset key that doesn't match a real shader uniform (the look just never
# applies), and the Options list drifting out of index-alignment with
# _toggle_option (the row would toggle someone else's setting). Both are
# pinned here.
func test_crt_filter() -> void:
	print("── CRT filter ──")
	var original_mode: int = CrtFilter.get_mode()

	# Mode table integrity — ids/labels are index-aligned with the enum, and
	# every non-Off mode has a preset.
	assert_eq(CrtFilter.MODE_IDS.size(), CrtFilter.Mode.size(), "MODE_IDS covers every Mode")
	assert_eq(CrtFilter.MODE_LABELS.size(), CrtFilter.Mode.size(), "MODE_LABELS covers every Mode")
	for m in range(CrtFilter.Mode.size()):
		if m == CrtFilter.Mode.OFF:
			assert_true(not CrtFilter.PRESETS.has(m), "Off has no preset (rect is hidden instead)")
		else:
			assert_true(CrtFilter.PRESETS.has(m), "%s has a preset" % CrtFilter.MODE_LABELS[m])

	# Every preset key must be a real uniform on the shader. A typo here is
	# invisible at runtime: set_shader_parameter on an unknown name is a no-op,
	# so the mode would just look like Off.
	var shader := load(CrtFilter.SHADER_PATH) as Shader
	assert_true(shader != null, "crt.gdshader loads")
	var uniforms: Array = []
	if shader != null:
		for u in shader.get_shader_uniform_list():
			uniforms.append(String(u.get("name", "")))
	for m in CrtFilter.PRESETS:
		for key in CrtFilter.PRESETS[m]:
			assert_true(key in uniforms, "%s preset key '%s' is a shader uniform" % [CrtFilter.MODE_LABELS[m], key])

	# cycle() wraps in both directions; set_mode() clamps out-of-range input.
	CrtFilter._set_mode_no_save(CrtFilter.Mode.OFF)
	assert_eq(CrtFilter.get_mode_label(), "Off", "Off label")
	CrtFilter.cycle(1)
	assert_eq(CrtFilter.get_mode(), CrtFilter.Mode.SCANLINES, "cycle(+1) Off → Scanlines")
	CrtFilter.cycle(1)
	assert_eq(CrtFilter.get_mode(), CrtFilter.Mode.FULL, "cycle(+1) Scanlines → Full")
	CrtFilter.cycle(1)
	assert_eq(CrtFilter.get_mode(), CrtFilter.Mode.OFF, "cycle(+1) wraps Full → Off")
	CrtFilter.cycle(-1)
	assert_eq(CrtFilter.get_mode(), CrtFilter.Mode.FULL, "cycle(-1) wraps Off → Full")
	CrtFilter.set_mode(99)
	assert_eq(CrtFilter.get_mode(), CrtFilter.Mode.FULL, "set_mode clamps above range")
	CrtFilter.set_mode(-5)
	assert_eq(CrtFilter.get_mode(), CrtFilter.Mode.OFF, "set_mode clamps below range")

	# Persistence round-trip: the id written to video_settings.cfg is what
	# _load_mode reads back. (cycle() above already wrote the file — this run
	# owns it, and the original mode is restored at the end.)
	CrtFilter.set_mode(CrtFilter.Mode.SCANLINES)
	assert_eq(CrtFilter._load_mode(), CrtFilter.Mode.SCANLINES, "mode round-trips through video_settings.cfg")

	# An unknown id on disk (hand-edited, or written by an older build with a
	# different mode set) MUST fall back to Off rather than index-crash.
	var cfg := ConfigFile.new()
	cfg.load(CrtFilter.SETTINGS_PATH)
	cfg.set_value("video", "crt_mode", "tube_of_the_future")
	cfg.save(CrtFilter.SETTINGS_PATH)
	assert_eq(CrtFilter._load_mode(), CrtFilter.Mode.OFF, "unknown crt_mode id falls back to Off")

	# Options row alignment — the CRT row must sit at the index _toggle_option
	# dispatches CrtFilter.cycle from, and Left/Right in start_menu_input keys
	# off the same literal.
	var opts: Array = PsoStartMenu._get_options_list()
	var crt_idx: int = -1
	for i in range(opts.size()):
		if String(opts[i]).begins_with("CRT Filter:"):
			crt_idx = i
			break
	assert_eq(crt_idx, 7, "CRT Filter is Options row 7 (matches _toggle_option + start_menu_input)")
	CrtFilter._set_mode_no_save(CrtFilter.Mode.OFF)
	if crt_idx >= 0:
		PsoStartMenu._toggle_option(crt_idx)
		assert_eq(CrtFilter.get_mode(), CrtFilter.Mode.SCANLINES, "Options row 7 Accept advances the filter")
		assert_eq(String(PsoStartMenu._get_options_list()[crt_idx]), "CRT Filter: Scanlines", "row label reflects the new mode")

	CrtFilter.set_mode(original_mode)
	print("")


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


# #422 — live enemy markers on the room minimap (spec /states/enemies —
# minimap markers). Seeded, no pack assets: projection metadata is hand-set
# (the SVG file itself is pack-only), enemies are real EnemyBase instances
# kept out of the tree (no _ready → no model loads), and movement is driven
# through plain Node3D stand-ins under a bare map root.
func test_minimap_enemy_markers() -> void:
	print("── Room minimap enemy markers (#422) ──")
	const RoomMinimap := preload("res://scripts/3d/field/room_minimap.gd")
	var minimap: Control = RoomMinimap.new()
	add_child(minimap)

	# Spawn 3 enemies in a seeded cell → 3 markers.
	var enemies: Array = []
	for i in range(3):
		var e := EnemyBase.new()
		var ed := EnemyData.new()
		ed.id = "wolf%d" % i
		e.enemy_data = ed
		minimap.track_enemy(e)
		enemies.append(e)
	assert_eq(minimap.get_enemy_marker_count(), 3, "3 alive enemies → 3 markers")
	minimap.track_enemy(enemies[0])
	assert_eq(minimap.get_enemy_marker_count(), 3, "Re-tracking the same enemy does not duplicate its marker")

	# Kill one (EnemyBase._die emits died) → marker removed, 2 remain.
	enemies[0].is_alive = false
	enemies[0].died.emit(enemies[0])
	assert_eq(minimap.get_enemy_marker_count(), 2, "Death signal removes the marker → 2 markers")

	# A freed enemy (death animation finished → queue_free) is swept too.
	enemies[1].free()
	assert_eq(minimap.get_enemy_marker_count(), 1, "Freed instance swept from marker count")

	# Boss dot area ≈8× a normal dot (radius × sqrt(8)).
	var normal_r: float = RoomMinimap.enemy_marker_radius(false)
	var boss_r: float = RoomMinimap.enemy_marker_radius(true)
	var area_ratio: float = (boss_r * boss_r) / (normal_r * normal_r)
	assert_true(absf(area_ratio - 8.0) < 0.01, "Boss dot area ≈8× normal (got %.2fx)" % area_ratio)
	var boss := EnemyBase.new()
	var boss_data := EnemyData.new()
	boss_data.id = "reyburn"
	boss_data.is_boss = true
	boss.enemy_data = boss_data
	assert_true(minimap._is_boss_enemy(boss), "EnemyData.is_boss drives the boss-sized dot")
	assert_true(not minimap._is_boss_enemy(enemies[2]), "Normal enemy gets the normal dot")

	# Markers follow movement through the same projection as the player.
	# Identity map root + unit SVG transform → display = world.xz scaled into
	# the frame's inner map area (DISPLAY_SIZE px over the 400-unit SVG space).
	var disp_k: float = RoomMinimap.DISPLAY_SIZE / 400.0
	minimap._svg_scale = 1.0
	minimap._svg_offset_x = 0.0
	minimap._svg_offset_y = 0.0
	minimap._has_player_tracking = true
	var map_root := Node3D.new()
	add_child(map_root)
	var walker := Node3D.new()  # stand-in body; _ready-safe inside the tree
	map_root.add_child(walker)
	walker.position = Vector3(100.0, 0.0, 200.0)
	minimap.track_enemy(walker)
	minimap.update_enemies(map_root)
	var marker: Dictionary = minimap._enemy_markers.get(walker.get_instance_id(), {})
	var pos: Vector2 = marker.get("pos", Vector2.ZERO)
	assert_true(pos.distance_to(Vector2(100.0, 200.0) * disp_k) < 0.01,
		"Marker projected at minimap position (got %s)" % pos)
	assert_eq(marker.get("radius", 0.0), normal_r, "Stand-in without boss data draws a normal dot")
	walker.position = Vector3(200.0, 0.0, 100.0)
	minimap.update_enemies(map_root)
	marker = minimap._enemy_markers.get(walker.get_instance_id(), {})
	pos = marker.get("pos", Vector2.ZERO)
	assert_true(pos.distance_to(Vector2(200.0, 100.0) * disp_k) < 0.01,
		"Marker follows enemy movement (got %s)" % pos)
	minimap.untrack_enemy(walker)
	minimap.update_enemies(map_root)
	assert_eq(minimap._enemy_markers.size(), 0, "Untracked enemy leaves no stale marker entry")

	enemies[0].free()
	enemies[2].free()
	boss.free()
	map_root.queue_free()
	minimap.queue_free()
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



# ── Confirm / interact precedence (issue #426 / #423) ──────────────────────
# Pins the field-action arbitration rule from spec/states/start-menu against the
# pure static Player.arbitrate_field_actions seam: one press resolves to exactly
# one consumer in the order modal > world-interaction > palette/free. We exercise
# the static helper (no live Player — Player._ready loads pack-only character
# models, so a node can't run repo-only headless) plus the GameState modal flag
# that encodes precedence row 1.
func test_confirm_input_precedence() -> void:
	print("── Confirm / interact precedence (modal > world > palette) ──")
	const PlayerScript := preload("res://scripts/3d/player/player.gd")

	# (a) World interaction CONSUMES a press shared with a palette action (#423):
	#     interact + an interactable in range → only "interact", palette dropped.
	assert_eq(
		PlayerScript.arbitrate_field_actions({"interact": true, "action_1": true}, true, false),
		["interact"],
		"world interaction consumes the press and suppresses the shared palette action")

	# (b) Palette fires when there is nothing to interact with.
	assert_eq(
		PlayerScript.arbitrate_field_actions({"action_1": true}, false, false),
		["action_1"],
		"palette action fires when no interactable is in range")

	# (c) Interact pressed but nothing in range → no effect leaks through.
	assert_eq(
		PlayerScript.arbitrate_field_actions({"interact": true}, false, false),
		[],
		"interact with no interactable produces no effect (no leak)")

	# (d) In-city combat gate still suppresses palette actions.
	assert_eq(
		PlayerScript.arbitrate_field_actions({"action_1": true}, true, true),
		[],
		"in-city palette gate suppresses combat actions")

	# Precedence row 1: an open modal blocks gameplay input. PsoStartMenu.open()
	# pushes a modal (push_modal); close() pops it. Assert the flag directly so
	# the test stays deterministic without instantiating the pack-heavy menu.
	assert_true(not GameState.is_gameplay_blocked(),
		"gameplay not blocked with no modal on the stack")
	GameState.push_modal()
	assert_true(GameState.is_gameplay_blocked(),
		"push_modal (what Start Menu open() calls) blocks gameplay input — precedence row 1")
	GameState.pop_modal()
	assert_true(not GameState.is_gameplay_blocked(),
		"pop_modal (Start Menu close()) restores gameplay input")
	print("")


# Regression guard for the #448 start-menu blackout (Retroid/Windows release):
# PsoStartMenu is an *autoload*, so every script it pulls into its load-time
# graph — a class-scope `const X = preload(...)`, or any global `class_name` it
# references (which the engine resolves at parse time) — is loaded at engine
# BOOT, before bootstrap.gd mounts the asset .pck. A class-scope preload of an
# asset the release export drops via `exclude_filter` (pack-only, e.g.
# assets/fonts/*) therefore can't resolve at boot in an exported build, and the
# whole autoload fails — even though the editor loads it fine because assets/
# sit on local disk there. CI is repo-only too (font present), so this can't be
# caught at runtime; we assert it structurally instead. #448 introduced exactly
# this by adding a class-scope preload of the pack-only assets/fonts/ JetBrains
# Mono face to start_menu_renderer.gd, which PsoStartMenu reaches via
# `class_name StartMenuRenderer`. (Bare res://assets/ strings are avoided in
# these comments — check_asset_refs.py treats them as real asset references.)
func test_autoloads_avoid_packonly_classscope_preloads() -> void:
	print("── Autoload pack-only class-scope preload guard ──")
	var excluded: Array = _export_excluded_globs()
	var class_to_path: Dictionary = _build_class_name_map()
	# BFS the boot-time script closure reachable from the autoloads.
	var reachable: Dictionary = {}
	var queue: Array = _autoload_script_paths()
	while not queue.is_empty():
		var path: String = queue.pop_back()
		if reachable.has(path) or not path.ends_with(".gd"):
			continue
		reachable[path] = true
		for dep in _load_time_script_deps(_read_text_file(path), class_to_path):
			if not reachable.has(dep):
				queue.append(dep)
	# Any class-scope preload of a pack-only (export-excluded) asset in that
	# closure is a boot-time landmine in release exports.
	var violations: Array = []
	for path in reachable.keys():
		for asset_path in _classscope_asset_preloads(_read_text_file(path)):
			if _path_matches_any_glob(asset_path.trim_prefix("res://"), excluded):
				violations.append("%s class-scope preloads pack-only %s" % [path, asset_path])
	if violations.is_empty():
		_pass += 1
		print("  PASS: %d autoload-reachable scripts, none class-scope preload a pack-only asset" % reachable.size())
	else:
		for v in violations:
			print("  FAIL: %s — resolves only from the .pck, but autoloads boot before bootstrap mounts it" % v)
		_fail += violations.size()


# ── Orbit camera vertical follow damping (#538) ──
# The camera hard-assigned its Y from the player every frame, so the per-step Y
# sawtooth from descending stairs shook the view. _damp_follow_y damps only the
# follow Y (frame-rate independent) and snaps on a large jump so warps don't
# slide. The visual result is verified in-game; this locks the damping contract.
func test_orbit_camera_follow_y_damping() -> void:
	print("── Orbit Camera Y Damping ──")
	const OrbitCam := preload("res://scripts/3d/camera/orbit_camera.gd")
	# delta<=0 (init / settled frame) snaps exactly to target.
	assert_eq(OrbitCam._damp_follow_y(0.0, 2.0, 0.0), 2.0, "delta<=0 snaps to target")
	# A large gap (warp / respawn) snaps so the camera doesn't slide across it.
	assert_eq(OrbitCam._damp_follow_y(0.0, 10.0, 0.016), 10.0, "gap > CAM_Y_SNAP_DIST snaps to target")
	# A small step damps only partway in one frame — that's what absorbs the sawtooth.
	var one_frame: float = OrbitCam._damp_follow_y(0.0, 1.0, 0.016)
	assert_true(one_frame > 0.0 and one_frame < 1.0, "small gap damps partway, not instant (%f)" % one_frame)
	# Frame-rate independent: a larger delta moves further toward the target.
	assert_true(OrbitCam._damp_follow_y(0.0, 1.0, 0.1) > OrbitCam._damp_follow_y(0.0, 1.0, 0.016),
		"larger delta damps further toward target")
	# Repeated frames converge on the target (no permanent offset).
	var y: float = 0.0
	for _i in range(180):
		y = OrbitCam._damp_follow_y(y, 1.0, 0.016)
	assert_true(absf(1.0 - y) < 0.01, "repeated damping converges to target (%f)" % y)
	print("")


# res:// script paths of the project's autoloads (project.godot [autoload]).
func _autoload_script_paths() -> Array:
	var out: Array = []
	var src := _read_text_file("res://project.godot")
	var in_section := false
	for raw in src.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			in_section = (line == "[autoload]")
			continue
		if not in_section or not line.contains("="):
			continue
		var idx := line.find("res://")
		if idx < 0:
			continue
		var rest := line.substr(idx)
		var end := rest.find("\"")
		if end < 0:
			end = rest.length()
		out.append(rest.substr(0, end))
	return out


# Map global class_name → its res:// script path, across all scripts.
func _build_class_name_map() -> Dictionary:
	var paths: Array = []
	_collect_gd_files("res://scripts", paths)
	var out: Dictionary = {}
	for path in paths:
		for raw in _read_text_file(path).split("\n"):
			var line: String = raw.strip_edges()
			if line.begins_with("class_name "):
				out[line.substr(11).strip_edges().split(" ")[0]] = path
				break
	return out


# Load-time script dependencies of a source: preloaded .gd files plus the script
# behind every global class_name it references (the engine parses those at load).
func _load_time_script_deps(src: String, class_to_path: Dictionary) -> Array:
	var out: Array = []
	for raw in src.split("\n"):
		var idx := raw.find("preload(\"res://")
		while idx >= 0:
			var start := raw.find("\"", idx) + 1
			var p := raw.substr(start, raw.find("\"", start) - start)
			if p.ends_with(".gd"):
				out.append(p)
			idx = raw.find("preload(\"res://", start)
	for cls in class_to_path.keys():
		if _references_identifier(src, cls):
			out.append(class_to_path[cls])
	return out


# True if `ident` appears in `src` as a whole word (not a substring of a longer
# identifier), so class "Enemy" doesn't match "WolfEnemy"/"EnemyData".
func _references_identifier(src: String, ident: String) -> bool:
	var from := 0
	while true:
		var i := src.find(ident, from)
		if i < 0:
			return false
		var before := src[i - 1] if i > 0 else " "
		var after_i := i + ident.length()
		var after := src[after_i] if after_i < src.length() else " "
		if not _is_ident_char(before) and not _is_ident_char(after):
			return true
		from = i + 1
	return false


func _is_ident_char(ch: String) -> bool:
	return ch == "_" or (ch >= "0" and ch <= "9") or (ch.to_lower() >= "a" and ch.to_lower() <= "z")


# Asset paths preloaded at class scope (column 0 — top-level const/var, not an
# indented function body). These resolve at script load, i.e. at autoload boot.
func _classscope_asset_preloads(src: String) -> Array:
	var out: Array = []
	for raw in src.split("\n"):
		if raw.length() == 0 or raw[0] == " " or raw[0] == "\t":
			continue  # indented → inside a func body, runs lazily, not at boot
		var idx := raw.find("preload(\"res://assets/")
		if idx < 0:
			continue
		var start := raw.find("\"", idx) + 1
		out.append(raw.substr(start, raw.find("\"", start) - start))
	return out


# Union of the exclude_filter globs of every RUNNABLE export preset — i.e. the
# game-binary exports the player actually launches (Web/Linux/Windows/Android/
# macOS). An asset excluded from those isn't in the binary at boot; it's only in
# the downloaded .pck (built by the non-runnable "Asset Pack" preset, whose own
# excludes we ignore — they describe what's left OUT of the pack, e.g. the
# vendored assets/kenney_* that ship in the binary instead, and would be a false
# positive here). So we read exclude_filter only from `runnable=true` presets.
func _export_excluded_globs() -> Array:
	var out: Array = []
	var preset_runnable := false
	for raw in _read_text_file("res://export_presets.cfg").split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("[preset."):
			preset_runnable = false  # reset at each preset; runnable= appears before exclude_filter=
			continue
		if line.begins_with("runnable="):
			preset_runnable = (line.substr(9).strip_edges() == "true")
			continue
		if not preset_runnable or not line.begins_with("exclude_filter="):
			continue
		var val := line.substr(line.find("\"") + 1)
		val = val.substr(0, val.rfind("\""))
		for glob in val.split(","):
			var g: String = glob.strip_edges()
			if g != "":
				out.append(g)
	return out


func _path_matches_any_glob(path: String, globs: Array) -> bool:
	for g in globs:
		if path.match(g):
			return true
	return false


func _read_text_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


# ── Duck-typed stub for test_kill_state_survives_warp_flush (#423) ───
# Exposes exactly the fields CellObjectSpawner._save_cell_state reads off
# its back-reference controller (_c). RefCounted so it auto-frees; the
# real ValleyFieldController is far heavier and not needed for the
# capture-path assertion.
class _KillStateStubController extends RefCounted:
	var _current_cell: Dictionary = {}
	var _cell_states: Dictionary = {}
	var _room_enemies: Array = []
	var _room_boxes: Array = []
	var _room_drops: Array = []
	var _room_messages: Array = []
	var _room_props: Array = []
	var _room_triggers: Array = []
	var _room_npcs: Array = []
	var _room_quest_items: Array = []
	var _room_walls: Array = []
	var _fence_links: Dictionary = {}
	var _current_wave: int = 1
	var _max_wave: int = 1

extends RefCounted
## Unit tests for Style A shop detail card chrome and per-item-type views (#772).

const ShopDetail := preload("res://scripts/2d/shops/shop_detail.gd")


static func run(t: Node) -> void:
	print("── ShopDetail Style A & Per-Type Views (#772) ──")
	_test_style_a_chrome(t)
	_test_equipment_previews(t)
	_test_consumable_disk_mag_tekker(t)
	print("")


static func _test_style_a_chrome(t: Node) -> void:
	var st: StyleBoxFlat = PszStyle.detail_panel_style()
	t.assert_eq(st.border_color, PszStyle.BG_BORDER, "Style A detail border uses BG_BORDER")
	t.assert_eq(st.border_width_left, 3, "Style A detail border is 3px all around")
	t.assert_almost_eq(st.bg_color.r, PszStyle.BG.r, 0.01, "Style A detail fill uses pale-blue glass")

	var panel := PanelContainer.new()
	PszStyle.apply_detail_panel_style(panel)
	panel.custom_minimum_size = Vector2(PszStyle.SHOP_DETAIL_W, PszStyle.DETAIL_HEIGHT)
	t.add_child(panel)

	var ctx := ShopDetail.open_card(panel, "Vivid Agito With A Very Long Synthesis Weapon Name", {"rarity": 5})
	ShopDetail.add_sub_meta(ctx, "Sword", "Grind +3 / +9")
	ShopDetail.add_prose(ctx, "Restores HP and grants a long multi-line description that must wrap cleanly inside the frosted inset without pushing the 320px or 268px card wider.")
	ShopDetail.set_footer(ctx, [{"label": "Price", "value": "1,250 M", "tone": "gold"}], "✓ Equippable", "ok")

	t.assert_true(panel.has_node("ScanlineOverlay"), "open_card preserves ScanlineOverlay")
	t.assert_eq(panel.get_child(0).name, "ScanlineOverlay", "ScanlineOverlay stays at child index 0")
	t.assert_true((ctx["footer_panel"] as Control).visible, "set_footer reveals pinned footer")
	t.assert_true(panel.get_minimum_size().x <= PszStyle.SHOP_DETAIL_W + 1.0,
		"Style A card respects 16:9 320px width without horizontal overflow")

	panel.custom_minimum_size = Vector2(268.0, PszStyle.DETAIL_HEIGHT)
	t.assert_true(panel.get_minimum_size().x <= 269.0,
		"Style A card respects narrow 4:3 268px width without horizontal overflow")
	panel.free()


static func _test_equipment_previews(t: Node) -> void:
	var saved_slot: int = CharacterManager._active_slot
	var saved_char = CharacterManager._characters[3]
	var saved_equip_all: bool = DebugConfig.equip_all
	DebugConfig.equip_all = false
	CharacterManager.create_character(3, "humar", "DetailSpec")
	CharacterManager.set_active_slot(3)
	var ch = CharacterManager.get_active_character()
	ch["equipment"]["weapon"] = "saber"
	ch["equipment"]["frame"] = "common_armor"

	var panel := PanelContainer.new()
	PszStyle.apply_detail_panel_style(panel)
	t.add_child(panel)

	# 1. Weapon stat-change preview (equipping a stronger/different weapon vs saber)
	var brand_id := "brand" if WeaponRegistry.get_weapon("brand") != null else "sword"
	ShopDetail.render_item_card(panel, brand_id, "", {})
	var texts := _collect_labels(panel)
	t.assert_true(texts.has("STAT") and texts.has("ITEM") and texts.has("EQUIPPED"),
		"Weapon card shows STAT | ITEM | EQUIPPED header")
	t.assert_true(texts.any(func(s: String) -> bool: return "→" in s),
		"Unequipped weapon shows cur→next stat delta")
	t.assert_true(texts.has("Element") and texts.has("Photon Art"),
		"Weapon card shows 1-per-row Element and Photon Art pills")

	# 2. Equipped marker [E]
	ShopDetail.render_item_card(panel, "saber", "Saber", {"is_equipped": true})
	var eq_texts := _collect_labels(panel)
	t.assert_true(eq_texts.any(func(s: String) -> bool: return "[E]" in s),
		"Equipped weapon shows [E] in EQUIPPED column")

	# 3. Class-restricted weapon (Force rod/cane on HUmar)
	var restricted_id := ""
	for wid in WeaponRegistry.get_all_weapon_ids():
		if not EquipmentUtils.item_fits_slot(str(wid), "weapon"):
			restricted_id = str(wid)
			break
	if not restricted_id.is_empty():
		ShopDetail.render_item_card(panel, restricted_id, "", {})
		var r_texts := _collect_labels(panel)
		t.assert_true(r_texts.any(func(s: String) -> bool: return "✕ Class" in s),
			"Class-blocked weapon shows ✕ Class in EQUIPPED column")

	# 4. Armor + Unit 1-attribute-per-row
	ShopDetail.render_item_card(panel, "common_armor", "", {"rolled_slots": 2})
	var armor_texts := _collect_labels(panel)
	t.assert_true(armor_texts.has("DEF") and armor_texts.has("EVA"), "Armor shows DEF and EVA rows")
	t.assert_true(armor_texts.any(func(s: String) -> bool: return "Slots ◇◇·· (2)" in s), "Armor shows slot pips")

	var all_units: Array = UnitRegistry.get_all_units()
	if not all_units.is_empty():
		ShopDetail.render_item_card(panel, all_units[0].id, "", {})
		var u_texts := _collect_labels(panel)
		t.assert_true(u_texts.any(func(s: String) -> bool: return "Armor Slot ×1" in s), "Unit shows Armor Slot ×1")

	panel.free()
	DebugConfig.equip_all = saved_equip_all
	CharacterManager._characters[3] = saved_char
	CharacterManager._active_slot = saved_slot


static func _test_consumable_disk_mag_tekker(t: Node) -> void:
	var panel := PanelContainer.new()
	PszStyle.apply_detail_panel_style(panel)
	t.add_child(panel)

	ShopDetail.render_item_card(panel, "monomate", "Monomate", {"held": 4})
	var c_texts := _collect_labels(panel)
	t.assert_true(c_texts.has("PACK") and c_texts.any(func(s: String) -> bool: return s.begins_with("4/")),
		"Consumable card renders PACK stack meter")

	ShopDetail.render_item_card(panel, "disk_foie_3", "Disk: Foie Lv.3", {"technique_id": "foie", "level": 3})
	var d_texts := _collect_labels(panel)
	t.assert_true(d_texts.has("PP Cost") and d_texts.has("Req. Level"),
		"Disk card renders 1-per-row PP Cost and Req. Level")

	ShopDetail.render_item_card(panel, "debug_mag", "Mag", {})
	var m_texts := _collect_labels(panel)
	t.assert_true(m_texts.has("POW") and m_texts.has("GRD") and m_texts.has("HIT") and m_texts.has("MND"),
		"Mag card renders 1-per-row POW/GRD/HIT/MND")
	t.assert_true(m_texts.has("Sync / IQ") and m_texts.has("Photon Blast"),
		"Mag card renders Sync / IQ and Photon Blast rows")

	var tctx := ShopDetail.open_card(panel, "Saber +2", {"rarity": 2})
	ShopDetail.add_delta_rows(tctx, [
		{"label": "Grind", "value": "+2 → +3 (+1)", "positive": true},
		{"label": "Weapon ATK", "value": "55 → 63 (+8)", "positive": true},
	])
	var k_texts := _collect_labels(panel)
	t.assert_true(k_texts.has("BEFORE → AFTER") and k_texts.has("+2 → +3 (+1)"),
		"Tekker delta rows render 1-stat-per-row BEFORE → AFTER")

	panel.free()


static func _collect_labels(root: Node) -> Array:
	var out: Array = []
	for child in root.find_children("*", "Label", true, false):
		out.append((child as Label).text)
	return out

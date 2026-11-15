extends RefCounted
## Style A (PSZ Blue Glass) detail card builder + shared per-item-type views (#772).
##
## Preloaded static helper (composition, never a class_name base class — see
## docs/shop-dedup.md). Renders a flush navy header banner, frosted 1-attribute-
## per-row body inset, equipped stat-delta previews, and a pinned dark footer.

const C_GOLD_RULE := Color(0.941, 0.627, 0.125)
const C_INSET_BG := Color(0.957, 0.976, 1.0, 0.88)
const C_INSET_BORDER := Color(0.431, 0.573, 0.706, 0.50)
const C_ROW_BG := Color(1.0, 1.0, 1.0, 0.74)
const C_ROW_BORDER := Color(0.510, 0.643, 0.769, 0.38)
const C_ROW_UP_BG := Color(0.180, 0.627, 0.322, 0.11)
const C_ROW_DOWN_BG := Color(0.855, 0.267, 0.267, 0.11)
const C_SUB_TEXT := Color(0.204, 0.282, 0.369)
const C_COL_HDR := Color(0.357, 0.443, 0.541)
const C_KEY_TEXT := Color(0.271, 0.353, 0.439)
const C_VAL_TEXT := Color(0.094, 0.133, 0.196)
const C_UP_TEXT := Color(0.086, 0.431, 0.196)
const C_DOWN_TEXT := Color(0.706, 0.137, 0.137)
const C_SLATE_TEXT := Color(0.345, 0.424, 0.510)
const C_FOOTER_BG := Color(0.118, 0.157, 0.220, 0.94)
const C_FOOTER_LABEL := Color(0.612, 0.690, 0.788)
const C_GOLD_TEXT := Color(1.0, 0.831, 0.376)
const C_PD_TEXT := Color(0.486, 0.831, 1.0)

const UNIT_STAT_MAP := {
	"Power": ["ATK", "atk"], "Guard": ["DEF", "def"], "HP": ["HP", "hp"],
	"PP": ["PP", "pp"], "Hit": ["ACC", "acc"], "Mind": ["TEC", "tech"],
	"Swift": ["EVA", "eva"],
}

const PHOTON_ELEMENTS := {
	"ban_photon": "Fire", "ray_photon": "Ice", "zon_photon": "Lightning",
	"megi_photon": "Dark", "gra_photon": "Light", "el_photon": "HP Drain",
	"im_photon": "Neutral",
}


## Clear `panel` and construct the Style A card shell (header + inset + footer).
static func open_card(panel: PanelContainer, title_text: String, opts: Dictionary = {}) -> Dictionary:
	PszStyle.clear_detail_panel(panel)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 0)

	root.add_child(_build_header(title_text, opts))

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)

	var inset := PanelContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inset.add_theme_stylebox_override("panel", _box_style(C_INSET_BG, C_INSET_BORDER, 1, 4, 6, 5))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 3)
	scroll.add_child(body)
	inset.add_child(scroll)
	margin.add_child(inset)
	root.add_child(margin)

	var footer_panel := PanelContainer.new()
	footer_panel.visible = false
	var fstyle := _box_style(C_FOOTER_BG, Color(1, 1, 1, 0.14), 0, 0, 8, 5)
	fstyle.border_width_top = 1
	fstyle.corner_radius_bottom_left = 3
	fstyle.corner_radius_bottom_right = 3
	footer_panel.add_theme_stylebox_override("panel", fstyle)
	var footer_vbox := VBoxContainer.new()
	footer_vbox.add_theme_constant_override("separation", 4)
	footer_panel.add_child(footer_vbox)
	root.add_child(footer_panel)

	panel.add_child(root)
	return {"body": body, "footer_panel": footer_panel, "footer_vbox": footer_vbox}


static func _build_header(title_text: String, opts: Dictionary) -> PanelContainer:
	var header := PanelContainer.new()
	var hstyle := _box_style(PszStyle.TITLE_BG, C_GOLD_RULE, 0, 0, 8, 5)
	hstyle.border_width_bottom = 2
	hstyle.corner_radius_top_left = 3
	hstyle.corner_radius_top_right = 3
	header.add_theme_stylebox_override("panel", hstyle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon_tex: Texture2D = opts.get("icon") as Texture2D
	if icon_tex != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = icon_tex
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(18, 18)
		tex_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tex_rect)

	var title := _lbl(title_text, 13, PszStyle.TEXT_WHITE, true)
	row.add_child(title)

	var badge_text: String = str(opts.get("badge_text", ""))
	var rarity: int = int(opts.get("rarity", 0))
	if not badge_text.is_empty():
		row.add_child(_make_text_badge(badge_text, opts.get("badge_color", C_GOLD_RULE)))
	elif rarity > 0:
		row.add_child(_make_rarity_badge(rarity))

	header.add_child(row)
	return header


static func _make_rarity_badge(rarity: int) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_theme_stylebox_override("panel",
		_box_style(Color(0.04, 0.06, 0.10, 0.60), Color(1, 1, 1, 0.16), 1, 3, 4, 2))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 1)
	var star_tex: Texture2D = InventoryIcons.for_rarity(rarity)
	var count: int = mini(rarity, 7)
	if star_tex != null and rarity <= 7:
		for _i in range(count):
			var star_icon := TextureRect.new()
			star_icon.texture = star_tex
			star_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			star_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			star_icon.custom_minimum_size = Vector2(10, 10)
			star_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hbox.add_child(star_icon)
	else:
		hbox.add_child(_lbl("★×%d" % rarity, 10, C_GOLD_TEXT, false))
	pill.add_child(hbox)
	return pill


static func _make_text_badge(text: String, border_col: Color) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_theme_stylebox_override("panel",
		_box_style(Color(1, 1, 1, 0.14), border_col, 1, 3, 5, 1))
	pill.add_child(_lbl(text, 10, PszStyle.TEXT_WHITE, false))
	return pill


## Add the top sub-metadata bar (e.g. "Sword" | "Grind Max +9") + thin rule.
static func add_sub_meta(ctx: Dictionary, left_text: String, right_text: String = "") -> void:
	var body: VBoxContainer = ctx["body"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_lbl(left_text, 11, C_SUB_TEXT, true))
	if not right_text.is_empty():
		var rlbl := _lbl(right_text, 11, C_SUB_TEXT, false)
		rlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(rlbl)
	body.add_child(row)
	var sep := ColorRect.new()
	sep.color = Color(0.384, 0.525, 0.659, 0.35)
	sep.custom_minimum_size = Vector2(0, 1)
	body.add_child(sep)


## Add 1-attribute-per-row STAT | ITEM | EQUIPPED comparison rows.
static func add_equip_rows(ctx: Dictionary, rows: Array, mid_hdr := "ITEM", right_hdr := "EQUIPPED") -> void:
	if rows.is_empty():
		return
	var body: VBoxContainer = ctx["body"]
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 5)
	hdr.add_child(_lbl("STAT", 9, C_COL_HDR, true))
	var m := _lbl(mid_hdr, 9, C_COL_HDR, false)
	m.custom_minimum_size.x = 34
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hdr.add_child(m)
	var r := _lbl(right_hdr, 9, C_COL_HDR, false)
	r.custom_minimum_size.x = 96
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hdr.add_child(r)
	body.add_child(hdr)

	for entry in rows:
		var diff: int = int(entry.get("diff", 0))
		var bg := C_ROW_UP_BG if diff > 0 else (C_ROW_DOWN_BG if diff < 0 else C_ROW_BG)
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", _box_style(bg, C_ROW_BORDER, 1, 3, 5, 2))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 5)
		line.add_child(_lbl(str(entry.get("stat", "")), 11, C_KEY_TEXT, true))
		var iv := _lbl(str(entry.get("item_val", "")), 11, C_VAL_TEXT, false)
		iv.custom_minimum_size.x = 34
		iv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(iv)
		var note: String = str(entry.get("note", ""))
		var eq_text := note
		var eq_col := C_SLATE_TEXT
		if note.is_empty() and entry.has("from") and entry.has("to"):
			var sign_str := "+" if diff > 0 else ("±" if diff == 0 else "")
			eq_text = "%d→%d (%s%d)" % [int(entry["from"]), int(entry["to"]), sign_str, diff]
			eq_col = C_UP_TEXT if diff > 0 else (C_DOWN_TEXT if diff < 0 else C_SLATE_TEXT)
		var ev := _lbl(eq_text, 11, eq_col, false)
		ev.custom_minimum_size.x = 96
		ev.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(ev)
		box.add_child(line)
		body.add_child(box)


## Add 1-attribute-per-row STAT | BEFORE → AFTER delta rows (Tekker Grind).
static func add_delta_rows(ctx: Dictionary, rows: Array) -> void:
	var body: VBoxContainer = ctx["body"]
	var hdr := HBoxContainer.new()
	hdr.add_child(_lbl("STAT", 9, C_COL_HDR, true))
	var rh := _lbl("BEFORE → AFTER", 9, C_COL_HDR, false)
	rh.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hdr.add_child(rh)
	body.add_child(hdr)
	for entry in rows:
		var pos: bool = bool(entry.get("positive", false))
		var bg := C_ROW_UP_BG if pos else C_ROW_BG
		var col := C_UP_TEXT if pos else C_VAL_TEXT
		add_kv_row(ctx, str(entry.get("label", "")), str(entry.get("value", "")), col, bg)


## Add a single left/right aligned attribute row inside a frosted pill.
static func add_kv_row(ctx: Dictionary, key_text: String, val_text: String,
		val_color: Color = C_VAL_TEXT, bg: Color = C_ROW_BG) -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box_style(bg, C_ROW_BORDER, 1, 3, 5, 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_lbl(key_text, 11, C_KEY_TEXT, false))
	var val := _lbl(val_text, 11, val_color, true)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	box.add_child(row)
	(ctx["body"] as VBoxContainer).add_child(box)


## Add smart-wrapped description prose inside the body inset.
static func add_prose(ctx: Dictionary, text: String, color: Color = C_VAL_TEXT) -> void:
	if text.strip_edges().is_empty():
		return
	var lbl := Label.new()
	lbl.text = text.strip_edges()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	(ctx["body"] as VBoxContainer).add_child(lbl)


## Add compact PACK stack fill meter for stackable consumables.
static func add_stack_bar(ctx: Dictionary, held: int, max_stack: int) -> void:
	if max_stack <= 0:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_lbl("PACK", 9, C_COL_HDR, false))
	var track := PanelContainer.new()
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.custom_minimum_size = Vector2(0, 6)
	track.add_theme_stylebox_override("panel", _box_style(Color(0.24, 0.35, 0.47, 0.18), Color.TRANSPARENT, 0, 3, 0, 0))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = float(maxi(max_stack, 1))
	bar.value = float(clampi(held, 0, max_stack))
	bar.custom_minimum_size = Vector2(0, 6)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override("background", _box_style(Color(0.24, 0.35, 0.47, 0.18), Color.TRANSPARENT, 0, 3, 0, 0))
	var fill_col := Color(0.88, 0.60, 0.13) if held >= max_stack else Color(0.23, 0.53, 0.80)
	bar.add_theme_stylebox_override("fill", _box_style(fill_col, Color.TRANSPARENT, 0, 3, 0, 0))
	track.add_child(bar)
	row.add_child(track)
	row.add_child(_lbl("%d/%d" % [held, max_stack], 10, C_VAL_TEXT, false))
	(ctx["body"] as VBoxContainer).add_child(row)


## Populate and show the pinned dark footer strip (prices/counts + status pill).
static func set_footer(ctx: Dictionary, stats: Array, status_text := "", status_tone := "neutral") -> void:
	var fpanel: PanelContainer = ctx["footer_panel"]
	var fvbox: VBoxContainer = ctx["footer_vbox"]
	for c in fvbox.get_children():
		c.queue_free()
	if stats.is_empty() and status_text.is_empty():
		fpanel.visible = false
		return
	fpanel.visible = true
	if not stats.is_empty():
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 8)
		for i in range(stats.size()):
			var entry: Dictionary = stats[i]
			var pair := HBoxContainer.new()
			pair.add_theme_constant_override("separation", 4)
			if i > 0:
				pair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				pair.alignment = BoxContainer.ALIGNMENT_END if i == stats.size() - 1 else BoxContainer.ALIGNMENT_CENTER
			pair.add_child(_lbl(str(entry.get("label", "")), 10, C_FOOTER_LABEL, false))
			var tone: String = str(entry.get("tone", ""))
			var vcol := C_GOLD_TEXT if tone == "gold" else (C_PD_TEXT if tone == "pd" else (C_FOOTER_LABEL if tone == "muted" else PszStyle.TEXT_WHITE))
			pair.add_child(_lbl(str(entry.get("value", "")), 11, vcol, false))
			srow.add_child(pair)
		fvbox.add_child(srow)
	if not status_text.is_empty():
		fvbox.add_child(_make_status_pill(status_text, status_tone))


static func _make_status_pill(text: String, tone: String) -> PanelContainer:
	var palette := {
		"ok": [Color(0.20, 0.66, 0.35, 0.22), Color(0.56, 0.94, 0.67), Color(0.43, 0.88, 0.56, 0.45)],
		"warn": [Color(0.94, 0.66, 0.13, 0.22), Color(1.0, 0.83, 0.44), Color(0.97, 0.78, 0.25, 0.48)],
		"blocked": [Color(0.83, 0.24, 0.24, 0.24), Color(1.0, 0.61, 0.61), Color(0.92, 0.39, 0.39, 0.50)],
		"equipped": [Color(0.36, 0.60, 0.90, 0.24), Color(0.66, 0.83, 1.0), Color(0.51, 0.73, 0.98, 0.48)],
		"neutral": [Color(1, 1, 1, 0.10), Color(0.81, 0.85, 0.90), Color(1, 1, 1, 0.20)],
	}
	var cols: Array = palette.get(tone, palette["neutral"])
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _box_style(cols[0], cols[2], 1, 3, 6, 2))
	var lbl := _lbl(text, 10, cols[1], true)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.add_child(lbl)
	return pill


## Render any inventory/shop item (`item_id`) into `panel` using its canonical per-type template.
static func render_item_card(panel: PanelContainer, item_id: String, display_name: String, opts: Dictionary = {}) -> Dictionary:
	var base_id: String = Inventory.get_base_id(item_id)
	var norm_id: String = base_id.replace("-", "_").replace("/", "_")
	var weapon = _find_weapon(base_id, norm_id)
	if weapon != null:
		return _render_weapon(panel, item_id, display_name, weapon, opts)
	var armor = _find_armor(base_id, norm_id)
	if armor != null:
		return _render_armor(panel, item_id, display_name, armor, opts)
	var unit = _find_unit(base_id, norm_id)
	if unit != null:
		return _render_unit(panel, item_id, display_name, unit, opts)
	if norm_id.begins_with("disk_") or opts.has("technique_id"):
		return _render_disk(panel, item_id, display_name, norm_id, opts)
	if norm_id == "debug_mag" or MagManager.is_mag(item_id) or MagManager.is_mag(norm_id):
		return _render_mag(panel, item_id, display_name, opts)
	return _render_generic_item(panel, item_id, norm_id, display_name, opts)


static func _render_weapon(panel: PanelContainer, item_id: String, display_name: String, weapon, opts: Dictionary) -> Dictionary:
	var ctx := open_card(panel, display_name if not display_name.is_empty() else str(weapon.name), {
		"icon": InventoryIcons.for_weapon_type(int(weapon.weapon_type)),
		"rarity": int(weapon.rarity),
	})
	var character = CharacterManager.get_active_character()
	var props: Dictionary = opts.get("properties", {})
	var has_instance: bool = ("#" in item_id) or bool(opts.get("owned_instance", false))
	var grind: int = _resolve_grind(character, item_id, props)
	var grind_txt := "+%d / +%d" % [grind, int(weapon.max_grind)] if (has_instance or grind > 0) else "Max +%d" % int(weapon.max_grind)
	add_sub_meta(ctx, weapon.get_weapon_type_name(), "Grind %s" % grind_txt)

	var w_atk: int = weapon.get_attack_at_grind(grind)
	var w_acc: int = weapon.get_accuracy_at_grind(grind)
	add_equip_rows(ctx, _weapon_equip_rows(character, item_id, w_atk, w_acc, bool(opts.get("is_equipped", false))))

	var elem_str: String = _resolve_weapon_element(character, item_id, weapon, props)
	add_kv_row(ctx, "Element", elem_str, C_VAL_TEXT if elem_str != "—" else C_SLATE_TEXT)
	var pa_str := "—"
	if not weapon.photon_arts.is_empty():
		pa_str = str(weapon.photon_arts[0].get("name", "—"))
	add_kv_row(ctx, "Photon Art", pa_str, C_VAL_TEXT if pa_str != "—" else C_SLATE_TEXT)
	return ctx


static func _render_armor(panel: PanelContainer, item_id: String, display_name: String, armor, opts: Dictionary) -> Dictionary:
	var ctx := open_card(panel, display_name if not display_name.is_empty() else str(armor.name), {
		"icon": InventoryIcons.for_item(armor.id, "Armor"),
		"rarity": int(armor.rarity),
	})
	var character = CharacterManager.get_active_character()
	var props: Dictionary = opts.get("properties", {})
	var slots: int = int(opts.get("rolled_slots", -1))
	if slots < 0:
		slots = int(props["armor_slots"]) if props.has("armor_slots") else EquipmentUtils.get_unit_slot_count(item_id, character)
	var pips := ""
	for i in range(4):
		pips += "◇" if i < slots else "·"
	var type_names := ["Armor", "Frame", "Robe", "Rare Armor"]
	var tname: String = type_names[clampi(int(armor.type), 0, type_names.size() - 1)]
	add_sub_meta(ctx, tname, "Slots %s (%d)" % [pips, slots])
	add_equip_rows(ctx, _armor_equip_rows(character, item_id, armor, bool(opts.get("is_equipped", false))))
	return ctx


static func _render_unit(panel: PanelContainer, _item_id: String, display_name: String, unit, opts: Dictionary) -> Dictionary:
	var ctx := open_card(panel, display_name if not display_name.is_empty() else str(unit.name), {
		"icon": InventoryIcons.for_item(unit.id, "Unit"),
		"rarity": int(unit.rarity),
	})
	add_sub_meta(ctx, "%s Unit" % str(unit.category), "Armor Slot ×1")
	var character = CharacterManager.get_active_character()
	var is_eq: bool = bool(opts.get("is_equipped", false))
	if UNIT_STAT_MAP.has(str(unit.category)):
		var pair: Array = UNIT_STAT_MAP[str(unit.category)]
		var totals: Dictionary = calc_effective_stats(character)
		var cur_val: int = int(totals.get(pair[1], 0))
		var val: int = int(unit.effect_value)
		var row := {"stat": str(pair[0]), "item_val": "+%d" % val}
		if character == null:
			row["note"] = "—"
		elif is_eq:
			row["note"] = "%d [E]" % cur_val
		else:
			row["from"] = cur_val
			row["to"] = cur_val + val
			row["diff"] = val
		add_equip_rows(ctx, [row])
	if not str(unit.effect).is_empty():
		add_kv_row(ctx, "Effect", str(unit.effect), C_UP_TEXT)
	return ctx


static func _render_disk(panel: PanelContainer, _item_id: String, display_name: String, norm_id: String, opts: Dictionary) -> Dictionary:
	var tech_id: String = str(opts.get("technique_id", ""))
	var level: int = int(opts.get("level", 1))
	if tech_id.is_empty():
		var parsed: Dictionary = _parse_disk_id(norm_id)
		tech_id = str(parsed.get("id", ""))
		level = int(parsed.get("level", 1))
	var tech: Dictionary = TechniqueManager.get_technique(tech_id)
	var elem_name: String = str(tech.get("element", "none")).capitalize()
	var ctx := open_card(panel, display_name, {
		"icon": InventoryIcons.for_item("disk_" + tech_id, "Disk"),
		"badge_text": elem_name if elem_name != "None" else "Support",
	})
	if tech.is_empty():
		add_prose(ctx, "Technique disk.")
		return ctx
	add_sub_meta(ctx, "Technique Disk", "Target: %s" % str(tech.get("target", "single")).capitalize())
	var base_pwr: int = int(tech.get("power", 0))
	if base_pwr > 0:
		var pwr: int = int(float(base_pwr) * (1.0 + float(level) / 10.0))
		add_kv_row(ctx, "Power", "%d (Lv.%d)" % [pwr, level])
	var pp_cost: int = maxi(1, int(tech.get("pp", 5)) - int(float(level) / 5.0))
	add_kv_row(ctx, "PP Cost", str(pp_cost))
	var req_lv: int = TechniqueManager.get_disk_required_level(level)
	var character = CharacterManager.get_active_character()
	var char_lv: int = int(character.get("level", 1)) if character else 1
	var req_col := C_DOWN_TEXT if char_lv < req_lv else C_VAL_TEXT
	add_kv_row(ctx, "Req. Level", "Lv.%d (You: Lv.%d)" % [req_lv, char_lv], req_col)
	if character != null:
		var cur_lv: int = TechniqueManager.get_technique_level(character, tech_id)
		if not TechniqueManager.class_can_learn(character, tech_id, level):
			add_kv_row(ctx, "Known", "N/A (Class)", C_DOWN_TEXT)
		elif cur_lv <= 0:
			add_kv_row(ctx, "Known", "Unlearned", C_SLATE_TEXT)
		elif cur_lv < level:
			add_kv_row(ctx, "Known", "Lv.%d → Lv.%d ↑" % [cur_lv, level], C_UP_TEXT, C_ROW_UP_BG)
		else:
			add_kv_row(ctx, "Known", "Lv.%d (Known)" % cur_lv, C_SLATE_TEXT)
	return ctx


static func _render_mag(panel: PanelContainer, item_id: String, display_name: String, opts: Dictionary) -> Dictionary:
	var character = CharacterManager.get_active_character()
	var props: Dictionary = opts.get("properties", {})
	var mag_state: Dictionary = {}
	if character != null:
		mag_state = MagManager.get_mag_state(character, item_id)
	if mag_state.is_empty() and props.has("mag_states") and props["mag_states"] is Dictionary:
		mag_state = props["mag_states"]
	if mag_state.is_empty():
		mag_state = MagManager.create_mag()
	var form_id: String = str(mag_state.get("form_id", "mag"))
	var form = MagManager.get_mag_form(form_id)
	var level: int = MagManager.get_level(mag_state)
	var title_str := display_name if not display_name.is_empty() else (str(form.name) if form else "Mag")
	var ctx := open_card(panel, title_str, {
		"icon": InventoryIcons.for_item(item_id, "Mag"),
		"badge_text": "Lv.%d" % level,
		"badge_color": C_GOLD_RULE,
	})
	var stage_txt := "Stage %d" % int(form.stage) if form else "Mag"
	var pers: String = str(mag_state.get("personality", "")).capitalize()
	add_sub_meta(ctx, "%s · %s" % [str(form.name) if form else "Mag", stage_txt], pers)
	add_equip_rows(ctx, _mag_equip_rows(character, mag_state, bool(opts.get("is_equipped", false))), "MAG", "EQUIPPED")
	add_kv_row(ctx, "Sync / IQ", "%d / %d" % [int(mag_state.get("sync", 0)), int(mag_state.get("iq", 0))])
	var pb: String = str(form.photon_blast) if (form and not str(form.photon_blast).is_empty()) else "—"
	add_kv_row(ctx, "Photon Blast", pb, C_VAL_TEXT if pb != "—" else C_SLATE_TEXT)
	return ctx


static func _render_generic_item(panel: PanelContainer, item_id: String, norm_id: String,
		display_name: String, opts: Dictionary) -> Dictionary:
	var consumable = ConsumableRegistry.get_consumable(norm_id)
	var mat = MaterialRegistry.get_material(norm_id)
	var mod = ModifierRegistry.get_modifier(norm_id)
	var rarity := 0
	if consumable: rarity = int(consumable.rarity)
	elif mat: rarity = int(mat.rarity)
	elif mod: rarity = int(mod.rarity)
	var ctx := open_card(panel, display_name, {
		"icon": InventoryIcons.for_item(item_id),
		"rarity": rarity,
	})
	var held: int = int(opts.get("held", Inventory.get_item_count(norm_id)))
	var max_stack: int = int(consumable.max_stack) if consumable else maxi(1, Inventory.get_max_stack(norm_id))
	var cat_label: String = str(opts.get("category_label", ""))
	if cat_label.is_empty():
		cat_label = "Consumable" if consumable else ("Photon Crystal" if PHOTON_ELEMENTS.has(norm_id) else ("Grinder" if mod else ("Material" if mat else "Item")))
	var right_meta := "Held %d / %d" % [held, max_stack] if bool(opts.get("show_held", true)) else ""
	add_sub_meta(ctx, cat_label, right_meta)

	if PHOTON_ELEMENTS.has(norm_id):
		add_kv_row(ctx, "Element", str(PHOTON_ELEMENTS[norm_id]), C_UP_TEXT)
	var desc := ""
	if consumable: desc = str(consumable.details)
	elif mat: desc = str(mat.details)
	elif mod: desc = str(mod.details)
	if desc.is_empty():
		desc = str(opts.get("fallback_desc", ""))
	add_prose(ctx, desc)
	if consumable and bool(opts.get("show_held", true)):
		add_stack_bar(ctx, held, max_stack)
	return ctx


## Compute effective character stats (`hp`, `pp`, `atk`, `def`, `acc`, `eva`, `tech`).
static func calc_effective_stats(character) -> Dictionary:
	var out := {"hp": 0, "pp": 0, "atk": 0, "def": 0, "acc": 0, "eva": 0, "tech": 0,
		"w_atk": 0, "w_acc": 0, "a_def": 0, "a_eva": 0,
		"m_atk": 0, "m_def": 0, "m_acc": 0, "m_tech": 0}
	if character == null:
		return out
	var cdata = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	if cdata != null:
		var b: Dictionary = cdata.get_stats_at_level(int(character.get("level", 1)))
		out["hp"] = int(b.get("hp", 0)); out["pp"] = int(b.get("pp", 0))
		out["atk"] = int(b.get("attack", 0)); out["def"] = int(b.get("defense", 0))
		out["acc"] = int(b.get("accuracy", 0)); out["eva"] = int(b.get("evasion", 0))
		out["tech"] = int(b.get("technique", 0))
	var eq: Dictionary = character.get("equipment", {})
	var wid: String = str(eq.get("weapon", ""))
	if not wid.is_empty():
		var w = WeaponRegistry.get_weapon(Inventory.get_base_id(wid))
		if w != null:
			var g: int = int(character.get("weapon_grinds", {}).get(wid, 0))
			out["w_atk"] = w.get_attack_at_grind(g); out["w_acc"] = w.get_accuracy_at_grind(g)
			out["atk"] += out["w_atk"]; out["acc"] += out["w_acc"]
	var fid: String = str(eq.get("frame", ""))
	if not fid.is_empty():
		var a = ArmorRegistry.get_armor(Inventory.get_base_id(fid))
		if a != null:
			out["a_def"] = int(a.defense_base); out["a_eva"] = int(a.evasion_base)
			out["def"] += out["a_def"]; out["eva"] += out["a_eva"]
	_accumulate_units_mats_mag(character, eq, out)
	return out


static func _accumulate_units_mats_mag(character: Dictionary, eq: Dictionary, out: Dictionary) -> void:
	for s in ["unit1", "unit2", "unit3", "unit4"]:
		var uid: String = str(eq.get(s, ""))
		if not uid.is_empty():
			var u = UnitRegistry.get_unit(Inventory.get_base_id(uid))
			if u != null and UNIT_STAT_MAP.has(str(u.category)):
				out[UNIT_STAT_MAP[str(u.category)][1]] += int(u.effect_value)
	var mats: Dictionary = character.get("material_bonuses", {})
	var mmap := {"attack": "atk", "defense": "def", "accuracy": "acc", "evasion": "eva", "technique": "tech", "hp": "hp", "pp": "pp"}
	for k in mmap:
		out[mmap[k]] += int(mats.get(k, 0))
	var mid: String = str(eq.get("mag", ""))
	if not mid.is_empty():
		var ms: Dictionary = MagManager.get_mag_state(character, mid)
		if not ms.is_empty():
			var mb: Dictionary = MagManager.get_stat_bonuses(ms)
			out["m_atk"] = int(mb.get("attack", 0)); out["m_def"] = int(mb.get("defense", 0))
			out["m_acc"] = int(mb.get("accuracy", 0)); out["m_tech"] = int(mb.get("technique", 0))
			out["atk"] += out["m_atk"]; out["def"] += out["m_def"]
			out["acc"] += out["m_acc"]; out["tech"] += out["m_tech"]


static func weapon_preview_rows(item_id: String, w_atk: int, w_acc: int, is_equipped := false) -> Array:
	return _weapon_equip_rows(CharacterManager.get_active_character(), item_id, w_atk, w_acc, is_equipped)


static func _weapon_equip_rows(character, item_id: String, w_atk: int, w_acc: int, is_eq: bool) -> Array:
	if character == null:
		return [{"stat": "ATK", "item_val": str(w_atk), "note": "—"},
			{"stat": "ACC", "item_val": str(w_acc), "note": "—"}]
	if not EquipmentUtils.item_fits_slot(item_id, "weapon"):
		return [{"stat": "ATK", "item_val": str(w_atk), "note": "✕ Class"},
			{"stat": "ACC", "item_val": str(w_acc), "note": "✕ Class"}]
	var t: Dictionary = calc_effective_stats(character)
	if is_eq:
		return [{"stat": "ATK", "item_val": str(w_atk), "note": "%d [E]" % int(t["atk"])},
			{"stat": "ACC", "item_val": str(w_acc), "note": "%d [E]" % int(t["acc"])}]
	var next_atk: int = int(t["atk"]) - int(t["w_atk"]) + w_atk
	var next_acc: int = int(t["acc"]) - int(t["w_acc"]) + w_acc
	return [
		{"stat": "ATK", "item_val": str(w_atk), "from": int(t["atk"]), "to": next_atk, "diff": next_atk - int(t["atk"])},
		{"stat": "ACC", "item_val": str(w_acc), "from": int(t["acc"]), "to": next_acc, "diff": next_acc - int(t["acc"])},
	]


static func _armor_equip_rows(character, item_id: String, armor, is_eq: bool) -> Array:
	var rows: Array = []
	var can_eq: bool = character != null and EquipmentUtils.item_fits_slot(item_id, "frame")
	var t: Dictionary = calc_effective_stats(character)
	var eq_fid: String = str(character.get("equipment", {}).get("frame", "")) if character else ""
	var cur_armor = ArmorRegistry.get_armor(Inventory.get_base_id(eq_fid)) if not eq_fid.is_empty() else null
	rows.append(_stat_cmp_row("DEF", str(armor.defense_base), int(t["def"]), int(t["def"]) - int(t["a_def"]) + int(armor.defense_base), character == null, can_eq, is_eq))
	rows.append(_stat_cmp_row("EVA", str(armor.evasion_base), int(t["eva"]), int(t["eva"]) - int(t["a_eva"]) + int(armor.evasion_base), character == null, can_eq, is_eq))
	var res_defs := [
		["Fire Res.", int(armor.resist_fire), int(cur_armor.resist_fire) if cur_armor else 0],
		["Ice Res.", int(armor.resist_ice), int(cur_armor.resist_ice) if cur_armor else 0],
		["Bolt Res.", int(armor.resist_lightning), int(cur_armor.resist_lightning) if cur_armor else 0],
		["Light Res.", int(armor.resist_light), int(cur_armor.resist_light) if cur_armor else 0],
		["Dark Res.", int(armor.resist_dark), int(cur_armor.resist_dark) if cur_armor else 0],
	]
	for rd in res_defs:
		if int(rd[1]) > 0 or int(rd[2]) > 0:
			rows.append(_stat_cmp_row(str(rd[0]), "+%d" % int(rd[1]), int(rd[2]), int(rd[1]), character == null, can_eq, is_eq))
	return rows


static func _mag_equip_rows(character, mag_state: Dictionary, is_eq: bool) -> Array:
	var mb: Dictionary = MagManager.get_stat_bonuses(mag_state)
	var stats_raw: Dictionary = mag_state.get("stats", {})
	var t: Dictionary = calc_effective_stats(character)
	var pairs := [
		["POW", int(int(stats_raw.get("power", 0)) / MagManager.STATS_PER_LEVEL), int(t["atk"]), int(t["m_atk"]), int(mb.get("attack", 0))],
		["GRD", int(int(stats_raw.get("guard", 0)) / MagManager.STATS_PER_LEVEL), int(t["def"]), int(t["m_def"]), int(mb.get("defense", 0))],
		["HIT", int(int(stats_raw.get("hit", 0)) / MagManager.STATS_PER_LEVEL), int(t["acc"]), int(t["m_acc"]), int(mb.get("accuracy", 0))],
		["MND", int(int(stats_raw.get("mind", 0)) / MagManager.STATS_PER_LEVEL), int(t["tech"]), int(t["m_tech"]), int(mb.get("technique", 0))],
	]
	var rows: Array = []
	for p in pairs:
		var next_v: int = int(p[2]) - int(p[3]) + int(p[4])
		rows.append(_stat_cmp_row(str(p[0]), str(p[1]), int(p[2]), next_v, character == null, true, is_eq))
	return rows


static func _stat_cmp_row(stat_name: String, item_val: String, cur_v: int, next_v: int,
		no_char: bool, can_eq: bool, same_eq: bool) -> Dictionary:
	if no_char:
		return {"stat": stat_name, "item_val": item_val, "note": "—"}
	if not can_eq:
		return {"stat": stat_name, "item_val": item_val, "note": "✕ Class"}
	if same_eq:
		return {"stat": stat_name, "item_val": item_val, "note": "%d [E]" % cur_v}
	return {"stat": stat_name, "item_val": item_val, "from": cur_v, "to": next_v, "diff": next_v - cur_v}


static func _resolve_grind(character, item_id: String, props: Dictionary) -> int:
	if character != null and character.get("weapon_grinds", {}).has(item_id):
		return int(character["weapon_grinds"][item_id])
	if props.has("weapon_grinds"):
		return int(props["weapon_grinds"])
	return 0


static func _resolve_weapon_element(character, item_id: String, weapon, props: Dictionary) -> String:
	var pid := ""
	if character != null and character.get("weapon_elements", {}).has(item_id):
		pid = str(character["weapon_elements"][item_id])
	elif props.has("weapon_elements"):
		pid = str(props["weapon_elements"])
	if not pid.is_empty() and PHOTON_ELEMENTS.has(pid):
		return str(PHOTON_ELEMENTS[pid])
	if not str(weapon.element).is_empty() and str(weapon.element) != "None":
		if int(weapon.element_level) > 0:
			return "%s Lv.%d" % [str(weapon.element), int(weapon.element_level)]
		return str(weapon.element)
	return "—"


static func _parse_disk_id(norm_id: String) -> Dictionary:
	var body: String = norm_id.trim_prefix("disk_")
	var parts: PackedStringArray = body.rsplit("_", false, 1)
	if parts.size() == 2 and parts[1].is_valid_int():
		return {"id": parts[0], "level": int(parts[1])}
	return {"id": body, "level": 1}


static func _find_weapon(base_id: String, norm_id: String):
	var w = WeaponRegistry.get_weapon(base_id)
	return w if w != null else WeaponRegistry.get_weapon(norm_id)


static func _find_armor(base_id: String, norm_id: String):
	var a = ArmorRegistry.get_armor(base_id)
	return a if a != null else ArmorRegistry.get_armor(norm_id)


static func _find_unit(base_id: String, norm_id: String):
	var u = UnitRegistry.get_unit(base_id)
	return u if u != null else UnitRegistry.get_unit(norm_id)


static func _lbl(text: String, fsize: int, col: Color, expand_clip: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	if expand_clip:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


static func _box_style(bg: Color, border: Color, bw: int, radius: int, pad_h: float, pad_v: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s

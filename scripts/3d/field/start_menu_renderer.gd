class_name StartMenuRenderer
extends RefCounted

## Start-menu canvas rendering, extracted from PsoStartMenu.
##
## Holds a back-reference to the PsoStartMenu autoload (`_c`) and delegates all
## menu-state access through it. Behavior is identical to the original inline
## implementation — this is a relocation refactor, not a logic change.
##
## Constants live on the PsoStartMenu autoload and are referenced statically as
## `PsoStartMenu.<CONST>` (warning-free); enum values as `PsoStartMenu.Mode.*`.

## Back-reference to the PsoStartMenu autoload that owns this renderer.
var _c

# Preloaded shop helper (static), for the shared "Type Race" capability string —
# composition, not inheritance (the sanctioned shop-dedup pattern).
const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")


func _init(controller) -> void:
	_c = controller


## True when the active character can never equip/use this inventory item — gear
## the class/race can't equip (weapon type or armor class restriction), or a disk
## the class can never learn. Drives the ✕ marker in the items list. Routes through
## the shared cannot-use predicate (ShopNav.sell_cannot_use → the canonical
## EquipmentUtils.item_fits_slot gate; spec /mechanics/equip-legality) so this
## marker can't drift from the shops or storage. WeaponData.usable_by is NOT
## consulted (drifted); armor uses its per-item class list, honoring equip_all.
func _item_cannot_use(item_id: String) -> bool:
	return ShopNav.sell_cannot_use(item_id)


## Both row-mute tiers for an inventory row, as [cannot_use, soft_disabled]:
##   [0] cannot_use   — permanent class block → ✕ marker (_item_cannot_use).
##   [1] soft_disabled — a temporary block (a disk already known at this level, or
##       below the required player level) → grey WITHOUT the ✕ (ShopNav.sell_disabled).
## Both route through the shared ShopNav predicates so the start menu greys in
## lockstep with the shops and storage (spec /mechanics/equip-legality).
func _item_mute_state(item_id: String) -> Array:
	return [_item_cannot_use(item_id), ShopNav.sell_disabled(item_id)]


func _draw_menu() -> void:
	var c: Control = _c._canvas
	var font := ThemeDB.fallback_font
	var vp := Vector2(PsoStartMenu.VIEWPORT_W, PsoStartMenu.VIEWPORT_H)

	# L-shaped backdrop
	var left_top := Rect2(0, 0, PsoStartMenu.LEFT_W, vp.y - PsoStartMenu.BOTTOM_H)
	var bottom_right := Rect2(PsoStartMenu.LEFT_W, vp.y - PsoStartMenu.BOTTOM_H, vp.x - PsoStartMenu.LEFT_W, PsoStartMenu.BOTTOM_H)
	var bottom_left := Rect2(0, vp.y - PsoStartMenu.BOTTOM_H, PsoStartMenu.LEFT_W, PsoStartMenu.BOTTOM_H)
	c.draw_rect(left_top, PsoStartMenu.C_BACKDROP)
	c.draw_rect(bottom_right, PsoStartMenu.C_BACKDROP)
	c.draw_rect(bottom_left, PsoStartMenu.C_BACKDROP)
	# Subtle scanline overlay
	_draw_scanlines(c, left_top)
	_draw_scanlines(c, bottom_right)
	_draw_scanlines(c, bottom_left)
	# Borders
	c.draw_line(Vector2(PsoStartMenu.LEFT_W, 0), Vector2(PsoStartMenu.LEFT_W, vp.y - PsoStartMenu.BOTTOM_H), PsoStartMenu.C_BACKDROP_BORDER, 1.5)
	c.draw_line(Vector2(PsoStartMenu.LEFT_W, vp.y - PsoStartMenu.BOTTOM_H), Vector2(vp.x, vp.y - PsoStartMenu.BOTTOM_H), PsoStartMenu.C_BACKDROP_BORDER, 1.5)

	# HUD draws its own HP/PP — no duplicate status panel here

	match _c._mode:
		PsoStartMenu.Mode.MAIN: _draw_main(c, font)
		PsoStartMenu.Mode.ITEMS, PsoStartMenu.Mode.ITEMS_MOVE: _draw_items(c, font)
		PsoStartMenu.Mode.EQUIP, PsoStartMenu.Mode.EQUIP_PICK: _draw_equip(c, font)
		PsoStartMenu.Mode.TECHS: _draw_techs(c, font)
		PsoStartMenu.Mode.PALETTE, PsoStartMenu.Mode.PALETTE_PICK: _draw_palette(c, font)
		PsoStartMenu.Mode.MAGS, PsoStartMenu.Mode.MAG_FEED: _draw_mags(c, font)
		PsoStartMenu.Mode.QUEST: _draw_quest(c, font)
		PsoStartMenu.Mode.SYSTEM: _draw_system(c, font)
		PsoStartMenu.Mode.OPTIONS: _draw_options(c, font)


func _draw_main(c: Control, font: Font) -> void:
	# Main menu uses the assets/ui/main.png sprite (200×292). Text area inside
	# the sprite: x=12, y=29, 176×233. Selection highlight and menu rows live
	# inside that region.
	var bg_x: float = PsoStartMenu.PAD
	var bg_y: float = 110.0
	c.draw_texture(PsoStartMenu.MAIN_BG, Vector2(bg_x, bg_y))

	var text_x: float = bg_x + 12
	var text_y: float = bg_y + 29
	var text_w: float = 176
	var text_h: float = 233

	# Menu list rows — distribute evenly across the full text area height so
	# we use the space the old description panel took.
	var labels: Array = _c._get_menu_labels()
	var row_h: float = text_h / float(maxi(labels.size(), 1))
	for i in range(labels.size()):
		var iy: float = text_y + i * row_h
		if i == _c._menu_idx:
			c.draw_rect(Rect2(text_x + 2, iy, text_w - 4, row_h - 2), PsoStartMenu.C_SELECT)
		var col: Color = PsoStartMenu.C_SELECT_TEXT if i == _c._menu_idx else PsoStartMenu.C_TEXT
		c.draw_string(font, Vector2(text_x + 12, iy + row_h * 0.7), labels[i], HORIZONTAL_ALIGNMENT_LEFT, text_w - 16, PsoStartMenu.FONT_SIZE_LG, col)

	# Info panel (bottom right)
	_draw_info_panel(c, font)


func _draw_scanlines(c: Control, rect: Rect2) -> void:
	var x1: float = rect.position.x
	var x2: float = rect.position.x + rect.size.x
	var y_end: float = rect.position.y + rect.size.y
	# Start the first line one SPACING in so the very top edge of the rect
	# isn't always painted — otherwise a visible dark seam lands exactly on
	# the bottom-right rect's top border (y = VIEWPORT_H - BOTTOM_H).
	var y: float = rect.position.y + PsoStartMenu.SCANLINE_SPACING
	while y < y_end:
		c.draw_line(Vector2(x1, y), Vector2(x2, y), PsoStartMenu.C_SCANLINE, 1.0)
		y += PsoStartMenu.SCANLINE_SPACING


func _draw_info_panel(c: Control, font: Font) -> void:
	# Stats panel uses the assets/ui/stats.png sprite (440×273, scaled 1.72×
	# from a 256×159 DS source). Layout coords inside the sprite:
	#   page indicator box: x=191, y=24, 65×28 (between the L/R icons)
	#   stat text area:     x=17,  y=58, 402×162
	var px: float = PsoStartMenu.VIEWPORT_W - PsoStartMenu.STATS_BG.get_width() - 50
	var py: float = PsoStartMenu.VIEWPORT_H - PsoStartMenu.STATS_BG.get_height() - 20
	c.draw_texture(PsoStartMenu.STATS_BG, Vector2(px, py))

	# Page selector centered in the indicator box
	var page_label := "%d/4" % [_c._info_page + 1]
	c.draw_string(font, Vector2(px + 191, py + 44), page_label, HORIZONTAL_ALIGNMENT_CENTER, 65, PsoStartMenu.FONT_SIZE_SM, PsoStartMenu.C_TEXT)

	# Stat rows — pull real data from character + class + equipment
	var ch: Dictionary = _c._get_character()
	var class_id: String = str(ch.get("class_id", ""))
	var class_data = ClassRegistry.get_class_data(class_id)
	var level: int = int(ch.get("level", 1))
	var equip: Dictionary = ch.get("equipment", {})

	# Base stats from class at current level
	var base_hp: int = class_data.get_stat_at_level("hp", level) if class_data else 0
	var base_pp: int = class_data.get_stat_at_level("pp", level) if class_data else 0
	var base_atk: int = class_data.get_stat_at_level("attack", level) if class_data else 0
	var base_def: int = class_data.get_stat_at_level("defense", level) if class_data else 0
	var base_acc: int = class_data.get_stat_at_level("accuracy", level) if class_data else 0
	var base_eva: int = class_data.get_stat_at_level("evasion", level) if class_data else 0
	var base_mst: int = class_data.get_stat_at_level("technique", level) if class_data else 0

	# Equipment bonuses
	var weapon_id: String = str(equip.get("weapon", ""))
	var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(weapon_id)) if not weapon_id.is_empty() else null
	var weapon_grind: int = int(ch.get("weapon_grinds", {}).get(weapon_id, 0))
	var weapon_atk: int = weapon.get_attack_at_grind(weapon_grind) if weapon else 0
	var weapon_acc: int = weapon.get_accuracy_at_grind(weapon_grind) if weapon else 0
	var weapon_name: String = weapon.name if weapon else "--"

	var frame_id: String = str(equip.get("frame", ""))
	var armor = ArmorRegistry.get_armor(Inventory.get_base_id(frame_id)) if not frame_id.is_empty() else null
	var armor_def: int = int(armor.defense_base) if armor else 0
	var armor_eva: int = int(armor.evasion_base) if armor else 0
	var frame_name: String = armor.name if armor else "--"
	# Per-instance rolled slot count of the equipped frame (not resource max_slots).
	var frame_slots: int = EquipmentUtils.get_unit_slot_count(frame_id, ch)

	# Material bonuses
	var mat_bonuses: Dictionary = ch.get("material_bonuses", {})

	# EXP progress
	var exp_progress: Dictionary = CharacterManager.get_exp_progress() if CharacterManager.has_method("get_exp_progress") else {}
	var to_next: String = str(exp_progress.get("needed", "---"))

	# Weapon special
	var ws: Dictionary = ch.get("weapon_stats", {}).get(weapon_id, {})
	var special_el: String = str(ws.get("element", ""))
	var special_str: String = special_el.capitalize() if not special_el.is_empty() else "--"

	var pages := [
		[["Lv", str(level)], ["Type", class_data.name if class_data else class_id], ["Exp Pts", str(int(ch.get("experience", 0)))], ["To Next Lv", to_next], ["Meseta", str(int(ch.get("meseta", 0)))]],
		[["ATP", str(base_atk + weapon_atk + int(mat_bonuses.get("attack", 0)))], ["ATA", str(base_acc + weapon_acc + int(mat_bonuses.get("accuracy", 0)))], ["Weapon", weapon_name], ["Grind", "+%d" % weapon_grind if weapon_grind > 0 else "--"], ["Special", special_str]],
		[["DFP", str(base_def + armor_def + int(mat_bonuses.get("defense", 0)))], ["EVP", str(base_eva + armor_eva + int(mat_bonuses.get("evasion", 0)))], ["Frame", frame_name], ["Slots", str(frame_slots)], ["Units", "%d / %d" % [_c._count_equipped_units(equip), frame_slots]]],
		[["MST", str(base_mst + int(mat_bonuses.get("technique", 0)))], ["HP", "%d / %d" % [int(ch.get("hp", base_hp)), base_hp + int(mat_bonuses.get("hp", 0))]], ["PP", "%d / %d" % [int(ch.get("pp", base_pp)), base_pp + int(mat_bonuses.get("pp", 0))]]],
	]
	var rows: Array = pages[_c._info_page] if _c._info_page < pages.size() else []
	# Text area inside the stats sprite: x=17, y=58, 402×162.
	# Row height targets ~30px so 5 rows fit in 162 with a bit of breathing room.
	var rows_x: float = px + 17
	var rows_y: float = py + 58
	var rows_w: float = 402
	var row_h: float = 30
	for i in range(rows.size()):
		var ry: float = rows_y + i * row_h + 22  # +22 for baseline offset inside the row
		c.draw_string(font, Vector2(rows_x + 8, ry), str(rows[i][0]), HORIZONTAL_ALIGNMENT_LEFT, rows_w - 16, PsoStartMenu.FONT_SIZE, PsoStartMenu.C_TEXT_MUTED)
		# Right-align value within the same row box so long strings don't overflow off-screen.
		c.draw_string(font, Vector2(rows_x + 8, ry), str(rows[i][1]), HORIZONTAL_ALIGNMENT_RIGHT, rows_w - 16, PsoStartMenu.FONT_SIZE, PsoStartMenu.C_TEXT)


func _draw_items(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Items")
	var inv: Array = _c._get_inventory()

	var px: float = 5.0
	var py: float = PsoStartMenu.VIEWPORT_H - 305.0
	var pw: float = 300.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))

	# Slot count header
	c.draw_string(font, Vector2(px + 10, py + 14), "%d/40 slots" % Inventory.get_total_slots(), HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_XS, PsoStartMenu.C_TEXT_MUTED)

	# Two-pass scroll calc: each row is one fixed-height entry now that
	# category banners are gone. Type is shown via the per-row icon instead.
	var content_y: float = 20.0
	var item_positions: Array = []
	for _i in range(inv.size()):
		item_positions.append(content_y)
		content_y += 22

	var view_h: float = ph - 6
	if _c._sub_idx >= 0 and _c._sub_idx < item_positions.size():
		var sel_y: float = item_positions[_c._sub_idx]
		if sel_y - _c._item_scroll < 20:
			_c._item_scroll = int(sel_y - 20)
		elif sel_y - _c._item_scroll + 22 > view_h:
			_c._item_scroll = int(sel_y + 22 - view_h)
	_c._item_scroll = maxf(_c._item_scroll, 0.0)

	# Origin row index when the player is mid-Manual-sort, so we can paint
	# it distinctively (cool blue) — distinct from the orange selection tint.
	var move_idx: int = _c._move_from_idx if _c._mode == PsoStartMenu.Mode.ITEMS_MOVE else -1

	# Draw pass
	var draw_y: float = py + 20.0 - _c._item_scroll
	for i in range(inv.size()):
		if draw_y + 22 < py or draw_y > py + ph:
			draw_y += 22
			continue
		var item: Dictionary = inv[i]
		var is_sel: bool = i == _c._sub_idx
		var is_move_origin: bool = i == move_idx

		if is_sel:
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 20), PsoStartMenu.C_SELECT)
		elif is_move_origin:
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 20), Color(0.34, 0.55, 0.85))
		else:
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 20), Color(1, 1, 1, 0.85))
		var item_id: String = str(item.get("id", ""))
		var category: String = str(item.get("category", "Other"))
		var is_equipped: bool = bool(item.get("equipped", false))
		var mute := _item_mute_state(item_id)
		var cannot_use: bool = mute[0]
		# Grey-without-✕: a disk already known at this level (or below the required
		# player level) — same temporary-block predicate the shops/storage use.
		var soft_disabled: bool = mute[1]

		var is_highlight: bool = is_sel or is_move_origin
		# Disabled = the class can never use it (✕) OR it's temporarily useless (a
		# disk already known at this level / below the required level). A highlighted
		# row stays readable so the cursor is visible even on a disabled item.
		var disabled: bool = (cannot_use or soft_disabled) and not is_highlight
		var col: Color = PsoStartMenu.C_SELECT_TEXT if is_highlight else PsoStartMenu.C_TEXT
		if disabled:
			col = PsoStartMenu.C_TEXT_DISABLED

		# Leftmost fixed marker slot (✕ can't-use / [E] equipped / empty),
		# reserved on every row so item names stay aligned — same convention as
		# the shops and storage. ✕ takes precedence (equipped gear is equippable).
		if cannot_use:
			c.draw_texture_rect(PszStyle.cannot_use_icon(), Rect2(px + 6, draw_y + 2, 16, 16), false)
		elif is_equipped:
			c.draw_string(font, Vector2(px + 6, draw_y + 14), "[E]", HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_XS, col)

		# Per-item icon (PNG when known, fallback to colored letter block), shifted
		# right past the marker slot.
		var icon_rect := Rect2(px + 24, draw_y + 2, 16, 16)
		# Disabled rows dim their icon too (alpha modulate), so the whole row reads
		# as greyed — not just the text — making "you can't use this" unmissable.
		var icon_mod: Color = Color(1, 1, 1, 0.35) if disabled else Color.WHITE
		var tex: Texture2D = _c._get_item_icon(item_id, category)
		if tex:
			c.draw_texture_rect(tex, icon_rect, false, icon_mod)
		else:
			var type_key: String = _c._category_to_type(category)
			var icon_letter: String = str(PsoStartMenu.TYPE_ICONS.get(type_key, "?"))
			var icon_color: Color = PsoStartMenu.TYPE_COLORS.get(type_key, Color.GRAY)
			if is_sel or is_move_origin:
				icon_color = Color(1, 1, 1, 0.4)
			elif disabled:
				icon_color = Color(icon_color, 0.4)
			c.draw_rect(icon_rect, icon_color)
			c.draw_string(font, Vector2(px + 27, draw_y + 15), icon_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)

		# Item name (the [E]/✕ marker lives in the leftmost slot, not the name).
		c.draw_string(font, Vector2(px + 46, draw_y + 14), str(item.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_SM, col)

		# Quantity
		var qty: int = int(item.get("quantity", 1))
		if qty > 1:
			c.draw_string(font, Vector2(px + pw - 40, draw_y + 14), "x%d" % qty, HORIZONTAL_ALIGNMENT_RIGHT, -1, PsoStartMenu.FONT_SIZE_XS, Color(col, 0.7))

		draw_y += 22

	# Description
	var desc: String = ""
	if _c._sub_idx < inv.size():
		var item: Dictionary = inv[_c._sub_idx]
		var item_id: String = str(item.get("id", ""))
		var base_id: String = Inventory.get_base_id(item_id)
		desc = str(item.get("name", ""))
		# Try to get details from registries
		var weapon = WeaponRegistry.get_weapon(base_id)
		if weapon:
			desc += "\nATK: %d  ACC: %d" % [weapon.attack_base, weapon.accuracy_base]
			if not weapon.element.is_empty() and weapon.element != "None":
				desc += "\nElement: %s" % weapon.element
		var armor = ArmorRegistry.get_armor(base_id)
		if armor:
			var slots: int = EquipmentUtils.get_unit_slot_count(item_id, CharacterManager.get_active_character())
			desc += "\nDEF: %d  EVA: %d\nSlots: %d" % [armor.defense_base, armor.evasion_base, slots]
		var consumable = ConsumableRegistry.get_consumable(item_id)
		if consumable and not str(consumable.details).is_empty():
			desc += "\n%s" % str(consumable.details)
		# Technique disks: show what they teach and the use prompt. Parse from the
		# BASE id, not the raw instance id — a duplicate disk's id is "disk_foie_3#2"
		# and the raw suffix would leak into the teach-line as "Lv.3#2" (#417).
		if item_id.begins_with("disk_"):
			var rest := Inventory.get_base_id(item_id).substr(5)
			var us := rest.rfind("_")
			if us >= 0:
				var tech_id := rest.substr(0, us)
				var tech_lvl := rest.substr(us + 1)
				var tech_name := tech_id.capitalize()
				if TechniqueManager.TECHNIQUES.has(tech_id):
					tech_name = str(TechniqueManager.TECHNIQUES[tech_id].get("name", tech_name))
				desc += "\nTeaches %s Lv.%s" % [tech_name, tech_lvl]
		if _c._mode == PsoStartMenu.Mode.ITEMS_MOVE:
			desc += "\n[Enter] Move here  [Esc] Cancel"
		else:
			desc += "\n[Enter] Open"
	if not _c._action_message.is_empty():
		desc += "\n\n" + _c._action_message
	_draw_bottom_desc(c, font, desc)


func _draw_equip(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Equip")
	var slots: Array = _c._get_equip_slots()
	var idx: int = _c._sub_idx if _c._mode == PsoStartMenu.Mode.EQUIP else _c._equip_slot_idx
	if idx >= slots.size():
		idx = 0

	# Custom equip list with headers and white rows
	var px: float = 5.0
	var py: float = PsoStartMenu.VIEWPORT_H - 305.0
	var pw: float = 300.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))

	var draw_y: float = py + 4
	var last_type := ""
	for i in range(slots.size()):
		var s: Dictionary = slots[i]
		var slot_type: String = str(s.get("type", ""))

		# Section header for each type group
		var header := ""
		match slot_type:
			"weapon": header = "Weapon" if last_type != "weapon" else ""
			"armor": header = "Armor" if last_type != "armor" else ""
			"unit": header = "Units" if last_type != "unit" else ""
			"mag": header = "Mag" if last_type != "mag" else ""
		if not header.is_empty():
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 18), Color(0.12, 0.16, 0.28))
			c.draw_string(font, Vector2(px + 8, draw_y + 13), header, HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_XS, PsoStartMenu.C_TEXT_LIGHT)
			draw_y += 20
		last_type = slot_type

		var is_sel: bool = i == idx
		if is_sel:
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 22), PsoStartMenu.C_SELECT)
		else:
			c.draw_rect(Rect2(px + 2, draw_y, pw - 4, 22), Color(1, 1, 1, 0.85))
		var col: Color = PsoStartMenu.C_SELECT_TEXT if is_sel else PsoStartMenu.C_TEXT

		# Slot label
		var slot_label: String = str(s.get("label", ""))
		c.draw_string(font, Vector2(px + 8, draw_y + 16), slot_label, HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_SM, Color(col, 0.6) if not is_sel else col)

		# Item name — look up proper display name
		var item_id: String = str(s.get("item", ""))
		var display_name: String = "--"
		if not item_id.is_empty():
			var info: Dictionary = Inventory._lookup_item(item_id)
			display_name = str(info.get("name", item_id))
		c.draw_string(font, Vector2(px + 80, draw_y + 16), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_SM, col)

		draw_y += 24

	if _c._mode == PsoStartMenu.Mode.EQUIP_PICK:
		_draw_equip_picker(c, font)
	else:
		var desc: String = ""
		var desc_idx: int = _c._sub_idx if _c._sub_idx < slots.size() else 0
		if desc_idx < slots.size():
			var item_id: String = str(slots[desc_idx].get("item", ""))
			if not item_id.is_empty():
				var info: Dictionary = Inventory._lookup_item(item_id)
				desc = str(info.get("name", item_id))
				var wdata = WeaponRegistry.get_weapon(Inventory.get_base_id(item_id))
				var adata = ArmorRegistry.get_armor(Inventory.get_base_id(item_id))
				if wdata:
					desc += "\nATK: %d  ACC: %d" % [wdata.attack_base, wdata.accuracy_base]
					if not wdata.element.is_empty() and wdata.element != "None":
						desc += "\nElement: %s" % wdata.element
				elif adata:
					var aslots: int = EquipmentUtils.get_unit_slot_count(item_id, CharacterManager.get_active_character())
					desc += "\nDEF: %d  EVA: %d\nSlots: %d" % [adata.defense_base, adata.evasion_base, aslots]
			else:
				desc = "Empty slot\n\n[Enter] Equip"
		_draw_bottom_desc(c, font, desc)


func _draw_equip_picker(c: Control, font: Font) -> void:
	var candidates: Array = _c._get_equip_candidates(_c._equip_slot_idx)
	var px: float = 310.0
	var py: float = PsoStartMenu.VIEWPORT_H - 305.0
	var pw: float = 200.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	for i in range(candidates.size()):
		var iy: float = py + 4 + i * 24
		if i == _c._equip_item_idx:
			c.draw_rect(Rect2(px + 2, iy, pw - 4, 22), PsoStartMenu.C_SELECT)
		var col: Color = PsoStartMenu.C_SELECT_TEXT if i == _c._equip_item_idx else PsoStartMenu.C_TEXT
		c.draw_string(font, Vector2(px + 10, iy + 16), str(candidates[i].get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_SM, col)


func _draw_techs(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Techs")
	var techs: Array = _c._get_techniques()
	var in_field: bool = _c._is_in_field()

	# Draw tech list
	var px: float = 5.0
	var py: float = PsoStartMenu.VIEWPORT_H - 305.0
	var pw: float = 300.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))

	var scroll_offset: int = maxi(0, _c._sub_idx - 11)
	for i in range(techs.size()):
		var draw_i: int = i - scroll_offset
		if draw_i < 0:
			continue
		var iy: float = py + 4 + draw_i * 24
		if iy > py + ph - 6:
			break
		var tech: Dictionary = techs[i]
		var is_sel: bool = i == _c._sub_idx
		var learned: bool = tech.get("learned", false)

		if is_sel:
			c.draw_rect(Rect2(px + 2, iy, pw - 4, 22), PsoStartMenu.C_SELECT)

		var col: Color
		if is_sel:
			col = PsoStartMenu.C_SELECT_TEXT
		elif not learned:
			col = Color(0.5, 0.5, 0.5)
		else:
			col = PsoStartMenu.C_TEXT

		# Tech icon
		var icon: Texture2D = _c._get_action_icon(str(tech.get("id", "")))
		if icon:
			if not learned:
				c.draw_texture_rect(icon, Rect2(px + 6, iy + 1, 20, 20), false, Color(0.4, 0.4, 0.4))
			else:
				c.draw_texture_rect(icon, Rect2(px + 6, iy + 1, 20, 20), false)

		# Tech name
		var level_str: String = "Lv%d" % tech.level if learned else "--"
		c.draw_string(font, Vector2(px + 30, iy + 16), str(tech.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_SM, col)
		c.draw_string(font, Vector2(px + pw - 80, iy + 16), level_str, HORIZONTAL_ALIGNMENT_RIGHT, -1, PsoStartMenu.FONT_SIZE_XS, col)
		c.draw_string(font, Vector2(px + pw - 30, iy + 16), "%dPP" % tech.pp, HORIZONTAL_ALIGNMENT_RIGHT, -1, PsoStartMenu.FONT_SIZE_XS, col)

	# Description
	var desc: String = ""
	if _c._sub_idx < techs.size():
		var tech: Dictionary = techs[_c._sub_idx]
		var td: Dictionary = TechniqueManager.TECHNIQUES.get(str(tech.get("id", "")), {})
		desc = str(td.get("name", ""))
		desc += "\n%s element" % str(td.get("element", "none")).capitalize()
		desc += "\nPP: %d" % int(td.get("pp", 0))
		desc += "\nTarget: %s" % str(td.get("target", "single")).capitalize()
		desc += "\nMax Level: %d" % tech.max_level
		if tech.get("learned", false):
			desc += "\nCurrent: Lv %d" % tech.level
			if in_field:
				desc += "\n\n[Enter] Cast"
			else:
				desc += "\n\n(Only in field)"
		else:
			desc += "\n\nNot yet learned"
	_draw_bottom_desc(c, font, desc)


func _draw_palette(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Palette")

	var base_y: float = PsoStartMenu.VIEWPORT_H - PsoStartMenu.BOTTOM_H + 8
	var panel_h: float = PsoStartMenu.BOTTOM_H - 16

	# Left side: page tabs + HUD preview + slot list
	var lx: float = 5.0
	var lw: float = 230.0
	_draw_inner_panel(c, Rect2(lx, base_y, lw, panel_h))
	_draw_scanlines(c, Rect2(lx, base_y, lw, panel_h))

	# Page tabs
	var tab_y: float = base_y + 8
	for pi in range(ActionPalette.pages.size()):
		var tab_x: float = lx + 10 + pi * 70
		var is_active: bool = pi == _c._pal_page_idx
		if is_active:
			c.draw_rect(Rect2(tab_x, tab_y, 60, 24), PsoStartMenu.C_SELECT)
		c.draw_string(font, Vector2(tab_x + 10, tab_y + 18), "Page %d" % (pi + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_SM, PsoStartMenu.C_SELECT_TEXT if is_active else PsoStartMenu.C_TEXT_MUTED)

	# HUD preview with palette_bg. Fetch via the autoload's cached getter rather
	# than load()-ing inline every draw: the menu survives area transitions, and
	# an uncached load() could transiently miss on a post-transition redraw and
	# silently skip the background until the player re-entered the page (#421).
	var hud_y: float = tab_y + 34
	var hud_scale: float = 1.7
	var bg_tex: Texture2D = _c._get_palette_bg(_c._pal_page_idx)
	if bg_tex:
		c.draw_texture_rect(bg_tex, Rect2(lx + 8, hud_y, 128.0 * hud_scale, 67.0 * hud_scale), false)

	var slot_centers := [Vector2(26.0, 27.0), Vector2(58.0, 41.0), Vector2(90.0, 27.0)]
	var page: Array = ActionPalette.pages[_c._pal_page_idx]
	for si in range(3):
		var center: Vector2 = slot_centers[si] * hud_scale + Vector2(lx + 8, hud_y)
		var icon: Texture2D = _c._get_action_icon(page[si])
		if icon:
			c.draw_texture_rect(icon, Rect2(center.x - 16, center.y - 16, 32, 32), false)
		if si == _c._pal_slot_idx:
			c.draw_rect(Rect2(center.x - 18, center.y - 18, 36, 36), Color(0.3, 0.8, 0.3, 0.8), false, 2.0)

	# Slot list under preview
	var slot_y: float = hud_y + 67.0 * hud_scale + 10
	var browsing: bool = _c._mode == PsoStartMenu.Mode.PALETTE
	var picking: bool = _c._mode == PsoStartMenu.Mode.PALETTE_PICK
	for si in range(3):
		var action_id: String = str(page[si])
		var data: Dictionary = ActionPalette.get_action_data(action_id)
		var label: String = str(data.get("label", action_id))
		var is_sel: bool = si == _c._pal_slot_idx
		var row_y: float = slot_y + si * 30

		if is_sel and browsing:
			c.draw_rect(Rect2(lx + 4, row_y, lw - 8, 28), PsoStartMenu.C_SELECT)
		elif is_sel and picking:
			c.draw_rect(Rect2(lx + 4, row_y, lw - 8, 28), Color(0.12, 0.18, 0.35, 0.9))

		var slot_col: Color
		var label_col: Color
		if is_sel and browsing:
			slot_col = PsoStartMenu.C_SELECT_TEXT
			label_col = PsoStartMenu.C_SELECT_TEXT
		elif is_sel and picking:
			slot_col = PsoStartMenu.C_TEXT_LIGHT
			label_col = PsoStartMenu.C_TEXT_LIGHT
		else:
			slot_col = PsoStartMenu.C_TEXT_MUTED
			label_col = PsoStartMenu.C_TEXT
		c.draw_string(font, Vector2(lx + 12, row_y + 20), "Slot %d" % (si + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_SM, slot_col)
		c.draw_string(font, Vector2(lx + 78, row_y + 20), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE, label_col)

	# Actions panel (single rect for both columns)
	var mx: float = 240.0
	var mw: float = 280.0
	var rx: float = 524.0
	var rw: float = 280.0
	var total_w: float = (rx + rw) - mx
	_draw_inner_panel(c, Rect2(mx, base_y, total_w, panel_h))
	_draw_scanlines(c, Rect2(mx, base_y, total_w, panel_h))

	var sel_flat: int = _c._sub_idx if _c._mode == PsoStartMenu.Mode.PALETTE_PICK else -1
	var current_id: String = str(page[_c._pal_slot_idx])
	_draw_palette_grid_split(c, font, mx, base_y, mw, rx, base_y, rw, panel_h, current_id, sel_flat)


const _PAL_COMBAT_RECOVERY_ROWS: Array = [
	{"label": "Combat", "ids": ["attack", "strong_attack", "dodge"]},
	{"label": "Recovery", "ids": ["monomate", "dimate", "trimate"]},
	{"ids": ["monofluid", "difluid", "trifluid"]},
	{"ids": ["sol_atomizer", "star_atomizer", "moon_atomizer"]},
	{"ids": ["telepipe", "kill_all"]},
]

const _PAL_TECHNIQUE_ROWS: Array = [
	{"label": "Technique", "ids": ["foie", "barta", "zonde"]},
	{"ids": ["grants", "megid"]},
	{"ids": ["resta", "anti"]},
	{"ids": ["shifta", "deband"]},
	{"ids": ["jellen", "zalure"]},
]


func _draw_palette_grid_split(c: Control, font: Font, mx: float, my: float, mw: float, rx: float, ry: float, rw: float, ph: float, current_id: String, selected_flat: int) -> void:
	var flat_idx: int = 0
	flat_idx = _draw_palette_column(c, font, mx, my, mw, ph, _PAL_COMBAT_RECOVERY_ROWS, current_id, selected_flat, flat_idx)
	_draw_palette_column(c, font, rx, ry, rw, ph, _PAL_TECHNIQUE_ROWS, current_id, selected_flat, flat_idx)


func _draw_palette_column(c: Control, font: Font, px: float, py: float, pw: float, _ph: float, rows: Array, _current_id: String, selected_flat: int, start_flat: int) -> int:
	var cell_h: float = 36.0
	var icon_sz: float = 30.0
	var draw_y: float = py + 6
	var flat_idx: int = start_flat

	for row_def in rows:
		if row_def.has("label"):
			c.draw_string(font, Vector2(px + 10, draw_y + 18), str(row_def.label),
				HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE, PsoStartMenu.C_TEXT_LIGHT)
			draw_y += 26

		var row_ids: Array = row_def.ids
		var cell_w: float = (pw - 12.0) / 3.0
		for ci in range(row_ids.size()):
			var action_id: String = row_ids[ci]
			var data: Dictionary = ActionPalette.get_action_data(action_id)
			var label: String = str(data.get("label", action_id))
			var is_sel: bool = flat_idx == selected_flat
			var available: bool = _c._is_palette_action_available(action_id)

			var cx: float = px + 6 + ci * cell_w

			if is_sel:
				c.draw_rect(Rect2(cx, draw_y, cell_w - 2, cell_h), PsoStartMenu.C_SELECT)

			var icon_y: float = draw_y + (cell_h - icon_sz) * 0.5
			c.draw_rect(Rect2(cx + 3, icon_y, icon_sz, icon_sz), Color(0.05, 0.05, 0.1, 0.9))
			var icon: Texture2D = _c._get_action_icon(action_id)
			if icon:
				var icon_mod: Color = Color(0.4, 0.4, 0.4) if not available else Color.WHITE
				c.draw_texture_rect(icon, Rect2(cx + 3, icon_y, icon_sz, icon_sz), false, icon_mod)

			var col: Color
			if is_sel:
				col = PsoStartMenu.C_SELECT_TEXT
			elif not available:
				col = Color(0.5, 0.5, 0.5)
			else:
				col = PsoStartMenu.C_TEXT
			c.draw_string(font, Vector2(cx + icon_sz + 8, draw_y + 23), label,
				HORIZONTAL_ALIGNMENT_LEFT, cell_w - icon_sz - 12, PsoStartMenu.FONT_SIZE, col)

			flat_idx += 1

		draw_y += cell_h + 2

	return flat_idx


func _draw_mags(c: Control, font: Font) -> void:
	var ch: Dictionary = _c._get_character()
	var mags: Array = _c._get_mags()

	if _c._mode == PsoStartMenu.Mode.MAG_FEED:
		_draw_section_label(c, font, "Feed Mag")

		# Left panel: mag stats with gauge bars
		var px: float = 5.0
		var py: float = PsoStartMenu.VIEWPORT_H - 305.0
		var pw: float = 300.0
		var ph: float = 300.0
		_draw_inner_panel(c, Rect2(px, py, pw, ph))

		var mag_id: String = str(mags[_c._mag_idx].get("id", "")) if _c._mag_idx < mags.size() else ""
		var mag_state: Dictionary = MagManager.get_mag_state(ch, mag_id) if not ch.is_empty() and not mag_id.is_empty() else {}

		var dy: float = py + 4
		if not mag_state.is_empty():
			var form_id: String = str(mag_state.get("form_id", "mag"))
			var form = MagManager.get_mag_form(form_id)
			var form_name: String = form.name if form else "Mag"
			var level: int = MagManager.get_level(mag_state)

			c.draw_rect(Rect2(px + 2, dy, pw - 4, 18), Color(0.12, 0.16, 0.28))
			c.draw_string(font, Vector2(px + 8, dy + 13), "%s  Lv.%d" % [form_name, level], HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_SM, PsoStartMenu.C_TEXT_LIGHT)
			dy += 22

			var stats_dict: Dictionary = mag_state.get("stats", {})
			var stat_colors := {"power": Color(0.9, 0.3, 0.3), "guard": Color(0.3, 0.5, 0.9), "hit": Color(0.3, 0.8, 0.3), "mind": Color(0.7, 0.3, 0.9)}
			var stat_labels := {"power": "POW", "guard": "GRD", "hit": "HIT", "mind": "MND"}
			for stat_key in ["power", "guard", "hit", "mind"]:
				var raw: int = int(stats_dict.get(stat_key, 0))
				var stat_lvl: int = int(raw / MagManager.STATS_PER_LEVEL)
				var gauge: int = raw % MagManager.STATS_PER_LEVEL
				var gauge_pct: float = float(gauge) / float(MagManager.STATS_PER_LEVEL)

				c.draw_rect(Rect2(px + 2, dy, pw - 4, 24), Color(1, 1, 1, 0.85))
				c.draw_string(font, Vector2(px + 8, dy + 17), stat_labels[stat_key], HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_SM, PsoStartMenu.C_TEXT)
				c.draw_string(font, Vector2(px + 55, dy + 17), str(stat_lvl), HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_SM, PsoStartMenu.C_TEXT)
				# Gauge bar
				var bar_x: float = px + 80
				var bar_w: float = pw - 90
				c.draw_rect(Rect2(bar_x, dy + 6, bar_w, 12), Color(0, 0, 0, 0.15))
				if gauge_pct > 0:
					c.draw_rect(Rect2(bar_x, dy + 6, bar_w * gauge_pct, 12), stat_colors[stat_key])
				dy += 26

			dy += 4
			c.draw_rect(Rect2(px + 2, dy, pw - 4, 20), Color(1, 1, 1, 0.85))
			c.draw_string(font, Vector2(px + 8, dy + 14), "Sync: %d/%d" % [int(mag_state.get("sync", 0)), MagManager.MAX_SYNC], HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_XS, PsoStartMenu.C_TEXT_MUTED)
			c.draw_string(font, Vector2(px + 150, dy + 14), "IQ: %d/%d" % [int(mag_state.get("iq", 0)), MagManager.MAX_IQ], HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_XS, PsoStartMenu.C_TEXT_MUTED)
			dy += 22

			if form and not str(form.photon_blast).is_empty():
				c.draw_rect(Rect2(px + 2, dy, pw - 4, 20), Color(1, 1, 1, 0.85))
				c.draw_string(font, Vector2(px + 8, dy + 14), "P.Blast: %s" % str(form.photon_blast), HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_XS, Color(0.2, 0.6, 0.3))
				dy += 22

		# Right panel: feedable items
		var feed: Array = _c._get_feed_items()
		var dpx: float = 310.0
		var dpy: float = PsoStartMenu.VIEWPORT_H - 305.0
		var dpw: float = 200.0
		var dph: float = 300.0
		_draw_inner_panel(c, Rect2(dpx, dpy, dpw, dph))
		c.draw_rect(Rect2(dpx + 2, dpy + 2, dpw - 4, 16), Color(0.12, 0.16, 0.28))
		c.draw_string(font, Vector2(dpx + 6, dpy + 14), "Feed Item", HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_XS, PsoStartMenu.C_TEXT_LIGHT)
		var feed_y: float = dpy + 20
		for i in range(feed.size()):
			if feed_y > dpy + dph - 6:
				break
			var is_sel: bool = i == _c._sub_idx
			if is_sel:
				c.draw_rect(Rect2(dpx + 2, feed_y, dpw - 4, 20), PsoStartMenu.C_SELECT)
			else:
				c.draw_rect(Rect2(dpx + 2, feed_y, dpw - 4, 20), Color(1, 1, 1, 0.85))
			var col: Color = PsoStartMenu.C_SELECT_TEXT if is_sel else PsoStartMenu.C_TEXT
			c.draw_string(font, Vector2(dpx + 6, feed_y + 14), str(feed[i].get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_XS, col)
			var qty: int = int(feed[i].get("quantity", 0))
			if qty > 1:
				c.draw_string(font, Vector2(dpx + dpw - 30, feed_y + 14), "x%d" % qty, HORIZONTAL_ALIGNMENT_RIGHT, -1, PsoStartMenu.FONT_SIZE_XS, Color(col, 0.7))
			feed_y += 22
	else:
		_draw_section_label(c, font, "Mags")
		var items: Array = []
		for m in mags:
			var tag: String = " [E]" if m.get("equipped", false) else ""
			items.append({"name": str(m.get("name", "")) + tag, "type": "mag", "equipped": m.get("equipped", false)})
		_draw_bottom_list(c, font, items, _c._sub_idx)
		var desc: String = ""
		if _c._sub_idx < mags.size():
			var mag: Dictionary = mags[_c._sub_idx]
			var mag_state: Dictionary = MagManager.get_mag_state(ch, str(mag.get("id", ""))) if not ch.is_empty() else {}
			if not mag_state.is_empty():
				var form_id: String = str(mag_state.get("form_id", "mag"))
				var form = MagManager.get_mag_form(form_id)
				if form:
					desc += "Form: %s\n" % form.name
					if not str(form.photon_blast).is_empty():
						desc += "P.Blast: %s\n" % str(form.photon_blast)
				var stats_dict: Dictionary = mag_state.get("stats", {})
				for stat_key in ["power", "guard", "hit", "mind"]:
					var raw: int = int(stats_dict.get(stat_key, 0))
					var stat_lvl: int = int(raw / MagManager.STATS_PER_LEVEL)
					desc += "%s: %d\n" % [stat_key.capitalize(), stat_lvl]
				desc += "\n[Enter] Feed"
		_draw_bottom_desc(c, font, desc)


func _draw_quest(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Quest")
	var px: float = 5.0
	var py: float = PsoStartMenu.VIEWPORT_H - 305.0
	var pw: float = 505.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	# TODO: pull real quest data from session
	c.draw_string(font, Vector2(px + 16, py + 30), "No active quest.", HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE, PsoStartMenu.C_TEXT_MUTED)


func _draw_system(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "System")
	var items: Array = []
	for s in PsoStartMenu.SYSTEM_LABELS:
		items.append({"name": s, "type": "tool"})
	_draw_bottom_list(c, font, items, _c._sub_idx)
	var desc: String = PsoStartMenu.SYSTEM_DESCS[_c._sub_idx] if _c._sub_idx < PsoStartMenu.SYSTEM_DESCS.size() else ""
	_draw_bottom_desc(c, font, desc)


func _draw_options(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Options")
	var opts: Array = _c._get_options_list()
	var items: Array = []
	for o in opts:
		items.append({"name": o, "type": "tool"})
	_draw_bottom_list(c, font, items, _c._options_idx)
	_draw_bottom_desc(c, font, "Toggle debug settings.\n\n[Enter] Toggle\n[Esc] Back")


# ── Draw helpers ────────────────────────────────────────────────────────────────
func _draw_inner_panel(c: Control, rect: Rect2) -> void:
	c.draw_rect(rect, PsoStartMenu.C_PANEL)
	c.draw_rect(rect, PsoStartMenu.C_PANEL_BORDER, false, 1.5)


func _draw_section_label(c: Control, font: Font, text: String) -> void:
	var lx := PsoStartMenu.PAD
	var ly := 110.0  # Below the HUD stats panel
	var lw: float = PsoStartMenu.LEFT_W - PsoStartMenu.PAD * 2
	c.draw_rect(Rect2(lx, ly, lw, 28), PsoStartMenu.C_LABEL_BG)
	c.draw_string(font, Vector2(lx + 12, ly + 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE, PsoStartMenu.C_TEXT_LIGHT)


func _draw_bottom_list(c: Control, font: Font, items: Array, selected: int) -> void:
	var px: float = 5.0
	var py: float = PsoStartMenu.VIEWPORT_H - 305.0
	var pw: float = 300.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	# Visible-row count derived from panel size and 22px row height. Scroll
	# the window to keep the selected row in view — same pattern as
	# _draw_techs and _draw_palette_picker.
	const ROW_H: int = 22
	var visible_rows: int = int(floor((ph - 8) / ROW_H))
	var scroll_offset: int = maxi(0, selected - (visible_rows - 1))
	var max_scroll: int = maxi(0, items.size() - visible_rows)
	scroll_offset = mini(scroll_offset, max_scroll)
	for i in range(items.size()):
		var draw_i: int = i - scroll_offset
		if draw_i < 0:
			continue
		var iy: float = py + 4 + draw_i * ROW_H
		if iy > py + ph - ROW_H + 2:
			break
		if i == selected:
			c.draw_rect(Rect2(px + 2, iy, pw - 4, 20), PsoStartMenu.C_SELECT)
		var col: Color = PsoStartMenu.C_SELECT_TEXT if i == selected else PsoStartMenu.C_TEXT
		var item_name: String = str(items[i].get("name", ""))
		var item_type: String = str(items[i].get("type", ""))
		# Type icon: PNG for the few types we have art for, otherwise the
		# colored letter block (System/Options menu rows pass type="tool"
		# even though they aren't items, so we don't try to look those up
		# as inventory items).
		var icon_rect := Rect2(px + 6, iy + 2, 16, 16)
		var tex: Texture2D = null
		match item_type:
			"mag": tex = InventoryIcons.for_item("", "Mag")
		if tex:
			c.draw_texture_rect(tex, icon_rect, false)
		else:
			var icon_letter: String = str(PsoStartMenu.TYPE_ICONS.get(item_type, "?"))
			var icon_color: Color = PsoStartMenu.TYPE_COLORS.get(item_type, Color.GRAY) if i != selected else Color(1, 1, 1, 0.4)
			c.draw_rect(icon_rect, icon_color)
			c.draw_string(font, Vector2(px + 9, iy + 15), icon_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)
		var qty: int = int(items[i].get("quantity", 0))
		var qty_str: String = "x%d" % qty if qty > 1 else ""
		c.draw_string(font, Vector2(px + 28, iy + 15), item_name, HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_SM, col)
		if not qty_str.is_empty():
			c.draw_string(font, Vector2(px + pw - 40, iy + 15), qty_str, HORIZONTAL_ALIGNMENT_RIGHT, -1, PsoStartMenu.FONT_SIZE_XS, Color(col, 0.7))
	# Scroll cue: "▲ more" / "▼ more" hints in the corners when content
	# extends past the visible window.
	if scroll_offset > 0:
		c.draw_string(font, Vector2(px + pw - 60, py + 14), "▲ more", HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_XS, PsoStartMenu.C_TEXT_MUTED)
	if scroll_offset + visible_rows < items.size():
		c.draw_string(font, Vector2(px + pw - 60, py + ph - 8), "▼ more", HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_XS, PsoStartMenu.C_TEXT_MUTED)


func _draw_bottom_desc(c: Control, font: Font, text: String) -> void:
	var px: float = 310.0
	var py: float = PsoStartMenu.VIEWPORT_H - 305.0
	var pw: float = 200.0
	var ph: float = 300.0
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	# Simple multi-line text
	var lines := text.split("\n")
	for i in range(lines.size()):
		c.draw_string(font, Vector2(px + 12, py + 20 + i * 18), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_SM, PsoStartMenu.C_TEXT)

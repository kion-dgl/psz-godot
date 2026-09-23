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

# The start menu draws its text in immediate mode (draw_string), so it doesn't
# pick up the rpg_theme font the way the 2D Control screens do. Preload the same
# face the shops render with (rpg_theme.tres → JetBrainsMono) and draw every
# menu string in it, so the start menu and the shop lists share one typeface
# (#417 — Rozalin: "the font doesn't seem identical"). ThemeDB.fallback_font
# (the old default) is Godot's built-in sans, a different face entirely.
#
# This preload is at class scope, which PsoStartMenu (an autoload) resolves at
# engine boot — BEFORE bootstrap.gd mounts the asset .pck. That is only safe
# because JetBrains Mono is vendored in source and ships IN THE BINARY (it's
# OFL, not a SEGA pack asset — see .gitignore !/assets/fonts/ and the runnable
# export presets, which no longer exclude assets/fonts/). #448 hit exactly this
# trap by preloading the font while it was still pck-gated, blacking out the
# menu in release exports; #450 moved the font into the binary. Do NOT
# class-scope-preload a genuinely pack-only asset here — see
# test_autoloads_avoid_packonly_classscope_preloads.
const MENU_FONT: Font = preload("res://assets/fonts/JetBrainsMono-Regular.ttf")


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
	# The redesigned MAIN page is a node-based skin (StartMenuMainSkin) that
	# covers the viewport while visible; skip the legacy canvas painting so
	# the L-backdrop doesn't bleed around it. Sub-modes still paint here.
	if _c._main_skin != null and _c._main_skin.visible:
		return
	var font: Font = MENU_FONT
	var vp := Vector2(PsoStartMenu.VIEWPORT_W, PsoStartMenu.VIEWPORT_H)

	# The sub-menu port (round 5): ported screens draw the Flauros octagon L
	# and set VT323; everything else keeps the legacy dark look until its turn.
	const FLAUROS_MODES := [PsoStartMenu.Mode.ITEMS, PsoStartMenu.Mode.ITEMS_MOVE]
	if _c._mode in FLAUROS_MODES:
		StartMenuMainSkin.draw_backdrop(c, vp.x, vp.y)
		font = StartMenuMainSkin.FONT
		_draw_items(c, font)
		return

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
		PsoStartMenu.Mode.ITEMS, PsoStartMenu.Mode.ITEMS_MOVE: _draw_items(c, font)
		PsoStartMenu.Mode.EQUIP, PsoStartMenu.Mode.EQUIP_PICK: _draw_equip(c, font)
		PsoStartMenu.Mode.TECHS: _draw_techs(c, font)
		PsoStartMenu.Mode.PALETTE, PsoStartMenu.Mode.PALETTE_PICK: _draw_palette(c, font)
		PsoStartMenu.Mode.MAGS, PsoStartMenu.Mode.MAG_FEED: _draw_mags(c, font)
		PsoStartMenu.Mode.QUEST: _draw_quest(c, font)
		PsoStartMenu.Mode.SYSTEM: _draw_system(c, font)
		PsoStartMenu.Mode.OPTIONS: _draw_options(c, font)
		PsoStartMenu.Mode.DEBUG: _draw_debug(c, font)


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


func _draw_items(c: Control, font: Font) -> void:
	# Flauros port (round 5): same geometry and scroll/mute logic, new chrome.
	var skin := StartMenuMainSkin
	c.draw_string(font, Vector2(PsoStartMenu.PAD + 2.0, 132.0), "Items",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, skin.C_TEXT)
	var inv: Array = _c._get_inventory()

	var px: float = 5.0
	var py: float = PsoStartMenu.VIEWPORT_H - 305.0
	# Wider than the other sub-screens' 300px list (Kion: "make the inventory a bit
	# wider") — the description panel shifts right to match (see the _draw_bottom_desc
	# call below). The bottom backdrop strip is full-width, so there's ample room.
	var pw: float = 340.0
	var ph: float = 300.0
	skin.draw_chamfer_rect(c, Rect2(px, py, pw, ph))

	# Slot count header
	c.draw_string(font, Vector2(px + 16, py + 20), "%d/40 slots" % Inventory.get_total_slots(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, skin.C_INNER_NAVY)

	# Taller rows + the shop's name-font size, so the list reads with the same
	# padding/weight as the 2D shop lists instead of the old cramped 22px/size-13
	# rows (Kion: "align the inventory to have the same padding + margin as the shop").
	const ROW_H := 26
	const ROW_RECT_H := 24
	# Content band the rows live in: below the slot header, inset from the panel
	# bottom so a row never paints past the inner-panel border. The list scrolls by
	# whole rows and is clipped to this band, so it respects the panel's bounds
	# instead of spilling rows out the bottom of the UI (#417 — Kion: "the inventory
	# list in the start menu doesn't respect overflow Y").
	var list_top: float = py + 22.0
	var list_bottom: float = py + ph - 4.0
	var visible_rows: int = int(floor((list_bottom - list_top) / float(ROW_H)))

	# Whole-row scroll window that keeps the selection in view — same model as
	# _draw_bottom_list (no partial rows, nothing drawn past the panel edge).
	var scroll_offset: int = maxi(0, _c._sub_idx - (visible_rows - 1))
	var max_scroll: int = maxi(0, inv.size() - visible_rows)
	scroll_offset = mini(scroll_offset, max_scroll)

	# Origin row index when the player is mid-Manual-sort, so we can paint
	# it distinctively (cool blue) — distinct from the orange selection tint.
	var move_idx: int = _c._move_from_idx if _c._mode == PsoStartMenu.Mode.ITEMS_MOVE else -1

	# Draw pass — only the rows that fully fit the visible window.
	for i in range(inv.size()):
		var draw_i: int = i - scroll_offset
		if draw_i < 0 or draw_i >= visible_rows:
			continue
		var draw_y: float = list_top + draw_i * ROW_H
		# Baseline for text vertically centered in the taller row rect.
		var text_y: float = draw_y + ROW_RECT_H * 0.5 + 5.0
		var icon_y: float = draw_y + (ROW_RECT_H - 16.0) * 0.5
		var item: Dictionary = inv[i]
		var is_sel: bool = i == _c._sub_idx
		var is_move_origin: bool = i == move_idx

		var row_state: int = 1 if is_sel else (2 if is_move_origin else 0)
		skin.draw_menu_row(c, Rect2(px + 2, draw_y, pw - 4, ROW_RECT_H), row_state)
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
		# Dark-on-paper / dark-on-orange text (the mock's palette); disabled
		# items keep the grey.
		var col: Color = skin.C_TEXT
		if disabled:
			col = skin.C_TEXT_DISABLED

		# Leftmost fixed marker slot (✕ can't-use / [E] equipped / empty),
		# reserved on every row so item names stay aligned — same convention as
		# the shops and storage. ✕ takes precedence (equipped gear is equippable).
		# The slot is wide enough for the "[E]" tag so it doesn't crowd the item icon.
		if cannot_use:
			c.draw_texture_rect(PszStyle.cannot_use_icon(), Rect2(px + 8, icon_y, 16, 16), false)
		elif is_equipped:
			c.draw_string(font, Vector2(px + 8, text_y), "[E]", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)

		# Per-item icon (PNG when known, fallback to colored letter block), past the
		# fixed ~26px marker slot so the [E] tag and the icon never overlap.
		var icon_rect := Rect2(px + 32, icon_y, 16, 16)
		# Disabled rows dim their icon too (alpha modulate), so the whole row reads
		# as greyed — not just the text. Same modulate the shops use (#417 parity).
		var icon_mod: Color = PszStyle.DISABLED_ICON_MOD if disabled else Color.WHITE
		var tex: Texture2D = _c._get_item_icon(item_id, category)
		if tex:
			c.draw_texture_rect(tex, icon_rect, false, icon_mod)
		else:
			var type_key: String = _c._category_to_type(category)
			var icon_letter: String = str(PsoStartMenu.TYPE_ICONS.get(type_key, "?"))
			var icon_color: Color = PsoStartMenu.TYPE_COLORS.get(type_key, Color.GRAY)
			if is_highlight:
				icon_color = Color(1, 1, 1, 0.4)
			elif disabled:
				icon_color = Color(icon_color, 0.4)
			c.draw_rect(icon_rect, icon_color)
			c.draw_string(font, Vector2(px + 35, icon_y + 13), icon_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

		# Item name (the [E]/✕ marker lives in the leftmost slot, not the name).
		c.draw_string(font, Vector2(px + 54, text_y), str(item.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)

		# Quantity
		var qty: int = int(item.get("quantity", 1))
		if qty > 1:
			c.draw_string(font, Vector2(px + pw - 40, text_y), "x%d" % qty, HORIZONTAL_ALIGNMENT_RIGHT, -1, 15, Color(col, 0.7))

	# Scroll cues when the list extends past the visible window (matches the
	# ▲/▼ hints the other start-menu lists draw via _draw_bottom_list).
	# VT323 has no arrow glyphs — ASCII cues (the MAIN footer drew vector
	# triangles for the same reason).
	if scroll_offset > 0:
		c.draw_string(font, Vector2(px + pw - 70, py + 20), "^ more", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, skin.C_INNER_NAVY)
	if scroll_offset + visible_rows < inv.size():
		c.draw_string(font, Vector2(px + pw - 70, py + ph - 10), "v more", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, skin.C_INNER_NAVY)

	# Description sits to the right of the (wider) items list, not the default 310px.
	_draw_bottom_desc(c, font, _items_description(inv), 350.0, 380.0, true)


## The detail text for the currently-selected inventory item — stats from the
## registries, the disk teach-line, and the contextual prompt. Split out of
## _draw_items so that routine doesn't fan out across every registry (#295
## god-orchestrator bound).
func _items_description(inv: Array) -> String:
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
	return desc


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
			# Icons are cropped 20x20 (content fills the frame); a 24px box
			# centered on the slot renders them without the old up-left offset.
			c.draw_texture_rect(icon, Rect2(center.x - 12, center.y - 12, 24, 24), false)
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


## Both columns come from PsoStartMenu._PAL_PICKER_ROWS — the same table the
## input layer navigates. They used to be separate consts here, so the drawn
## grid and the navigable grid could drift apart without anything noticing.
func _draw_palette_grid_split(c: Control, font: Font, mx: float, my: float, mw: float, rx: float, ry: float, rw: float, ph: float, current_id: String, selected_flat: int) -> void:
	var rows: Array = PsoStartMenu._PAL_PICKER_ROWS
	var split: int = PsoStartMenu._PAL_LEFT_COL_SIZE
	var flat_idx: int = 0
	flat_idx = _draw_palette_column(c, font, mx, my, mw, ph, rows.slice(0, split), current_id, selected_flat, flat_idx)
	_draw_palette_column(c, font, rx, ry, rw, ph, rows.slice(split), current_id, selected_flat, flat_idx)


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
		# Three cells is the normal width; a longer row (Traps has four) packs
		# tighter rather than overflowing the panel. At four across there is no
		# room for an icon box AND readable text, so those cells drop the icon
		# and use the action's `short` name across the full cell.
		var per_row: int = maxi(3, row_ids.size())
		var cell_w: float = (pw - 12.0) / float(per_row)
		var tight: bool = row_ids.size() > 3
		for ci in range(row_ids.size()):
			var action_id: String = row_ids[ci]
			var data: Dictionary = ActionPalette.get_action_data(action_id)
			var label: String = str(data.get("short", "") if tight else data.get("label", action_id))
			if label.is_empty():
				label = str(data.get("label", action_id))
			var is_sel: bool = flat_idx == selected_flat
			var available: bool = _c._is_palette_action_available(action_id)

			var cx: float = px + 6 + ci * cell_w

			if is_sel:
				c.draw_rect(Rect2(cx, draw_y, cell_w - 2, cell_h), PsoStartMenu.C_SELECT)

			var text_x: float = cx + 3
			if not tight:
				var icon_y: float = draw_y + (cell_h - icon_sz) * 0.5
				c.draw_rect(Rect2(cx + 3, icon_y, icon_sz, icon_sz), Color(0.05, 0.05, 0.1, 0.9))
				var icon: Texture2D = _c._get_action_icon(action_id)
				if icon:
					var icon_mod: Color = Color(0.4, 0.4, 0.4) if not available else Color.WHITE
					c.draw_texture_rect(icon, Rect2(cx + 3, icon_y, icon_sz, icon_sz), false, icon_mod)
				text_x = cx + icon_sz + 8

			var col: Color
			if is_sel:
				col = PsoStartMenu.C_SELECT_TEXT
			elif not available:
				col = Color(0.5, 0.5, 0.5)
			else:
				col = PsoStartMenu.C_TEXT
			c.draw_string(font, Vector2(text_x, draw_y + 23), label,
				HORIZONTAL_ALIGNMENT_LEFT, cx + cell_w - 6 - text_x, PsoStartMenu.FONT_SIZE, col)

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
	_draw_bottom_desc(c, font, "Adjust game settings.\n\n[Enter] Select\n[Esc] Back")


func _draw_debug(c: Control, font: Font) -> void:
	_draw_section_label(c, font, "Debug")
	var rows: Array = _c._get_debug_list()
	var items: Array = []
	for o in rows:
		items.append({"name": o, "type": "tool"})
	_draw_bottom_list(c, font, items, _c._debug_idx)
	var desc: String = _c._debug_msg if _c._debug_msg != "" else "Debug tools and cheats.\n\n[Enter] Select\n[Esc] Back"
	_draw_bottom_desc(c, font, desc)


# ── Draw helpers ────────────────────────────────────────────────────────────────
# Cached rounded panel style for the inner list/desc panels — rounded corners +
# a border, drawn via draw_style_box so the start menu's panels read like the 2D
# shop's rounded cards (Kion: "add some border radius … closer to the look of the
# shop") instead of the old hard-cornered draw_rect. Built once, reused per frame.
var _panel_sbox: StyleBoxFlat = null


func _inner_panel_sbox() -> StyleBoxFlat:
	if _panel_sbox == null:
		var s := StyleBoxFlat.new()
		s.bg_color = PsoStartMenu.C_PANEL
		s.border_color = PsoStartMenu.C_PANEL_BORDER
		s.set_border_width_all(2)
		s.set_corner_radius_all(6)
		_panel_sbox = s
	return _panel_sbox


func _draw_inner_panel(c: Control, rect: Rect2) -> void:
	c.draw_style_box(_inner_panel_sbox(), rect)


# Reusable rounded-rect style for list ROWS (the inventory pills) so they read like
# the 2D shop's rounded list rows instead of hard-cornered bars (Kion). One
# instance, recoloured per row — draw_style_box paints with the current bg_color
# synchronously, so reusing it across rows in a frame is safe.
var _row_sbox: StyleBoxFlat = null


func _draw_row_pill(c: Control, rect: Rect2, color: Color) -> void:
	if _row_sbox == null:
		_row_sbox = StyleBoxFlat.new()
		_row_sbox.set_corner_radius_all(4)
	_row_sbox.bg_color = color
	c.draw_style_box(_row_sbox, rect)


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


func _draw_bottom_desc(c: Control, font: Font, text: String, px: float = 310.0, pw: float = 200.0, flauros := false) -> void:
	var py: float = PsoStartMenu.VIEWPORT_H - 305.0
	var ph: float = 300.0
	var lines := text.split("\n")
	if flauros:
		StartMenuMainSkin.draw_chamfer_rect(c, Rect2(px, py, pw, ph))
		for i in range(lines.size()):
			c.draw_string(font, Vector2(px + 16, py + 28 + i * 24), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, StartMenuMainSkin.C_TEXT)
		return
	_draw_inner_panel(c, Rect2(px, py, pw, ph))
	# Simple multi-line text
	for i in range(lines.size()):
		c.draw_string(font, Vector2(px + 12, py + 20 + i * 18), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, PsoStartMenu.FONT_SIZE_SM, PsoStartMenu.C_TEXT)

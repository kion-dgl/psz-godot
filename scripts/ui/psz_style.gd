class_name PszStyle
## PSZ menu style utilities — pale icy blue palette with pill rows and tab buttons.

# ── Panel Colors ──
const BG := Color(0.66, 0.80, 0.91)
const BG_BORDER := Color(0.48, 0.63, 0.75)
const TITLE_BG := Color(0.16, 0.20, 0.28)
const INNER_BG := Color(1.0, 1.0, 1.0, 0.3)
const INNER_BORDER := Color(0.59, 0.71, 0.82, 0.4)
const SCANLINE := Color(0.47, 0.63, 0.78, 0.08)

# ── Pill / Tab Colors ──
const PILL_BG := Color(1.0, 1.0, 1.0, 0.85)
const PILL_BORDER := Color(0.59, 0.71, 0.82, 0.4)
const SEL_BG := Color(0.94, 0.63, 0.13)
const SEL_BORDER := Color(0.82, 0.5, 0.06)
const HINT_BG := Color(1.0, 1.0, 1.0, 0.7)

# Diegetic shop overlay geometry (see setup_shop_portrait / spec presentation).
# The menu occupies the left of the 1280×720 frame; RIGHT_RESERVE keeps the
# right free for the 3D shopkeeper the camera frames there.
const LEFT_MARGIN := 24.0
const TOP_MARGIN := 24.0
const BOTTOM_MARGIN := 24.0
const RIGHT_RESERVE := 486.0   # right edge lands at x≈794 of 1280
const DETAIL_HEIGHT := 288.0   # info card height (~40% of 720)

# Pinned column widths (#626): body + 12px separation + detail = 770 = the fixed
# panel width, so the split is constant across every shop/tab/selection. Text must
# wrap/truncate inside these (see detail_label / the row label) — an unwrapped
# Label's width becomes its card's minimum width and the split drifts again.
# Detail matches the web fixture's 320 (web/src/shop-3d/parts.tsx ShopColumns).
const SHOP_BODY_W := 438.0
const SHOP_DETAIL_W := 320.0

# ── Text Colors ──
const TEXT := Color(0.1, 0.1, 0.17)
const TEXT_WHITE := Color(1.0, 1.0, 1.0)
const TEXT_LIGHT := Color(0.23, 0.29, 0.35)
const TEXT_MUTED := Color(0.40, 0.45, 0.55)
const TEXT_DANGER := Color(0.80, 0.20, 0.20)
const TEXT_WARNING := Color(0.75, 0.50, 0.08)
const TEXT_SUCCESS := Color(0.13, 0.53, 0.13)
const TEXT_QUEST := Color(0.30, 0.38, 0.60)
const TEXT_CLEAR := Color(0.20, 0.50, 0.25)
const TEXT_HIGHLIGHT := Color(0.82, 0.45, 0.05)
const TEXT_MESETA := Color(0.82, 0.58, 0.05)

## Icon modulate for a muted/disabled list row — the row's leading item icon is
## dimmed along with its text so the WHOLE row reads as greyed, not just the
## label. Shared with the 3D start-menu inventory (PsoStartMenu references this)
## so the shops and the inventory dim icons identically (#417).
const DISABLED_ICON_MOD := Color(1, 1, 1, 0.35)

# ── Font Sizes ──
const FONT_TITLE := 16
const FONT_ITEM := 14
const FONT_HINT := 13
const FONT_DETAIL := 13
const FONT_TAB := 12


static func pill_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if selected:
		s.bg_color = SEL_BG
		s.border_color = SEL_BORDER
		s.border_width_left = 2
		s.border_width_top = 2
		s.border_width_right = 2
		s.border_width_bottom = 2
	else:
		s.bg_color = PILL_BG
		s.border_color = PILL_BORDER
		s.border_width_left = 1
		s.border_width_top = 1
		s.border_width_right = 1
		s.border_width_bottom = 1
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_right = 3
	s.corner_radius_bottom_left = 3
	s.content_margin_left = 10.0
	s.content_margin_right = 10.0
	s.content_margin_top = 5.0
	s.content_margin_bottom = 5.0
	return s


## Apply the pill style (selected → orange, else white) to every visual state of
## a Button. Extracted so the confirm / choice / defeat modals don't each re-roll
## the identical five add_theme_stylebox_override calls (code-health dedup, #294).
static func apply_pill_button_style(btn: Button, selected: bool) -> void:
	var style := pill_style(selected)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, style)


static func tab_style(active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if active:
		s.bg_color = SEL_BG
		s.border_color = SEL_BORDER
		s.border_width_left = 2
		s.border_width_top = 2
		s.border_width_right = 2
		s.border_width_bottom = 2
	else:
		s.bg_color = PILL_BG
		s.border_color = PILL_BORDER
		s.border_width_left = 1
		s.border_width_top = 1
		s.border_width_right = 1
		s.border_width_bottom = 1
	s.corner_radius_top_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_right = 4
	s.corner_radius_bottom_left = 4
	s.content_margin_left = 12.0
	s.content_margin_right = 12.0
	s.content_margin_top = 4.0
	s.content_margin_bottom = 4.0
	return s


static func title_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = TITLE_BG
	s.content_margin_left = 14.0
	s.content_margin_right = 14.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	return s


static func hint_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = HINT_BG
	s.border_color = BG_BORDER
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.corner_radius_bottom_left = 12
	s.corner_radius_bottom_right = 12
	s.content_margin_left = 14.0
	s.content_margin_right = 14.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s


static func inner_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = INNER_BG
	s.border_color = INNER_BORDER
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_right = 6
	s.corner_radius_bottom_left = 6
	s.content_margin_left = 8.0
	s.content_margin_top = 8.0
	s.content_margin_right = 8.0
	s.content_margin_bottom = 8.0
	return s


static func section_header_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.48, 0.63, 0.75, 0.3)
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_right = 3
	s.corner_radius_bottom_left = 3
	s.content_margin_left = 10.0
	s.content_margin_right = 10.0
	s.content_margin_top = 3.0
	s.content_margin_bottom = 3.0
	return s


static func create_pill(left_text: String, selected: bool, right_text: String = "", text_color := Color.TRANSPARENT) -> PanelContainer:
	return create_pill_with_icons([], left_text, selected, right_text, text_color)


## Same as create_pill but with an optional row of icons in front of
## the label. Pass an empty array to get the plain create_pill output.
## Each icon renders as a 16×16 TextureRect; nulls in the array are
## skipped so callers can pass [type_icon, rarity_icon] without
## branching on missing assets.
static func create_pill_with_icons(icons: Array, left_text: String, selected: bool, right_text: String = "", text_color := Color.TRANSPARENT, lead: Control = null, dim_icons: bool = false) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", pill_style(selected))
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	# Optional fixed-width leftmost cell (the [E]/✕ marker slot), before any icon.
	if lead != null:
		hbox.add_child(lead)
	for icon in icons:
		if icon == null:
			continue
		var rect := TextureRect.new()
		rect.texture = icon
		rect.custom_minimum_size = Vector2(16, 16)
		rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Dim the item icon on a muted row so the whole row greys, not just the
		# text — same modulate the inventory uses (#417 shop/inventory parity).
		if dim_icons:
			rect.modulate = DISABLED_ICON_MOD
		hbox.add_child(rect)
	var label := Label.new()
	label.text = left_text
	var color: Color = text_color if text_color.a > 0.0 else TEXT
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", FONT_ITEM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Long names trim with an ellipsis instead of painting past the pill edge —
	# the list scroll disables horizontal scrolling, so the row width is capped
	# and overflow otherwise draws outside the card (#626).
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(label)
	if not right_text.is_empty():
		var right := Label.new()
		right.text = right_text
		right.add_theme_color_override("font_color", TEXT_LIGHT if text_color.a == 0.0 else color)
		right.add_theme_font_size_override("font_size", FONT_ITEM)
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(right)
	pill.add_child(hbox)
	return pill


## The ONE shop/storage list row, shared by every shop (#368 — match the Astro
## mock at spec/src/components/screens/shops). Rules, identical everywhere
## (normative contract: spec /states/shops "row contract"):
##   • A buy-shop row greys out when the character CAN'T USE/EQUIP it — a
##     capability limit (wrong class/race, an unlearnable or already-known
##     technique, below the level requirement). Affordability and inventory
##     space do NOT grey a row; an unaffordable row stays normal and the buy is
##     blocked at accept with the shared info modal instead.
##   • A row the character can never equip/use (a permanent race/class block,
##     e.g. a HUmar's cannot-equip weapon) ALSO carries a red ✕ marker icon
##     (`cannot_use`). A merely-temporary block (req-level, already-known) greys
##     without the marker (`disabled`).
##   • Greyed rows stay SELECTABLE and BUYABLE — the player may still purchase
##     gear/disks they can't use if they have room + meseta (#375).
##   • Equipped gear is marked with an [E] PREFIX (not a right-side tag).
##   • Rarity stars / req-level tags do NOT go in the name; they belong in the
##     detail panel.
## `opts`: { icons:Array, equipped:bool, affordable:bool=true, disabled:bool=false,
##           cannot_use:bool=false, selected:bool }. `affordable` is retained for
## list-only shops (crafting/tekker) that still gate the row on a resource cost;
## buy shops pass `disabled`/`cannot_use` (capability) instead.
static func shop_row(item_name: String, right_text: String, opts: Dictionary = {}) -> PanelContainer:
	var equipped: bool = bool(opts.get("equipped", false))
	var affordable: bool = bool(opts.get("affordable", true))
	var disabled: bool = bool(opts.get("disabled", false))
	var cannot_use: bool = bool(opts.get("cannot_use", false))
	var selected: bool = bool(opts.get("selected", false))
	var icons: Array = (opts.get("icons", []) as Array).duplicate()
	# Leftmost FIXED-WIDTH marker cell, before the item icon — ✕ when the
	# character can never use/equip it, else [E] for equipped gear, else an empty
	# reserved gap so item names stay aligned whether or not a row has a marker
	# (PSOBB convention; Rozalin playtest). The marker, not a text prefix, carries
	# the [E]/✕ so all shop lists line up identically.
	var marker_kind := "x" if cannot_use else ("e" if equipped else "")
	# Muted when the player can't act on the row: capability block (can't
	# use/equip, or already-known/req-level), equipped gear (can't re-buy /
	# deposit / sell), or — for the legacy cost-gated list shops — unaffordable.
	var muted: bool = (not affordable) or equipped or disabled or cannot_use
	var color: Color = TEXT_MUTED if muted else Color.TRANSPARENT
	# Dim the row's item icon when muted so the icon greys with the text (#417) —
	# the ✕ marker in the leftmost cell stays full-colour (it's a marker, not item art).
	return create_pill_with_icons(icons, item_name, selected, right_text, color, marker_cell(marker_kind), muted)


## Width of the leftmost shop-row marker slot. Wide enough for the "[E]" tag; the
## ✕ icon and the empty gap reserve the same width so names align across rows.
const MARKER_W := 22


## A fixed-width leftmost marker cell for shop rows: the ✕ "can't use" icon
## (`"x"`), the "[E]" equipped tag (`"e"`), or an empty reserved gap (anything
## else). Every shop_row reserves this slot so item names line up regardless of
## whether the row carries a marker.
static func marker_cell(kind: String) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(MARKER_W, 16)
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if kind == "x":
		var rect := TextureRect.new()
		rect.texture = cannot_use_icon()
		rect.custom_minimum_size = Vector2(16, 16)
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		cell.add_child(rect)
	elif kind == "e":
		var lbl := Label.new()
		lbl.text = "[E]"
		lbl.add_theme_color_override("font_color", TEXT_MUTED)
		lbl.add_theme_font_size_override("font_size", FONT_TAB)
		lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		cell.add_child(lbl)
	return cell


static var _cannot_use_tex: Texture2D = null


## A 16×16 red "✕" marker drawn at runtime — prepended to shop rows for gear/items
## the character can never equip/use (permanent race/class block). Generated in
## code (like scanline_texture) so it ships no new asset file and needs no pack
## republish. Cached after first build.
static func cannot_use_icon() -> Texture2D:
	if _cannot_use_tex != null:
		return _cannot_use_tex
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Two 3px-thick diagonals forming an ✕, inset 2px from the edges.
	for i in range(2, n - 2):
		for t in range(-1, 2):
			var x: int = i + t
			if x >= 2 and x < n - 2:
				img.set_pixel(x, i, TEXT_DANGER)            # ╲
				img.set_pixel(x, n - 1 - i, TEXT_DANGER)    # ╱
	_cannot_use_tex = ImageTexture.create_from_image(img)
	return _cannot_use_tex


static func create_section_header(text: String) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", section_header_style())
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", TITLE_BG)
	label.add_theme_font_size_override("font_size", FONT_DETAIL)
	pill.add_child(label)
	return pill


## The standard vertical scrolling list container for shop/storage screens:
## fills its slot and scrolls vertically only. Add a VBox of rows as its child.
## Shared so every list scrolls identically (#368 list-scroll consistency).
static func make_list_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return scroll


## Scroll `row`'s ancestor ScrollContainer so the row is visible. Walks up from
## the row itself, so it works whoever holds the reference (rebuild or
## incremental update). MUST be called after the row is in the tree (under the
## scroll); deferred so it runs once layout has settled. No-ops otherwise.
static func scroll_into_view(row: Control) -> void:
	if row == null:
		return
	var p: Node = row.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p is ScrollContainer:
		(p as ScrollContainer).ensure_control_visible.call_deferred(row)


## Like scroll_into_view, but keeps `margin_rows` of context between the selected
## row and the viewport edge, so the selection moves *within* the visible area
## and the list only scrolls once the selection nears an edge (playtest: the
## cursor should travel inside the view before the whole list scrolls, rather
## than the bar jumping on every move). Deferred so it runs after layout settles.
## Use this for the cursor-follow in shop lists; storage etc. may still use the
## flush ensure_control_visible via scroll_into_view.
static func scroll_selected_into_view(row: Control, margin_rows: int = 1) -> void:
	if row == null:
		return
	var p: Node = row.get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	if p is ScrollContainer:
		_apply_scroll_margin.call_deferred(p as ScrollContainer, row, margin_rows)


static func _apply_scroll_margin(scroll: ScrollContainer, row: Control, margin_rows: int) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(row):
		return
	var view_h: float = scroll.size.y
	var row_top: float = row.position.y
	var row_h: float = row.size.y
	# One "row" of margin ≈ the row height plus the VBox separation (3px).
	var margin: float = (row_h + 3.0) * float(maxi(margin_rows, 0))
	var v: float = float(scroll.scroll_vertical)
	var top_limit: float = row_top - margin
	var bottom_limit: float = row_top + row_h + margin - view_h
	if v > top_limit:
		v = top_limit
	elif v < bottom_limit:
		v = bottom_limit
	scroll.scroll_vertical = int(maxf(0.0, v))


## Cursor-move restyle shared by every shop's incremental selection update:
## de-highlight the old row, then highlight + margin-scroll the new one. Indices
## out of range are ignored, so a stale cache simply no-ops. The screen renders
## its own detail panel separately (see ShopNav.cursor_move).
static func restyle_selection(pill_nodes: Array, old_index: int, new_index: int) -> void:
	if old_index >= 0 and old_index < pill_nodes.size():
		var old_pill = pill_nodes[old_index]
		if is_instance_valid(old_pill):
			old_pill.add_theme_stylebox_override("panel", pill_style(false))
	if new_index >= 0 and new_index < pill_nodes.size():
		var new_pill = pill_nodes[new_index]
		if is_instance_valid(new_pill):
			new_pill.add_theme_stylebox_override("panel", pill_style(true))
			scroll_selected_into_view(new_pill)


static func create_tab_bar(tab_names: Array, active_tab: int) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	for i in range(tab_names.size()):
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", tab_style(i == active_tab))
		var label := Label.new()
		label.text = str(tab_names[i])
		label.add_theme_color_override("font_color", TEXT)
		label.add_theme_font_size_override("font_size", FONT_TAB)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(label)
		hbox.add_child(panel)
	return hbox


static func create_meseta_label(meseta: int) -> Label:
	var label := Label.new()
	label.text = "%d M" % meseta
	label.add_theme_color_override("font_color", TEXT_MESETA)
	label.add_theme_font_size_override("font_size", FONT_ITEM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## Restructure a shop into the standard fullscreen layout and return its detail
## card. Left 3/5: title, tabs, list, hints. Right 2/5: detail card on top,
## stopping 10px above the shop portrait (NOT full height). The portrait itself
## is an absolute overlay added separately by ShopPreviewSprite; `model_path` is
## the same preview texture path, used here to size the bottom spacer that
## reserves the portrait's footprint.
##
## This is THE single layout path every shop uses, so they stay consistent:
##   • Pass `detail_ref` when the scene already has a DetailPanel node (item,
##     weapon, guild, storage) — it's lifted out of the inner HBox into the slot.
##   • Pass `null` and this creates a styled detail card for shops whose scene
##     has no detail node (photon, crafting, tekker). Either way the returned
##     PanelContainer is the card the shop renders its selection into.
static func setup_shop_portrait(
		panel: PanelContainer, detail_ref: PanelContainer,
		_model_path: String) -> PanelContainer:
	# Diegetic framing (spec /states/shops#presentation): the shop is an overlay
	# on the live 3D city, not a full-screen panel. Anchor the menu to the LEFT
	# ~60% so the 3D shopkeeper NPC — framed by the camera — stays visible on the
	# right, and keep the outer panel transparent so the body/detail glass cards
	# read against the scene. Layout: a tall body card (title/tabs/list/hint) on
	# the left, a shorter detail card (~40% height, top-aligned) beside it.
	panel.offset_left = LEFT_MARGIN
	panel.offset_top = TOP_MARGIN
	panel.offset_right = -RIGHT_RESERVE
	panel.offset_bottom = -BOTTOM_MARGIN
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	# Pull VBox out of Panel. When the scene supplies the detail node, lift it
	# out of its inner HBox; otherwise create a styled card for the right slot.
	var vbox := panel.get_child(0) as VBoxContainer
	panel.remove_child(vbox)
	var detail := detail_ref
	if detail != null:
		detail.get_parent().remove_child(detail)
	else:
		detail = PanelContainer.new()
		detail.name = "DetailPanel"
	apply_detail_panel_style(detail)

	# Outer HBox: left body card (3/5) + right detail column (2/5).
	var outer := HBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 12)

	# LEFT: the body (title / tabs / list / hint) in a glass card, full height.
	var body_card := PanelContainer.new()
	body_card.name = "ShopBodyCard"
	body_card.custom_minimum_size = Vector2(SHOP_BODY_W, 0.0)
	body_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_card.size_flags_stretch_ratio = 3.0
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color(BG.r, BG.g, BG.b, 0.82)
	glass.content_margin_left = 10.0
	glass.content_margin_right = 10.0
	glass.content_margin_top = 8.0
	glass.content_margin_bottom = 8.0
	glass.corner_radius_top_left = 6
	glass.corner_radius_top_right = 6
	glass.corner_radius_bottom_left = 6
	glass.corner_radius_bottom_right = 6
	glass.border_width_top = 3
	glass.border_color = TITLE_BG
	body_card.add_theme_stylebox_override("panel", glass)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_card.add_child(vbox)
	outer.add_child(body_card)

	# RIGHT: the detail card, top-aligned, ~40% of frame height.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 2.0
	right.add_theme_constant_override("separation", 0)
	var detail_holder := MarginContainer.new()
	detail_holder.custom_minimum_size = Vector2(SHOP_DETAIL_W, DETAIL_HEIGHT)
	detail_holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_holder.add_child(detail)
	right.add_child(detail_holder)
	outer.add_child(right)

	panel.add_child(outer)
	return detail


static func detail_label(text: String, color := TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", FONT_DETAIL)
	# Wrap inside the fixed-width detail card (#626): an unwrapped Label's width
	# becomes the card's minimum width, so the longest item name would resize the
	# whole list/info split. The web fixture wraps the same way (CSS default).
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func style_menu(p_title: Label, p_hint: Label, panels: Array = []) -> void:
	p_title.add_theme_stylebox_override("normal", title_style())
	p_title.add_theme_color_override("font_color", TEXT_WHITE)
	p_title.add_theme_font_size_override("font_size", FONT_TITLE)
	p_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	p_hint.add_theme_stylebox_override("normal", hint_style())
	p_hint.add_theme_color_override("font_color", TEXT)
	p_hint.add_theme_font_size_override("font_size", FONT_HINT)
	# Wrap within the fixed-width menu (#626): the hint sentence is the widest
	# single-line text in the body card ("Left/Right: Category …" ≈ 504 px) and
	# otherwise floors the card's minimum width above the pinned 438 split.
	p_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for panel in panels:
		if panel is PanelContainer:
			panel.add_theme_stylebox_override("panel", inner_panel_style())


# ── Detail panel (the white scan-lined card, matching the shop mock) ──────────
# The mock's DetailPanel is a translucent-white card with a subtle scanline
# texture, a thin border with a darker top edge, and rounded corners. See
# spec/src/components/screens/pszui.tsx (DetailPanel + SCANLINES).
const DETAIL_BG := Color(1.0, 1.0, 1.0, 0.85)
const DETAIL_BORDER := Color(0.165, 0.204, 0.282)  # dark-blue edge (#2a3448)
const SCANLINE_COLOR := Color(0.47, 0.627, 0.784, 0.08)

static var _scanline_tex: Texture2D = null


static func detail_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = DETAIL_BG
	s.border_color = DETAIL_BORDER
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_width_top = 3  # heavier top edge, like the mock
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_right = 6
	s.corner_radius_bottom_left = 6
	s.content_margin_left = 12.0
	s.content_margin_right = 12.0
	s.content_margin_top = 10.0
	s.content_margin_bottom = 10.0
	return s


## A 1×4 tiling texture: two transparent rows then two faint-line rows, so a
## TextureRect on STRETCH_TILE paints horizontal scanlines every 4px.
static func scanline_texture() -> Texture2D:
	if _scanline_tex != null:
		return _scanline_tex
	var img := Image.create(1, 4, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	img.set_pixel(0, 1, Color(0, 0, 0, 0))
	img.set_pixel(0, 2, SCANLINE_COLOR)
	img.set_pixel(0, 3, SCANLINE_COLOR)
	_scanline_tex = ImageTexture.create_from_image(img)
	return _scanline_tex


## Apply the white scan-lined card style to a detail PanelContainer and ensure
## a single back-most scanline overlay. Idempotent — safe to call every refresh.
static func apply_detail_panel_style(panel: PanelContainer) -> void:
	panel.add_theme_stylebox_override("panel", detail_panel_style())
	var overlay: TextureRect = panel.get_node_or_null("ScanlineOverlay")
	if overlay == null:
		overlay = TextureRect.new()
		overlay.name = "ScanlineOverlay"
		overlay.texture = scanline_texture()
		overlay.stretch_mode = TextureRect.STRETCH_TILE
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(overlay)
	panel.move_child(overlay, 0)


## Clear a detail panel's content (everything but the scanline overlay) and
## (re)apply the card style. Shops call this, then add their content VBox.
static func clear_detail_panel(panel: PanelContainer) -> void:
	apply_detail_panel_style(panel)
	for child in panel.get_children():
		if child.name != "ScanlineOverlay":
			child.queue_free()

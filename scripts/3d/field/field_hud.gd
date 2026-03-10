extends CanvasLayer
## Field HUD — shows player stats (HP/PP bars, level, name) top-left,
## quest log docked left (toggleable, only when quest active),
## and hosts the room minimap (always visible).

const MARGIN := 12.0

var _stats_panel: Control
var _quest_log: Control
var _action_palette: Control
var _log_visible: bool = false
var _hidden_for_overlay: bool = false

# Cached character info (static for session)
var _char_name: String = ""
var _char_level: int = 1


func _ready() -> void:
	layer = 99
	name = "FieldHud"
	process_mode = Node.PROCESS_MODE_ALWAYS

	var ch = CharacterManager.get_active_character()
	if ch:
		_char_name = str(ch.get("name", ""))
		_char_level = int(ch.get("level", 1))

	_stats_panel = _StatsPanel.new()
	_stats_panel.char_name = _char_name
	_stats_panel.char_level = _char_level
	add_child(_stats_panel)

	_quest_log = _QuestLogPanel.new()
	add_child(_quest_log)

	_action_palette = _ActionPalette.new()
	add_child(_action_palette)

	GameState.hp_changed.connect(_on_stats_changed)
	GameState.max_hp_changed.connect(_on_stats_changed)
	GameState.mp_changed.connect(_on_stats_changed)
	GameState.max_mp_changed.connect(_on_stats_changed)

	# Auto-show log if we're in a quest session
	if _is_in_quest():
		_log_visible = true
		_quest_log.visible = true
	else:
		_quest_log.visible = false


func _process(_delta: float) -> void:
	# Hide HUD when an overlay (shop, menu, dialog) is open
	var has_overlay: bool = not SceneManager._overlay_stack.is_empty()
	if has_overlay and not _hidden_for_overlay:
		_hidden_for_overlay = true
		hide_for_menu()
	elif not has_overlay and _hidden_for_overlay:
		_hidden_for_overlay = false
		restore_after_menu()


func _unhandled_input(event: InputEvent) -> void:
	# Toggle log with backtick (`) key
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT:
			_toggle_log()
			get_viewport().set_input_as_handled()


func _toggle_log() -> void:
	_log_visible = not _log_visible
	_quest_log.visible = _log_visible


func _is_in_quest() -> bool:
	if SessionManager.has_accepted_quest():
		return true
	var session: Dictionary = SessionManager.get_session()
	return not session.is_empty() and str(session.get("type", "")) == "quest"


## Hide all HUD elements when a menu/shop/dialog is open.
func hide_for_menu() -> void:
	for child in get_children():
		if child is Control:
			child.visible = false


## Restore HUD visibility after menu closes.
func restore_after_menu() -> void:
	for child in get_children():
		if child is Control:
			child.visible = true
	# Log respects its own toggle state
	_quest_log.visible = _log_visible


func _on_stats_changed(_value: int) -> void:
	_stats_panel.queue_redraw()


## Log companion speech to the action log.
func log_speech(speaker: String, text: String) -> void:
	_quest_log.add_speech_entry(speaker, text)
	_auto_show_log()


## Log an arbitrary entry to the action log.
func log_entry(text: String, color: Color = Color(0.85, 0.85, 0.85)) -> void:
	_quest_log.add_entry(text, color)
	_auto_show_log()


## Auto-show log when a new entry arrives during a quest.
func _auto_show_log() -> void:
	if not _log_visible:
		_log_visible = true
		_quest_log.visible = true


# ── Stats Panel (top-left) ───────────────────────────────────────────────────

class _StatsPanel extends Control:
	const PANEL_W := 170.0
	const PANEL_H := 56.0
	const BAR_H := 10.0
	const FONT_SIZE_MAIN := 11
	const FONT_SIZE_SMALL := 9
	const FONT_SIZE_BAR := 8

	# PSZ palette — semi-transparent for single-screen
	const BG_BLUE := Color(0.66, 0.80, 0.91, 0.6)   # Pale icy blue, translucent
	const BORDER_BLUE := Color(0.48, 0.63, 0.75, 0.5)
	const TEXT_DARK := Color(0.1, 0.1, 0.17)         # Near-black text
	const TEXT_LIGHT := Color(0.23, 0.29, 0.35)      # Secondary text
	const HP_COLOR := Color(0.27, 0.73, 0.27)        # Green HP fill
	const HP_COLOR_TOP := Color(0.4, 0.87, 0.4)      # HP gradient top
	const HP_BG := Color(0.85, 0.91, 0.85)           # HP bar background
	const HP_YELLOW := Color(0.9, 0.9, 0.2)
	const HP_RED := Color(0.9, 0.2, 0.2)
	const PP_COLOR := Color(0.2, 0.53, 0.93)         # Blue PP fill
	const PP_COLOR_TOP := Color(0.4, 0.6, 1.0)       # PP gradient top
	const PP_BG := Color(0.85, 0.85, 0.94)           # PP bar background
	const HP_LABEL := Color(0.2, 0.53, 0.2)          # Dark green
	const PP_LABEL := Color(0.2, 0.4, 0.73)          # Dark blue
	const BAR_VALUE := Color(1.0, 1.0, 1.0)          # White value on bar
	const MAX_VALUE := Color(0.1, 0.1, 0.17)         # Dark max value at end

	var char_name: String = ""
	var char_level: int = 1
	var _bg_style: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		position = Vector2(MARGIN, MARGIN)
		size = Vector2(PANEL_W, PANEL_H)
		custom_minimum_size = size

		# Rounded panel background
		_bg_style = StyleBoxFlat.new()
		_bg_style.bg_color = BG_BLUE
		_bg_style.border_color = BORDER_BLUE
		_bg_style.set_border_width_all(2)
		_bg_style.corner_radius_top_left = 4
		_bg_style.corner_radius_top_right = 16
		_bg_style.corner_radius_bottom_right = 10
		_bg_style.corner_radius_bottom_left = 12

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var hp: int = GameState.hp
		var max_hp: int = GameState.max_hp
		var pp: int = GameState.mp
		var max_pp: int = GameState.max_mp

		# Panel background — rounded with asymmetric corners
		draw_style_box(_bg_style, Rect2(Vector2.ZERO, Vector2(PANEL_W, PANEL_H)))

		# Scanline overlay (clipped to panel area)
		for sy in range(2, int(PANEL_H) - 2, 4):
			draw_rect(Rect2(2, sy + 2, PANEL_W - 4, 2), Color(0.47, 0.63, 0.78, 0.08))

		var pad := 10.0
		var y := 14.0

		# Player name + level
		draw_string(font, Vector2(pad, y), char_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_MAIN, TEXT_DARK)
		var lv_text := "Lv. %d" % char_level
		var lv_w: float = font.get_string_size(lv_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SMALL).x
		draw_string(font, Vector2(PANEL_W - pad - lv_w, y), lv_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SMALL, TEXT_LIGHT)

		# Separator line
		y += 4.0
		draw_line(Vector2(pad, y), Vector2(PANEL_W - pad, y), Color(0.47, 0.63, 0.78, 0.3), 1.0)

		y += 14.0
		_draw_stat_bar(font, Vector2(pad, y), "HP", hp, max_hp, true)
		y += 14.0
		_draw_stat_bar(font, Vector2(pad, y), "PP", pp, max_pp, false)

	func _draw_stat_bar(font: Font, pos: Vector2, label: String, current: int, maximum: int, is_hp: bool) -> void:
		var label_color: Color = HP_LABEL if is_hp else PP_LABEL
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SMALL, label_color)

		var label_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SMALL).x
		var bar_x: float = pos.x + label_w + 4.0
		var bar_y: float = pos.y - BAR_H + 1.0
		var bar_w: float = PANEL_W - bar_x - 30.0  # leave room for max value

		# Bar background (rounded)
		var bar_bg: Color = HP_BG if is_hp else PP_BG
		draw_rect(Rect2(bar_x, bar_y, bar_w, BAR_H), bar_bg)

		# Bar fill
		var pct: float = float(current) / float(maximum) if maximum > 0 else 0.0
		var fill_w: float = bar_w * clampf(pct, 0.0, 1.0)
		var fill_color: Color
		if is_hp:
			if pct > 0.5:
				fill_color = HP_COLOR
			elif pct > 0.25:
				fill_color = HP_YELLOW
			else:
				fill_color = HP_RED
		else:
			fill_color = PP_COLOR
		if fill_w > 0:
			draw_rect(Rect2(bar_x, bar_y, fill_w, BAR_H), fill_color)
			# Top gradient highlight
			var top_color: Color = HP_COLOR_TOP if is_hp else PP_COLOR_TOP
			draw_rect(Rect2(bar_x, bar_y, fill_w, BAR_H / 2), Color(top_color, 0.3))

		# Current value centered on bar
		var cur_text := str(current)
		var cur_w: float = font.get_string_size(cur_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_BAR).x
		var cur_x: float = bar_x + (bar_w - cur_w) * 0.5
		draw_string(font, Vector2(cur_x, pos.y - 1), cur_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_BAR, BAR_VALUE)

		# Max value at right end of bar
		var max_text := str(maximum)
		var max_w: float = font.get_string_size(max_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_BAR).x
		draw_string(font, Vector2(PANEL_W - 8.0 - max_w, pos.y - 1), max_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_BAR, MAX_VALUE)


# ── Action Log (bottom-left, fixed box with scroll) ─────────────────────────

class _QuestLogPanel extends Control:
	const PANEL_W := 180.0
	const PANEL_H := 120.0
	const PAD := 4.0
	const FONT_SIZE := 9

	# PSZ palette — semi-transparent for single-screen
	const BG_COLOR := Color(0.66, 0.80, 0.91, 0.5)   # Pale icy blue, translucent
	const BORDER_COLOR := Color(0.48, 0.63, 0.75, 0.4)
	const HEADER_BG := Color(0.16, 0.16, 0.22, 0.7)   # Dark navy header
	const HEADER_TEXT := Color(1.0, 1.0, 1.0, 0.9)
	const CONTENT_BG := Color(1.0, 1.0, 1.0, 0.6)     # White content area, translucent
	const TEXT_COLOR := Color(0.1, 0.1, 0.17)          # Dark text
	const ITEM_COLOR := Color(0.53, 0.33, 0.13)        # Brown/orange items
	const MESETA_COLOR := Color(0.53, 0.4, 0.0)        # Dark gold
	const QUEST_COLOR := Color(0.17, 0.33, 0.6)        # Dark blue
	const SPEECH_COLOR := Color(0.2, 0.2, 0.3)         # Dark gray
	const COMPLETE_COLOR := Color(0.13, 0.53, 0.13)    # Dark green

	var _scroll: ScrollContainer
	var _vbox: VBoxContainer
	var _prev_meseta: int = 0
	var _panel_bg: PanelContainer

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

		# Bottom-left corner
		set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		offset_left = MARGIN
		offset_bottom = -MARGIN
		offset_top = -MARGIN - PANEL_H
		offset_right = MARGIN + PANEL_W
		size = Vector2(PANEL_W, PANEL_H)

		# Background panel — PSZ blue
		_panel_bg = PanelContainer.new()
		_panel_bg.mouse_filter = MOUSE_FILTER_IGNORE
		_panel_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var style := StyleBoxFlat.new()
		style.bg_color = BG_COLOR
		style.border_color = BORDER_COLOR
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(PAD)
		_panel_bg.add_theme_stylebox_override("panel", style)
		add_child(_panel_bg)

		# Outer VBox: header label + scroll content
		var outer_vbox := VBoxContainer.new()
		outer_vbox.mouse_filter = MOUSE_FILTER_IGNORE
		outer_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		outer_vbox.add_theme_constant_override("separation", 2)
		_panel_bg.add_child(outer_vbox)

		# "Log" header label
		var header := Label.new()
		header.text = "Log"
		header.add_theme_font_size_override("font_size", 10)
		header.add_theme_color_override("font_color", HEADER_TEXT)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.mouse_filter = MOUSE_FILTER_IGNORE
		var header_panel := PanelContainer.new()
		header_panel.mouse_filter = MOUSE_FILTER_IGNORE
		var header_style := StyleBoxFlat.new()
		header_style.bg_color = HEADER_BG
		header_style.set_corner_radius_all(4)
		header_style.content_margin_left = 8.0
		header_style.content_margin_right = 8.0
		header_style.content_margin_top = 2.0
		header_style.content_margin_bottom = 2.0
		header_panel.add_theme_stylebox_override("panel", header_style)
		header_panel.add_child(header)
		outer_vbox.add_child(header_panel)

		# White content area
		var content_panel := PanelContainer.new()
		content_panel.mouse_filter = MOUSE_FILTER_IGNORE
		content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var content_style := StyleBoxFlat.new()
		content_style.bg_color = CONTENT_BG
		content_style.set_corner_radius_all(3)
		content_style.set_content_margin_all(4.0)
		content_panel.add_theme_stylebox_override("panel", content_style)
		outer_vbox.add_child(content_panel)

		# ScrollContainer — auto-scrolls to bottom
		_scroll = ScrollContainer.new()
		_scroll.mouse_filter = MOUSE_FILTER_IGNORE
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content_panel.add_child(_scroll)

		# VBoxContainer holds the label entries
		_vbox = VBoxContainer.new()
		_vbox.mouse_filter = MOUSE_FILTER_IGNORE
		_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_vbox.add_theme_constant_override("separation", 2)
		_scroll.add_child(_vbox)

		SessionManager.quest_item_collected.connect(_on_item_collected)
		SessionManager.quest_completed.connect(_on_quest_completed)
		GameState.meseta_changed.connect(_on_meseta_changed)
		_prev_meseta = GameState.meseta

		# Restore entries from previous rooms
		for entry in SessionManager._action_log:
			_add_label(str(entry.get("text", "")), entry.get("color", TEXT_COLOR))
		_scroll_to_bottom.call_deferred()

		# Log quest acceptance once per quest (not every room transition)
		var objectives: Array = SessionManager.get_quest_objectives()
		if not objectives.is_empty() and not SessionManager._quest_accepted_shown:
			SessionManager._quest_accepted_shown = true
			get_tree().create_timer(0.5).timeout.connect(func() -> void:
				_add_entry("Quest accepted", QUEST_COLOR)
			)

	func _on_item_collected(item_id: String, new_count: int, target: int) -> void:
		var label := item_id
		for obj in SessionManager.get_quest_objectives():
			if str(obj.get("item_id", "")) == item_id:
				label = str(obj.get("label", item_id))
				break
		_add_entry("Picked up %s (%d/%d)" % [label, mini(new_count, target), target], ITEM_COLOR)

	func _on_quest_completed() -> void:
		_add_entry("Quest complete!", COMPLETE_COLOR)

	func _on_meseta_changed(new_amount: int) -> void:
		var diff: int = new_amount - _prev_meseta
		_prev_meseta = new_amount
		if diff > 0:
			_add_entry("Picked up %d meseta" % diff, MESETA_COLOR)

	## Public: log companion speech to the action log.
	func add_speech_entry(speaker: String, text: String) -> void:
		_add_entry("%s: %s" % [speaker, text], SPEECH_COLOR)

	## Public: log an arbitrary action.
	func add_entry(text: String, color: Color = TEXT_COLOR) -> void:
		_add_entry(text, color)

	func _add_entry(text: String, color: Color) -> void:
		# Persist to SessionManager so entries survive room transitions
		SessionManager._action_log.append({"text": text, "color": color})
		_add_label(text, color)
		_scroll_to_bottom.call_deferred()

	func _add_label(text: String, color: Color) -> void:
		var lbl := Label.new()
		lbl.text = text
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", FONT_SIZE)
		lbl.add_theme_color_override("font_color", color)
		lbl.mouse_filter = MOUSE_FILTER_IGNORE
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_vbox.add_child(lbl)

	func _scroll_to_bottom() -> void:
		await get_tree().process_frame
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


# ── Action Palette (bottom-right) ────────────────────────────────────────────

class _ActionPalette extends Control:
	## PSO-style action palette: I (swap), J/K/L (action slots).
	## I centered above, J/L raised, K lower (diamond-ish layout).

	const PILL_BG := Color(1.0, 1.0, 1.0, 0.5)
	const PILL_BORDER := Color(0.59, 0.71, 0.82, 0.3)
	const KEY_BG := Color(0.16, 0.24, 0.31, 0.5)
	const KEY_TEXT := Color(1.0, 1.0, 1.0)
	const LABEL_TEXT := Color(0.1, 0.1, 0.17)
	const LABEL_LIGHT := Color(0.23, 0.29, 0.35)
	const FONT_SIZE_KEY := 8
	const FONT_SIZE_LABEL := 10
	const FONT_SIZE_SMALL := 8

	# Layout constants
	const PILL_W := 44.0
	const PILL_H := 28.0
	const SWAP_W := 40.0
	const SWAP_H := 18.0
	const GAP := 4.0
	const RAISED := 10.0  # J and L raised above K

	var _bg_pill: StyleBoxFlat
	var _bg_swap: StyleBoxFlat

	# Action slot data
	var _slots: Array = [
		{"key": "J", "label": "Atk"},
		{"key": "K", "label": "Foie"},
		{"key": "L", "label": "Mate"},
	]
	var _palette_index: int = 1
	var _palette_count: int = 6

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

		# Total size: 3 pills + 2 gaps wide, swap pill + gap + tallest pill high
		var total_w: float = PILL_W * 3 + GAP * 2
		var total_h: float = SWAP_H + 2.0 + PILL_H + RAISED
		custom_minimum_size = Vector2(total_w, total_h)
		size = Vector2(total_w, total_h)

		# Anchor bottom-right
		anchor_left = 1.0
		anchor_right = 1.0
		anchor_top = 1.0
		anchor_bottom = 1.0
		offset_left = -total_w - MARGIN
		offset_right = -MARGIN
		offset_top = -total_h - MARGIN
		offset_bottom = -MARGIN

		# Pill style
		_bg_pill = StyleBoxFlat.new()
		_bg_pill.bg_color = PILL_BG
		_bg_pill.border_color = PILL_BORDER
		_bg_pill.set_border_width_all(1)
		_bg_pill.set_corner_radius_all(8)

		# Swap pill style (smaller)
		_bg_swap = StyleBoxFlat.new()
		_bg_swap.bg_color = PILL_BG
		_bg_swap.border_color = PILL_BORDER
		_bg_swap.set_border_width_all(1)
		_bg_swap.set_corner_radius_all(8)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var total_w: float = size.x

		# I — palette swap, centered above JKL
		var swap_x: float = (total_w - SWAP_W) * 0.5
		var swap_y: float = 0.0
		draw_style_box(_bg_swap, Rect2(swap_x, swap_y, SWAP_W, SWAP_H))

		# "I" key badge
		var key_rect := Rect2(swap_x + 6, swap_y + 4, 16, 13)
		draw_rect(key_rect, KEY_BG)
		draw_string(font, Vector2(swap_x + 10, swap_y + 14), "I",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_KEY, KEY_TEXT)

		# Palette number
		var pn_text := "%d/%d" % [_palette_index, _palette_count]
		draw_string(font, Vector2(swap_x + 26, swap_y + 14), pn_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SMALL, LABEL_LIGHT)

		# JKL row — bottom-aligned, J and L raised
		var row_y: float = SWAP_H + 2.0
		for i in range(3):
			var slot: Dictionary = _slots[i]
			var px: float = i * (PILL_W + GAP)
			var py: float = row_y + (0.0 if slot["key"] == "K" else 0.0)
			# J and L are raised (lower py = higher on screen)
			if slot["key"] != "K":
				py = row_y
			else:
				py = row_y + RAISED

			draw_style_box(_bg_pill, Rect2(px, py, PILL_W, PILL_H))

			# Key badge
			var kx: float = px + (PILL_W - 16) * 0.5
			var ky: float = py + 5
			draw_rect(Rect2(kx, ky, 16, 13), KEY_BG)
			draw_string(font, Vector2(kx + 4, ky + 10), slot["key"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_KEY, KEY_TEXT)

			# Action label
			var lbl: String = slot["label"]
			var lbl_w: float = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_LABEL).x
			draw_string(font, Vector2(px + (PILL_W - lbl_w) * 0.5, py + PILL_H - 5),
				lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_LABEL, LABEL_TEXT)

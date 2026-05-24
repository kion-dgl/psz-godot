extends CanvasLayer
## Field HUD — shows player stats (HP/PP bars, level, name) top-left,
## quest log docked left (toggleable, only when quest active),
## and hosts the room minimap (always visible).

const MARGIN := 12.0

var _stats_panel: Control
var _quest_log: Control
var _action_palette: Control
var _quick_menu: Control
var _debug_info: Control
var _fps_label: Label
var _log_visible: bool = false
var _hidden_for_overlay: bool = false
# Tracks the keep_stats arg we last applied so we can detect transitions
# within the "is hidden" state — e.g. start menu open (keep_stats=true) →
# pushed scene overlay (keep_stats=false) needs to re-hide the stats panel.
var _last_keep_stats: bool = false

# Cached character info (static for session)
var _char_name: String = ""
var _char_level: int = 1


func _ready() -> void:
	layer = 200  # Above start menu (150) so HP/PP shows on top
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

	_action_palette = _ActionPalette.new()
	add_child(_action_palette)

	_quick_menu = _QuickMenu.new()
	add_child(_quick_menu)

	GameState.hp_changed.connect(_on_stats_changed)
	GameState.max_hp_changed.connect(_on_stats_changed)
	GameState.mp_changed.connect(_on_stats_changed)
	GameState.max_mp_changed.connect(_on_stats_changed)
	CharacterManager.level_up.connect(_on_level_up)

	# FPS counter (top-right)
	_fps_label = Label.new()
	_fps_label.anchor_left = 1.0
	_fps_label.anchor_right = 1.0
	_fps_label.offset_left = -80
	_fps_label.offset_right = -MARGIN
	_fps_label.offset_top = MARGIN
	_fps_label.add_theme_font_size_override("font_size", 12)
	_fps_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.2))
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_fps_label)

	# Quest log disabled for now
	_log_visible = false


func _process(_delta: float) -> void:
	# FPS counter (only update when value changes)
	if _fps_label:
		var fps: int = int(Engine.get_frames_per_second())
		if fps != _fps_label.get_meta("last_fps", -1):
			_fps_label.set_meta("last_fps", fps)
			_fps_label.text = "%d FPS" % fps
			var band: int = 0 if fps < 30 else (1 if fps < 50 else 2)
			if band != _fps_label.get_meta("band", -1):
				_fps_label.set_meta("band", band)
				var colors := [Color(1.0, 0.3, 0.3), Color(1.0, 0.8, 0.2), Color(0.5, 0.8, 0.3)]
				_fps_label.add_theme_color_override("font_color", colors[band])

	# Hide HUD when an overlay (shop, menu, dialog) is open, or when the
	# PSO start menu is up — the start menu isn't tracked in
	# SceneManager._overlay_stack so we check its autoload directly.
	# HP/PP stays visible only for the PSO start menu path; full-screen
	# overlays (shops, storage, guild, inventory) hide everything including
	# stats so the shop UI isn't overlaid with the gameplay HUD.
	var has_scene_overlay: bool = not SceneManager._overlay_stack.is_empty()
	var start_menu_open: bool = PsoStartMenu.is_open()
	var has_overlay: bool = has_scene_overlay or start_menu_open
	# keep_stats: HP/PP stays visible only when the start menu is the lone
	# overlay (so the player can see their health while toggling options).
	# Once a scene overlay is pushed (e.g. Reconfigure Controls), hide
	# everything so the modal isn't drawn on top of stats.
	var target_keep_stats: bool = start_menu_open and not has_scene_overlay
	if has_overlay:
		# Re-apply hide_for_menu both on first-hide AND when keep_stats
		# changes mid-overlay (start-menu-only → start-menu + scene overlay,
		# or close start menu while scene overlay pushes), otherwise the
		# stats panel sticks at its earlier visibility.
		if not _hidden_for_overlay or _last_keep_stats != target_keep_stats:
			_hidden_for_overlay = true
			_last_keep_stats = target_keep_stats
			hide_for_menu(target_keep_stats)
	elif _hidden_for_overlay:
		_hidden_for_overlay = false
		restore_after_menu()

	# Action palette is a combat HUD element — hide it in the city (Dairon
	# / Pioneer 2 equivalent) where the player is shopping and talking to
	# NPCs, not fighting. Palette itself is also input-blocked in these
	# scenes via GameState.is_gameplay_blocked() for safety.
	if _action_palette and not _hidden_for_overlay:
		_action_palette.visible = not _is_in_city()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quest_log"):
		_toggle_log()
		get_viewport().set_input_as_handled()


func _toggle_log() -> void:
	if not _quest_log:
		return
	_log_visible = not _log_visible
	_quest_log.visible = _log_visible


func _is_in_quest() -> bool:
	if SessionManager.has_accepted_quest():
		return true
	var session: Dictionary = SessionManager.get_session()
	return not session.is_empty() and str(session.get("type", "")) == "quest"


func _is_in_city() -> bool:
	return SessionManager.get_location() == "city"


## Hide all HUD elements when a menu/shop/dialog is open.
## HP/PP stays up only for the PSO start menu (keep_stats=true); full-screen
## SceneManager overlays (shops, storage, guild, inventory) hide everything
## so the overlay isn't painted on top of the stats panel.
func hide_for_menu(keep_stats: bool = false) -> void:
	for child in get_children():
		if child is Control:
			if keep_stats and child == _stats_panel:
				continue
			child.visible = false


## Restore HUD visibility after menu closes.
func restore_after_menu() -> void:
	for child in get_children():
		if child is Control:
			child.visible = true
	# Log respects its own toggle state
	if _quest_log:
		_quest_log.visible = _log_visible
	# Grid minimap respects its toggle state (stored as meta by field controller)
	for child in get_children():
		if child.has_meta("toggled_off") and child.get_meta("toggled_off"):
			child.visible = false


func _on_stats_changed(_value: int) -> void:
	_stats_panel.update_display()


func _on_level_up(new_level: int) -> void:
	_char_level = new_level
	_stats_panel.char_level = new_level
	_stats_panel.update_display()


## Log companion speech to the action log.
func log_speech(speaker: String, text: String) -> void:
	if not _quest_log:
		return
	_quest_log.add_speech_entry(speaker, text)
	_auto_show_log()


## Log an arbitrary entry to the action log.
func log_entry(text: String, color: Color = Color(0.85, 0.85, 0.85)) -> void:
	if not _quest_log:
		return
	_quest_log.add_entry(text, color)
	_auto_show_log()


## Auto-show log when a new entry arrives during a quest.
func _auto_show_log() -> void:
	if not _quest_log:
		return
	if not _log_visible:
		_log_visible = true
		_quest_log.visible = true


## Set the debug info text shown at top-center (quest ID, section, cell).
func set_debug_info(_quest_id: String, _section_text: String, _cell_pos: String) -> void:
	pass


# ── Debug Info Panel (top-center) ────────────────────────────────────────────

class _DebugInfoPanel extends Control:
	## Always-visible debug overlay at top-center showing quest context.
	const FONT_SIZE := 12
	const BG_COLOR := Color(0.0, 0.0, 0.0, 0.45)
	const BORDER_COLOR := Color(0.4, 0.4, 0.4, 0.3)
	const TEXT_COLOR := Color(1.0, 1.0, 1.0, 0.85)
	const PAD_H := 12.0
	const PAD_V := 4.0

	var _label: Label
	var _panel: PanelContainer

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

		_panel = PanelContainer.new()
		_panel.mouse_filter = MOUSE_FILTER_IGNORE

		# Semi-transparent dark background
		var style := StyleBoxFlat.new()
		style.bg_color = BG_COLOR
		style.border_color = BORDER_COLOR
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = PAD_H
		style.content_margin_right = PAD_H
		style.content_margin_top = PAD_V
		style.content_margin_bottom = PAD_V
		_panel.add_theme_stylebox_override("panel", style)

		# Anchor top-center
		_panel.anchor_left = 0.5
		_panel.anchor_right = 0.5
		_panel.anchor_top = 0.0
		_panel.anchor_bottom = 0.0
		_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_panel.offset_top = 6.0

		_label = Label.new()
		_label.text = ""
		_label.add_theme_font_size_override("font_size", FONT_SIZE)
		_label.add_theme_color_override("font_color", TEXT_COLOR)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.mouse_filter = MOUSE_FILTER_IGNORE
		_panel.add_child(_label)

		add_child(_panel)

	func set_info(quest_id: String, section_text: String, cell_pos: String) -> void:
		if not _label:
			return
		var parts: PackedStringArray = PackedStringArray()
		if not quest_id.is_empty():
			parts.append(quest_id)
		if not section_text.is_empty():
			parts.append(section_text)
		if not cell_pos.is_empty():
			parts.append("Cell %s" % cell_pos)
		_label.text = " | ".join(parts)


# ── Stats Panel (top-left) ───────────────────────────────────────────────────

class _StatsPanel extends Control:
	const PANEL_W := 256.0
	const PANEL_H := 120.0
	const BAR_LEFT := 76.0
	const BAR_WIDTH := 160.0
	const BAR_HEIGHT := 7.0
	const HP_BAR_TOP := 62.0
	const PP_BAR_TOP := 98.0
	const LEVEL_FONT_SIZE := 16
	const VAL_FONT_SIZE := 14

	const HP_COLOR := Color(0.27, 0.85, 0.27)
	const PP_COLOR := Color(0.22, 0.56, 0.93)
	const LEVEL_COLOR := Color(1, 1, 1, 1)
	const VALUE_COLOR := Color(0, 0, 0, 1)
	const PANEL_SCALE := 0.8

	var char_name: String = ""
	var char_level: int = 1

	var _level_label: Label
	var _hp_cur_label: Label
	var _hp_max_label: Label
	var _pp_cur_label: Label
	var _pp_max_label: Label
	var _hp_bar: ColorRect
	var _pp_bar: ColorRect

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		position = Vector2(MARGIN, MARGIN)
		size = Vector2(PANEL_W, PANEL_H)
		custom_minimum_size = size
		pivot_offset = Vector2.ZERO
		scale = Vector2(PANEL_SCALE, PANEL_SCALE)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

		var bg := TextureRect.new()
		bg.texture = preload("res://assets/hud/hp-pp.png")
		bg.position = Vector2.ZERO
		bg.size = Vector2(PANEL_W, PANEL_H)
		bg.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(bg)

		_hp_bar = ColorRect.new()
		_hp_bar.color = HP_COLOR
		_hp_bar.position = Vector2(BAR_LEFT, HP_BAR_TOP)
		_hp_bar.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
		_hp_bar.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_hp_bar)

		_pp_bar = ColorRect.new()
		_pp_bar.color = PP_COLOR
		_pp_bar.position = Vector2(BAR_LEFT, PP_BAR_TOP)
		_pp_bar.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
		_pp_bar.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_pp_bar)

		_level_label = _make_label(Vector2(109, 13), Vector2(46, 22), LEVEL_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT, LEVEL_COLOR)
		_hp_cur_label = _make_label(Vector2(109, 40), Vector2(46, 18), VAL_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT, VALUE_COLOR)
		_hp_max_label = _make_label(Vector2(190, 40), Vector2(46, 18), VAL_FONT_SIZE, HORIZONTAL_ALIGNMENT_LEFT, VALUE_COLOR)
		_pp_cur_label = _make_label(Vector2(109, 76), Vector2(46, 18), VAL_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT, VALUE_COLOR)
		_pp_max_label = _make_label(Vector2(190, 76), Vector2(46, 18), VAL_FONT_SIZE, HORIZONTAL_ALIGNMENT_LEFT, VALUE_COLOR)

		update_display()

	func _make_label(pos: Vector2, sz: Vector2, font_size: int, align: int, color: Color) -> Label:
		var lbl := Label.new()
		lbl.position = pos
		lbl.size = sz
		lbl.custom_minimum_size = sz
		lbl.horizontal_alignment = align
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", font_size)
		lbl.add_theme_color_override("font_color", color)
		lbl.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(lbl)
		return lbl

	func update_display() -> void:
		if not is_inside_tree():
			return
		var hp: int = GameState.hp
		var max_hp: int = GameState.max_hp
		var pp: int = GameState.mp
		var max_pp: int = GameState.max_mp

		_level_label.text = str(char_level)
		_hp_cur_label.text = str(hp)
		_hp_max_label.text = str(max_hp)
		_pp_cur_label.text = str(pp)
		_pp_max_label.text = str(max_pp)

		var hp_ratio: float = clampf(float(hp) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 0.0
		var pp_ratio: float = clampf(float(pp) / float(max_pp), 0.0, 1.0) if max_pp > 0 else 0.0
		_hp_bar.size.x = BAR_WIDTH * hp_ratio
		_hp_bar.visible = hp_ratio > 0.0
		_pp_bar.size.x = BAR_WIDTH * pp_ratio
		_pp_bar.visible = pp_ratio > 0.0


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
	## PSO-style action palette: reads from ActionPalette autoload.
	## Swap centered above, slot 0 and 2 raised, slot 1 lower (diamond-ish layout).

	const PILL_BG := Color(0.08, 0.08, 0.12, 0.7)
	const PILL_BORDER := Color(0.3, 0.5, 0.3, 0.5)
	const LABEL_LIGHT := Color(0.23, 0.29, 0.35)
	const FONT_SIZE_SMALL := 8

	# Layout constants — square pills for icons
	const PILL_W := 36.0
	const PILL_H := 36.0
	const SWAP_W := 40.0
	const SWAP_H := 18.0
	const GAP := 4.0
	const RAISED := 10.0  # Outer slots raised above center

	const KENNEY_BASE := "res://assets/kenney_input-prompts/"

	## Swap button icon per scheme
	const SWAP_ICONS := {
		"keyboard":  "Keyboard & Mouse/Default/keyboard_i.png",
		"xinput":    "Xbox Series/Default/xbox_rb.png",
		"switch":    "Nintendo Switch/Default/switch_button_r.png",
		"ds_cross":  "PlayStation Series/Default/playstation_trigger_r1.png",
		"ds_circle": "PlayStation Series/Default/playstation_trigger_r1.png",
	}
	const SWAP_KEY_FALLBACK := {
		"keyboard": "I", "xinput": "RB", "switch": "R", "ds_cross": "R1", "ds_circle": "R1",
	}

	var _bg_pill: StyleBoxFlat
	var _bg_swap: StyleBoxFlat
	var _swap_texture: Texture2D = null
	var _slot_icons: Array = []  # TextureRect nodes for action icons

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

		# Use nearest filtering so pixel art icons don't blur to white
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

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

		# Load icons for current control scheme
		_load_scheme_icons()

		# Create TextureRect nodes for action slot icons
		var row_y: float = SWAP_H + 2.0
		for i in range(3):
			var tex_rect := TextureRect.new()
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex_rect.mouse_filter = MOUSE_FILTER_IGNORE
			var px: float = i * (PILL_W + GAP)
			var py: float = row_y + RAISED if i == 1 else row_y
			tex_rect.position = Vector2(px, py)
			tex_rect.size = Vector2(PILL_W, PILL_H)
			add_child(tex_rect)
			_slot_icons.append(tex_rect)
		_update_slot_icons()

		# Connect to ActionPalette signals for live updates
		ActionPalette.page_changed.connect(_on_palette_changed)
		ActionPalette.config_changed.connect(_on_palette_changed)
		if InputConfig.has_signal("scheme_changed"):
			InputConfig.scheme_changed.connect(_on_scheme_changed)

	func _on_scheme_changed(_scheme = null) -> void:
		_load_scheme_icons()
		queue_redraw()

	func _load_scheme_icons() -> void:
		var scheme: String = InputConfig.current_scheme
		var swap_path: String = KENNEY_BASE + SWAP_ICONS.get(scheme, SWAP_ICONS["keyboard"])
		if ResourceLoader.exists(swap_path):
			_swap_texture = load(swap_path)
		else:
			_swap_texture = null

	## Consumable action IDs that map to inventory items with counts.
	const CONSUMABLE_IDS := ["monomate", "dimate", "trimate", "monofluid", "difluid", "trifluid"]

	func _update_slot_icons() -> void:
		var slots: Array = ActionPalette.get_current_slots()
		for i in range(3):
			var action_id: String = slots[i] if i < slots.size() else ""
			var icon: Texture2D = ActionPalette.get_action_icon(action_id)
			if i < _slot_icons.size():
				_slot_icons[i].texture = icon
				_slot_icons[i].visible = icon != null
				# Grey out consumable icons when count is 0
				if action_id in CONSUMABLE_IDS:
					var qty: int = Inventory.get_item_count(action_id)
					_slot_icons[i].modulate = Color(0.3, 0.3, 0.3) if qty <= 0 else Color.WHITE
				else:
					_slot_icons[i].modulate = Color.WHITE

	func _on_palette_changed(_arg = null) -> void:
		_update_slot_icons()
		queue_redraw()

	func _process(_delta: float) -> void:
		# Live-update item counts (consumed mid-combat, picked up, etc.)
		_update_slot_icons()
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var total_w: float = size.x

		var page_idx: int = ActionPalette.current_page
		var page_count: int = ActionPalette.pages.size()
		var slots: Array = ActionPalette.get_current_slots()

		# Swap badge — centered above slots
		var swap_x: float = (total_w - SWAP_W) * 0.5
		var swap_y: float = 0.0
		draw_style_box(_bg_swap, Rect2(swap_x, swap_y, SWAP_W, SWAP_H))

		# Swap button icon or text fallback
		if _swap_texture:
			var icon_size := 14.0
			draw_texture_rect(_swap_texture, Rect2(swap_x + 4, swap_y + 2, icon_size, icon_size), false)
		else:
			var scheme: String = InputConfig.current_scheme
			var swap_key: String = SWAP_KEY_FALLBACK.get(scheme, "R")
			draw_string(font, Vector2(swap_x + 6, swap_y + 14), swap_key,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SMALL, Color.WHITE)

		# Palette number
		var pn_text := "%d/%d" % [page_idx + 1, page_count]
		draw_string(font, Vector2(swap_x + 26, swap_y + 14), pn_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SMALL, LABEL_LIGHT)

		# 3 action slots — outer raised, center lower (diamond)
		var row_y: float = SWAP_H + 2.0
		for i in range(3):
			var action_id: String = slots[i] if i < slots.size() else ""

			var px: float = i * (PILL_W + GAP)
			var py: float = row_y + RAISED if i == 1 else row_y

			# Icons are handled by TextureRect children (_slot_icons)
			# Only draw text fallback if no icon
			if i < _slot_icons.size() and not _slot_icons[i].visible:
				draw_style_box(_bg_pill, Rect2(px, py, PILL_W, PILL_H))
				var data: Dictionary = ActionPalette.get_action_data(action_id)
				var lbl: String = data.get("short", action_id)
				var lbl_w: float = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SMALL).x
				draw_string(font, Vector2(px + (PILL_W - lbl_w) * 0.5, py + PILL_H * 0.5 + 4),
					lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_SMALL, Color.WHITE)

			# Item count badge for consumable slots (#189)
			if action_id in CONSUMABLE_IDS:
				var qty: int = Inventory.get_item_count(action_id)
				var badge_text := "x%d" % qty
				var badge_color: Color = Color(0.9, 0.9, 0.9) if qty > 0 else Color(0.5, 0.3, 0.3)
				var badge_w: float = font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
				# Bottom-right corner of the pill
				draw_string(font, Vector2(px + PILL_W - badge_w - 2, py + PILL_H - 2),
					badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, badge_color)



# ── Quick Menu (bottom-left, 3-page: Weapon / Item / Tech) ───────────────────

class _QuickMenu extends Control:
	## PSO-style quick menu with three pages — Weapon, Item, Technique.
	## Toggle with quick_weapon input; cycle pages with palette_swap (R1/Tab).
	## Accept selects (equip weapon, use item, cast tech). Cancel closes.
	## Remembers last-open page for the session.

	enum Page { WEAPON, ITEM, TECH }
	const PAGE_LABELS := ["Weapon", "Item", "Technique"]

	const MENU_W := 200.0
	const ROW_H := 22.0
	const VISIBLE_ROWS := 5
	const HEADER_H := 24.0
	const MENU_H: float = HEADER_H + ROW_H * VISIBLE_ROWS + 8.0
	const BG_COLOR := Color(0.05, 0.05, 0.1, 0.85)
	const BORDER_COLOR := Color(0.3, 0.5, 0.3, 0.6)
	const HEADER_BG := Color(0.10, 0.18, 0.35, 0.9)
	const SELECTED_BG := Color(0.15, 0.3, 0.15, 0.8)
	const EQUIPPED_COLOR := Color(0.3, 0.8, 0.3)
	const TEXT_COLOR := Color(0.85, 0.85, 0.85)
	const TEXT_DIM := Color(0.5, 0.5, 0.5)
	const EMPTY_COLOR := Color(0.4, 0.4, 0.5)
	const HEADER_TEXT_COL := Color(1.0, 1.0, 1.0, 0.95)
	const TAB_INACTIVE := Color(0.5, 0.5, 0.6, 0.7)
	const PP_COLOR := Color(0.4, 0.6, 1.0)

	var _is_open: bool = false
	var _current_page: int = Page.WEAPON  # persists across open/close
	var _selected_index: int = 0
	var _scroll_offset: int = 0
	var _list: Array = []  # [{id, name, equipped?, quantity?, pp_cost?}]

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		visible = false
		anchor_left = 0.0
		anchor_right = 0.0
		anchor_top = 1.0
		anchor_bottom = 1.0
		offset_left = MARGIN
		offset_right = MARGIN + MENU_W
		offset_top = -MARGIN - MENU_H
		offset_bottom = -MARGIN
		custom_minimum_size = Vector2(MENU_W, MENU_H)
		size = Vector2(MENU_W, MENU_H)

	func _unhandled_input(event: InputEvent) -> void:
		# Mouse wheel opens menu and navigates
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
				if not _is_open:
					_open()
				if _list.size() > 0:
					if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
						_selected_index = wrapi(_selected_index - 1, 0, _list.size())
					else:
						_selected_index = wrapi(_selected_index + 1, 0, _list.size())
					_update_scroll()
					queue_redraw()
				get_viewport().set_input_as_handled()
				return

		if event.is_action_pressed("quick_weapon"):
			if _is_open:
				_close()
			else:
				_open()
			get_viewport().set_input_as_handled()
			return

		if not _is_open:
			return

		# Page cycle: palette_swap (R1) flips Weapon -> Item -> Tech -> Weapon
		if event.is_action_pressed("palette_swap"):
			_current_page = wrapi(_current_page + 1, 0, 3)
			_rebuild_list()
			SfxManager.play("res://assets/sfx/ui/menu_move.wav")
			get_viewport().set_input_as_handled()
			return

		if event.is_action_pressed("ui_up"):
			if _list.size() > 0:
				_selected_index = wrapi(_selected_index - 1, 0, _list.size())
				SfxManager.play("res://assets/sfx/ui/menu_move.wav")
			_update_scroll()
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down"):
			if _list.size() > 0:
				_selected_index = wrapi(_selected_index + 1, 0, _list.size())
				SfxManager.play("res://assets/sfx/ui/menu_move.wav")
			_update_scroll()
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			_activate_selected()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel"):
			_close()
			get_viewport().set_input_as_handled()

	# ── Open / Close ──

	func _open() -> void:
		_rebuild_list()
		_is_open = true
		visible = true
		SfxManager.play("res://assets/sfx/ui/menu_open.wav")
		queue_redraw()

	func _close() -> void:
		_is_open = false
		visible = false
		SfxManager.play("res://assets/sfx/ui/menu_close.wav")

	# ── List builders ──

	func _rebuild_list() -> void:
		_list.clear()
		_selected_index = 0
		_scroll_offset = 0
		match _current_page:
			Page.WEAPON:
				_build_weapon_list()
			Page.ITEM:
				_build_item_list()
			Page.TECH:
				_build_tech_list()
		queue_redraw()

	func _build_weapon_list() -> void:
		var character = CharacterManager.get_active_character()
		if character == null:
			return
		var class_id: String = str(character.get("class_id", ""))
		var class_data = ClassRegistry.get_class_data(class_id)
		var equipped_id: String = str(character.get("equipment", {}).get("weapon", ""))

		for item_info in Inventory.get_all_items():
			var item_id: String = str(item_info.get("id", ""))
			var base_id: String = Inventory.get_base_id(item_id)
			var weapon = WeaponRegistry.get_weapon(base_id)
			if weapon == null:
				continue
			if class_data and not class_data.can_equip_weapon_type(weapon.weapon_type):
				continue
			var is_equipped: bool = item_id == equipped_id
			_list.append({"id": item_id, "name": str(item_info.get("name", base_id)), "equipped": is_equipped})

		# Sort: equipped first, then alphabetical
		_list.sort_custom(func(a, b):
			if a.equipped != b.equipped:
				return a.equipped
			return str(a.name) < str(b.name)
		)
		# Pre-select equipped weapon
		for i in range(_list.size()):
			if _list[i].get("equipped", false):
				_selected_index = i
				break

	func _build_item_list() -> void:
		# Show consumable items only (monomate, dimate, etc.)
		for item_info in Inventory.get_all_items():
			var item_id: String = str(item_info.get("id", ""))
			var base_id: String = Inventory.get_base_id(item_id)
			# Include consumables and telepipes
			if Inventory.CONSUMABLE_EFFECTS.has(base_id) or base_id == "telepipe":
				var qty: int = int(item_info.get("quantity", 1))
				_list.append({"id": item_id, "name": str(item_info.get("name", base_id)), "quantity": qty})

		_list.sort_custom(func(a, b):
			return str(a.name) < str(b.name)
		)

	func _build_tech_list() -> void:
		var character = CharacterManager.get_active_character()
		if character == null:
			return
		var techniques: Dictionary = character.get("techniques", {})
		for tech_id in techniques:
			var level: int = int(techniques[tech_id])
			if level <= 0:
				continue
			var tech: Dictionary = TechniqueManager.TECHNIQUES.get(tech_id, {})
			if tech.is_empty():
				continue
			var pp_cost: int = int(tech.get("pp", 0))
			_list.append({"id": tech_id, "name": "%s Lv.%d" % [tech["name"], level], "pp_cost": pp_cost})

		_list.sort_custom(func(a, b):
			return str(a.name) < str(b.name)
		)

	# ── Scroll ──

	func _update_scroll() -> void:
		if _selected_index < _scroll_offset:
			_scroll_offset = _selected_index
		elif _selected_index >= _scroll_offset + VISIBLE_ROWS:
			_scroll_offset = _selected_index - VISIBLE_ROWS + 1
		_scroll_offset = clampi(_scroll_offset, 0, maxi(0, _list.size() - VISIBLE_ROWS))

	# ── Activate (accept) ──

	func _activate_selected() -> void:
		if _selected_index < 0 or _selected_index >= _list.size():
			return
		var entry: Dictionary = _list[_selected_index]

		match _current_page:
			Page.WEAPON:
				_equip_weapon(entry)
			Page.ITEM:
				_use_item(entry)
			Page.TECH:
				_cast_tech(entry)

	func _equip_weapon(entry: Dictionary) -> void:
		if entry.get("equipped", false):
			_close()
			return
		var character = CharacterManager.get_active_character()
		if character == null:
			return
		var equipment: Dictionary = character.get("equipment", {})
		equipment["weapon"] = entry.id
		print("[QuickMenu] Equipped: %s" % entry.name)
		SfxManager.play("res://assets/sfx/ui/menu_select.wav")

		var players: Array = get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0].has_method("refresh_weapon"):
			players[0].refresh_weapon()
		_close()

	func _use_item(entry: Dictionary) -> void:
		var base_id: String = Inventory.get_base_id(str(entry.id))
		if not Inventory.has_item(str(entry.id)):
			SfxManager.play("res://assets/sfx/ui/menu_invalid.wav")
			return

		# Route to player for consumable use (so heal numbers spawn, etc.)
		var players: Array = get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0].has_method("use_consumable_from_menu"):
			players[0].use_consumable_from_menu(base_id)
		else:
			Inventory.use_item(str(entry.id))
		SfxManager.play("res://assets/sfx/ui/menu_select.wav")

		# Refresh list (quantity changed); stay on same page
		var prev_idx := _selected_index
		_rebuild_list()
		_selected_index = mini(prev_idx, maxi(0, _list.size() - 1))
		_update_scroll()

	func _cast_tech(entry: Dictionary) -> void:
		var players: Array = get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0].has_method("cast_technique_from_menu"):
			players[0].cast_technique_from_menu(str(entry.id))
		SfxManager.play("res://assets/sfx/ui/menu_select.wav")
		_close()

	# ── Drawing ──

	func _draw() -> void:
		if not _is_open:
			return
		var font: Font = ThemeDB.fallback_font

		# Background
		draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
		draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 1.0)

		# Header bar with page tabs
		draw_rect(Rect2(0, 0, MENU_W, HEADER_H), HEADER_BG)
		var tab_w: float = MENU_W / 3.0
		for i in range(3):
			var tx: float = tab_w * i
			var tab_color: Color = HEADER_TEXT_COL if i == _current_page else TAB_INACTIVE
			var label_text: String = PAGE_LABELS[i]
			var lbl_w: float = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(font, Vector2(tx + (tab_w - lbl_w) * 0.5, HEADER_H - 7),
				label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tab_color)
			# Active tab underline
			if i == _current_page:
				draw_line(Vector2(tx + 4, HEADER_H - 1), Vector2(tx + tab_w - 4, HEADER_H - 1),
					EQUIPPED_COLOR, 2.0)

		# Empty list message
		if _list.is_empty():
			var empty_text: String = "No %ss available" % PAGE_LABELS[_current_page].to_lower()
			var ew: float = font.get_string_size(empty_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(font, Vector2((MENU_W - ew) * 0.5, HEADER_H + MENU_H * 0.3),
				empty_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, EMPTY_COLOR)
			return

		# Draw visible rows
		var y: float = HEADER_H + 4.0
		var end_idx: int = mini(_scroll_offset + VISIBLE_ROWS, _list.size())
		for i in range(_scroll_offset, end_idx):
			var entry: Dictionary = _list[i]
			var row_rect := Rect2(2, y, MENU_W - 4, ROW_H)

			if i == _selected_index:
				draw_rect(row_rect, SELECTED_BG)

			var label: String = str(entry.name)
			var color: Color = TEXT_COLOR
			var right_text: String = ""
			var right_color: Color = TEXT_DIM

			match _current_page:
				Page.WEAPON:
					if entry.get("equipped", false):
						label = "> " + label
						color = EQUIPPED_COLOR
				Page.ITEM:
					var qty: int = int(entry.get("quantity", 0))
					right_text = "x%d" % qty
					if qty <= 0:
						color = TEXT_DIM
				Page.TECH:
					var pp: int = int(entry.get("pp_cost", 0))
					right_text = "%dPP" % pp
					right_color = PP_COLOR
					# Dim if not enough PP
					if GameState.mp < pp:
						color = TEXT_DIM
						right_color = TEXT_DIM

			draw_string(font, Vector2(8, y + ROW_H - 6), label,
				HORIZONTAL_ALIGNMENT_LEFT, MENU_W - 50, 12, color)

			# Right-aligned info (quantity or PP cost)
			if not right_text.is_empty():
				var rw: float = font.get_string_size(right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
				draw_string(font, Vector2(MENU_W - rw - 8, y + ROW_H - 6),
					right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, right_color)

			y += ROW_H

		# Scroll indicators
		if _scroll_offset > 0:
			draw_string(font, Vector2(MENU_W - 16, HEADER_H + 14), "▲",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_DIM)
		if end_idx < _list.size():
			draw_string(font, Vector2(MENU_W - 16, MENU_H - 4), "▼",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_DIM)

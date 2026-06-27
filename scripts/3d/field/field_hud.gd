extends CanvasLayer
## Field HUD — shows player stats (HP/PP bars, level, name) top-left,
## quest log docked left (toggleable, only when quest active),
## and hosts the room minimap (always visible).

const MARGIN := 12.0

var _stats_panel: Control
var _quest_log: Control
var _action_palette: Control
var _quick_weapon: Control
var _debug_info: Control
var _fps_label: Label
# Cached state for the autopilot debug overlay so _process can re-render the
# wall-clock without re-querying the field controller every frame.
var _session_start_msec: int = 0
var _debug_last_quest: String = ""
var _debug_last_section: String = ""
var _debug_last_cell: String = ""
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

	_quick_weapon = _QuickWeaponMenu.new()
	add_child(_quick_weapon)

	_connect_player_charge_signals.call_deferred()

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

	# Quest-context overlay (top-center): quest id, section, cell, wall-clock.
	# Only mounted when PSZ_AUTOPILOT=1 so it's invisible in normal play but
	# always visible in recorded autopilot runs — makes debugging stuck-walks
	# from the recording-window timestamp trivial.
	if OS.has_environment("PSZ_AUTOPILOT"):
		_debug_info = _DebugInfoPanel.new()
		add_child(_debug_info)
		set_process(true)
		_session_start_msec = Time.get_ticks_msec()

	# Quest log disabled for now
	_log_visible = false


func _connect_player_charge_signals() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player = players[0]
	if player.has_signal("tech_charge_started"):
		player.tech_charge_started.connect(func(_slot: int): pass)
		player.tech_charge_ready.connect(func(slot: int): _action_palette.set_charging_slot(slot))
		player.tech_charge_released.connect(func(_slot: int): _action_palette.set_charging_slot(-1))


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

	# Autopilot HUD overlay (top-center): wall-clock + quest + cell. The
	# overlay is only instantiated when PSZ_AUTOPILOT=1, so this is a
	# cheap nil-check in normal play.
	if _debug_info:
		_render_debug_info()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quest_log"):
		_toggle_log()
		get_viewport().set_input_as_handled()


func _toggle_log() -> void:
	if not _quest_log:
		return
	_log_visible = not _log_visible
	_quest_log.visible = _log_visible


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
			# A DialogBox owns its own visibility (only up while a dialog is
			# active). Blanket-restoring it re-shows a box the player already
			# closed — the "Picked up X" toast that then sticks until the room
			# unloads. Honour its active state; everything else restores normally.
			if child is DialogBox:
				child.visible = (child as DialogBox).is_active()
			else:
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
## No-op when the panel wasn't mounted (i.e. PSZ_AUTOPILOT wasn't set).
func set_debug_info(quest_id: String, section_text: String, cell_pos: String) -> void:
	_debug_last_quest = quest_id
	_debug_last_section = section_text
	_debug_last_cell = cell_pos
	if _debug_info:
		_render_debug_info()


func _render_debug_info() -> void:
	if not _debug_info or not (_debug_info is _DebugInfoPanel):
		return
	var elapsed_ms: int = Time.get_ticks_msec() - _session_start_msec
	var total_sec: int = elapsed_ms / 1000
	var mm: int = total_sec / 60
	var ss: int = total_sec % 60
	var time_str := "%02d:%02d" % [mm, ss]
	(_debug_info as _DebugInfoPanel).set_info(time_str, _debug_last_quest, _debug_last_section, _debug_last_cell)


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

	func set_info(time_str: String, quest_id: String, section_text: String, cell_pos: String) -> void:
		if not _label:
			return
		var parts: PackedStringArray = PackedStringArray()
		if not time_str.is_empty():
			parts.append(time_str)
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
	## PSZ-style action palette: octagon HUD with 3 slots in diamond layout.
	## Tapping R swaps between palette_bg.png (page 1) and palette_bg_r.png (page 2).

	const PALETTE_BG_BASE := "res://assets/ui/psz-palette/palette_bg"
	const FONT_SIZE_SMALL := 8
	const FONT_SIZE_COUNT := 7
	const LABEL_LIGHT := Color(0.23, 0.29, 0.35)
	const GREY_OUT := Color(1.0, 1.0, 1.0, 0.5)

	# BG image is 128x67; rendered at 2x scale for readability
	const BG_SCALE := 2.0
	const BG_W := 128.0
	const BG_H := 67.0

	# Slot centers measured from pixel analysis of the 128x67 source image.
	# Slots 0 & 2 are raised (y=27), slot 1 is lower (y=41) — diamond layout.
	const SLOT_CENTERS := [
		Vector2(26.0, 27.0),
		Vector2(58.0, 41.0),
		Vector2(90.0, 27.0),
	]
	const ICON_SIZE := 38.0  # Content is ~56% of 32x32 image; 38px shows ~21px visible

	var _bg_textures: Array = [null, null]  # [page1, page2/R variant]
	var _bg_texture: Texture2D = null
	var _slot_icons: Array = []
	var _slot_counts: Array = []
	var _charging_slot: int = -1

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

		var total_w: float = BG_W * BG_SCALE
		var total_h: float = BG_H * BG_SCALE
		custom_minimum_size = Vector2(total_w, total_h)
		size = Vector2(total_w, total_h)

		anchor_left = 1.0
		anchor_right = 1.0
		anchor_top = 1.0
		anchor_bottom = 1.0
		offset_left = -total_w - MARGIN
		offset_right = -MARGIN
		offset_top = -total_h - MARGIN
		offset_bottom = -MARGIN

		var path_1 := PALETTE_BG_BASE + ".png"
		var path_r := PALETTE_BG_BASE + "_r.png"
		if ResourceLoader.exists(path_1):
			_bg_textures[0] = load(path_1)
		if ResourceLoader.exists(path_r):
			_bg_textures[1] = load(path_r)
		_bg_texture = _bg_textures[0]

		for i in range(3):
			var center: Vector2 = SLOT_CENTERS[i] * BG_SCALE
			var icon_display := ICON_SIZE * BG_SCALE

			var tex_rect := TextureRect.new()
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex_rect.mouse_filter = MOUSE_FILTER_IGNORE
			tex_rect.position = Vector2(center.x - icon_display * 0.5, center.y - icon_display * 0.5)
			tex_rect.size = Vector2(icon_display, icon_display)
			add_child(tex_rect)
			_slot_icons.append(tex_rect)

			var count_label := Label.new()
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			count_label.add_theme_font_size_override("font_size", int(FONT_SIZE_COUNT * BG_SCALE))
			count_label.add_theme_color_override("font_color", Color.WHITE)
			count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
			count_label.add_theme_constant_override("shadow_offset_x", 1)
			count_label.add_theme_constant_override("shadow_offset_y", 1)
			count_label.position = Vector2(center.x - icon_display * 0.5, center.y + icon_display * 0.25)
			count_label.size = Vector2(icon_display, 16.0 * BG_SCALE)
			count_label.mouse_filter = MOUSE_FILTER_IGNORE
			count_label.visible = false
			add_child(count_label)
			_slot_counts.append(count_label)

		_update_slot_icons()

		ActionPalette.page_changed.connect(_on_palette_changed)
		ActionPalette.config_changed.connect(_on_palette_changed)
		Inventory.item_added.connect(_on_inventory_changed)
		Inventory.item_removed.connect(_on_inventory_changed)

	func _update_slot_icons() -> void:
		var slots: Array = ActionPalette.get_current_slots()
		for i in range(3):
			var action_id: String = slots[i] if i < slots.size() else ""
			var icon: Texture2D
			if i == _charging_slot:
				icon = ActionPalette.get_charge_icon(action_id)
				if icon == null:
					icon = ActionPalette.get_action_icon(action_id)
			else:
				icon = ActionPalette.get_action_icon(action_id)
			if i < _slot_icons.size():
				_slot_icons[i].texture = icon
				_slot_icons[i].visible = icon != null

			_update_slot_count(i, action_id)

	func _update_slot_count(slot: int, action_id: String) -> void:
		if slot >= _slot_counts.size():
			return
		var label: Label = _slot_counts[slot]
		if ActionPalette.is_consumable(action_id):
			var count: int = Inventory.get_item_count(action_id)
			label.text = "x%d" % count
			label.visible = true
			if count <= 0:
				_slot_icons[slot].modulate = GREY_OUT
			else:
				_slot_icons[slot].modulate = Color.WHITE
		else:
			label.visible = false
			_slot_icons[slot].modulate = Color.WHITE

	func set_charging_slot(slot: int) -> void:
		_charging_slot = slot
		_update_slot_icons()
		queue_redraw()

	func _on_palette_changed(_arg = null) -> void:
		var page_idx: int = ActionPalette.current_page
		var tex_idx: int = clampi(page_idx, 0, _bg_textures.size() - 1)
		_bg_texture = _bg_textures[tex_idx] if _bg_textures[tex_idx] else _bg_textures[0]
		_update_slot_icons()
		queue_redraw()

	func _on_inventory_changed(_arg1 = null, _arg2 = null, _arg3 = null) -> void:
		_update_slot_icons()
		queue_redraw()

	func _draw() -> void:
		if _bg_texture:
			draw_texture_rect(_bg_texture, Rect2(Vector2.ZERO, size), false)

		var slots: Array = ActionPalette.get_current_slots()
		var font := ThemeDB.fallback_font
		for i in range(3):
			if i < _slot_icons.size() and not _slot_icons[i].visible:
				var action_id: String = slots[i] if i < slots.size() else ""
				var data: Dictionary = ActionPalette.get_action_data(action_id)
				var lbl: String = data.get("short", action_id)
				var center: Vector2 = SLOT_CENTERS[i] * BG_SCALE
				var lbl_w: float = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FONT_SIZE_SMALL * BG_SCALE)).x
				draw_string(font, Vector2(center.x - lbl_w * 0.5, center.y + 4.0),
					lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, int(FONT_SIZE_SMALL * BG_SCALE), Color.WHITE)


# ── Quick Weapon Menu (bottom-left, toggled with quick_weapon input) ─────────

class _QuickWeaponMenu extends Control:
	## Small scrollable weapon select overlay. Shows equipped weapon + equippable
	## weapons from inventory. 5 visible lines, scroll with up/down, accept to
	## equip, cancel to close.

	const MENU_W := 180.0
	const ROW_H := 22.0
	const VISIBLE_ROWS := 5
	const MENU_H: float = ROW_H * VISIBLE_ROWS + 8.0  # 5 rows + padding
	const BG_COLOR := Color(0.05, 0.05, 0.1, 0.85)
	const BORDER_COLOR := Color(0.3, 0.5, 0.3, 0.6)
	const SELECTED_BG := Color(0.15, 0.3, 0.15, 0.8)
	const EQUIPPED_COLOR := Color(0.3, 0.8, 0.3)
	const TEXT_COLOR := Color(0.85, 0.85, 0.85)
	const TEXT_DIM := Color(0.5, 0.5, 0.5)

	var _is_open: bool = false
	var _selected_index: int = 0
	var _scroll_offset: int = 0
	var _weapon_list: Array = []  # [{id, name, equipped}]
	# Shared hold-to-repeat (d-pad + right stick), same as the shops/start menu.
	var _nav: NavRepeat

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		visible = false
		_nav = NavRepeat.new(["ui_up", "ui_down"], _on_nav_repeat)
		set_process(true)
		# Bottom-left positioning
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
		# Mouse wheel opens menu and navigates (works when closed or open)
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
				if not _is_open:
					_open()
				_move_selection(-1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
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

		# Right-stick scroll is driven by NavRepeat (polls the axis + repeats like
		# the d-pad); swallow its motion events so they don't also pan the camera
		# while the menu is open.
		if event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis == JOY_AXIS_RIGHT_Y:
			get_viewport().set_input_as_handled()
			return

		if event.is_action_pressed("ui_up"):
			_move_selection(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down"):
			_move_selection(1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			_equip_selected()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel"):
			_close()
			get_viewport().set_input_as_handled()


	## Move the cursor and keep it in the scroll window. Shared by d-pad,
	## right-stick repeat (NavRepeat), and the mouse wheel.
	func _move_selection(dir: int) -> void:
		if _weapon_list.is_empty():
			return
		_selected_index = wrapi(_selected_index + dir, 0, _weapon_list.size())
		_update_scroll()
		queue_redraw()


	func _on_nav_repeat(action: String) -> void:
		if _is_open:
			_move_selection(-1 if action == "ui_up" else 1)


	func _process(delta: float) -> void:
		# Tick hold-to-repeat only while open; reset so the right stick stays free
		# for the camera otherwise.
		if _nav:
			if _is_open:
				_nav.tick(delta)
			else:
				_nav.reset()

	func _open() -> void:
		_build_weapon_list()
		if _weapon_list.is_empty():
			return
		_is_open = true
		visible = true
		# Pre-select currently equipped weapon
		for i in range(_weapon_list.size()):
			if _weapon_list[i].equipped:
				_selected_index = i
				break
		_update_scroll()
		queue_redraw()

	func _close() -> void:
		_is_open = false
		visible = false

	func _build_weapon_list() -> void:
		_weapon_list.clear()
		var character = CharacterManager.get_active_character()
		if character == null:
			return
		var class_id: String = str(character.get("class_id", ""))
		var class_data = ClassRegistry.get_class_data(class_id)
		var equipped_id: String = str(character.get("equipment", {}).get("weapon", ""))

		# Gather all weapons from inventory that this class can equip
		for item_info in Inventory.get_all_items():
			var item_id: String = str(item_info.get("id", ""))
			var base_id: String = Inventory.get_base_id(item_id)
			var weapon = WeaponRegistry.get_weapon(base_id)
			if weapon == null:
				continue
			if class_data and not class_data.can_equip_weapon_type(weapon.weapon_type):
				continue
			var is_equipped: bool = item_id == equipped_id
			_weapon_list.append({"id": item_id, "name": str(item_info.get("name", base_id)), "equipped": is_equipped})

		# Sort: equipped first, then alphabetical
		_weapon_list.sort_custom(func(a, b):
			if a.equipped != b.equipped:
				return a.equipped  # equipped comes first
			return str(a.name) < str(b.name)
		)

	func _update_scroll() -> void:
		# Keep selected item visible in the scroll window
		if _selected_index < _scroll_offset:
			_scroll_offset = _selected_index
		elif _selected_index >= _scroll_offset + VISIBLE_ROWS:
			_scroll_offset = _selected_index - VISIBLE_ROWS + 1
		_scroll_offset = clampi(_scroll_offset, 0, maxi(0, _weapon_list.size() - VISIBLE_ROWS))

	func _equip_selected() -> void:
		if _selected_index < 0 or _selected_index >= _weapon_list.size():
			return
		var weapon_entry: Dictionary = _weapon_list[_selected_index]
		if weapon_entry.equipped:
			_close()
			return

		# Equip the weapon
		var character = CharacterManager.get_active_character()
		if character == null:
			return
		var equipment: Dictionary = character.get("equipment", {})
		equipment["weapon"] = weapon_entry.id
		print("[QuickWeapon] Equipped: %s" % weapon_entry.name)

		# Refresh player model
		var players: Array = get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0].has_method("refresh_weapon"):
			players[0].refresh_weapon()

		_close()

	func _draw() -> void:
		if not _is_open:
			return
		var font: Font = ThemeDB.fallback_font

		# Background
		draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
		draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 1.0)

		# Draw visible rows
		var y := 4.0
		var end_idx: int = mini(_scroll_offset + VISIBLE_ROWS, _weapon_list.size())
		for i in range(_scroll_offset, end_idx):
			var entry: Dictionary = _weapon_list[i]
			var row_rect := Rect2(2, y, MENU_W - 4, ROW_H)

			# Highlight selected
			if i == _selected_index:
				draw_rect(row_rect, SELECTED_BG)

			# Equipped marker
			var label: String = str(entry.name)
			var color: Color = TEXT_COLOR
			if entry.equipped:
				label = "> " + label
				color = EQUIPPED_COLOR

			draw_string(font, Vector2(8, y + ROW_H - 6), label,
				HORIZONTAL_ALIGNMENT_LEFT, MENU_W - 16, 12, color)
			y += ROW_H

		# Scroll indicators
		if _scroll_offset > 0:
			draw_string(font, Vector2(MENU_W - 16, 14), "\u25b2",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_DIM)
		if end_idx < _weapon_list.size():
			draw_string(font, Vector2(MENU_W - 16, MENU_H - 4), "\u25bc",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_DIM)

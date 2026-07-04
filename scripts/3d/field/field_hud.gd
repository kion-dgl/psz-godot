extends CanvasLayer
## Field HUD — per-scene HUD elements: quest log docked left (toggleable, only
## when quest active), action palette, quick weapon menu, FPS counter, and it
## hosts the room minimap (always visible).
##
## The HP/PP/Lv stats panel is NOT here: it lives on the persistent HudStats
## autoload (#444; spec /states/field-lifecycle) so it survives area
## transitions instead of being freed/rebuilt with this per-scene layer.

const MARGIN := 12.0

var _target_info: Control
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


func _ready() -> void:
	layer = 200  # Same layer as the HudStats autoload; above start menu (150)
	name = "FieldHud"
	process_mode = Node.PROCESS_MODE_ALWAYS

	_action_palette = _ActionPalette.new()
	add_child(_action_palette)

	# Target info renders under the quick weapon menu in the same corner —
	# the menu owns the corner while open (spec /mechanics/targeting).
	_target_info = _TargetInfoPanel.new()
	add_child(_target_info)

	_quick_weapon = _QuickWeaponMenu.new()
	add_child(_quick_weapon)

	_connect_player_charge_signals.call_deferred()

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
	# Quick Menu open drops an in-progress charge — the fifth drop case
	# (spec /states/player-state, #377), mirroring the PsoStartMenu.opened
	# connection made in player._ready.
	if _quick_weapon and player.has_method("_drop_charge"):
		_quick_weapon.opened.connect(player._drop_charge)


func _process(_delta: float) -> void:
	_update_fps_label()

	# Hide this per-scene HUD when an overlay (shop, menu, dialog) is open, or
	# when the PSO start menu is up — the start menu isn't tracked in
	# SceneManager._overlay_stack so we check its autoload directly. The
	# HP/PP/Lv panel is not ours: the HudStats autoload applies its own
	# keep-visible-under-start-menu rule (#444), so there is no keep_stats
	# special case left here.
	var has_overlay: bool = not SceneManager._overlay_stack.is_empty() or PsoStartMenu.is_open()
	if has_overlay:
		if not _hidden_for_overlay:
			_hidden_for_overlay = true
			hide_for_menu()
	elif _hidden_for_overlay:
		_hidden_for_overlay = false
		restore_after_menu()

	# Action palette is a combat HUD element — hide it in the city (Dairon
	# / Pioneer 2 equivalent) where the player is shopping and talking to
	# NPCs, not fighting. Palette itself is also input-blocked in these
	# scenes via GameState.is_gameplay_blocked() for safety.
	if _action_palette and not _hidden_for_overlay:
		_action_palette.visible = not _is_in_city()

	_update_target_info_panel()

	# Autopilot HUD overlay (top-center): wall-clock + quest + cell. The
	# overlay is only instantiated when PSZ_AUTOPILOT=1, so this is a
	# cheap nil-check in normal play.
	if _debug_info:
		_render_debug_info()


## FPS counter (top-right) — only touches the label when the value changes.
func _update_fps_label() -> void:
	if not _fps_label:
		return
	var fps: int = int(Engine.get_frames_per_second())
	if fps == _fps_label.get_meta("last_fps", -1):
		return
	_fps_label.set_meta("last_fps", fps)
	_fps_label.text = "%d FPS" % fps
	var band: int = 0 if fps < 30 else (1 if fps < 50 else 2)
	if band != _fps_label.get_meta("band", -1):
		_fps_label.set_meta("band", band)
		var colors := [Color(1.0, 0.3, 0.3), Color(1.0, 0.8, 0.2), Color(0.5, 0.8, 0.3)]
		_fps_label.add_theme_color_override("font_color", colors[band])


## Target-info panel (spec /mechanics/targeting): the primary target's info
## in the bottom-left. The quick weapon menu owns that corner while open —
## the panel MUST NOT render under it. Combat HUD element, so the city hides
## it like the palette.
func _update_target_info_panel() -> void:
	if not _target_info or _hidden_for_overlay:
		return
	var info: Dictionary = {}
	if not _is_in_city() and not _quick_weapon.get("_is_open"):
		var players: Array = get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			var v = players[0].get("_primary_target_info")
			if v is Dictionary:
				info = v
	_target_info.update_info(info)


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


## Hide all per-scene HUD elements when a menu/shop/dialog is open. The
## persistent HP/PP/Lv panel (HudStats autoload) manages its own visibility —
## it stays up under the PSO start menu and hides under full-screen
## SceneManager overlays (#444).
func hide_for_menu() -> void:
	for child in get_children():
		if child is Control:
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

	# Centers of the 22x22 dark recess in each slot, pixel-analysis centroids
	# of the 128x67 source (the black area, not the octagon rim). Slots 0 & 2
	# are raised (y=27.5), slot 1 is lower (y=41.5) — diamond layout.
	const SLOT_CENTERS := [
		Vector2(26.5, 27.5),
		Vector2(58.5, 41.5),
		Vector2(90.5, 27.5),
	]
	const ICON_SIZE := 18.0  # Cropped 20x20 art drawn into an 18px box — sits centered inside the ~22px black recess with margin

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

class _TargetInfoPanel extends Control:
	## Bottom-left primary-target plate (spec /mechanics/targeting): enemy →
	## name + HP bar; ground item → item name. Renders NOTHING without a
	## target; field_hud._process keeps it hidden while the quick weapon menu
	## owns the corner. Drawn in the shared PszPanel plate style.

	const PANEL_W := 200.0
	const PANEL_H := 54.0
	const HP_COLOR := Color(0.27, 0.85, 0.27)
	const HP_LOW_COLOR := Color(0.92, 0.66, 0.2)
	const HP_TRACK := Color(0.19, 0.31, 0.49)

	var _info: Dictionary = {}

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		visible = false
		anchor_left = 0.0
		anchor_right = 0.0
		anchor_top = 1.0
		anchor_bottom = 1.0
		offset_left = MARGIN
		offset_right = MARGIN + PANEL_W
		offset_top = -MARGIN - PANEL_H
		offset_bottom = -MARGIN
		size = Vector2(PANEL_W, PANEL_H)

	func update_info(info: Dictionary) -> void:
		if info == _info:
			return
		_info = info.duplicate()
		visible = not _info.is_empty()
		queue_redraw()

	func _draw() -> void:
		if _info.is_empty():
			return
		var font: Font = ThemeDB.fallback_font
		PszPanel.draw_plate(self, size, false)
		if str(_info.get("kind")) == "enemy":
			draw_string(font, Vector2(14, 20), str(_info.get("name", "")),
				HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 28, 13, PszPanel.TEXT_DARK)
			var max_hp: int = int(_info.get("max_hp", 0))
			var hp: int = int(_info.get("hp", 0))
			var ratio: float = clampf(float(hp) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 0.0
			var bar := Rect2(14, 28, PANEL_W - 42, 7)
			draw_rect(bar, HP_TRACK)
			if ratio > 0.0:
				draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)),
					HP_COLOR if ratio > 0.35 else HP_LOW_COLOR)
			draw_string(font, Vector2(14, 47), "HP %d/%d" % [hp, max_hp],
				HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 28, 10, PszPanel.TEXT_DARK)
		else:
			draw_string(font, Vector2(14, 18), "ITEM",
				HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 28, 9, Color(0.28, 0.42, 0.62))
			draw_string(font, Vector2(14, 38), str(_info.get("name", "")),
				HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 28, 14, PszPanel.TEXT_DARK)


class _QuickWeaponMenu extends Control:
	## Small scrollable weapon select overlay. Shows equipped weapon + equippable
	## weapons from inventory. 5 visible lines, scroll with up/down, accept to
	## equip, cancel to close.

	## Fired when the menu actually opens (list non-empty). The player drops a
	## mid-charge technique on this — the fifth charge-drop case
	## (spec /states/player-state, #377), matching PsoStartMenu.opened.
	signal opened()

	const MENU_W := 180.0
	const ROW_H := 22.0
	const VISIBLE_ROWS := 5
	const MENU_H: float = ROW_H * VISIBLE_ROWS + 8.0  # 5 rows + padding
	# PSZ plate style (PszPanel, spec /mechanics/targeting) — navy striped
	# plate; behavior contract (spec /states/quick-weapon-menu) unchanged.
	const SELECTED_BG := Color(0.33, 0.47, 0.72, 0.55)
	const EQUIPPED_COLOR := Color(0.45, 0.9, 0.5)
	const TEXT_COLOR := PszPanel.TEXT_LIGHT
	const TEXT_DIM := Color(0.45, 0.53, 0.66)

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
		opened.emit()
		# Cursor starts at the top of the list (spec /states/quick-weapon-menu,
		# issue #141) — a fixed, predictable entry point. It deliberately does NOT
		# pre-select the equipped row (which sorts to the bottom as the "unequip"
		# choice), so the cursor never lands at the far end of the palette on open.
		_selected_index = 0
		_scroll_offset = 0
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
		var equipped_id: String = str(character.get("equipment", {}).get("weapon", ""))

		# Gather inventory weapons the class can equip — via the single canonical gate
		# (EquipmentUtils.item_fits_slot; spec /mechanics/equip-legality) so the in-field
		# weapon palette matches the shop/menu ✕ markers and honors DebugConfig.equip_all
		# (the hand-rolled check this replaces ignored equip_all, so debug-equipped
		# weapons vanished from the swap list).
		for item_info in Inventory.get_all_items():
			var item_id: String = str(item_info.get("id", ""))
			var base_id: String = Inventory.get_base_id(item_id)
			if WeaponRegistry.get_weapon(base_id) == null:
				continue
			if not EquipmentUtils.item_fits_slot(item_id, "weapon"):
				continue
			var is_equipped: bool = item_id == equipped_id
			_weapon_list.append({"id": item_id, "name": str(item_info.get("name", base_id)), "equipped": is_equipped})

		# Sort: equipped row LAST, the rest alphabetical (spec
		# /states/quick-weapon-menu, issue #424). Selecting the equipped row
		# unequips, so it reads as the "take it off" action at the bottom of
		# the palette rather than the first thing the cursor lands on.
		_weapon_list.sort_custom(func(a, b):
			if a.equipped != b.equipped:
				return not a.equipped  # non-equipped first; equipped sinks to the end
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
		var character = CharacterManager.get_active_character()
		if character == null:
			return
		# Same equipment dict the equip branch mutates — class-legality already
		# governed by the canonical EquipmentUtils.item_fits_slot gate that built
		# the list (PR #419), so no re-derivation here.
		var equipment: Dictionary = character.get("equipment", {})

		if weapon_entry.equipped:
			# Selecting the already-equipped row UNEQUIPS to barehanded, then
			# closes (spec /states/quick-weapon-menu, issue #424). Previously this
			# just dismissed the menu with no state change.
			print("[sanity] checkpoint: quickmenu-unequip-barehanded")
			equipment["weapon"] = ""
			print("[QuickWeapon] Unequipped: %s (now barehanded)" % weapon_entry.name)
		else:
			equipment["weapon"] = weapon_entry.id
			print("[QuickWeapon] Equipped: %s" % weapon_entry.name)

		# Refresh player model (equip and unequip both restyle the held weapon).
		var players: Array = get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0].has_method("refresh_weapon"):
			players[0].refresh_weapon()

		_close()

	func _draw() -> void:
		if not _is_open:
			return
		var font: Font = ThemeDB.fallback_font

		# Background — the shared PSZ plate (dark variant)
		PszPanel.draw_plate(self, size, true)

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

extends Node
## Autopilot — scripted boot / menu / city driver for the sanity-check harness.
##
## INERT in normal play. Activates only when launched with PSZ_AUTOPILOT=1
## (set by scripts/tools/autoplay/sanity_check.sh). Watches scene changes AND
## SceneManager overlay pushes (guild_counter, warp_teleporter), then walks the
## first-run flow:
##
##   splash → title → character_select → character_create
##     → city_office (intro)   → counter
##     → counter_npc.interact  → guild_counter overlay → ui_accept ×3 (accept)
##     → counter → office (briefing)  → spam accept until briefing_shown
##     → counter → city_warp   → WarpPad.interact → warp_teleporter overlay → ui_accept
##     → valley_field (DONE)
##
## Movement = teleport (player.global_position) + synthetic input actions; we
## don't simulate analog walking. Prints `[sanity] …` checkpoints to stdout for
## the orchestrator to assert on.

# ── Scene paths ────────────────────────────────────────────────
const INPUT_SELECT := "res://scenes/2d/input_select.tscn"
const TITLE := "res://scenes/2d/title.tscn"
const CHAR_SELECT := "res://scenes/2d/character_select.tscn"
const CHAR_CREATE := "res://scenes/2d/character_create.tscn"
const CITY_OFFICE := "res://scenes/3d/city/city_office.tscn"
const CITY_COUNTER := "res://scenes/3d/city/city_counter.tscn"
const CITY_WARP := "res://scenes/3d/city/city_warp.tscn"
const GUILD_COUNTER := "res://scenes/2d/guild_counter.tscn"
const WARP_TELEPORTER := "res://scenes/2d/warp_teleporter.tscn"
const VALLEY_FIELD := "res://scenes/3d/field/valley_field.tscn"

# ── Teleport targets (from the city controllers) ───────────────
const OFFICE_EXIT_POS := Vector3(0, 0.5, 27)             # office Area3D → counter
const COUNTER_NPC_POS := Vector3(-8.31, 0.5, -9.5)       # inside QuestCounterNPC range
const COUNTER_TO_OFFICE_POS := Vector3(11.496, 0.5, -11.572)   # counter Area3D → office
const COUNTER_TO_WARP_POS := Vector3(-0.015, 0.5, -22.305)     # counter Area3D → warp
const WARP_PAD_POS := Vector3(0.08, 0.5, 1.0)                  # central WarpTeleporter pad

# ── Timing ─────────────────────────────────────────────────────
const STEP_DELAY := 0.8         # let a scene settle (slide/fade) before acting
const POLL_INTERVAL := 0.7      # accept-spam / re-check interval inside dialogs
const QUIT_GRACE := 0.4
const CHAR_NAME := "humar"

# ── State ──────────────────────────────────────────────────────
var _enabled := false
var _last_scene := ""
var _last_overlay := ""
var _cc_acted_step := -1
var _office_intro_advances := 0
var _office_briefing_advances := 0
var _counter_npc_interacted := false
var _guild_accept_count := 0
var _warp_pad_interacted := false


func _ready() -> void:
	_enabled = OS.has_environment("PSZ_AUTOPILOT") or ("--autopilot" in OS.get_cmdline_user_args())
	if not _enabled:
		set_process(false)
		return
	print("[sanity] autopilot enabled")
	set_process(true)


func _process(_delta: float) -> void:
	# Base scene change
	var cs := get_tree().current_scene
	if cs != null:
		var path := cs.scene_file_path
		if path != "" and path != _last_scene:
			_last_scene = path
			print("[sanity] scene: %s" % path)
			_drive_scene(path)

	# Overlay push (guild_counter / warp_teleporter) — current_scene stays the
	# base scene because SceneManager.push_scene mounts on a CanvasLayer, so we
	# poll _scene_stack to detect overlays opening.
	var overlay := ""
	if SceneManager != null and not SceneManager._scene_stack.is_empty():
		overlay = String(SceneManager._scene_stack[SceneManager._scene_stack.size() - 1])
	if overlay != _last_overlay:
		_last_overlay = overlay
		if overlay != "":
			print("[sanity] overlay: %s" % overlay)
			_drive_overlay(overlay)


func _drive_scene(path: String) -> void:
	if path == INPUT_SELECT:
		_after(STEP_DELAY, _pick_keyboard)
	elif path == TITLE:
		print("[sanity] checkpoint: title")
		_after(STEP_DELAY, func() -> void: _press_action("ui_accept"))
	elif path == CHAR_SELECT:
		print("[sanity] checkpoint: character_select")
		_after(STEP_DELAY, func() -> void: _press_action("ui_accept"))
	elif path == CHAR_CREATE:
		print("[sanity] checkpoint: character_create")
		_cc_acted_step = -1
		_after(STEP_DELAY, _drive_char_create)
	elif path == CITY_OFFICE:
		print("[sanity] checkpoint: city_office")
		_office_intro_advances = 0
		_office_briefing_advances = 0
		# Wait a bit longer for the 3D scene + dialog to settle.
		_after(STEP_DELAY * 2.0, _drive_city_office)
	elif path == CITY_COUNTER:
		print("[sanity] checkpoint: city_counter")
		_counter_npc_interacted = false
		_after(STEP_DELAY * 2.0, _drive_city_counter)
	elif path == CITY_WARP:
		print("[sanity] checkpoint: city_warp")
		_warp_pad_interacted = false
		_after(STEP_DELAY * 2.0, _drive_city_warp)
	elif path == VALLEY_FIELD:
		print("[sanity] checkpoint: valley_field reached")
		print("[sanity] DONE ok")
		_after(QUIT_GRACE, func() -> void: get_tree().quit(0))


func _drive_overlay(path: String) -> void:
	if path == GUILD_COUNTER:
		print("[sanity] checkpoint: guild_counter")
		_guild_accept_count = 0
		_after(STEP_DELAY, _drive_guild_counter)
	elif path == WARP_TELEPORTER:
		print("[sanity] checkpoint: warp_teleporter")
		_after(STEP_DELAY, func() -> void: _press_action("ui_accept"))


# ── Input + teleport helpers ───────────────────────────────────

## Controller-config screen accepts any key — press Enter to pick keyboard.
## Send a paired down+up so later screens don't see Enter stuck held (the
## first thing after this is the title's ui_accept handler).
func _pick_keyboard() -> void:
	print("[sanity] input_select: injecting keyboard keypress")
	var down := InputEventKey.new()
	down.physical_keycode = KEY_ENTER
	down.keycode = KEY_ENTER
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_ENTER
	up.keycode = KEY_ENTER
	up.pressed = false
	Input.parse_input_event(up)


## Inject a logical action press — works for handlers using
## event.is_action_pressed (title / char_select / char_create / dialogs / UIs).
func _press_action(action: String) -> void:
	print("[sanity] press %s" % action)
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


## Snap the player onto a known position (trigger area or NPC range). Clears
## velocity so a residual move doesn't carry them out before the trigger fires.
func _teleport_player(pos: Vector3) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		print("[sanity] WARN: no player in scene")
		return
	p.global_position = pos
	if "velocity" in p:
		p.velocity = Vector3.ZERO
	print("[sanity] teleport player → (%.2f, %.2f, %.2f)" % [pos.x, pos.y, pos.z])


func _after(seconds: float, cb: Callable) -> void:
	get_tree().create_timer(seconds).timeout.connect(cb)


# ── Character-create wizard ────────────────────────────────────
## Walk the create wizard by its _step (CLASS_SELECT=0, APPEARANCE=1,
## NAME_ENTRY=2): accept defaults, then set + submit the name to fire
## _on_name_submitted → _create_character → city. Re-arms until scene leaves.
func _drive_char_create() -> void:
	var node := get_tree().current_scene
	if node == null or node.scene_file_path != CHAR_CREATE:
		return
	var step: int = int(node.get("_step"))
	if step != _cc_acted_step:
		_cc_acted_step = step
		match step:
			0, 1:
				_press_action("ui_accept")
			2:
				_enter_name(node)
	_after(0.8, _drive_char_create)


func _enter_name(node: Node) -> void:
	var le := _find_line_edit(node)
	if le == null:
		print("[sanity] WARN: no LineEdit found for name entry")
		return
	le.text = CHAR_NAME
	print("[sanity] entering name: %s" % CHAR_NAME)
	le.text_submitted.emit(CHAR_NAME)


func _find_line_edit(n: Node) -> LineEdit:
	if n is LineEdit:
		return n
	for c in n.get_children():
		var found := _find_line_edit(c)
		if found:
			return found
	return null


# ── City: office ───────────────────────────────────────────────
## Two paths through the office:
##   • intro (first visit, _is_intro=true): 3-page dialog → accept ×N → exit
##   • briefing (after accept, _is_briefing=true): 7-page dialog → accept until
##     SessionManager.get_accepted_quest()["briefing_shown"] → exit
func _drive_city_office() -> void:
	var node := get_tree().current_scene
	if node == null or node.scene_file_path != CITY_OFFICE:
		return

	if bool(node.get("_is_intro")):
		_drive_office_intro()
	elif bool(node.get("_is_briefing")):
		_drive_office_briefing()
	else:
		# Neither dialog active → just exit.
		print("[sanity] office: idle, exit to counter")
		_teleport_player(OFFICE_EXIT_POS)


func _drive_office_intro() -> void:
	# 3 pages; spam ~5 accepts (with safety buffer), then teleport to exit.
	if _office_intro_advances < 5:
		_press_action("ui_accept")
		_office_intro_advances += 1
		_after(POLL_INTERVAL, _drive_city_office)
	else:
		print("[sanity] office intro complete → exit to counter")
		_teleport_player(OFFICE_EXIT_POS)


func _drive_office_briefing() -> void:
	var accepted: Dictionary = SessionManager.get_accepted_quest()
	if bool(accepted.get("briefing_shown", false)):
		print("[sanity] office briefing complete → exit to counter")
		_teleport_player(OFFICE_EXIT_POS)
		return
	if _office_briefing_advances < 14:  # 7 pages + buffer
		_press_action("ui_accept")
		_office_briefing_advances += 1
		_after(POLL_INTERVAL, _drive_city_office)
	else:
		print("[sanity] WARN: briefing advance limit; forcing exit")
		_teleport_player(OFFICE_EXIT_POS)


# ── City: counter ──────────────────────────────────────────────
## Three states routed by SessionManager:
##   • no accepted quest → teleport to NPC + press interact (opens guild_counter)
##   • accepted, briefing not shown → teleport to office trigger (briefing fires)
##   • accepted, briefing shown → teleport to warp trigger
func _drive_city_counter() -> void:
	var node := get_tree().current_scene
	if node == null or node.scene_file_path != CITY_COUNTER:
		return

	if not SessionManager.has_accepted_quest():
		if not _counter_npc_interacted:
			_counter_npc_interacted = true
			print("[sanity] counter: teleport to guild NPC")
			_teleport_player(COUNTER_NPC_POS)
			_after(0.6, func() -> void: _press_action("interact"))
		return

	var accepted: Dictionary = SessionManager.get_accepted_quest()
	if not bool(accepted.get("briefing_shown", false)):
		print("[sanity] counter: teleport to office trigger (for briefing)")
		_teleport_player(COUNTER_TO_OFFICE_POS)
	else:
		print("[sanity] counter: teleport to warp trigger")
		_teleport_player(COUNTER_TO_WARP_POS)


# ── Guild counter overlay ──────────────────────────────────────
## Search and Rescue is the manifest-first quest, so it's pre-selected.
## ui_accept #1 → difficulty mode; #2 → confirm modal; #3 → confirms → pop.
func _drive_guild_counter() -> void:
	if SessionManager.has_accepted_quest():
		print("[sanity] guild_counter: quest accepted")
		# Wait for the overlay to pop, then re-drive counter (state-aware).
		_after(2.0, _drive_city_counter)
		return
	if _guild_accept_count >= 6:
		print("[sanity] WARN: guild accept limit reached")
		return
	_press_action("ui_accept")
	_guild_accept_count += 1
	_after(1.2, _drive_guild_counter)


# ── City: warp ─────────────────────────────────────────────────
## Teleport onto the central WarpTeleporter pad and press interact, which
## opens the warp_teleporter UI overlay.
func _drive_city_warp() -> void:
	var node := get_tree().current_scene
	if node == null or node.scene_file_path != CITY_WARP:
		return
	if _warp_pad_interacted:
		return
	_warp_pad_interacted = true
	print("[sanity] warp: teleport to central pad")
	_teleport_player(WARP_PAD_POS)
	_after(0.8, func() -> void: _press_action("interact"))

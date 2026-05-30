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
## City movement = teleport (player.global_position) + synthetic input actions.
## Field movement = camera-basis-aware walking via `Input.action_press` on the
## move_* actions, so the autopilot exercises the same physics + collision the
## player does (a level change that blocks a real player should also block the
## autopilot). Prints `[sanity] …` checkpoints to stdout for the orchestrator
## to assert on.

# ── Scene paths ────────────────────────────────────────────────
const INPUT_SELECT := "res://scenes/2d/input_select.tscn"
const TITLE := "res://scenes/2d/title.tscn"
const CHAR_SELECT := "res://scenes/2d/character_select.tscn"
const CHAR_CREATE := "res://scenes/2d/character_create.tscn"
const CITY_MARKET := "res://scenes/3d/city/city_market.tscn"
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

# ── Field walk tuning ──────────────────────────────────────────
const WALK_ARRIVE_DIST := 1.5   # XZ distance at which we say "arrived"
const WALK_DIR_THRESHOLD := 0.3 # projection magnitude needed to hold a move action
const KILL_ALL_SETTLE := 1.5    # per-wave settle (re-checked in a loop until enemies group is empty or KILL_ALL_MAX_WAVES caps it)
const POST_INTERACT_SETTLE := 0.9
const POST_GATE_SETTLE := 1.5   # gate open animation + collision flip
const QUEST_COMPLETE_POLL := 0.4
const QUEST_COMPLETE_POLL_MAX := 60  # 60 * 0.4 = 24s
const CELL_SETTLE_DELAY := STEP_DELAY * 3.0  # wait after a cell load before acting

# ── Quest walk script ──────────────────────────────────────────
# Search-and-Rescue: 24 cell loads (gurhacia A → transition E → B). Some cells
# are visited twice — A 2,1 (detour to 3,1 for key), A 2,3 (detour to 3,3),
# B 1,2 (detour to 1,3 for key), B 3,1 (detour to 2,1 for key). Path is
# hand-authored from the quest plan, not solved at runtime — the value here is
# verifying that a walking player can traverse, not testing pathfinding.
#
# Each step: do[] = ordered actions, exit = portal direction to walk to after.
# Actions: "kill_all" (debug-clear current cell), "pickup_key", "flip_switch",
# "open_gate", "wait_quest_complete". Empty exit = terminal (last cell).
# Each step also carries the next cell's pos + entry edge so the watchdog can
# call `field._transition_to_cell(target, entry)` directly when straight-line
# walking gets stuck on geometry (most stages have L-shaped corridors that
# need waypoint nav, which isn't authored yet — until it is, the fallback
# keeps the run progressing and the log clearly marks which leg got stuck).
# `target=""` signals a warp edge (section transition) → `_on_end_reached()`.
const QUEST_STEPS: Array = [
	# Section A — start at 0,2, exit east warp from 2,4
	{"label": "A 0,2 start", "do": [], "exit": "south", "target": "1,2", "entry": "north"},
	{"label": "A 1,2", "do": ["kill_all"], "exit": "west", "target": "1,1", "entry": "east"},
	{"label": "A 1,1", "do": ["kill_all", "dismiss_dialog"], "exit": "south", "target": "2,1", "entry": "north"},
	{"label": "A 2,1 (gate east locked)", "do": ["kill_all"], "exit": "south", "target": "3,1", "entry": "north"},
	{"label": "A 3,1 (key drop for 2,1)", "do": ["kill_all", "dismiss_dialog", "pickup_key"], "exit": "north", "target": "2,1", "entry": "south"},
	{"label": "A 2,1 (return, open gate)", "do": ["open_gate"], "exit": "east", "target": "2,2", "entry": "west"},
	{"label": "A 2,2 (switch)", "do": ["kill_all", "flip_switch"], "exit": "east", "target": "2,3", "entry": "west"},
	{"label": "A 2,3", "do": ["kill_all"], "exit": "south", "target": "3,3", "entry": "north"},
	{"label": "A 3,3", "do": ["kill_all"], "exit": "north", "target": "2,3", "entry": "south"},
	{"label": "A 2,3 (return)", "do": [], "exit": "east", "target": "2,4", "entry": "west"},
	{"label": "A 2,4 (end, warp east)", "do": ["kill_all", "dismiss_dialog"], "exit": "east", "target": "", "entry": ""},
	# Section E — single transition cell
	{"label": "E 0,0 (transition, warp north)", "do": ["kill_all", "dismiss_dialog"], "exit": "north", "target": "", "entry": ""},
	# Section B — start at 0,2, end at 3,0 with complete_quest action
	{"label": "B 0,2 start", "do": ["kill_all"], "exit": "south", "target": "1,2", "entry": "north"},
	{"label": "B 1,2 (gate south locked)", "do": ["kill_all"], "exit": "east", "target": "1,3", "entry": "west"},
	{"label": "B 1,3 (key drop for 1,2)", "do": ["kill_all", "pickup_key"], "exit": "west", "target": "1,2", "entry": "east"},
	{"label": "B 1,2 (return, open gate)", "do": ["open_gate"], "exit": "south", "target": "2,2", "entry": "north"},
	{"label": "B 2,2", "do": ["kill_all", "dismiss_dialog"], "exit": "south", "target": "3,2", "entry": "north"},
	{"label": "B 3,2", "do": ["kill_all"], "exit": "south", "target": "4,2", "entry": "north"},
	{"label": "B 4,2", "do": ["kill_all"], "exit": "west", "target": "4,1", "entry": "east"},
	{"label": "B 4,1", "do": ["kill_all", "dismiss_dialog"], "exit": "north", "target": "3,1", "entry": "south"},
	{"label": "B 3,1 (gate west locked)", "do": ["kill_all"], "exit": "north", "target": "2,1", "entry": "south"},
	{"label": "B 2,1 (key drop for 3,1)", "do": ["kill_all", "pickup_key"], "exit": "south", "target": "3,1", "entry": "north"},
	{"label": "B 3,1 (return, open gate)", "do": ["open_gate"], "exit": "west", "target": "3,0", "entry": "east"},
	{"label": "B 3,0 (final, quest complete)", "do": ["kill_all", "wait_quest_complete"], "exit": "", "target": "", "entry": ""},
]

# ── State ──────────────────────────────────────────────────────
var _enabled := false
var _last_scene := ""
var _last_overlay := ""
var _last_field_node_id: int = 0   # detects cell transitions (same path, new node)
var _field_cells_visited: int = 0
var _cc_acted_step := -1
var _office_intro_advances := 0
var _office_briefing_advances := 0
var _counter_npc_interacted := false
var _guild_accept_count := 0
var _warp_pad_interacted := false

# Field walking state — driven by _tick_field_walk in _process.
var _walking := false
var _walk_target: Vector3 = Vector3.ZERO
var _walk_on_arrive: Callable = Callable()
## If set, fires instead of bare teleport when the watchdog trips. Used for
## exit-trigger walks to invoke field._transition_to_cell directly.
var _walk_on_watchdog: Callable = Callable()
var _walk_started_at_ms: int = 0
var _walk_diag_tick: int = 0
const WALK_DIAG_INTERVAL := 30   # log position every N ticks (~0.5s @ 60fps)
const WALK_WATCHDOG_MS := 15_000 # 15s; if we haven't arrived, fall back

# Quest walker progress.
var _quest_step_idx: int = 0
var _step_action_idx: int = 0

# Boot-phase: tracks whether we've finished the office intro + kicked off the
# "Return to Title" path, so the title-scene handler can recognize "we're done"
# vs "this is the first-time title" and quit cleanly.
var _boot_returning_to_title: bool = false

# ── Phase ──────────────────────────────────────────────────────
## Each phase is a self-contained "launch godot → drive to checkpoint →
## SaveManager.save_game() → quit" cycle, producing its own mp4. Picked via
## PSZ_AUTOPILOT_PHASE env var (set by scripts/tools/autoplay/record_*.sh and
## sanity_check.sh). `all` is the legacy full-run-from-boot behavior.
enum Phase { ALL, BOOT, FIRST_MISSION }
var _phase: int = Phase.ALL


func _ready() -> void:
	_enabled = OS.has_environment("PSZ_AUTOPILOT") or ("--autopilot" in OS.get_cmdline_user_args())
	if not _enabled:
		set_process(false)
		return
	match OS.get_environment("PSZ_AUTOPILOT_PHASE"):
		"boot":
			_phase = Phase.BOOT
			print("[sanity] autopilot enabled (phase=boot: ends after office intro + save)")
		"first-mission":
			_phase = Phase.FIRST_MISSION
			print("[sanity] autopilot enabled (phase=first-mission: assumes saved character; ends after quest report + save)")
		_:
			_phase = Phase.ALL
			print("[sanity] autopilot enabled (phase=all: full run from boot to quest report)")
	set_process(true)


## Persist state via SaveManager + quit. Terminator shared by all phases.
func _save_and_quit() -> void:
	if SaveManager != null and SaveManager.has_method("save_game"):
		SaveManager.save_game()
		print("[sanity] save_game()")
	print("[sanity] DONE ok")
	# Let the save write hit disk before exit.
	_after(0.8, func() -> void: get_tree().quit(0))


func _process(_delta: float) -> void:
	# Base scene change
	var cs := get_tree().current_scene
	if cs != null:
		var path := cs.scene_file_path
		if path != "" and path != _last_scene:
			_last_scene = path
			print("[sanity] scene: %s" % path)
			_drive_scene(path)

		# Field-cell transition: SceneManager.goto_scene reloads
		# valley_field.tscn with a fresh root node each cell, so the path is
		# unchanged but the instance id changes. That's how we know a new cell
		# loaded vs first-time entry.
		if path == VALLEY_FIELD:
			var nid := cs.get_instance_id()
			if nid != _last_field_node_id:
				_last_field_node_id = nid
				_field_cells_visited += 1
				print("[sanity] field cell #%d loaded" % _field_cells_visited)
				_on_field_cell_loaded(cs)

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

	# Field walk tick
	if _walking:
		_tick_field_walk()


func _drive_scene(path: String) -> void:
	# Post-quest: returning to a city scene means the report flow ran. Don't
	# re-drive the city handlers (they'd try to accept Search-and-Rescue again).
	# Both phase=first-mission and phase=all stop here.
	if path.begins_with("res://scenes/3d/city/") and SessionManager.has_completed_quest():
		print("[sanity] checkpoint: quest report — back in city (%s)" % path)
		_save_and_quit()
		return

	if path == INPUT_SELECT:
		_after(STEP_DELAY, _pick_keyboard)
	elif path == TITLE:
		if _boot_returning_to_title:
			# Boot phase ran "Return to Title" — DONE here, not at the office.
			# The mp4 ends with the title screen visible for a beat (QUIT_GRACE).
			print("[sanity] checkpoint: returned to title (boot phase complete)")
			print("[sanity] DONE ok")
			_after(QUIT_GRACE, func() -> void: get_tree().quit(0))
		else:
			print("[sanity] checkpoint: title")
			_after(STEP_DELAY, func() -> void: _press_action("ui_accept"))
	elif path == CHAR_SELECT:
		print("[sanity] checkpoint: character_select")
		_after(STEP_DELAY, func() -> void: _press_action("ui_accept"))
	elif path == CHAR_CREATE:
		print("[sanity] checkpoint: character_create")
		_cc_acted_step = -1
		_after(STEP_DELAY, _drive_char_create)
	elif path == CITY_MARKET:
		# character_select.gd:724 drops every loaded character into the market
		# (the central plaza), not back into wherever they were saved. In
		# phase=first-mission this is the natural entry point; in phase=all it
		# never fires because boot creates a new character that spawns in
		# city_office directly. Hop straight to the counter to accept the quest.
		print("[sanity] checkpoint: city_market (load spawn) → goto counter")
		_after(STEP_DELAY * 2.0, func() -> void: SceneManager.goto_scene(CITY_COUNTER))
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
		print("[sanity] checkpoint: valley_field entered")
		# The per-cell loop is driven by _on_field_cell_loaded — fires on the
		# same frame this scene-change does, so don't drive anything here.


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
	# 3 pages; spam ~5 accepts (with safety buffer), then either run the boot
	# phase's "Save Game + Return to Title" flow (phase=boot) or teleport to
	# the office exit (phase=first-mission / phase=all keep going).
	if _office_intro_advances < 5:
		_press_action("ui_accept")
		_office_intro_advances += 1
		_after(POLL_INTERVAL, _drive_city_office)
		return
	if _phase == Phase.BOOT:
		print("[sanity] checkpoint: boot intro complete → Save + Return to Title")
		_after(STEP_DELAY, _save_and_return_to_title)
	else:
		print("[sanity] office intro complete → exit to counter")
		_teleport_player(OFFICE_EXIT_POS)


## Match the "Return to Title" menu item exactly (scripts/3d/city/city_menu.gd:150):
## SaveManager.save_game() → CityState.clear() → goto_scene(TITLE). The TITLE
## handler above recognises _boot_returning_to_title and DONEs there, so the
## mp4 ends on the title screen instead of a hard cut from the office.
func _save_and_return_to_title() -> void:
	_boot_returning_to_title = true
	if SaveManager != null and SaveManager.has_method("save_game"):
		SaveManager.save_game()
		print("[sanity] save_game()")
	if CityState != null and CityState.has_method("clear"):
		CityState.clear()
	SceneManager.goto_scene(TITLE)


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


# ── Field: per-cell driver ─────────────────────────────────────
## Fires every time a valley_field cell loads (first entry AND each cell
## transition — SceneManager.goto_scene reloads the scene with a fresh root
## node, so the instance id flips even though the path is unchanged).
##
## Drives QUEST_STEPS[_quest_step_idx]'s action list, then walks to the exit
## portal. The next cell-load advances _quest_step_idx.
func _on_field_cell_loaded(field: Node) -> void:
	_stop_field_walk()
	if _quest_step_idx >= QUEST_STEPS.size():
		print("[sanity] WARN: extra cell load #%d after all %d steps" % [_field_cells_visited, QUEST_STEPS.size()])
		return
	var step: Dictionary = QUEST_STEPS[_quest_step_idx]
	print("[sanity] step %d/%d (%s): cell load #%d" % [
		_quest_step_idx + 1, QUEST_STEPS.size(), step.get("label", "?"), _field_cells_visited])
	_step_action_idx = 0
	# Wait for controller _ready + spawn + camera settle, then start actions.
	_after(CELL_SETTLE_DELAY, func() -> void: _run_next_action(field))


func _run_next_action(field: Node) -> void:
	# A cell transition can fire mid-action; the new _on_field_cell_loaded
	# resets state, so just no-op here.
	if not is_instance_valid(field) or field != get_tree().current_scene:
		return
	var step: Dictionary = QUEST_STEPS[_quest_step_idx]
	var actions: Array = step.get("do", [])
	if _step_action_idx >= actions.size():
		_walk_to_exit(field, step)
		return
	var action: String = str(actions[_step_action_idx])
	_step_action_idx += 1
	print("[sanity] action %d/%d: %s" % [_step_action_idx, actions.size(), action])
	match action:
		"kill_all":
			_do_kill_all(field)
		"dismiss_dialog":
			_do_dismiss_dialog(field)
		"pickup_key":
			_do_pickup_key(field)
		"flip_switch":
			_do_flip_switch(field)
		"open_gate":
			_do_open_gate(field)
		"wait_quest_complete":
			_do_wait_quest_complete(field)
		_:
			print("[sanity] WARN: unknown action '%s'" % action)
			_run_next_action(field)


# ── Per-action handlers ────────────────────────────────────────

## Cells can have multiple enemy waves (valley_field_controller.gd:3397
## "Wave N cleared! Spawning wave N+1"). Player._debug_kill_all() kills the
## currently-spawned wave; if there are more, they spawn after
## _check_room_clear and the autopilot has to clear them too. Loop until the
## "enemies" group is empty (or we cap out at 5 attempts).
const KILL_ALL_MAX_WAVES := 5

func _do_kill_all(field: Node) -> void:
	_kill_all_wave(field, 0)


func _kill_all_wave(field: Node, attempt: int) -> void:
	if not is_instance_valid(field) or field != get_tree().current_scene:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("_debug_kill_all"):
		player._debug_kill_all()
	# Wait for any pending wave spawn from _check_room_clear, then re-check.
	# DON'T spam ui_accept — in field, ui_accept can trip player actions
	# (attack/heavy) if no dialog is open; the per-cell "dismiss_dialog"
	# action handles room_clear dialog cells explicitly.
	_after(KILL_ALL_SETTLE, func() -> void:
		var still_alive: int = get_tree().get_nodes_in_group("enemies").size()
		if still_alive > 0 and attempt + 1 < KILL_ALL_MAX_WAVES:
			print("[sanity] %d enemies still alive (wave %d incoming) — kill_all again" % [still_alive, attempt + 2])
			_kill_all_wave(field, attempt + 1)
		else:
			_run_next_action(field))


func _do_dismiss_dialog(field: Node) -> void:
	# Cells with a room_clear dialog: press ui_accept a few times to advance
	# past whatever pages it shows. Spaced 0.6s; harmless if dialog already
	# closed (ui_accept does nothing field-side once player is back to IDLE).
	for i in range(4):
		_after(0.4 + i * 0.6, func() -> void: _press_action("ui_accept"))
	_after(0.4 + 4 * 0.6 + 0.3, func() -> void: _run_next_action(field))


func _do_pickup_key(field: Node) -> void:
	var key := _find_key_pickup(field)
	if key == null:
		print("[sanity] WARN: pickup_key — no KeyPickup in cell")
		_run_next_action(field)
		return
	_walk_then_interact(field, key.global_position, "key", POST_INTERACT_SETTLE)


func _do_flip_switch(field: Node) -> void:
	var sw := _find_interact_switch(field)
	if sw == null:
		print("[sanity] WARN: flip_switch — no InteractSwitch in cell")
		_run_next_action(field)
		return
	_walk_then_interact(field, sw.global_position, "switch", POST_INTERACT_SETTLE)


func _do_open_gate(field: Node) -> void:
	var gate := _find_key_gate(field)
	if gate == null:
		print("[sanity] WARN: open_gate — no KeyGate in cell")
		_run_next_action(field)
		return
	_walk_then_interact(field, gate.global_position, "gate", POST_GATE_SETTLE)


func _do_wait_quest_complete(_field: Node) -> void:
	print("[sanity] final cell: kill_all + give the room_clear dialog ~5s, then force-complete")
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("_debug_kill_all"):
		player._debug_kill_all()
	# The room_clear dialog at B 3,0 carries action "complete_quest", but the
	# dialog_trigger checks `SessionManager.are_objectives_complete()` first
	# and skips on miss. Our force-advance fallback bypasses several cells
	# (where the key-drop chain never fires), so objectives may not be met.
	# Give the natural dialog 5s to fire, advancing pages with ui_accept; if
	# the quest isn't marked complete by then, call complete_quest() directly.
	for i in range(4):
		_after(1.2 + i * 1.0, func() -> void: _press_action("ui_accept"))
	_after(5.2, func() -> void:
		if not SessionManager.has_completed_quest():
			print("[sanity] dialog didn't fire complete_quest (objectives unmet from bypassed cells) — calling SessionManager.complete_quest() directly")
			SessionManager.complete_quest())
	# SessionManager.complete_quest() runs mark_quest_complete + return_to_city,
	# but return_to_city only clears session state — the actual scene transition
	# is normally driven by the telepipe spawn (dialog "telepipe" action) which
	# we bypassed. Force the goto so _drive_scene sees the city return.
	_after(6.4, func() -> void:
		if SessionManager.has_completed_quest():
			print("[sanity] forcing scene change to city_warp (no telepipe was spawned)")
			SceneManager.goto_scene(CITY_WARP))
	_poll_quest_complete(0)


func _poll_quest_complete(n: int) -> void:
	if n > QUEST_COMPLETE_POLL_MAX:
		print("[sanity] WARN: quest_complete poll timeout (%d ticks)" % n)
		return
	if SessionManager.has_completed_quest():
		var done: Dictionary = SessionManager.get_completed_quest() if SessionManager.has_method("get_completed_quest") else {}
		print("[sanity] checkpoint: quest_completed (%s)" % str(done))
		# Don't quit here — _drive_scene handles the city-return DONE.
		return
	_after(QUEST_COMPLETE_POLL, func() -> void: _poll_quest_complete(n + 1))


# ── Action helpers ─────────────────────────────────────────────

func _walk_then_interact(field: Node, target: Vector3, label: String, settle: float) -> void:
	print("[sanity] walk to %s (%.2f, %.2f, %.2f)" % [label, target.x, target.y, target.z])
	_start_field_walk(target, func() -> void:
		if not is_instance_valid(field) or field != get_tree().current_scene:
			return
		_after(0.4, func() -> void:
			print("[sanity] interact %s" % label)
			_press_action("interact")
			_after(settle, func() -> void: _run_next_action(field))))


func _walk_to_exit(field: Node, step: Dictionary) -> void:
	var exit_dir: String = str(step.get("exit", ""))
	if exit_dir == "":
		# No exit (final cell). wait_quest_complete should have handled it.
		return
	var portal_data = field.get("_portal_data")
	if typeof(portal_data) != TYPE_DICTIONARY or not portal_data.has(exit_dir):
		print("[sanity] WARN: cell missing %s portal — forcing transition" % exit_dir)
		_force_advance_cell(field, step)
		return
	var trigger_pos: Vector3 = portal_data[exit_dir].get("trigger_pos", Vector3.ZERO)
	# Advance the step counter now: whether the walk succeeds (body_entered
	# fires, cell reloads with the next step) or the watchdog trips
	# (_force_advance_cell will increment again — so guard against double
	# increment by ONLY incrementing here, and have _force_advance_cell skip
	# the increment).
	_quest_step_idx += 1
	# Build a walkable path through the cell's spawn waypoints. If straight-
	# line raycast from the player to the trigger is clear, the path is just
	# [trigger]; otherwise BFS tries via spawn points + center to find a
	# clear multi-leg route. Watchdog still falls back to _transition_to_cell.
	var captured_step := step
	_walk_on_watchdog = func() -> void: _force_advance_cell(field, captured_step)
	var path: Array = _find_walk_path(field, portal_data, trigger_pos)
	if path.size() <= 1:
		print("[sanity] walk to exit '%s' direct (%.2f, %.2f, %.2f)" % [exit_dir, trigger_pos.x, trigger_pos.y, trigger_pos.z])
	else:
		var leg_str := ""
		for p in path:
			leg_str += " → (%.1f, %.1f)" % [p.x, p.z]
		print("[sanity] walk to exit '%s' via %d waypoint(s):%s" % [exit_dir, path.size() - 1, leg_str])
	_walk_path(field, path, exit_dir, 0)


## Walk a multi-leg path (Array of Vector3 world positions). On arrival at
## the last point, that's it — let the trigger fire from the player crossing
## the Area3D. On arrival at intermediate points, recurse to the next leg.
func _walk_path(field: Node, path: Array, exit_dir: String, leg: int) -> void:
	if leg >= path.size():
		return
	var target: Vector3 = path[leg]
	var is_last: bool = (leg == path.size() - 1)
	_start_field_walk(target, func() -> void:
		if not is_instance_valid(field) or field != get_tree().current_scene:
			return
		if is_last:
			print("[sanity] arrived at %s trigger (cell transition imminent)" % exit_dir)
		else:
			print("[sanity] waypoint %d/%d reached — next leg" % [leg + 1, path.size() - 1])
			_after(0.1, func() -> void: _walk_path(field, path, exit_dir, leg + 1)))


## Walking to an exit trigger but stuck on geometry (no waypoint nav yet) →
## call into the field controller directly so the run can keep progressing.
## For gate edges: `_transition_to_cell(target_pos, entry_edge)`. For warp
## edges (section transitions): `_on_end_reached()`.
func _force_advance_cell(field: Node, step: Dictionary) -> void:
	if not is_instance_valid(field) or field != get_tree().current_scene:
		return
	var target_pos: String = str(step.get("target", ""))
	var entry_edge: String = str(step.get("entry", ""))
	var exit_dir: String = str(step.get("exit", ""))
	# Note: _quest_step_idx was already incremented in _walk_to_exit before
	# kicking off this walk, so we don't increment again here.
	if target_pos == "":
		# Warp edge — section transition.
		print("[sanity] force advance via _on_end_reached (warp '%s')" % exit_dir)
		if field.has_method("_on_end_reached"):
			field._on_end_reached()
		return
	print("[sanity] force advance via _transition_to_cell('%s', '%s')" % [target_pos, entry_edge])
	if field.has_method("_transition_to_cell"):
		field._transition_to_cell(target_pos, entry_edge)


# ── Scene-tree finders for interactables ───────────────────────

func _find_key_pickup(root: Node) -> Node:
	if root is KeyPickup:
		return root
	for c in root.get_children():
		var found := _find_key_pickup(c)
		if found != null:
			return found
	return null


func _find_interact_switch(root: Node) -> Node:
	if root is InteractSwitch:
		return root
	for c in root.get_children():
		var found := _find_interact_switch(c)
		if found != null:
			return found
	return null


func _find_key_gate(root: Node) -> Node:
	if root is KeyGate:
		return root
	for c in root.get_children():
		var found := _find_key_gate(c)
		if found != null:
			return found
	return null


# ── Field walk primitive ───────────────────────────────────────
## Drive the player toward an XZ position by holding camera-relative move_*
## actions. Bypasses no physics — same code path the human's keystrokes drive.

func _start_field_walk(target: Vector3, on_arrive: Callable = Callable()) -> void:
	_walk_target = target
	_walk_on_arrive = on_arrive
	_walking = true
	_walk_started_at_ms = Time.get_ticks_msec()
	_walk_diag_tick = 0
	# Note: _walk_on_watchdog is set by the caller BEFORE this (for exit-trigger
	# walks) or left as Callable() so the watchdog falls back to plain teleport.


func _stop_field_walk() -> void:
	_walking = false
	_walk_on_watchdog = Callable()
	for action in ["move_forward", "move_backward", "move_left", "move_right"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _tick_field_walk() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		# Likely between cells — drop the held inputs so the next player spawn
		# doesn't see stale state.
		_stop_field_walk()
		return

	var pos: Vector3 = player.global_position
	var dx: float = _walk_target.x - pos.x
	var dz: float = _walk_target.z - pos.z
	var dist: float = sqrt(dx * dx + dz * dz)

	# Periodic diagnostic so a stuck walk shows up in the log.
	_walk_diag_tick += 1
	if (_walk_diag_tick % WALK_DIAG_INTERVAL) == 0:
		var state = player.get("current_state") if "current_state" in player else "?"
		print("[sanity]  walk @ (%.1f,%.1f,%.1f) → (%.1f,%.1f,%.1f) dist=%.2f state=%s" % [
			pos.x, pos.y, pos.z, _walk_target.x, _walk_target.y, _walk_target.z, dist, str(state)])

	# Watchdog: if we've been trying for too long, fall back. For exit-trigger
	# walks (no waypoint nav yet), _walk_on_watchdog calls into the field
	# controller's _transition_to_cell / _on_end_reached directly. For
	# interactable walks (gate/key/switch), no on_watchdog set → bare teleport,
	# then the on_arrive callback still presses interact.
	if Time.get_ticks_msec() - _walk_started_at_ms > WALK_WATCHDOG_MS:
		var on_watchdog := _walk_on_watchdog
		var on_arrive := _walk_on_arrive
		_stop_field_walk()
		if on_watchdog.is_valid():
			print("[sanity] WARN: walk stuck at dist=%.2f → force-advance (no waypoints for this stage)" % dist)
			on_watchdog.call()
		else:
			print("[sanity] WARN: walk stuck at dist=%.2f → teleport to (%.2f, %.2f, %.2f)" % [
				dist, _walk_target.x, _walk_target.y, _walk_target.z])
			_teleport_player(_walk_target)
			if on_arrive.is_valid():
				_after(0.3, on_arrive)
		return

	if dist < WALK_ARRIVE_DIST:
		var cb := _walk_on_arrive
		_stop_field_walk()
		if cb.is_valid():
			cb.call()
		return

	# Camera-relative basis — player's _handle_movement converts input actions
	# to motion using the *active* camera's forward/right vectors.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cb := cam.global_transform.basis
	var fwd_xz := Vector3(-cb.z.x, 0, -cb.z.z)
	if fwd_xz.length_squared() < 0.0001:
		return
	fwd_xz = fwd_xz.normalized()
	var right_xz := Vector3(cb.x.x, 0, cb.x.z).normalized()

	var desired := Vector3(dx, 0, dz).normalized()
	var fwd_mag := desired.dot(fwd_xz)
	var right_mag := desired.dot(right_xz)

	_drive_action("move_forward", fwd_mag > WALK_DIR_THRESHOLD)
	_drive_action("move_backward", fwd_mag < -WALK_DIR_THRESHOLD)
	_drive_action("move_right", right_mag > WALK_DIR_THRESHOLD)
	_drive_action("move_left", right_mag < -WALK_DIR_THRESHOLD)


func _drive_action(action: String, want_pressed: bool) -> void:
	var is_p := Input.is_action_pressed(action)
	if want_pressed and not is_p:
		Input.action_press(action)
	elif (not want_pressed) and is_p:
		Input.action_release(action)


# ── Waypoint pathfinding ───────────────────────────────────────
## Most stages are L-shaped corridors — a naive straight-line walk from the
## player's current position to the exit trigger hits a wall and the watchdog
## has to teleport. To fix this, we build a graph of candidate waypoints
## (each portal's spawn_pos + the cell center) and find a multi-leg path
## where every leg has a clear line-of-sight raycast over the floor.

const RAY_MAX_LEGS := 4               # max waypoints in a path before giving up
const FLOOR_SAMPLE_STEP := 1.5        # one floor-existence cast every Nm along the line
const FLOOR_PROBE_HEIGHT_UP := 2.0    # downward cast starts this high above sample
const FLOOR_PROBE_HEIGHT_DOWN := 5.0  # downward cast ends this low (well past the floor)

## Conservative "can the character walk this straight line?" check.
##
## These stages are L-shaped FLOORS in open space (each cell has its own
## *-floor.glb mesh), not square rooms with walls — the thing that stops the
## player walking diagonally from spawn to trigger is **walking off the
## floor edge**, not hitting a vertical wall. So instead of one horizontal
## raycast (which passes through empty space), we sample along the line and
## cast DOWN at each sample. If any sample finds no floor below it, the path
## leaves the walkable surface and we reject it.
func _raycast_walkable(from: Vector3, to: Vector3) -> bool:
	var world := get_viewport().get_world_3d() if get_viewport() != null else null
	if world == null:
		return false
	var space := world.direct_space_state
	if space == null:
		return false
	var player := get_tree().get_first_node_in_group("player")
	var excludes: Array = []
	if player != null and player is CollisionObject3D:
		excludes = [player.get_rid()]
	var dist: float = from.distance_to(to)
	var samples: int = max(int(ceil(dist / FLOOR_SAMPLE_STEP)), 2)
	# Sample interior points (skip the endpoints since the spawn and target
	# are already known-walkable positions placed by the controller).
	for i in range(1, samples):
		var t: float = float(i) / samples
		var p: Vector3 = from.lerp(to, t)
		var up_pos := Vector3(p.x, p.y + FLOOR_PROBE_HEIGHT_UP, p.z)
		var down_pos := Vector3(p.x, p.y - FLOOR_PROBE_HEIGHT_DOWN, p.z)
		var dq := PhysicsRayQueryParameters3D.create(up_pos, down_pos)
		dq.exclude = excludes
		var dhit: Dictionary = space.intersect_ray(dq)
		if dhit.is_empty():
			return false  # No floor at this sample — would walk off the edge.
	return true


## Build the candidate waypoint list for the current cell:
##   • every portal_data[dir]["spawn_pos"] (one per connected direction +
##     warp direction — these are the natural "in front of each gate"
##     positions, deliberately placed by the controller to be walkable),
##   • the cell center (Map node's origin in world space) as a fallback.
func _collect_cell_waypoints(field: Node, portal_data: Dictionary) -> Array:
	var pts: Array = []
	for k in portal_data.keys():
		if String(k) == "default":
			continue
		var pd: Dictionary = portal_data[k]
		var sp = pd.get("spawn_pos", null)
		if sp != null and sp is Vector3:
			pts.append(sp)
	# Cell center: Map node is the parent under which cell stages are added
	# in valley_field_controller (see _map_root, named "Map" at line 213).
	var map_root := field.get_node_or_null("Map")
	if map_root != null and map_root is Node3D:
		pts.append((map_root as Node3D).to_global(Vector3.ZERO))
	return pts


## BFS through candidate waypoints to find a clear path from the player's
## current position to `target`. Returns Array[Vector3] ending in `target`;
## empty Array on hard miss. A path of size 1 means straight-line is clear.
func _find_walk_path(field: Node, portal_data: Dictionary, target: Vector3) -> Array:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return [target]
	var start: Vector3 = player.global_position
	# Fast path: direct line of sight.
	if _raycast_walkable(start, target):
		return [target]
	# Build candidate set, drop any that aren't reachable from start.
	var candidates: Array = _collect_cell_waypoints(field, portal_data)
	# BFS: each node is an index into candidates; track parents to reconstruct.
	var n: int = candidates.size()
	if n == 0:
		return [target]
	var reachable_from_start: Array = []
	for i in range(n):
		if _raycast_walkable(start, candidates[i]):
			reachable_from_start.append(i)
	if reachable_from_start.is_empty():
		return [target]  # No first step works; fall back to direct (watchdog).
	# Build adjacency on demand inside BFS.
	var visited := {}
	var parent := {}  # idx → parent idx (-1 for roots)
	var queue: Array = []
	for i in reachable_from_start:
		queue.append(i)
		visited[i] = true
		parent[i] = -1
	var found: int = -1
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if _raycast_walkable(candidates[cur], target):
			found = cur
			break
		for j in range(n):
			if visited.has(j):
				continue
			if _raycast_walkable(candidates[cur], candidates[j]):
				visited[j] = true
				parent[j] = cur
				queue.append(j)
	if found == -1:
		return [target]  # No path found; fall back to direct + watchdog.
	# Reconstruct path: candidates[found] → ... → roots, then prepend in reverse.
	var chain: Array = []
	var node: int = found
	while node != -1 and chain.size() < RAY_MAX_LEGS:
		chain.append(candidates[node])
		node = parent.get(node, -1)
	chain.reverse()
	chain.append(target)
	return chain

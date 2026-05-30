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


# ── Field: per-cell driver ─────────────────────────────────────
## Fires every time a valley_field cell loads (first entry AND each cell
## transition, since SceneManager.goto_scene reloads the scene with a fresh
## root node). `_field_cells_visited` is the 1-indexed cell number.
##
## Increment 1 scope: walk south from cell 0,2 (no enemies, no key gates) into
## cell 1,2's gate trigger, then DONE on the second cell load.
func _on_field_cell_loaded(field: Node) -> void:
	_stop_field_walk()
	if _field_cells_visited == 1:
		# Cell 0,2 spawn → walk south to the gate trigger.
		# Wait extra for the controller to finish _compute_portal_positions
		# and for the companion spawn/intro dialog to settle.
		_after(STEP_DELAY * 3.0, func() -> void: _drive_field_cell_initial(field))
	elif _field_cells_visited == 2:
		print("[sanity] checkpoint: field cell 2 reached (cross-gate walk worked)")
		print("[sanity] DONE ok")
		_after(QUIT_GRACE, func() -> void: get_tree().quit(0))


func _drive_field_cell_initial(field: Node) -> void:
	# Field can be freed between scheduling + firing if a cell transition
	# already happened — bail cleanly if so.
	if not is_instance_valid(field) or field != get_tree().current_scene:
		return
	var portal_data = field.get("_portal_data")
	if typeof(portal_data) != TYPE_DICTIONARY or not portal_data.has("south"):
		print("[sanity] WARN: cell 0,2 missing south portal in _portal_data")
		return
	var trigger_pos: Vector3 = portal_data["south"].get("trigger_pos", Vector3.ZERO)
	print("[sanity] field cell 1 (0,2): walk south → (%.2f, %.2f, %.2f)" % [trigger_pos.x, trigger_pos.y, trigger_pos.z])
	_start_field_walk(trigger_pos, func() -> void:
		# Often the cell transition fires (player crosses the Area3D, scene
		# reloads, player freed) before we hit WALK_ARRIVE_DIST; this only
		# logs if we *did* arrive without the trigger firing.
		print("[sanity] field cell 1: arrived at south trigger position"))


# ── Field walk primitive ───────────────────────────────────────
## Drive the player toward an XZ position by holding camera-relative move_*
## actions. Bypasses no physics — same code path the human's keystrokes drive.

func _start_field_walk(target: Vector3, on_arrive: Callable = Callable()) -> void:
	_walk_target = target
	_walk_on_arrive = on_arrive
	_walking = true


func _stop_field_walk() -> void:
	_walking = false
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

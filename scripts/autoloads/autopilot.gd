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
const GUILD_COUNTER := "res://scenes/2d/guild_counter.tscn"
const WARP_TELEPORTER := "res://scenes/2d/warp_teleporter.tscn"
const VALLEY_FIELD := "res://scenes/3d/field/valley_field.tscn"
const ITEM_SHOP := "res://scenes/2d/shops/item_shop.tscn"
const WEAPON_SHOP := "res://scenes/2d/shops/weapon_shop.tscn"
const EQUIPMENT := "res://scenes/2d/equipment.tscn"
const STORAGE := "res://scenes/2d/storage.tscn"

# ── Teleport targets (from the city controllers) ───────────────
const OFFICE_EXIT_POS := Vector3(0, 0.5, 6.5)            # office Area3D → counter (#356 library room)
# QuestCounterNPC sits at (-7.86, -10.67, 111.39) in the merged counter map
# (#449 — city_counter_controller._add_interactables), interaction box 3.6.
# The player stands in FRONT of the counter to talk to it. The prior fix moved
# this constant into the merged frame but landed at (-7.86, z=110), which is
# inside a NOTCH in the floor collider (s00e_sa2-floor.glb has no floor at
# x=-7.86 for z<115) — so the warped player fell through before it could
# interact, hanging every sanity run at "press interact". The floored spot the
# player actually talks to the NPC from in-game is (-6.20, -10.67, 112.84);
# teleport a touch above it so the settle-onto-floor motion fires area_entered.
const COUNTER_NPC_POS := Vector3(-6.20, -9.0, 112.84)    # floored, in front of QuestCounterNPC
const COUNTER_TO_OFFICE_POS := Vector3(14.30, -9.0, 107.47)    # counter Area3D → office (merged map)
# Warp teleporter merged into the counter (#city-merge): interact in-place, no
# counter→warp scene transition.
const WARP_PAD_POS := Vector3(0.05, -5.0, 60.96)               # WarpTeleporter pad in the counter

# ── Timing ─────────────────────────────────────────────────────
const STEP_DELAY := 0.8         # let a scene settle (slide/fade) before acting
const POLL_INTERVAL := 0.7      # accept-spam / re-check interval inside dialogs
const QUIT_GRACE := 0.4
const CHAR_NAME := "humar"

# ── Field walk tuning ──────────────────────────────────────────
## "Arrived" XZ distance for interactable walks (key, switch, gate) — has to
## be tight or we won't be in the element's interact range when we press the
## button.
const WALK_ARRIVE_DIST_INTERACT := 1.5
## Step-switch collision is 1.5m on a side (half-extent 0.75m); arriving 1.5m
## from the switch's center leaves the player OUTSIDE the trigger box, so the
## switch never fires and the linked fence stays up. Use a tighter arrive
## distance for auto_collect (step-on) targets to walk deep into the box.
const WALK_ARRIVE_DIST_STEP_ON := 0.5
## "Arrived" XZ distance for exit-trigger walks. The trigger Area3D is 6m on
## a side (valley_field_controller.gd:1524 `BoxShape3D.size = Vector3(6, 3, 6)`)
## — half-size 3m around trigger_pos — and we need the player's collider to
## actually be INSIDE the area for body_entered to fire. arrive_dist=1.5
## means the player's center is 1.5m past trigger center: well past the
## boundary, body_entered already fired, scene reload is queued.
const WALK_ARRIVE_DIST_TRIGGER := 1.5
const WALK_DIR_THRESHOLD := 0.3 # projection magnitude needed to hold a move action
const KILL_ALL_SETTLE := 0.9    # per-wave settle (re-checked in a loop until enemies group is empty or KILL_ALL_MAX_WAVES caps it)
const POST_INTERACT_SETTLE := 0.9
const POST_GATE_SETTLE := 1.5   # gate open animation + collision flip
# Quest-item pickups need the autopilot to dwell in the cell long enough
# for the multi-page pickup dialog to fully advance — cell transitions
# free the field HUD which holds the dialog_complete callback that calls
# SessionManager.collect_quest_item. Without this dwell the item is
# stepped on but never registers, the next pickup's item_count condition
# matches the wrong dialog branch, and paru pact's final "spawn telepipe"
# action (gated on item_count==4) never fires.
const POST_QUEST_ITEM_SETTLE := 10.0
const QUEST_COMPLETE_POLL := 0.4
const QUEST_COMPLETE_POLL_MAX := 60  # 60 * 0.4 = 24s
# Telepipe interact can lose the priority gamble against a dropped item that
# happens to land at the same XZ — the interact press picks up the item
# instead of activating the telepipe, the player ends up next to an empty
# telepipe with no scene change. After the first attempt, poll for the
# scene-change to CITY_COUNTER; if still in VALLEY_FIELD, walk back and re-press.
# Item is gone after the first pickup, so attempt #2 unambiguously targets
# the telepipe. 3 attempts total covers up to 2 stacked drops.
const TELEPIPE_RETRY_DELAY := POST_INTERACT_SETTLE + 0.7
const TELEPIPE_RETRY_MAX := 3
const CELL_SETTLE_DELAY := STEP_DELAY * 2.0  # wait after a cell load before acting

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
const SR_QUEST_STEPS: Array = [
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
var _walk_arrive_dist: float = WALK_ARRIVE_DIST_INTERACT
var _walk_started_at_ms: int = 0
var _walk_diag_tick: int = 0
var _failed: bool = false  # latched once _fail_with_reason fires; gates further actions
const WALK_DIAG_INTERVAL := 30   # log position every N ticks (~0.5s @ 60fps)
const WALK_WATCHDOG_MS := 15_000 # 15s; if we haven't arrived, FAIL the run

# Quest walker progress.
# _quest_step_idx is legacy — the cell-load handler used to read
# _quest_steps[_quest_step_idx] and assume the step counter mirrored cell
# loads. That broke as soon as anything reloaded a cell out of order (section
# transitions that warp back, future telepipe mechanics, etc.) — the counter
# would race ahead of reality and cell N would run with step N+k's actions.
# Cell-keyed lookup via _steps_by_cell + _cell_visit_count replaces the
# counter. _quest_step_idx is still maintained for the post-quest telepipe
# poll which reads it to label the final step.
var _quest_step_idx: int = 0
var _step_action_idx: int = 0
# The step we're currently executing — resolved from the cell that just
# loaded, NOT from a linear counter. Empty when no plan entry exists for
# the loaded cell (signals "react to engine, don't run scripted actions").
var _current_step: Dictionary = {}
# "<section_idx>:<pos>" → Array of step dicts, one per visit. visit_n=1 uses
# index 0, visit_n=2 uses index 1, etc. Populated once at startup from
# _quest_steps via _populate_steps_by_cell.
var _steps_by_cell: Dictionary = {}
# "<section_idx>:<pos>" → int. Incremented each time the cell loads so we
# pick the right plan entry for re-visits (e.g. B 1,2 → B 1,3 → B 1,2 return).
var _cell_visit_count: Dictionary = {}
# Set by _walk_to_exit from step.target right before the exit trigger fires.
# Checked by the next _on_field_cell_loaded — if the loaded cell key differs,
# the autopilot logs CELL DRIFT (something warped us somewhere unexpected).
var _expected_next_cell_key: String = ""

# cell_pos → last cell-flush tally seen for that cell (dead, boxes_destroyed,
# drops_pending, msgs_read, items_collected). Fed by CellObjectSpawner via
# observe_cell_flush() to enforce the /states/field-lifecycle persistence
# contract live: progress (kills/breaks/reads/pickups) MUST NOT regress and
# ground drops MUST NOT respawn across a cell re-visit.
var _cell_flush_tally: Dictionary = {}

# observe_hud_stats() tracks the persistent HP/PP/Lv panel's instance id (#444)
# — it must never change across scene transitions. 0 = not yet observed.
var _hud_stats_panel_id: int = 0

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

# Active quest steps + manifest index for the quest the autopilot is driving.
# Defaults to search_and_rescue (hardcoded steps); other quests load from
# data/quest_plans/<id>.json via _build_steps_from_plan.
var _quest_id: String = "search_and_rescue"
var _quest_steps: Array = SR_QUEST_STEPS
var _quest_manifest_index: int = 0  # used by guild_counter to scroll-down before accepting

# Floor-only debug mode: when PSZ_AUTOPILOT_FLOOR_ONLY=1, shrink the player
# capsule to nearly a point so it doesn't collide with wall geometry or
# decoration meshes. Lets us validate the SOLVER's floor pathfinding without
# also having to solve wall avoidance. Floor collision (which is what keeps
# the player on the ground via floor_snap) is unaffected — only horizontal
# wall hits go away.
var _floor_only := false

# Adversarial pickup mode: when PSZ_AUTOPILOT_SKIP_PICKUP_DIALOG=1, quest-item
# pickups are consumed but the "Picked up X" dialog is NEVER confirmed — the
# autopilot leaves immediately, mirroring a player who walks off at the system
# message. Used by the regression matrix's dialogue-bug probe (#239): on the
# bug, registration is deferred to dialog_complete, so the fragment is consumed
# yet never counted and the quest can't legitimately clear. The fix
# (register-on-contact) makes the run pass with this flag on.
var _skip_pickup_dialog := false

# Toast-persistence probe: when PSZ_AUTOPILOT_MENU_DURING_PICKUP=1, after each
# quest-item pickup the autopilot confirms the dialog (so the "Picked up X" box
# closes) and then toggles the PSO start menu a few times. FieldHud's
# restore_after_menu blindly re-shows every Control child on menu-close,
# including the already-closed DialogBox whose stale text was never cleared, so
# "Picked up X" reappears and sticks until the room unloads.
var _menu_during_pickup := false

# Shop/storage smoke coverage: when PSZ_AUTOPILOT_SHOPS=1, after the office
# intro the autopilot detours through the principal (debug meseta grant) and
# the shop/storage screens instead of accepting a quest. Gated so the
# regression-matrix quest flow is completely untouched. See issue #9.
var _shops_phase := false

# Defeat probe (spec /states/player-death): when PSZ_AUTOPILOT_DEFEAT=1, the
# autopilot drives normally into the first field cell, then kills the player
# instead of running the cell plan — exercising the HP-zero defeat flow end to
# end (red screen → "Yes" → return to city, 50% meseta penalty, full revive).
# Success oracle is the same DONE ok line.
var _defeat_probe := false
var _defeat_triggered := false      # killed the player already (fires once)
var _defeat_awaiting_city := false  # chose Yes, waiting to land in the city
var _defeat_meseta_before := 0

var _commitment_probe := false      # #377/#428 action-commitment probe
var _commitment_triggered := false  # ran the probe already (fires once)

var _combo_probe := false           # #155 three-tier combo-timing probe
var _combo_triggered := false       # ran the probe already (fires once)

var _enemy_freeze_probe := false    # #477 big-rig attack-wedge probe
var _enemy_freeze_triggered := false  # ran the probe already (fires once)
var _enemy_freeze_id := "hildegigas"  # roster id to spawn ("1" = default)


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
	_parse_probe_flags()
	# Optionally override which quest to drive (defaults to search_and_rescue).
	# Other quests load their step list from data/quest_plans/<id>.json.
	var qenv: String = OS.get_environment("PSZ_AUTOPILOT_QUEST")
	if qenv != "" and qenv != "search_and_rescue":
		_quest_id = qenv
		var generated := _build_steps_from_plan(qenv)
		if generated.is_empty():
			print("[sanity] FAIL: could not build steps from quest plan %s — falling back to search_and_rescue" % qenv)
			_quest_id = "search_and_rescue"
		else:
			_quest_steps = generated
			_quest_manifest_index = _manifest_index_for_quest(qenv)
			print("[sanity] autopilot quest=%s (%d steps, manifest index %d)" % [_quest_id, _quest_steps.size(), _quest_manifest_index])
	# Build cell-keyed lookup AFTER the final _quest_steps assignment so both
	# hardcoded SR and generated quest plans get the same treatment.
	# Deep-duplicate so the step dicts are mutable — SR_QUEST_STEPS is a
	# const Array; in Godot 4 GDScript, modifying a Dictionary inside a
	# const Array fails (silently or with an error that kills the
	# enclosing function), which left _steps_by_cell empty for SR. Generated
	# quest plans (paru pact, etc.) are fresh dicts already; the duplicate
	# is a small no-op cost for them.
	_quest_steps = _quest_steps.duplicate(true)
	_steps_by_cell = _populate_steps_by_cell(_quest_steps)
	_dump_plan(_quest_steps, _steps_by_cell)
	# Speed up the entire sim by 3x by default (overridable via
	# PSZ_AUTOPILOT_TIME_SCALE=N — e.g. =1 to disable, =5 for fast-forward).
	# Engine.time_scale multiplies how much GAME time advances per process
	# frame; --write-movie with --fixed-fps 30 then produces an output MP4
	# that shows the run at N× speed while the underlying autopilot timers
	# (which all go through SceneTreeTimer + create_timer, both respecting
	# time_scale) keep their relative spacing intact. Bump
	# physics_ticks_per_second proportionally so per-tick movement stays
	# small enough to avoid overshoot in collision detection (the
	# QuestItemPickup interaction box is only 1m radius — at 3× speed with
	# default 60 ticks/sec, the player could skip past it in one tick).
	var time_scale_env: String = OS.get_environment("PSZ_AUTOPILOT_TIME_SCALE")
	var scale: float = 3.0 if time_scale_env == "" else float(time_scale_env)
	if scale <= 0.0:
		scale = 1.0
	if scale != 1.0:
		Engine.time_scale = scale
		Engine.physics_ticks_per_second = int(60.0 * scale)
		print("[sanity] autopilot time_scale=%.2f, physics_ticks_per_second=%d" % [scale, Engine.physics_ticks_per_second])
	_floor_only = OS.has_environment("PSZ_AUTOPILOT_FLOOR_ONLY")
	if _floor_only:
		print("[sanity] autopilot floor-only mode: shrinking player capsule, walls won't block")
	_skip_pickup_dialog = OS.has_environment("PSZ_AUTOPILOT_SKIP_PICKUP_DIALOG")
	if _skip_pickup_dialog:
		print("[sanity] autopilot SKIP_PICKUP_DIALOG on: quest-item pickups will not confirm the dialog (dialogue-bug probe)")
	_menu_during_pickup = OS.has_environment("PSZ_AUTOPILOT_MENU_DURING_PICKUP")
	if _menu_during_pickup:
		print("[sanity] autopilot MENU_DURING_PICKUP on: will toggle the start menu during quest-item pickups (toast-persistence probe)")
	set_process(true)


## One env flag per optional coverage phase / first-field-cell probe.
func _parse_probe_flags() -> void:
	_shops_phase = OS.has_environment("PSZ_AUTOPILOT_SHOPS")
	if _shops_phase:
		print("[sanity] autopilot SHOPS coverage enabled (principal → shops → storage smoke)")
	_defeat_probe = OS.has_environment("PSZ_AUTOPILOT_DEFEAT")
	if _defeat_probe:
		print("[sanity] autopilot DEFEAT probe enabled (kill player in first field cell → return to city)")
	_commitment_probe = OS.has_environment("PSZ_AUTOPILOT_COMMITMENT")
	if _commitment_probe:
		print("[sanity] autopilot COMMITMENT probe enabled (attack/dodge must not cancel each other in first field cell)")
	_combo_probe = OS.has_environment("PSZ_AUTOPILOT_COMBO")
	if _combo_probe:
		print("[sanity] autopilot COMBO probe enabled (three-tier timing windows in first field cell)")
	_enemy_freeze_probe = OS.has_environment("PSZ_AUTOPILOT_ENEMY_FREEZE")
	if _enemy_freeze_probe:
		var freeze_val := OS.get_environment("PSZ_AUTOPILOT_ENEMY_FREEZE")
		if freeze_val != "" and freeze_val != "1":
			_enemy_freeze_id = freeze_val
		print("[sanity] autopilot ENEMY-FREEZE probe enabled (%s must exit ATTACKING unhit in first field cell)" % _enemy_freeze_id)


## Called every frame from _process — when floor-only mode is on, mark every
## non-floor StaticBody3D in the current scene as non-blocking so the
## player only collides with the floor mesh. The floor is the one named
## "collision_floor" (created in valley_field_controller._create_collision_from_meshes).
## Everything else (walls, decoration colliders, etc.) loses its collision_layer.
## Floor-only: between walks, pin the player at their last position so
## enemies can't push them across the cell during the 5-wave kill_all loop.
## We only pin between walks; during a walk, _floor_only_walk_step is
## driving position directly anyway.
var _floor_only_pin_pos: Vector3 = Vector3.ZERO
var _floor_only_pin_active := false
var _floor_only_pin_player_id: int = 0
func _maybe_apply_floor_only_capsule() -> void:
	if not _floor_only:
		return
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != VALLEY_FIELD:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	# Player just changed (new cell load): re-record their spawn position as
	# the pin point.
	if player.get_instance_id() != _floor_only_pin_player_id:
		_floor_only_pin_player_id = player.get_instance_id()
		_floor_only_pin_pos = player.global_position
		_floor_only_pin_active = true
		return
	# If we're not actively walking, hold position to prevent enemy pushback.
	if not _walking and _floor_only_pin_active:
		var p: Vector3 = player.global_position
		if p.distance_to(_floor_only_pin_pos) > 0.2:
			player.global_position = _floor_only_pin_pos


## Floor-only walk substitute: each tick, take a small step toward the target
## XZ, raycast straight down to find the floor, and snap the player there.
## Bypasses all collision (walls, decorations, enemies) so the autopilot only
## tests "is there continuous floor under the solver's path?". Fails if no
## floor is found within MAX_FLOOR_DROP meters below the step position.
const FLOOR_ONLY_STEP_PER_SEC := 6.0   # m/s — roughly running speed
const FLOOR_ONLY_RAY_FROM_Y := 5.0
const FLOOR_ONLY_RAY_LEN := 20.0       # search below the step's start Y
func _floor_only_walk_step(player: Node, target: Vector3, delta_ms: int) -> bool:
	var pos: Vector3 = player.global_position
	var dx := target.x - pos.x
	var dz := target.z - pos.z
	var dist := sqrt(dx * dx + dz * dz)
	if dist < 0.01:
		return true
	var step_m := FLOOR_ONLY_STEP_PER_SEC * (float(delta_ms) / 1000.0)
	if step_m > dist:
		step_m = dist
	var nx := pos.x + (dx / dist) * step_m
	var nz := pos.z + (dz / dist) * step_m
	# Raycast down to find floor at the new XZ.
	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(nx, pos.y + FLOOR_ONLY_RAY_FROM_Y, nz),
		Vector3(nx, pos.y + FLOOR_ONLY_RAY_FROM_Y - FLOOR_ONLY_RAY_LEN, nz),
	)
	ray.exclude = [player.get_rid()]
	var hit: Dictionary = space_state.intersect_ray(ray)
	if hit.is_empty():
		return false # no floor → caller fails
	player.global_position = Vector3(nx, hit.get("position").y + 0.05, nz)
	return true


# ── Quest-step generator (for quests that aren't the hardcoded SR) ────────
## Build a QUEST_STEPS-shaped array from a quest plan JSON. Sequential
## traversal in pathOrder; no detour logic (assumes keys are collected before
## the gate cell, which is true for paru_pact and most non-SR quests).
##
## Loader for the flat-step plan. The solver (scripts/tools/quest_plan.ts)
## emits sections[].steps[] with everything the executor needs (label, do[],
## exit, exit_portal_id, target, _section_idx, _pos). All planning logic —
## BFS detour insertion, action-list building from cell properties, exit
## direction derivation, portal-ID resolution — lives in the solver now.
func _build_steps_from_plan(quest_id: String) -> Array:
	var path := "res://data/quest_plans/%s.json" % quest_id
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return []
	var parsed: Variant = JSON.parse_string(fa.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var plan: Dictionary = parsed
	var sections: Array = plan.get("sections", [])
	var steps: Array = []
	for section_data in sections:
		var section: Dictionary = section_data
		var section_steps: Array = section.get("steps", [])
		for step_data in section_steps:
			# Deep duplicate so downstream mutation (e.g. _populate_steps_by_cell
			# adds _section_idx / _pos when they're missing for hardcoded SR
			# steps) doesn't share refs with the parsed JSON.
			steps.append(step_data.duplicate(true))
	return steps


## Build "<section_idx>:<pos>" → Array of step dicts (one per visit) from
## the linear quest step list. For generated steps (paru pact etc.) the
## section_idx + pos are baked in. For hardcoded SR_QUEST_STEPS, parse the
## label format "<X> <pos> [...]" and map letters → indices in first-seen
## order — for the canonical A/E/B section ordering this lands on 0/1/2,
## matching SessionManager.get_current_section() at runtime.
func _populate_steps_by_cell(steps: Array) -> Dictionary:
	var by_cell: Dictionary = {}
	var letter_to_idx: Dictionary = {}
	for i in range(steps.size()):
		var step: Dictionary = steps[i]
		# Store the linear index so the post-quest telepipe poll can label
		# the final step the same way it used to with _quest_step_idx.
		step["_step_idx"] = i
		var sec_idx: int
		var pos: String
		if step.has("_section_idx") and step.has("_pos"):
			sec_idx = int(step["_section_idx"])
			pos = str(step["_pos"])
		else:
			var label: String = str(step.get("label", ""))
			var parts: PackedStringArray = label.split(" ", false)
			if parts.size() < 2:
				continue
			var letter: String = str(parts[0]).to_lower()
			if not letter_to_idx.has(letter):
				letter_to_idx[letter] = letter_to_idx.size()
			sec_idx = int(letter_to_idx[letter])
			pos = str(parts[1])
			step["_section_idx"] = sec_idx
			step["_pos"] = pos
		var key: String = "%d:%s" % [sec_idx, pos]
		if not by_cell.has(key):
			by_cell[key] = []
		(by_cell[key] as Array).append(step)
	return by_cell


## One-time dump at autopilot startup — makes the full plan diffable when a
## drift bug fires later.
func _dump_plan(steps: Array, by_cell: Dictionary) -> void:
	print("[autopilot] PLAN: %d steps for quest=%s" % [steps.size(), _quest_id])
	for i in range(steps.size()):
		var s: Dictionary = steps[i]
		print("[autopilot]   #%d cell=%d:%s label='%s' do=%s exit='%s' target='%s' portal_id='%s'" % [
			i + 1, int(s.get("_section_idx", -1)), str(s.get("_pos", "?")),
			str(s.get("label", "?")), str(s.get("do", [])),
			str(s.get("exit", "")), str(s.get("target", "")),
			str(s.get("exit_portal_id", ""))])
	print("[autopilot] BY-CELL: %d unique cells" % by_cell.size())
	var keys: Array = by_cell.keys()
	keys.sort()
	for k in keys:
		var visits: Array = by_cell[k]
		var labels: Array = []
		for v in visits:
			labels.append(str(v.get("label", "?")))
		print("[autopilot]   %s × %d: %s" % [k, visits.size(), str(labels)])


## Compute the section_idx:pos key for the cell currently loaded in the
## given valley_field. Returns "" if anything is missing.
func _get_current_cell_key(field: Node) -> String:
	if field == null:
		return ""
	var current_cell = field.get("_current_cell")
	if typeof(current_cell) != TYPE_DICTIONARY:
		return ""
	var pos: String = str(current_cell.get("pos", ""))
	if pos.is_empty():
		return ""
	var sec_idx: int = 0
	if SessionManager and SessionManager.has_method("get_current_section"):
		sec_idx = int(SessionManager.get_current_section())
	return "%d:%s" % [sec_idx, pos]


## Live persistence oracle (#423 + /states/field-lifecycle §Persistence).
## CellObjectSpawner._save_cell_state hands us the per-cell tally (keyed by
## SECTION + pos) on every exit-flush. On a re-flush of a cell we've already
## seen, the *accumulating* progress MUST NOT regress — killed enemies, broken
## boxes, read messages, and collected items only ever go up for a given cell;
## a drop in any of those counts means a re-entry resurrected something (the bug
## this feature guards against). We print "[sanity] FAIL:" so the autopilot
## pass-oracle (grep 'FAIL:') flags the run. Non-aborting: we keep going so the
## run also reports any *other* regressions in later cells.
##
## NOTE: drops_pending is reported but NOT asserted here — ground loot is
## *generated* by combat/box-breaks that can post-date an early pass-through
## flush, so the count is legitimately non-monotonic. Drop identity persistence
## (a specific drop keeps its position + amount through a round-trip, and
## collected drops don't reappear) is pinned by the seeded unit test
## test_drop_state_survives_warp_flush instead.
func observe_cell_flush(cell_key: String, tally: Dictionary) -> void:
	var prev: Dictionary = _cell_flush_tally.get(cell_key, {})
	if not prev.is_empty():
		# Accumulating fields: a re-visit must never show LESS progress.
		for field in ["dead", "boxes_destroyed", "msgs_read", "items_collected"]:
			var now_v: int = int(tally.get(field, 0))
			var was_v: int = int(prev.get(field, 0))
			if now_v < was_v:
				print("[sanity] FAIL: state regressed at cell %s (%s %d→%d) — respawn/undo on re-entry" % [
					cell_key, field, was_v, now_v])
	# Keep the highest tally seen for this cell (guards against a late
	# pass-through flush — e.g. an 'open_gate' return visit that doesn't
	# re-fight — making the baseline drop and masking a later real regression).
	var merged := tally.duplicate()
	for field in ["dead", "boxes_destroyed", "msgs_read", "items_collected"]:
		merged[field] = max(int(tally.get(field, 0)), int(prev.get(field, 0)))
	_cell_flush_tally[cell_key] = merged
	print("[sanity] checkpoint: cell-state-held cell=%s dead=%d boxes_destroyed=%d drops_pending=%d msgs_read=%d items_collected=%d" % [
		cell_key, int(tally.get("dead", 0)), int(tally.get("boxes_destroyed", 0)),
		int(tally.get("drops_pending", 0)), int(tally.get("msgs_read", 0)),
		int(tally.get("items_collected", 0))])


## Live persistence oracle for the HP/PP/Lv stats panel (#444;
## /states/field-lifecycle §HUD across an area transition). The panel is a
## persistent autoload (HudStats) — it MUST be the SAME node instance across
## every scene transition, never freed and rebuilt by a per-scene controller.
## HudStats reports its panel's instance id + in-tree state on every
## SceneManager.scene_changed; a changed id means something rebuilt the panel,
## an out-of-tree panel means it got freed. Either prints "[sanity] FAIL:" so
## the pass-oracle (grep 'FAIL:') flags the run. Non-aborting, like
## observe_cell_flush.
func observe_hud_stats(panel_id: int, in_tree: bool, scene_path: String) -> void:
	if not in_tree:
		print("[sanity] FAIL: hud-stats panel left the tree at %s — panel was freed" % scene_path)
	elif _hud_stats_panel_id != 0 and panel_id != _hud_stats_panel_id:
		print("[sanity] FAIL: hud-stats panel instance changed across transition (%d→%d at %s) — panel was rebuilt" % [
			_hud_stats_panel_id, panel_id, scene_path])
	_hud_stats_panel_id = panel_id
	print("[sanity] checkpoint: hud-stats-held id=%d scene=%s" % [panel_id, scene_path.get_file()])


## Position of a quest in data/quests/manifest.json (0-based). Returns 0 if not
## found. Used to scroll-down at the guild counter — entries are displayed in
## manifest order after the passthrough "report / cancel" rows.
func _manifest_index_for_quest(quest_id: String) -> int:
	var fa := FileAccess.open("res://data/quests/manifest.json", FileAccess.READ)
	if fa == null:
		return 0
	var parsed: Variant = JSON.parse_string(fa.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		return 0
	var arr: Array = parsed
	for i in range(arr.size()):
		if str(arr[i]) == quest_id:
			return i
	return 0


## Post-quest report flow (#354): quests are reported at the GUILD COUNTER
## only — the Principal is story dialog (intro/briefing), never completion.
## The autopilot tests BOTH surfaces in one pass:
##   1. Talk to the Principal — the interaction must work, but MUST NOT
##      complete the quest (negative guard). If it does, that's a regression.
##   2. Leave the office, go to the counter, report there → quest clears → DONE.
const PRINCIPAL_INTERACT_POS := Vector3(0.0, 0.5, -3.9)  # desk front, within INTERACTION_RADIUS of Principal at z=-5.6 (#356)

var _report_acted := false           # office Principal-guard fired
var _principal_guard_done := false   # Principal proven not to complete the quest
var _counter_report_tries := 0       # counter-report interact attempts (retry guard)
var _guild_report_count := 0

func _drive_office_report() -> void:
	var node := get_tree().current_scene
	if node == null or node.scene_file_path != CITY_OFFICE:
		return
	if _report_acted:
		return
	_report_acted = true
	# Talk to the Principal — interaction must work + direct to the counter,
	# but MUST NOT complete the quest (#354).
	print("[sanity] teleport to Principal (report-guard) at (%.2f, %.2f, %.2f)" % [PRINCIPAL_INTERACT_POS.x, PRINCIPAL_INTERACT_POS.y, PRINCIPAL_INTERACT_POS.z])
	_teleport_player(PRINCIPAL_INTERACT_POS)
	_after(0.6, func() -> void:
		print("[sanity] press interact (Principal)")
		_press_action("interact"))
	# Advance the Principal's "report at the counter" dialog (2 pages + slack).
	for i in range(4):
		_after(1.2 + 0.4 * i, func() -> void: _press_action("ui_accept"))
	_after(3.4, _verify_principal_did_not_report)


func _verify_principal_did_not_report() -> void:
	# The Principal is story-dialog only (#354): talking to it MUST NOT
	# complete the quest. If it did, that's exactly the regression we guard.
	if not SessionManager.has_completed_quest():
		_fail_and_quit("Principal completed the quest — reporting must happen at the guild counter only (#354)")
		return
	print("[sanity] checkpoint: Principal did NOT complete the quest (correct) — going to guild counter to report")
	_principal_guard_done = true
	SceneManager.goto_scene(CITY_COUNTER)


## At the counter scene with a completed quest: teleport to the guild NPC and
## interact, which pushes the guild_counter overlay (driven by _drive_guild_report).
## Retries the interact if the overlay doesn't open — a single missed interact
## must not hang the whole matrix (the no-retry version could; #354 follow-up).
func _drive_counter_report() -> void:
	var node := get_tree().current_scene
	if node == null or node.scene_file_path != CITY_COUNTER:
		return
	# Overlay already up → _drive_guild_report owns it; stop retrying.
	if SceneManager != null and not SceneManager._scene_stack.is_empty():
		return
	if _counter_report_tries >= 8:
		_fail_and_quit("counter report — guild overlay never opened after 8 tries")
		return
	_counter_report_tries += 1
	print("[sanity] counter: teleport to guild NPC to report quest (try %d)" % _counter_report_tries)
	_teleport_player(COUNTER_NPC_POS)
	_after(0.6, func() -> void: _press_action("interact"))
	_after(1.8, _drive_counter_report)


## In the guild_counter overlay with a completed quest: the "Report" entry is
## at index 0. ui_accept opens the confirm modal; another confirms → report_quest
## clears the completed-quest state → DONE.
func _drive_guild_report() -> void:
	if not SessionManager.has_completed_quest():
		print("[sanity] checkpoint: quest reported at guild counter")
		_save_and_quit()
		return
	if _guild_report_count >= 6:
		_fail_and_quit("guild-counter report did not complete after 6 accepts")
		return
	_press_action("ui_accept")
	_guild_report_count += 1
	_after(1.0, _drive_guild_report)


## Fail terminator — print the FAIL line (matrix oracle greps for it) and quit
## non-zero, deliberately WITHOUT the DONE-ok marker so the phase reads failed.
func _fail_and_quit(reason: String) -> void:
	print("[sanity] FAIL: %s" % reason)
	_after(0.5, func() -> void: get_tree().quit(1))


## Persist state via SaveManager + quit. Terminator shared by all phases.
func _save_and_quit() -> void:
	if SaveManager != null and SaveManager.has_method("save_game"):
		SaveManager.save_game()
		print("[sanity] save_game()")
	print("[sanity] DONE ok")
	# Let the save write hit disk before exit.
	_after(0.8, func() -> void: get_tree().quit(0))


func _process(_delta: float) -> void:
	# Floor-only debug: shrink the active player's capsule whenever a new
	# player node is spawned (cell loads instantiate a fresh player).
	_maybe_apply_floor_only_capsule()
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
	# Post-quest report flow (#354): after complete_quest, the player returns
	# to a city scene with has_completed_quest() true. Test BOTH surfaces:
	# first the Principal (must NOT complete — office report-guard), then the
	# guild counter (the only real turn-in). Always do the office guard first,
	# regardless of which city scene we land in.
	if SessionManager.has_completed_quest() and path.begins_with("res://scenes/3d/city/"):
		if not _principal_guard_done:
			if path == CITY_OFFICE:
				print("[sanity] checkpoint: office — Principal report-guard (#354)")
				_after(STEP_DELAY * 2.0, _drive_office_report)
			else:
				print("[sanity] checkpoint: quest report — go to office for Principal guard (%s)" % path)
				_after(STEP_DELAY, func() -> void: SceneManager.goto_scene(CITY_OFFICE))
		else:
			if path == CITY_COUNTER:
				print("[sanity] checkpoint: counter — report quest (#354)")
				_after(STEP_DELAY * 2.0, _drive_counter_report)
			else:
				print("[sanity] checkpoint: quest report — go to counter (%s)" % path)
				_after(STEP_DELAY, func() -> void: SceneManager.goto_scene(CITY_COUNTER))
		return

	if path == INPUT_SELECT:
		_after(STEP_DELAY, _pick_keyboard)
	elif path == TITLE:
		_drive_title_scene()
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
		# Defeat probe: chose "Yes" on the defeat screen and arrived in the city.
		# Assert the consequences and finish — don't fall into the accept flow.
		if _defeat_awaiting_city:
			_finish_defeat_probe()
			return
		print("[sanity] checkpoint: city_counter")
		_counter_npc_interacted = false
		_warp_pad_interacted = false  # warp pad lives here now (merged map)
		_after(STEP_DELAY * 2.0, _drive_city_counter)
	elif path == VALLEY_FIELD:
		print("[sanity] checkpoint: valley_field entered")
		# The per-cell loop is driven by _on_field_cell_loaded — fires on the
		# same frame this scene-change does, so don't drive anything here.


func _drive_title_scene() -> void:
	if _boot_returning_to_title:
		# Boot phase ran "Return to Title" — DONE here, not at the office.
		# The mp4 ends with the title screen visible for a beat (QUIT_GRACE).
		print("[sanity] checkpoint: returned to title (boot phase complete)")
		# #425: title.gd::_ready already ran SessionManager.reset_all_state(),
		# the production chokepoint that must wipe the city-hub position cache.
		# Assert it here so a regression (reset_all_state no longer clearing
		# CityState) is caught by the probe rather than only the unit test.
		if CityState != null and CityState.get_player_position() == null:
			print("[sanity] checkpoint: city-state cleared on title-return")
		else:
			print("[sanity] FAIL: CityState not cleared on title-return — stale city position survives reset_all_state (#425)")
		print("[sanity] DONE ok")
		_after(QUIT_GRACE, func() -> void: get_tree().quit(0))
	else:
		print("[sanity] checkpoint: title")
		_after(STEP_DELAY, func() -> void: _press_action("ui_accept"))


func _drive_overlay(path: String) -> void:
	if path == GUILD_COUNTER:
		print("[sanity] checkpoint: guild_counter")
		# A completed quest → report flow; otherwise the accept flow (#354).
		if SessionManager.has_completed_quest():
			_guild_report_count = 0
			_after(STEP_DELAY, _drive_guild_report)
		else:
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
## Walk the create wizard by its flow step (CLASS_SELECT=0, APPEARANCE=1,
## NAME_ENTRY=2, read from the screen's CharacterCreateState): accept
## defaults, then set + submit the name to fire _on_name_submitted →
## _create_character → city. Re-arms until scene leaves.
func _drive_char_create() -> void:
	var node := get_tree().current_scene
	if node == null or node.scene_file_path != CHAR_CREATE:
		return
	var create_state: Object = node.get("_state")
	if create_state == null:
		return
	var step: int = int(create_state.get("step"))
	if step != _cc_acted_step:
		_cc_acted_step = step
		match step:
			0:
				# Exercise the class-select slat tween — the path that produced
				# the #380 cutout wobble — by navigating right then back left
				# before confirming, so the selection width animation actually
				# runs. (Previously this step pressed ui_accept immediately and
				# the slats were never animated.)
				for i in range(3):
					_after(0.25 * float(i), func() -> void: _press_action("ui_right"))
				for i in range(2):
					_after(0.75 + 0.25 * float(i), func() -> void: _press_action("ui_left"))
				_after(1.4, func() -> void: _press_action("ui_accept"))
			1:
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
		_menu_carry_open_before_exit()
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
	elif _shops_phase:
		print("[sanity] office intro complete → shop/storage smoke (PSZ_AUTOPILOT_SHOPS)")
		_after(STEP_DELAY, _drive_shop_smoke)
	else:
		print("[sanity] office intro complete → exit to counter")
		_menu_carry_open_before_exit()
		_teleport_player(OFFICE_EXIT_POS)


## Match the "Return to Title" sequence: SaveManager.save_game() →
## goto_scene(TITLE). The title scene's _ready calls SessionManager.reset_all_state(),
## which is the SINGLE production chokepoint that wipes session + CityState (#425).
## This autopilot path used to call CityState.clear() itself here, which masked the
## production gap — issue #425 was exactly that the real return-to-title path never
## cleared the city-hub position cache. We now drive ONLY the production reset (no
## manual clear) and assert CityState is empty once the title scene has loaded, so a
## regression where reset_all_state stops clearing CityState would fail this probe.
## The TITLE handler above recognises _boot_returning_to_title and DONEs there, so the
## mp4 ends on the title screen instead of a hard cut from the office.
func _save_and_return_to_title() -> void:
	_boot_returning_to_title = true
	if SaveManager != null and SaveManager.has_method("save_game"):
		SaveManager.save_game()
		print("[sanity] save_game()")
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


# ── Shop / storage smoke (PSZ_AUTOPILOT_SHOPS) ─────────────────
# Exercises the shop + storage screens the regression matrix never opens, to
# catch flow regressions (and screen-load breaks like #283). Runs after the
# office intro instead of accepting a quest; each step prints a [sanity]
# checkpoint asserted by the smoke script. Built incrementally — see #9.
var _shop_meseta_before := -1
var _shop_buy_before := -1


func _get_active_meseta() -> int:
	if CharacterManager != null and CharacterManager.has_method("get_active_character"):
		var c = CharacterManager.get_active_character()
		if c:
			return int(c.get("meseta", 0))
	return -1


func _drive_shop_smoke() -> void:
	var node := get_tree().current_scene
	if node == null or node.scene_file_path != CITY_OFFICE:
		return
	# Inc 0: talk to the principal for the debug 10k-meseta grant. The grant
	# path (_on_principal_interact) only fires when no quest is completed —
	# true here, pre-quest — see city_office_controller.gd.
	_shop_meseta_before = _get_active_meseta()
	print("[sanity] shop-smoke: meseta before principal = %d" % _shop_meseta_before)
	_teleport_player(PRINCIPAL_INTERACT_POS)
	_after(0.6, func() -> void:
		print("[sanity] shop-smoke: interact principal (debug meseta)")
		_press_action("interact"))
	_after(1.5, func() -> void: _poll_principal_meseta(0))


func _poll_principal_meseta(n: int) -> void:
	if (n % 2) == 0:
		_press_action("ui_accept")  # advance the grant dialog
	var now := _get_active_meseta()
	if _shop_meseta_before >= 0 and now > _shop_meseta_before:
		print("[sanity] checkpoint: principal debug meseta granted (%d -> %d)" % [_shop_meseta_before, now])
		_after(STEP_DELAY, _open_item_shop)
		return
	if n > 20:
		print("[sanity] FAIL: principal debug meseta not granted (still %d)" % now)
		_save_and_quit()
		return
	_after(0.5, func() -> void: _poll_principal_meseta(n + 1))


# Inc 1: open the Item Shop overlay (the screen class that broke in #283) and
# assert it mounts. Pushed directly — same call the market NPC makes — rather
# than physically walking office→counter→market.
func _open_item_shop() -> void:
	print("[sanity] shop-smoke: opening item_shop")
	SceneManager.push_scene(ITEM_SHOP, {"npc_display_name": "Item Shop"})
	_after(2.0, _check_item_shop_opened)


func _check_item_shop_opened() -> void:
	var top := ""
	if SceneManager != null and not SceneManager._scene_stack.is_empty():
		top = String(SceneManager._scene_stack[SceneManager._scene_stack.size() - 1])
	if top != ITEM_SHOP:
		print("[sanity] FAIL: item_shop did not open (top overlay='%s')" % top)
		_after(STEP_DELAY, _save_and_quit)
		return
	print("[sanity] checkpoint: item_shop opened")
	# Inc 2: buy the first Items-tab row (affordable — 10.5k meseta + fresh
	# inventory). ui_accept opens the buy modal; QuantityDialog wants
	# accept-to-advance then accept-to-confirm, ConfirmDialog just confirms — so a
	# few spaced ui_accepts cover both paths. Assert success by a meseta drop.
	_shop_buy_before = _get_active_meseta()
	print("[sanity] shop-smoke: buying item (meseta before = %d)" % _shop_buy_before)
	_after(0.6, func() -> void: _press_action("ui_accept"))   # open buy modal
	_after(1.2, func() -> void: _press_action("ui_accept"))   # qty → confirm step
	_after(1.8, func() -> void: _press_action("ui_accept"))   # confirm
	_after(2.6, _check_item_bought)


func _check_item_bought() -> void:
	var now := _get_active_meseta()
	if _shop_buy_before >= 0 and now < _shop_buy_before:
		print("[sanity] checkpoint: item_shop bought (meseta %d -> %d)" % [_shop_buy_before, now])
	else:
		print("[sanity] FAIL: item_shop purchase did not register (meseta still %d)" % now)
	# Close the item shop, then on to the weapon shop (Inc 3).
	_after(STEP_DELAY, func() -> void:
		if SceneManager != null and SceneManager.has_method("pop_scene"):
			SceneManager.pop_scene()
		_after(STEP_DELAY, _open_weapon_shop))


# Inc 3: weapon shop. Opening it is the hard regression assert (it's a ShopBase
# screen too). The buy is best-effort: weapon rows can be legitimately disabled
# by class-equippability, so try a few rows and WARN (not FAIL) if none take.
var _weapon_buy_attempt := 0


func _open_weapon_shop() -> void:
	print("[sanity] shop-smoke: opening weapon_shop")
	SceneManager.push_scene(WEAPON_SHOP, {"npc_display_name": "Weapon Shop"})
	_after(2.0, _check_weapon_shop_opened)


func _check_weapon_shop_opened() -> void:
	var top := ""
	if SceneManager != null and not SceneManager._scene_stack.is_empty():
		top = String(SceneManager._scene_stack[SceneManager._scene_stack.size() - 1])
	if top != WEAPON_SHOP:
		print("[sanity] FAIL: weapon_shop did not open (top overlay='%s')" % top)
		_after(STEP_DELAY, _save_and_quit)
		return
	print("[sanity] checkpoint: weapon_shop opened")
	_shop_buy_before = _get_active_meseta()
	_weapon_buy_attempt = 0
	_after(0.6, _try_weapon_buy)


func _try_weapon_buy() -> void:
	# Try the current row: open the buy modal + confirm (covers Confirm/Quantity).
	_press_action("ui_accept")
	_after(0.5, func() -> void: _press_action("ui_accept"))
	_after(1.0, func() -> void: _press_action("ui_accept"))
	_after(1.6, _check_weapon_buy_result)


func _check_weapon_buy_result() -> void:
	var now := _get_active_meseta()
	if _shop_buy_before >= 0 and now < _shop_buy_before:
		print("[sanity] checkpoint: weapon_shop bought (meseta %d -> %d)" % [_shop_buy_before, now])
		_finish_weapon_shop()
		return
	_weapon_buy_attempt += 1
	if _weapon_buy_attempt >= 6:
		# Not a hard fail: the open succeeded (the regression-critical part); a
		# class may simply not be able to equip the first rows.
		print("[sanity] WARN: weapon_shop — no buyable row in first %d (class equippability?)" % _weapon_buy_attempt)
		_finish_weapon_shop()
		return
	# Close any modal that opened on a disabled/echo row, move to next row, retry.
	_press_action("ui_cancel")
	_after(0.3, func() -> void: _press_action("ui_down"))
	_after(0.7, _try_weapon_buy)


func _finish_weapon_shop() -> void:
	# Close the weapon shop, then exercise the equipment screen (Inc 4).
	_after(STEP_DELAY, func() -> void:
		if SceneManager != null and SceneManager.has_method("pop_scene"):
			SceneManager.pop_scene()
		_after(STEP_DELAY, _open_equipment))


# Inc 4: equipment screen. Opening it is a hard regression assert (a complex
# stat-preview screen that could break on load like the shops did). Then equip
# a weapon and assert the active character's weapon slot actually changed.
#
# The character starts with a class starter weapon already equipped (saber /
# handgun / rod), and Inc 3's weapon-shop buy is best-effort (class
# equippability can leave it a no-op). So rather than depend on either, we seed
# one guaranteed class-equippable weapon into the inventory, then drive the
# screen to equip it — the assertion is "weapon slot changed", robust to row
# ordering and to whatever Inc 3 did.
var _equip_weapon_before := ""


func _open_equipment() -> void:
	print("[sanity] shop-smoke: opening equipment")
	SceneManager.push_scene(EQUIPMENT, {})
	_after(2.0, _check_equipment_opened)


func _check_equipment_opened() -> void:
	var top := ""
	if SceneManager != null and not SceneManager._scene_stack.is_empty():
		top = String(SceneManager._scene_stack[SceneManager._scene_stack.size() - 1])
	if top != EQUIPMENT:
		print("[sanity] FAIL: equipment did not open (top overlay='%s')" % top)
		_after(STEP_DELAY, _save_and_quit)
		return
	print("[sanity] checkpoint: equipment opened")
	# Seed a guaranteed class-equippable weapon distinct from the equipped one.
	var seeded := _seed_equippable_weapon()
	_equip_weapon_before = _get_equipped_weapon()
	if seeded.is_empty():
		# Fresh character + full registry: the class should always have some
		# equippable weapon that fits in inventory. Empty here means a broken
		# class/registry definition or the inventory rejected every add — a real
		# regression, so fail hard rather than silently skip the equip assert.
		print("[sanity] FAIL: equipment — no class-equippable weapon could be seeded")
		_after(STEP_DELAY, _save_and_quit)
		return
	print("[sanity] shop-smoke: equipping weapon (slot 0, before = '%s')" % _equip_weapon_before)
	# Slot 0 is the weapon slot by default. Open its item list, step off the
	# [Equipped] row to the first inventory weapon, equip it.
	_after(0.6, func() -> void: _press_action("ui_accept"))   # open weapon item list
	_after(1.2, func() -> void: _press_action("ui_down"))     # off [Equipped] → inventory weapon
	_after(1.8, func() -> void: _press_action("ui_accept"))   # equip it
	_after(2.6, _check_weapon_equipped)


## Add one class-equippable weapon (different from the equipped one) to the
## inventory so the equip list has a concrete row to select. Returns the id that
## was actually added, or "" if none could be seeded. Ids are sorted so the pick
## is deterministic regardless of registry/filesystem load order.
func _seed_equippable_weapon() -> String:
	var character = CharacterManager.get_active_character()
	if character == null:
		return ""
	var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	var equipped: String = str(character.get("equipment", {}).get("weapon", ""))
	var ids: Array = WeaponRegistry.get_all_weapon_ids()
	ids.sort()
	for wid in ids:
		if wid == equipped:
			continue
		var w = WeaponRegistry.get_weapon(wid)
		if w == null:
			continue
		if class_data == null or class_data.can_equip_weapon_type(w.weapon_type):
			# add_item can fail (e.g. inventory full); only claim success when
			# the weapon is actually in inventory, otherwise keep looking.
			if Inventory.add_item(wid, 1):
				print("[sanity] equipment: seeded equippable weapon '%s'" % wid)
				return wid
	return ""


func _get_equipped_weapon() -> String:
	var character = CharacterManager.get_active_character()
	if character == null:
		return ""
	return str(character.get("equipment", {}).get("weapon", ""))


func _check_weapon_equipped() -> void:
	var now := _get_equipped_weapon()
	if now != _equip_weapon_before and not now.is_empty():
		print("[sanity] checkpoint: equipment equipped weapon ('%s' -> '%s')" % [_equip_weapon_before, now])
	else:
		print("[sanity] FAIL: equipment — weapon slot unchanged (still '%s')" % now)
	# Inc 4b (#357): the duplicate-frame regression — seed several copies of one
	# frame, then equip a NON-first copy through this same screen. The player bug
	# was "only the first copy equips; the rest act like tools." The weapon equip
	# left the screen in slot-navigation mode (_choosing_item=false), so the probe
	# drives the frame slot directly (no ui_cancel — that would pop the screen).
	_after(STEP_DELAY, _probe_frame_dup_equip)


# Inc 4b (#357): drive the live equipment screen to list + equip duplicate
# frame instances. A hard regression assert — this is the exact surface the
# Rozalin playtest flagged. Reads the screen node from SceneManager's overlay
# top and calls its own _open_item_selection / _equip_selected_item so the
# assertion follows the real code path (item_fits_slot filtering included).
func _probe_frame_dup_equip() -> void:
	var screen: Node = SceneManager._get_current_top() if SceneManager != null else null
	if screen == null or not screen.has_method("_open_item_selection"):
		print("[sanity] FAIL: frame-dup — equipment screen node not on top (got '%s')" % (
			screen.name if screen != null else "<null>"))
		_after(STEP_DELAY, _save_and_quit)
		return
	var character = CharacterManager.get_active_character()
	if character == null:
		print("[sanity] FAIL: frame-dup — no active character")
		_after(STEP_DELAY, _save_and_quit)
		return
	# Each sub-step prints its own checkpoint/FAIL and, on failure, schedules the
	# save+quit and returns false so the chain stops. (#357/#363 + per-instance.)
	if not _pf_list_and_equip_nonfirst(screen, character):
		return
	if not _pf_frame_change_clears_units(screen, character):
		return
	if not _pf_per_instance_slots(screen, character):
		return
	if not _pf_equip_legality(screen, character):
		return
	_pf_cleanup_and_finish(character)


## Index of the always-present "frame" slot in the screen's visible slot list.
func _pf_frame_slot_idx(screen: Node) -> int:
	return (screen._get_visible_slots() as Array).find("frame")


## Seed 3 same-type frames, assert all list as equippable, equip a #N-suffixed
## (non-first) instance, and assert it sticks AND contributes full DEF (#357/#363).
func _pf_list_and_equip_nonfirst(screen: Node, character) -> bool:
	# add_item gives the first copy the bare id and the rest "#N" suffixes — the
	# suffix is what broke item_fits_slot pre-#357.
	for _i in range(3):
		Inventory.add_item("armor", 1)
	var frame_idx: int = _pf_frame_slot_idx(screen)
	if frame_idx < 0:
		print("[sanity] FAIL: frame-dup — no frame slot visible")
		_after(STEP_DELAY, _save_and_quit)
		return false
	screen._selected_slot = frame_idx
	screen._open_item_selection()
	# Count the listed frame instances + locate a #N-suffixed (non-first) one.
	var listed := 0
	var suffixed_idx := -1
	for i in range(screen._equippable_items.size()):
		var row: Dictionary = screen._equippable_items[i]
		var rid: String = str(row.get("id", ""))
		if Inventory.get_base_id(rid) == "armor" and not bool(row.get("equipped", false)):
			listed += 1
			if "#" in rid and suffixed_idx < 0:
				suffixed_idx = i
	if listed < 3 or suffixed_idx < 0:
		print("[sanity] FAIL: frame-dup — screen listed %d/3 frame copies, suffixed_idx=%d (the #357 regression)" % [
			listed, suffixed_idx])
		_after(STEP_DELAY, _save_and_quit)
		return false
	print("[sanity] checkpoint: frame-dup all 3 copies listed as equippable")
	# Equip the non-first instance through the screen and assert it sticks.
	var target_id: String = str(screen._equippable_items[suffixed_idx].get("id", ""))
	screen._selected_item = suffixed_idx
	screen._equip_selected_item()
	var equipped_frame: String = str(character.get("equipment", {}).get("frame", ""))
	if equipped_frame != target_id:
		print("[sanity] FAIL: frame-dup — non-first frame did not equip (want '%s', got '%s')" % [
			target_id, equipped_frame])
		_after(STEP_DELAY, _save_and_quit)
		return false
	print("[sanity] checkpoint: frame-dup equipped non-first instance ('%s')" % target_id)
	# Rule 1 (/mechanics/inventory): a suffixed instance is a full, equal item —
	# it must contribute its base type's DEF through the live screen, not read as
	# 0 (the #363 raw-suffixed-id registry bug, distinct from "can't equip it").
	var dup_def: int = int(screen._calc_equip_bonuses(character["equipment"], character).get("def", 0))
	if dup_def <= 0:
		print("[sanity] FAIL: frame-dup — suffixed frame gave 0 DEF (raw-suffixed-id lookup, #363)")
		_after(STEP_DELAY, _save_and_quit)
		return false
	print("[sanity] checkpoint: frame-dup suffixed frame full stats (def=%d)" % dup_def)
	return true


## Rule 2 (/mechanics/inventory): equip a unit, swap to a different frame instance
## through the screen, and assert every unit slot comes back empty.
func _pf_frame_change_clears_units(screen: Node, character) -> bool:
	Inventory.add_item("ace_guard", 1)
	character["equipment"]["unit1"] = "ace_guard"
	screen._selected_slot = _pf_frame_slot_idx(screen)
	screen._open_item_selection()
	var swap_idx := -1
	for i in range(screen._equippable_items.size()):
		var r: Dictionary = screen._equippable_items[i]
		if Inventory.get_base_id(str(r.get("id", ""))) == "armor" and not bool(r.get("equipped", false)):
			swap_idx = i
			break
	if swap_idx < 0:
		print("[sanity] FAIL: frame-change — no second frame instance to swap to")
		_after(STEP_DELAY, _save_and_quit)
		return false
	screen._selected_item = swap_idx
	screen._equip_selected_item()
	var units_after: Array = []
	for s in ["unit1", "unit2", "unit3", "unit4"]:
		if not str(character["equipment"].get(s, "")).is_empty():
			units_after.append(s)
	if not units_after.is_empty():
		print("[sanity] FAIL: frame-change — units survived a frame swap: %s" % str(units_after))
		_after(STEP_DELAY, _save_and_quit)
		return false
	print("[sanity] checkpoint: frame-change cleared all units")
	return true


## Per-instance slots (/mechanics/inventory): record a 1-slot roll on one instance
## and assert the screen exposes exactly that count, not the base type's fallback.
func _pf_per_instance_slots(screen: Node, character) -> bool:
	var one_slot_id := ""
	for iid in Inventory._items.keys():
		if Inventory.get_base_id(iid) == "armor":
			one_slot_id = str(iid)
			break
	if one_slot_id.is_empty():
		return true  # nothing to assert — earlier steps already proved the path
	if not character.has("armor_slots"):
		character["armor_slots"] = {}
	character["armor_slots"][one_slot_id] = 1
	character["equipment"]["frame"] = one_slot_id
	var vis: Array = screen._get_visible_slots()
	var unit_slots := 0
	for s in vis:
		if str(s).begins_with("unit"):
			unit_slots += 1
	if unit_slots != 1 or not vis.has("unit1") or vis.has("unit2"):
		print("[sanity] FAIL: armor-slots — 1-slot instance exposed %d unit slots: %s" % [unit_slots, str(vis)])
		_after(STEP_DELAY, _save_and_quit)
		return false
	print("[sanity] checkpoint: armor-slots per-instance count = %d" % unit_slots)
	return true


# Inc 4c (equip-legality, spec /mechanics/equip-legality): the ✕ marker the shops
# and menus show MUST match what the equip ACTION actually allows — the exact class
# of bug Rozalin hit ("no ✕ / can equip" in the shop, but it won't equip; or a ✕ yet
# it still equips). On the LIVE equipment screen, seed a class-legal and a class-
# illegal weapon AND armor, then assert the screen's built equip list (the action)
# includes exactly the gear EquipmentUtils.item_fits_slot permits. Disks aren't
# equippable, so their ✕ is checked through the live start-menu renderer. Runs against
# real built screens (load + render + Android export), which the .new() unit tests can't.
func _pf_equip_legality(screen: Node, character) -> bool:
	# Weapons: get_all_weapon_ids enumerates the full set, so an illegal type always
	# exists for any class (no class allows every type).
	if not _el_check_slot(screen, "weapon", _el_pick_weapon(false), _el_pick_weapon(true)):
		return false
	# Armor: ArmorRegistry has no enumerator, so probe a known core set; "frame" is
	# always legal (empty usable_by). Skips with a WARN only if this class happens to
	# be able to wear every candidate (rare).
	if not _el_check_slot(screen, "frame", _el_pick_armor(false), _el_pick_armor(true)):
		return false
	return _el_disk_marker_ok(character)


## Assert the live equipment screen's built list for `slot_key` includes the legal
## item and excludes the illegal one (== item_fits_slot). Seeds + removes both.
## On mismatch, prints FAIL + schedules save/quit and returns false.
func _el_check_slot(screen: Node, slot_key: String, illegal_id: String, legal_id: String) -> bool:
	if illegal_id.is_empty() or legal_id.is_empty():
		print("[sanity] WARN: equip-legality — no illegal/legal %s pair for this class (skipped)" % slot_key)
		return true
	Inventory.add_item(illegal_id, 1)
	Inventory.add_item(legal_id, 1)
	var listed: Array = _el_listed_base_ids(screen, slot_key)
	var legal_ok: bool = legal_id in listed
	var illegal_ok: bool = not (illegal_id in listed)
	Inventory.remove_item(illegal_id, Inventory.get_item_count(illegal_id))
	Inventory.remove_item(legal_id, Inventory.get_item_count(legal_id))
	if not (legal_ok and illegal_ok):
		print("[sanity] FAIL: equip-legality %s — action != gate (legal '%s' listed=%s, illegal '%s' excluded=%s)" % [
			slot_key, legal_id, str(legal_ok), illegal_id, str(illegal_ok)])
		_after(STEP_DELAY, _save_and_quit)
		return false
	print("[sanity] checkpoint: equip-legality %s action == gate (legal '%s' listed, illegal '%s' excluded)" % [
		slot_key, legal_id, illegal_id])
	return true


## First weapon id whose legality (item_fits_slot, active class + equip_all) equals
## `want_legal`. Sorted so the pick is deterministic across registry load order.
func _el_pick_weapon(want_legal: bool) -> String:
	var ids: Array = WeaponRegistry.get_all_weapon_ids()
	ids.sort()
	for wid in ids:
		if EquipmentUtils.item_fits_slot(str(wid), "weapon") == want_legal:
			return str(wid)
	return ""


## First known-core armor whose legality equals `want_legal` for the active class.
const _EL_ARMOR_CANDIDATES := ["frame", "armor", "robe", "aegir_robe", "ancient_robe", "psy_armor", "cross_armor", "hide_suit", "battle_suit"]
func _el_pick_armor(want_legal: bool) -> String:
	for aid in _EL_ARMOR_CANDIDATES:
		if ArmorRegistry.get_armor(aid) == null:
			continue
		if EquipmentUtils.item_fits_slot(aid, "frame") == want_legal:
			return aid
	return ""


## Open the screen's item list for `slot_key` and return the base ids it offers.
func _el_listed_base_ids(screen: Node, slot_key: String) -> Array:
	var idx: int = (screen._get_visible_slots() as Array).find(slot_key)
	if idx < 0:
		return []
	screen._selected_slot = idx
	screen._open_item_selection()
	var out: Array = []
	for row in screen._equippable_items:
		out.append(Inventory.get_base_id(str(row.get("id", ""))))
	return out


## Disk ✕ via the LIVE start-menu renderer (disks aren't equippable — the ✕ is the
## whole UX). An unlearnable disk MUST be marked, a learnable one MUST NOT be.
func _el_disk_marker_ok(character) -> bool:
	if PsoStartMenu == null or PsoStartMenu._renderer == null:
		print("[sanity] WARN: equip-legality — start-menu renderer unavailable, disk check skipped")
		return true
	var inv: Array = TechniqueManager.generate_shop_inventory(int(character.get("level", 1)))
	var illegal_disk := ""
	var legal_disk := ""
	for d in inv:
		var tid := str(d.get("technique_id", ""))
		var lvl := int(d.get("level", 1))
		var did := "disk_%s_%d" % [tid, lvl]
		if TechniqueManager.class_can_learn(character, tid, lvl):
			if legal_disk.is_empty():
				legal_disk = did
		elif illegal_disk.is_empty():
			illegal_disk = did
	if illegal_disk.is_empty():
		print("[sanity] WARN: equip-legality — class can learn every shop disk; no unlearnable disk to check")
		return true
	Inventory.add_item(illegal_disk, 1)
	var illegal_marked: bool = PsoStartMenu._renderer._item_cannot_use(illegal_disk)
	Inventory.remove_item(illegal_disk, Inventory.get_item_count(illegal_disk))
	if not illegal_marked:
		print("[sanity] FAIL: equip-legality disk — unlearnable disk '%s' NOT marked ✕" % illegal_disk)
		_after(STEP_DELAY, _save_and_quit)
		return false
	if not legal_disk.is_empty():
		Inventory.add_item(legal_disk, 1)
		var legal_marked: bool = PsoStartMenu._renderer._item_cannot_use(legal_disk)
		Inventory.remove_item(legal_disk, Inventory.get_item_count(legal_disk))
		if legal_marked:
			print("[sanity] FAIL: equip-legality disk — learnable disk '%s' wrongly marked ✕" % legal_disk)
			_after(STEP_DELAY, _save_and_quit)
			return false
	print("[sanity] checkpoint: equip-legality disk ✕ (unlearnable '%s' marked, learnable not)" % illegal_disk)
	return _el_disk_dup_use_ok(character, legal_disk)


# #417: a duplicate learnable disk (minted as "disk_<t>_<n>#2") must still
# learn at Lv.N — not be rejected because int("<n>#2") concatenates to a
# huge over-cap level. Exercise the data path through Inventory.use_item on
# the SECOND instance, then restore the character's techniques.
func _el_disk_dup_use_ok(character, legal_disk: String) -> bool:
	if legal_disk.is_empty():
		return true
	var parts := legal_disk.split("_", false, 2)
	var tid := str(parts[1]) if parts.size() >= 3 else ""
	var lvl := int(str(parts[2])) if parts.size() >= 3 else 0
	var techs_backup: Dictionary = (character.get("techniques", {}) as Dictionary).duplicate(true)
	Inventory.add_item(legal_disk, 1)
	Inventory.add_item(legal_disk, 1)
	var dup_id := ""
	for k in Inventory._items.keys():
		var kk := str(k)
		if kk != legal_disk and kk.begins_with(legal_disk + "#"):
			dup_id = kk
			break
	var dup_ok: bool = (not dup_id.is_empty()) and Inventory.use_item(dup_id)
	var learned: int = TechniqueManager.get_technique_level(character, tid)
	# Display half: the technique is now known at Lv.N, and the FIRST copy is still
	# in the bag. It must read as grey-WITHOUT-✕ (already known) through the shared
	# sell_disabled predicate, not a permanent ✕. Capture before restoring techs.
	var ShopNavCls = load("res://scripts/2d/shops/shop_nav.gd")
	var rest_greyed: bool = ShopNavCls.sell_disabled(legal_disk)
	var rest_no_x: bool = not ShopNavCls.sell_cannot_use(legal_disk)
	# Clean up both instances and restore prior technique state.
	Inventory.remove_item(legal_disk, Inventory.get_item_count(legal_disk))
	if not dup_id.is_empty():
		Inventory.remove_item(dup_id, Inventory.get_item_count(dup_id))
	character["techniques"] = techs_backup
	if not dup_ok or learned != lvl:
		print("[sanity] FAIL: disk dup-use — '%s' (dup '%s') learned Lv.%d, expected Lv.%d (ok=%s)" % [legal_disk, dup_id, learned, lvl, str(dup_ok)])
		_after(STEP_DELAY, _save_and_quit)
		return false
	print("[sanity] checkpoint: disk dup-use strips suffix (#2 learns Lv.%d)" % lvl)
	if not rest_greyed or not rest_no_x:
		print("[sanity] FAIL: already-known disk grey — remaining '%s' greyed=%s no-✕=%s (expected true/true)" % [legal_disk, str(rest_greyed), str(rest_no_x)])
		_after(STEP_DELAY, _save_and_quit)
		return false
	print("[sanity] checkpoint: already-known disk greyed without ✕ (Lv.%d duplicate)" % lvl)
	return true


## Leave a clean slate for storage (Inc 5): unequip + drop the seeded gear.
func _pf_cleanup_and_finish(character) -> void:
	character["equipment"]["frame"] = ""
	for s in ["unit1", "unit2", "unit3", "unit4"]:
		character["equipment"][s] = ""
	for iid in Inventory._items.keys():
		if Inventory.get_base_id(iid) == "armor" or Inventory.get_base_id(iid) == "ace_guard":
			Inventory.remove_item(iid, Inventory.get_item_count(iid))
	_finish_equipment()


func _finish_equipment() -> void:
	# Close the equipment screen, then exercise storage (Inc 5).
	_after(STEP_DELAY, func() -> void:
		if SceneManager != null and SceneManager.has_method("pop_scene"):
			SceneManager.pop_scene()
		_after(STEP_DELAY, _open_storage))


# Inc 5: storage round-trip. Opening it is a hard regression assert (a 4-tab
# screen with its own modals that could break on load like the shops did). Then
# a full deposit→withdraw round-trip on both meseta and an item, asserting the
# GameState.stored_meseta / shared_storage state actually moves and comes back.
#
# Tabs cycle Deposit Items → Withdraw Items → Deposit Meseta → Withdraw Meseta
# via ui_right; the screen resets the row selection on each tab change. We read
# the live storage node (top overlay) to pick a non-equipped item rather than
# guessing a row index, so the deposit can't trip the "Unequip first!" block.
const STORAGE_MESETA_DEPOSIT := 2   # qty bumped to via one ui_up in the dialog
const STORAGE_MESETA_WITHDRAW := 1  # default qty (no bump) on the withdraw side
var _storage_meseta_before := -1
var _storage_meseta_after_deposit := -1
var _storage_deposit_item_id := ""
var _storage_count_before := -1


func _storage_node() -> Node:
	if SceneManager == null or SceneManager._overlay_stack.is_empty():
		return null
	var top = SceneManager._overlay_stack[SceneManager._overlay_stack.size() - 1].get("scene")
	if top != null and top.scene_file_path == STORAGE:
		return top
	return null


func _open_storage() -> void:
	print("[sanity] shop-smoke: opening storage")
	SceneManager.push_scene(STORAGE, {})
	_after(2.0, _check_storage_opened)


func _check_storage_opened() -> void:
	if _storage_node() == null:
		print("[sanity] FAIL: storage did not open")
		_after(STEP_DELAY, _save_and_quit)
		return
	print("[sanity] checkpoint: storage opened")
	_after(STEP_DELAY, _storage_deposit_meseta)


# ── Meseta deposit (tab 0 → Deposit Meseta = tab 2) ───────────────
func _storage_deposit_meseta() -> void:
	_storage_meseta_before = GameState.stored_meseta
	print("[sanity] storage: depositing meseta (bank before = %d)" % _storage_meseta_before)
	# Cycle Deposit Items (0) → Deposit Meseta (2).
	_press_action("ui_right")
	_after(0.4, func() -> void: _press_action("ui_right"))
	# Open the qty dialog, bump to 2 (so the later withdraw also has max_qty>1
	# and stays on the SelectingQty→Confirming path), then confirm.
	_after(0.9, func() -> void: _press_action("ui_accept"))   # open QuantityDialog
	_after(1.4, func() -> void: _press_action("ui_up"))       # qty 1 → 2
	_after(1.9, func() -> void: _press_action("ui_accept"))   # SelectingQty → Confirming
	_after(2.4, func() -> void: _press_action("ui_accept"))   # confirm
	_after(3.0, _check_meseta_deposited)


func _check_meseta_deposited() -> void:
	# Exact: the dialog was bumped to qty 2, so the bank must rise by exactly 2.
	# A dropped ui_up (depositing 1) would otherwise slip past a "just rose"
	# check and leave the withdraw on the wrong dialog path.
	var expected: int = _storage_meseta_before + STORAGE_MESETA_DEPOSIT
	if GameState.stored_meseta == expected:
		print("[sanity] checkpoint: storage deposited meseta (%d -> %d)" % [_storage_meseta_before, GameState.stored_meseta])
		_storage_meseta_after_deposit = GameState.stored_meseta
		_after(STEP_DELAY, _storage_deposit_item)
	else:
		print("[sanity] FAIL: storage meseta deposit wrong (bank %d, expected %d)" % [GameState.stored_meseta, expected])
		_after(STEP_DELAY, _save_and_quit)


# ── Item deposit (back to Deposit Items = tab 0) ──────────────────
func _storage_deposit_item() -> void:
	# Deposit Meseta (2) → Deposit Items (0).
	_press_action("ui_left")
	_after(0.4, func() -> void: _press_action("ui_left"))
	_after(0.9, _do_storage_item_deposit)


func _do_storage_item_deposit() -> void:
	var node := _storage_node()
	if node == null:
		print("[sanity] FAIL: storage node gone before item deposit")
		_after(STEP_DELAY, _save_and_quit)
		return
	# Pick the first non-equipped inventory row (equipped gear is blocked from
	# being stored). _inventory_items mirrors the Deposit-Items list order.
	var items: Array = node._inventory_items
	var target: int = -1
	for i in range(items.size()):
		if not node._is_equipped(str(items[i].get("id", ""))):
			target = i
			break
	if target < 0:
		print("[sanity] FAIL: storage — no depositable (non-equipped) item in inventory")
		_after(STEP_DELAY, _save_and_quit)
		return
	_storage_deposit_item_id = str(items[target].get("id", ""))
	_storage_count_before = GameState.shared_storage.size()
	print("[sanity] storage: depositing item '%s' (row %d, bank items before = %d)" % [_storage_deposit_item_id, target, _storage_count_before])
	# Navigate from row 0 (reset on tab change) down to the target, then confirm.
	_nav_down_to(target, _confirm_item_deposit)


func _confirm_item_deposit() -> void:
	# Per-slot gear → ConfirmDialog (one accept); stackables → QuantityDialog
	# (accept advances SelectingQty→Confirming, second accept confirms).
	_press_action("ui_accept")   # open the move modal
	if Inventory._is_per_slot(_storage_deposit_item_id):
		_after(0.6, func() -> void: _press_action("ui_accept"))   # Confirm Yes
		_after(1.2, _check_item_deposited)
	else:
		_after(0.6, func() -> void: _press_action("ui_accept"))   # SelectingQty → Confirming
		_after(1.1, func() -> void: _press_action("ui_accept"))   # confirm qty=1
		_after(1.7, _check_item_deposited)


func _check_item_deposited() -> void:
	if _storage_has_item(_storage_deposit_item_id):
		print("[sanity] checkpoint: storage deposited item ('%s')" % _storage_deposit_item_id)
		_after(STEP_DELAY, _storage_withdraw_item)
	else:
		print("[sanity] FAIL: storage item deposit did not register ('%s' not in bank)" % _storage_deposit_item_id)
		_after(STEP_DELAY, _save_and_quit)


# ── Item withdraw (Deposit Items 0 → Withdraw Items = tab 1) ──────
func _storage_withdraw_item() -> void:
	_press_action("ui_right")   # 0 → 1 (Withdraw Items)
	_after(0.6, _do_storage_item_withdraw)


func _do_storage_item_withdraw() -> void:
	# Row selection reset to 0 on tab change; the just-deposited item is the
	# first (only, on a fresh save) storage row.
	_press_action("ui_accept")   # open the move modal
	if Inventory._is_per_slot(_storage_deposit_item_id):
		_after(0.6, func() -> void: _press_action("ui_accept"))
		_after(1.2, _check_item_withdrawn)
	else:
		_after(0.6, func() -> void: _press_action("ui_accept"))
		_after(1.1, func() -> void: _press_action("ui_accept"))
		_after(1.7, _check_item_withdrawn)


func _check_item_withdrawn() -> void:
	if not _storage_has_item(_storage_deposit_item_id):
		print("[sanity] checkpoint: storage withdrew item ('%s' back to inventory)" % _storage_deposit_item_id)
		_after(STEP_DELAY, _storage_withdraw_meseta)
	else:
		print("[sanity] FAIL: storage item withdraw did not register ('%s' still in bank)" % _storage_deposit_item_id)
		_after(STEP_DELAY, _save_and_quit)


# ── Meseta withdraw (Withdraw Items 1 → Withdraw Meseta = tab 3) ──
func _storage_withdraw_meseta() -> void:
	print("[sanity] storage: withdrawing meseta (bank = %d)" % GameState.stored_meseta)
	_press_action("ui_right")   # 1 → 2
	_after(0.4, func() -> void: _press_action("ui_right"))   # 2 → 3 (Withdraw Meseta)
	_after(0.9, func() -> void: _press_action("ui_accept"))   # open QuantityDialog
	_after(1.4, func() -> void: _press_action("ui_accept"))   # SelectingQty → Confirming
	_after(1.9, func() -> void: _press_action("ui_accept"))   # confirm qty=1
	_after(2.5, _check_meseta_withdrawn)


func _check_meseta_withdrawn() -> void:
	# Exact: withdraw moved 1 back out, so the bank must drop by exactly 1 from
	# its post-deposit peak. Checking against the peak (not just "< peak") means
	# a failed withdraw — which would leave the bank AT the peak — fails here,
	# and a partial/over withdraw is caught too.
	var expected: int = _storage_meseta_after_deposit - STORAGE_MESETA_WITHDRAW
	if GameState.stored_meseta == expected:
		print("[sanity] checkpoint: storage withdrew meseta (%d -> %d)" % [_storage_meseta_after_deposit, GameState.stored_meseta])
		print("[sanity] checkpoint: storage round-trip")
	else:
		print("[sanity] FAIL: storage meseta withdraw wrong (bank %d, expected %d)" % [GameState.stored_meseta, expected])
		_after(STEP_DELAY, _save_and_quit)
		return
	_finish_storage()


func _finish_storage() -> void:
	# Close storage, then exercise the start menu.
	_after(STEP_DELAY, func() -> void:
		if SceneManager != null and SceneManager.has_method("pop_scene"):
			SceneManager.pop_scene()
		_after(STEP_DELAY, _open_start_menu))


## True if shared storage currently holds an entry for item_id.
func _storage_has_item(item_id: String) -> bool:
	for s in GameState.shared_storage:
		if str(s.get("id", "")) == item_id:
			return true
	return false


## Press ui_down `count` times (spaced) then run `done`. count==0 runs `done`
## immediately. Used to land on a known row before opening its modal.
func _nav_down_to(count: int, done: Callable) -> void:
	if count <= 0:
		done.call()
		return
	_press_action("ui_down")
	_after(0.35, func() -> void: _nav_down_to(count - 1, done))


# Start-menu leg (separate from the #290 shop increments, which end at Inc 5 /
# storage above). The PsoStartMenu autoload opens in the city too (post-
# onboarding, pre-quest — exactly this slot), so drive it here: open → enter a
# submenu → back → close. Open/close are hard asserts (it's a complex autoload
# that could regress); the submenu hop is best-effort.
func _open_start_menu() -> void:
	print("[sanity] shop-smoke: opening start menu")
	if PsoStartMenu == null:
		print("[sanity] FAIL: PsoStartMenu autoload missing")
		_after(STEP_DELAY, _save_and_quit)
		return
	PsoStartMenu.open()
	_after(1.0, _check_start_menu_opened)


func _check_start_menu_opened() -> void:
	if not PsoStartMenu.is_open():
		print("[sanity] FAIL: start menu did not open")
		_after(STEP_DELAY, _save_and_quit)
		return
	print("[sanity] checkpoint: start_menu opened")
	# Enter the first submenu (proves StartMenuInput routing works in the city).
	_press_action("ui_accept")
	_after(0.8, _check_start_menu_submenu)


func _check_start_menu_submenu() -> void:
	if PsoStartMenu._mode != PsoStartMenu.Mode.MAIN:
		print("[sanity] checkpoint: start_menu submenu entered (mode %d)" % PsoStartMenu._mode)
	else:
		print("[sanity] WARN: start_menu stayed on MAIN after accept (non-fatal)")
	_press_action("ui_cancel")  # back to MAIN
	_after(0.6, _close_start_menu)


func _close_start_menu() -> void:
	PsoStartMenu.close()
	_after(0.6, func() -> void:
		if PsoStartMenu.is_open():
			print("[sanity] FAIL: start menu did not close")
		else:
			print("[sanity] checkpoint: start_menu closed")
		_after(STEP_DELAY, _probe_freefield_accept))


# Inc 6 (#359): a suspended FREE field must not block guild quest accept. The
# Rozalin bug — enter a free field, StartWarp back to the city, then the guild
# refuses to let you accept a quest. Reproduce the precondition (a suspended
# type-"field" session — NOT a quest) and drive the REAL guild_counter overlay
# accept; assert acceptance succeeds. Guarded with a poll cap so a blocked/stuck
# accept fails loudly instead of hanging (the #354 lesson).
func _probe_freefield_accept() -> void:
	# Clean slate, then leave a free field the way StartWarp does — this flushes
	# a free run into the per-area Free-Roam store (mirrors test_freefield_quest_unblock).
	SessionManager.return_to_city()
	SessionManager._accepted_quest.clear()
	SessionManager._suspended_session.clear()
	SessionManager.clear_free_roam_state()
	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.flush_free_roam_field()
	if not SessionManager.has_free_roam_field("gurhacia") or SessionManager.has_suspended_session():
		print("[sanity] FAIL: freefield-accept — couldn't set up a free field in the store (freeroam=%s susp=%s)" % [
			str(SessionManager.has_free_roam_field("gurhacia")), str(SessionManager.has_suspended_session())])
		_after(STEP_DELAY, _save_and_quit)
		return
	print("[sanity] checkpoint: freefield-accept precondition (free field in store, not a quest)")
	# Reset the guild accept driver, then push the overlay — the _process overlay
	# poll auto-detects it and runs _drive_guild_counter (the same accept-spam the
	# matrix uses for every quest), exercising guild_counter._has_active_quest.
	_guild_accept_count = 0
	_guild_scroll_done = false
	_last_overlay = ""
	SessionManager._accepted_quest.clear()
	SceneManager.push_scene(GUILD_COUNTER, {})
	_after(2.0, func() -> void: _poll_freefield_accept(0))


func _poll_freefield_accept(n: int) -> void:
	if SessionManager.has_accepted_quest():
		print("[sanity] checkpoint: freefield-accept — quest accepted despite a free field in progress (#359)")
		SessionManager.cancel_accepted_quest()
		SessionManager.return_to_city()
		SessionManager._suspended_session.clear()
		SessionManager.clear_free_roam_state()
		_after(STEP_DELAY, _probe_field_quest_decouple)
		return
	if n > 12:
		print("[sanity] FAIL: freefield-accept — guild never accepted (free field in progress blocked it? #359)")
		_after(STEP_DELAY, _save_and_quit)
		return
	_after(1.0, func() -> void: _poll_freefield_accept(n + 1))


# Inc 7 (#384/#378): the Field-Context/Quest-State decoupling. Rozalin's crash
# was a player completing a quest's objectives, then MOVING — with the old code
# the session (field sections) was cleared on completion, so the next cell load
# hit "Invalid section index". Drive the real managers headlessly through the
# contract: completion keeps the field + telepipe alive; report tears both down.
# FAIL-capped (each failure saves + quits — no no-retry, #354 lesson).
func _probe_field_quest_decouple() -> void:
	SessionManager.return_to_city()
	SessionManager._suspended_session.clear()
	SessionManager._accepted_quest.clear()
	SessionManager._completed_quest.clear()
	TelepipeManager.cancel("decouple_probe_setup")
	# Enter a quest field and drop a telepipe in it.
	SessionManager.accept_quest("search_and_rescue", "normal")
	SessionManager.start_accepted_quest()
	TelepipeManager.place("gurhacia", 0, "0,0", Vector3(1, 0, 1), VALLEY_FIELD)
	if not SessionManager.has_active_session() or not TelepipeManager.is_active():
		print("[sanity] FAIL: decouple — couldn't set up quest field + telepipe")
		_after(STEP_DELAY, _save_and_quit)
		return
	# Completion MUST keep the Field Context (sections) + the telepipe alive —
	# this is exactly what prevents the #378 crash when the player then moves.
	SessionManager.complete_quest()
	if SessionManager.has_active_session() \
			and not SessionManager.get_field_sections().is_empty() \
			and TelepipeManager.is_active():
		print("[sanity] checkpoint: decouple — completion keeps field+telepipe alive (#384/#378)")
	else:
		print("[sanity] FAIL: decouple — completion cleared field/telepipe (active=%s sections=%d pipe=%s)" % [
			str(SessionManager.has_active_session()), SessionManager.get_field_sections().size(),
			str(TelepipeManager.is_active())])
		_after(STEP_DELAY, _save_and_quit)
		return
	# Report is the quest exit — it MUST tear down the field context + telepipe.
	SessionManager.report_quest()
	if not SessionManager.has_active_session() and not TelepipeManager.is_active():
		print("[sanity] checkpoint: decouple — report cleared field+telepipe (#384)")
	else:
		print("[sanity] FAIL: decouple — report didn't clear (active=%s pipe=%s)" % [
			str(SessionManager.has_active_session()), str(TelepipeManager.is_active())])
		_after(STEP_DELAY, _save_and_quit)
		return
	SessionManager.return_to_city()
	SessionManager._suspended_session.clear()
	SessionManager._completed_quest.clear()
	_after(STEP_DELAY, _save_and_quit)


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
			# #426 carried-over leg: the Start Menu is still open from the office.
			# The interact below MUST be consumed by the menu, not the NPC.
			if _menu_carry_opened and not _menu_carry_checked:
				_after(0.6, _probe_menu_carry_interact)
				return
			_after(0.6, func() -> void: _press_action("interact"))
		return

	var accepted: Dictionary = SessionManager.get_accepted_quest()
	if not bool(accepted.get("briefing_shown", false)):
		print("[sanity] counter: teleport to office trigger (for briefing)")
		_teleport_player(COUNTER_TO_OFFICE_POS)
	elif not _warp_pad_interacted:
		# Warp pad now lives in this scene (merged map). Teleport onto it and
		# interact in-place to open the warp_teleporter overlay — no transition.
		_warp_pad_interacted = true
		print("[sanity] counter: teleport to warp pad")
		_teleport_player(WARP_PAD_POS)
		# Targeted probe for issue #426 (Start Menu must capture the confirm press
		# so it can't trigger the WarpTeleporter underneath). Gated behind
		# PSZ_AUTOPILOT_MENU_GATE=1 so the standard regression matrix is unaffected
		# — when unset, the warp-pad interact is byte-for-byte the old behavior.
		if OS.get_environment("PSZ_AUTOPILOT_MENU_GATE") == "1":
			_after(0.8, _probe_start_menu_blocks_interact)
			return
		_after(0.8, func() -> void: _press_action("interact"))


# ── Guild counter overlay ──────────────────────────────────────
## Manifest order positions quests below a couple of passthrough entries.
## If PSZ_AUTOPILOT_QUEST selects something other than manifest-index 0
## (search_and_rescue), press ui_down enough times to land on the target
## entry before the ui_accept ×3 confirm-flow runs.
## ui_accept #1 → difficulty mode; #2 → confirm modal; #3 → confirms → pop.
var _guild_scroll_done := false
func _drive_guild_counter() -> void:
	if SessionManager.has_accepted_quest():
		print("[sanity] guild_counter: quest accepted")
		# Wait for the overlay to pop, then re-drive counter (state-aware).
		_after(2.0, _drive_city_counter)
		return
	# Scroll down to the right quest BEFORE the accept-spam starts. Each
	# ui_down moves selection one step in the entry list. Manifest entries
	# come after the passthroughs; the autopilot's selection cursor starts
	# at index 0 (whatever's at the top), so we need _quest_manifest_index
	# downs to reach the target. SR is index 0 → no scrolling.
	if not _guild_scroll_done:
		_guild_scroll_done = true
		if _quest_manifest_index > 0:
			print("[sanity] guild_counter: scrolling down %d to reach %s" % [_quest_manifest_index, _quest_id])
			for i in range(_quest_manifest_index):
				_after(0.15 * (i + 1), func() -> void: _press_action("ui_down"))
			_after(0.15 * (_quest_manifest_index + 1) + 0.3, _drive_guild_counter)
			return
	if _guild_accept_count >= 6:
		print("[sanity] WARN: guild accept limit reached")
		return
	_press_action("ui_accept")
	_guild_accept_count += 1
	_after(1.2, _drive_guild_counter)


# City warp is no longer a separate scene — the WarpTeleporter pad lives in the
# counter (merged map) and is driven in-place by _drive_city_counter (#city-merge).


## Issue #426 carried-over probe (PSZ_AUTOPILOT_MENU_CARRY=1). The fresh-open
## probe below covers a menu opened in the SAME area; this one covers Rozalin's
## carried-over repro (open in the market, transition, interact at the counter):
## the Start Menu is opened in the OFFICE and left open across the
## office→counter transition — the autoload survives the tree rebuild — then
## the interact press at the guild counter NPC MUST be consumed by the menu
## (spec /states/start-menu invariants; #426 edge case 2026-06-28).
var _menu_carry_opened := false
var _menu_carry_checked := false


func _menu_carry_open_before_exit() -> void:
	if OS.get_environment("PSZ_AUTOPILOT_MENU_CARRY") != "1" or _menu_carry_opened:
		return
	if PsoStartMenu == null:
		_fail_and_quit("menu-carry probe — PsoStartMenu autoload missing")
		return
	_menu_carry_opened = true
	PsoStartMenu.open()
	print("[sanity] menu-carry: Start Menu opened in office, exiting with it open")


func _probe_menu_carry_interact() -> void:
	if PsoStartMenu == null or not PsoStartMenu.is_open():
		_fail_and_quit("menu-carry — Start Menu did not survive the office→counter transition")
		return
	print("[sanity] menu-carry: at guild NPC with carried menu open, pressing interact (must be blocked)")
	_press_action("interact")
	_after(0.5, _probe_menu_carry_blocked_check)


func _probe_menu_carry_blocked_check() -> void:
	_menu_carry_checked = true
	var stack_size := 0
	if SceneManager != null:
		stack_size = SceneManager._scene_stack.size()
	var top := ""
	if stack_size > 0:
		top = String(SceneManager._scene_stack[stack_size - 1])
	if top == GUILD_COUNTER:
		_fail_and_quit("menu-carry — interact opened the guild counter while the carried Start Menu was open (#426)")
		return
	if not PsoStartMenu.is_open():
		# Not the double-fire itself, but the press should land in the menu, not
		# close it — surface it without failing (the hard assertion is above).
		print("[sanity] WARN: menu-carry — interact press closed the carried menu")
	print("[sanity] checkpoint: start-menu-carry-blocks-interact")
	# Close the menu and re-drive the counter with a fresh interact so the
	# normal accept flow (and the rest of the run) continues.
	if PsoStartMenu.is_open():
		PsoStartMenu.close()
	_counter_npc_interacted = false
	_after(0.5, _drive_city_counter)


## Issue #426 runtime probe (pack-gated — needs the city scene + the pack-only
## WarpPad mesh, so it runs only on a pack-mounted build, not repo-only CI).
## With the player standing on the WarpTeleporter pad: open the Start Menu,
## press interact, and assert NO warp overlay pushed (the modal consumed the
## press); then close the menu and confirm interact opens the overlay on the
## next frame. Emits `[sanity] checkpoint: start-menu-blocks-interact` on pass.
func _probe_start_menu_blocks_interact() -> void:
	if PsoStartMenu == null:
		_fail_and_quit("menu-gate probe — PsoStartMenu autoload missing")
		return
	print("[sanity] menu-gate: open Start Menu, then press interact (must be blocked)")
	PsoStartMenu.open()
	_after(0.4, func() -> void:
		_press_action("interact")
		_after(0.4, _probe_menu_blocked_check))


func _probe_menu_blocked_check() -> void:
	var stack_size := 0
	if SceneManager != null:
		stack_size = SceneManager._scene_stack.size()
	var top := ""
	if stack_size > 0:
		top = String(SceneManager._scene_stack[stack_size - 1])
	if top == WARP_TELEPORTER:
		_fail_and_quit("menu-gate — interact opened the warp overlay while the Start Menu was open (#426)")
		return
	print("[sanity] checkpoint: start-menu-blocks-interact")
	# Close the menu and confirm interact works again on the next frame (no
	# buffered confirm leak — the press below is a fresh one).
	PsoStartMenu.close()
	_after(0.4, func() -> void: _press_action("interact"))


# ── Field: per-cell driver ─────────────────────────────────────
## Fires every time a valley_field cell loads (first entry AND each cell
## transition — SceneManager.goto_scene reloads the scene with a fresh root
## node, so the instance id flips even though the path is unchanged).
##
## Resolve the step for the cell that just loaded (by section_idx:pos lookup,
## NOT by a linear counter), then drive its action list and walk to the exit
## portal. The next cell-load resolves the next step the same way — drifts
## from the planned cell sequence are caught and logged at the boundary.
# ── Defeat probe (spec /states/player-death) ───────────────────────────────

## First field cell loaded under PSZ_AUTOPILOT_DEFEAT: give the player a known
## meseta count, then deal lethal damage. The field controller raises the
## DefeatScreen on the `died` signal; _defeat_confirm_yes drives the "Yes".
## The player is spawned a beat after the cell-load callback fires, so poll a
## few frames until it joins the "player" group before striking.
func _run_defeat_probe(attempt: int = 0) -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		if attempt < 60:
			_after(STEP_DELAY, func() -> void: _run_defeat_probe(attempt + 1))
		else:
			print("[sanity] FAIL: defeat probe — no player in field to kill")
			_after(QUIT_GRACE, func() -> void: get_tree().quit(1))
		return
	var p = players[0]
	# Set meseta on the CHARACTER (source of truth) + the GameState mirror, so the
	# penalty is observable after the city re-syncs from the character on arrival.
	var ch = CharacterManager.get_active_character()
	if ch != null:
		ch["meseta"] = 100
	GameState.meseta = 100
	_defeat_meseta_before = 100
	print("[sanity] checkpoint: defeat probe — killing player (meseta=%d, hp=%d/%d)" % [
		GameState.meseta, GameState.hp, GameState.max_hp])
	p.take_damage(9999)
	_after(STEP_DELAY * 3.0, _defeat_confirm_yes)


## The DefeatScreen should be up now — confirm "Yes" to return to the city.
func _defeat_confirm_yes() -> void:
	var screens: Array = get_tree().get_nodes_in_group("defeat_screen")
	if screens.is_empty():
		print("[sanity] FAIL: defeat probe — defeat screen did not appear after death")
		_after(QUIT_GRACE, func() -> void: get_tree().quit(1))
		return
	print("[sanity] checkpoint: defeat probe — screen shown, choosing Yes")
	_defeat_awaiting_city = true
	screens[0].confirm_return()


## Arrived back in the city after the defeat "Yes" — assert the penalty + revive
## landed (they must survive the city's re-sync from the character) and finish.
func _finish_defeat_probe() -> void:
	_defeat_awaiting_city = false
	var want_meseta: int = _defeat_meseta_before / 2
	var ok: bool = GameState.meseta == want_meseta and GameState.hp == GameState.max_hp
	print("[sanity] checkpoint: defeat probe — arrived city, meseta %d->%d (want %d), hp %d/%d" % [
		_defeat_meseta_before, GameState.meseta, want_meseta, GameState.hp, GameState.max_hp])
	if ok:
		print("[sanity] DONE ok")
	else:
		print("[sanity] FAIL: defeat probe — meseta/hp not as expected after return")
	_after(QUIT_GRACE, func() -> void: get_tree().quit(0 if ok else 1))


# ── Action-commitment probe (#377/#428, spec /states/player-state) ─────────
## PSZ_AUTOPILOT_COMMITMENT=1: in the first field cell, assert commitment
## end-to-end — a real dodge press mid-swing must not flip ATTACKING, an
## attack input mid-roll must not flip DODGING, and the attack hitbox must be
## off once the swing ends. Runs INSTEAD of the cell plan (defeat-probe
## pattern) and ends the run with DONE ok / FAIL.

func _commitment_fail(msg: String) -> void:
	print("[sanity] FAIL: commitment probe — %s" % msg)
	_after(QUIT_GRACE, func() -> void: get_tree().quit(1))


## Poll until the player leaves `state` (or fail after ~8s game time).
func _commitment_wait_leave(p, state: int, next: Callable, attempt: int = 0) -> void:
	if not is_instance_valid(p):
		_commitment_fail("player freed mid-probe")
		return
	if p.get_state() != state:
		next.call()
		return
	if attempt >= 40:
		_commitment_fail("state %d never ended (stuck?)" % state)
		return
	_after(0.2, func() -> void: _commitment_wait_leave(p, state, next, attempt + 1))


func _run_commitment_probe(attempt: int = 0) -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		if attempt < 60:
			_after(STEP_DELAY, func() -> void: _run_commitment_probe(attempt + 1))
		else:
			_commitment_fail("no player in field")
		return
	var p = players[0]
	var states: Dictionary = p.PlayerState
	print("[sanity] checkpoint: commitment probe — starting attack, pressing dodge mid-swing")
	p._start_attack()
	if p.get_state() != states["ATTACKING"]:
		_commitment_fail("_start_attack did not enter ATTACKING")
		return
	# Real input press mid-swing — full _unhandled_input → arbitration path.
	_after(0.15, func() -> void:
		_press_action("dodge")
		_after(0.1, func() -> void: _commitment_attack_held(p, states)))


func _commitment_attack_held(p, states: Dictionary) -> void:
	if p.get_state() != states["ATTACKING"]:
		_commitment_fail("dodge press canceled the swing (#377)")
		return
	print("[sanity] checkpoint: commitment probe — swing held through dodge press")
	_commitment_wait_leave(p, states["ATTACKING"], func() -> void:
		# Swing over by any path — the hitbox must be off, targets cleared (#428).
		var hb = p.attack_hitbox
		if hb != null and (hb.monitoring or hb._hit_targets.size() > 0):
			_commitment_fail("attack hitbox outlived the swing (#428)")
			return
		print("[sanity] checkpoint: commitment probe — hitbox off after swing (#428)")
		_commitment_dodge_phase(p, states))


# ── Combo three-tier probe (#155, spec /mechanics/combos) ──────────────────
## PSZ_AUTOPILOT_COMBO=1: in the first field cell, drive a real swing and
## press attack inside each tier — miss-early must queue nothing, the just
## window must chain step 2 with the just flag, and the un-queued swing end
## must break to IDLE. Frame-polled so the presses land inside the windows
## regardless of box load / time_scale. Runs instead of the cell plan and
## ends the run with DONE ok / FAIL.

## Await cond (polled per frame) with a frame budget; false = timed out.
func _combo_await(cond: Callable, frames: int = 1800) -> bool:
	var n := 0
	while n < frames:
		if cond.call():
			return true
		await get_tree().process_frame
		n += 1
	return false


func _run_combo_probe(attempt: int = 0) -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		if attempt < 60:
			_after(STEP_DELAY, func() -> void: _run_combo_probe(attempt + 1))
		else:
			print("[sanity] FAIL: combo probe — no player in field")
			_after(QUIT_GRACE, func() -> void: get_tree().quit(1))
		return
	_combo_probe_run(players[0])


func _combo_probe_run(p) -> void:
	var states: Dictionary = p.PlayerState
	var t: Dictionary = CombatManager.get_combo_timing(p._get_equipped_weapon_type(), 1)
	if t.is_empty():
		print("[sanity] FAIL: combo probe — no timing config for equipped weapon")
		_after(QUIT_GRACE, func() -> void: get_tree().quit(1))
		return
	var just_mid: float = (float(t.just_start) + float(t.just_end)) / 2.0

	# Case 1: miss-early press FUMBLES the swing — nothing queued, later
	# presses inside the accept window are locked out, and the swing ending
	# un-queued breaks the combo: mashing defeats itself (Rozalin's #459
	# playtest fix).
	print("[sanity] checkpoint: combo probe — swing 1, miss-early press")
	p._start_attack()
	p._start_attack()  # frac ≈ 0 — miss-early → fumble
	if p._queued_combo != p.ComboQueue.NONE or not p._combo_fumbled:
		print("[sanity] FAIL: combo probe — miss-early press did not fumble the swing (#155)")
		_after(QUIT_GRACE, func() -> void: get_tree().quit(1))
		return
	print("[sanity] checkpoint: combo probe — miss-early fumbled the swing")
	var in_fwindow := await _combo_await(func() -> bool:
		return p.get_state() != states["ATTACKING"] or p._attack_frac() >= just_mid)
	if not in_fwindow or p.get_state() != states["ATTACKING"]:
		print("[sanity] FAIL: combo probe — fumbled swing ended before the accept window was reached")
		_after(QUIT_GRACE, func() -> void: get_tree().quit(1))
		return
	p._start_attack()  # inside the window, but fumbled — must be ignored
	if p._queued_combo != p.ComboQueue.NONE:
		print("[sanity] FAIL: combo probe — press after a fumble queued a chain (mash lockout broken)")
		_after(QUIT_GRACE, func() -> void: get_tree().quit(1))
		return
	var fumble_broke := await _combo_await(func() -> bool: return p.get_state() == states["IDLE"])
	if not fumble_broke or p.combo_state != 0:
		print("[sanity] FAIL: combo probe — fumbled swing did not break the combo to IDLE")
		_after(QUIT_GRACE, func() -> void: get_tree().quit(1))
		return
	print("[sanity] checkpoint: combo probe — fumbled swing broke to IDLE")
	_combo_probe_chain_phase(p, states, just_mid)


## Clean-combo half of the probe: a just-window press queues JUST, fires
## step 2 with the just flag at swing end, and the un-queued swing 2 breaks
## back to IDLE.
func _combo_probe_chain_phase(p, states: Dictionary, just_mid: float) -> void:
	print("[sanity] checkpoint: combo probe — swing 1 (clean), just-window press")
	p._start_attack()
	var in_window := await _combo_await(func() -> bool:
		return p.get_state() != states["ATTACKING"] or p._attack_frac() >= just_mid)
	if not in_window or p.get_state() != states["ATTACKING"]:
		print("[sanity] FAIL: combo probe — clean swing ended before the just window was reached")
		_after(QUIT_GRACE, func() -> void: get_tree().quit(1))
		return
	p._start_attack()
	if p._queued_combo != p.ComboQueue.JUST:
		print("[sanity] FAIL: combo probe — press at frac %.2f did not queue a JUST chain (#155)" % p._attack_frac())
		_after(QUIT_GRACE, func() -> void: get_tree().quit(1))
		return
	print("[sanity] checkpoint: combo probe — just chain queued at frac %.2f" % p._attack_frac())
	var fired := await _combo_await(func() -> bool: return p.combo_state == 2 or p.get_state() != states["ATTACKING"])
	if not fired or p.combo_state != 2 or not p._is_just_attack:
		print("[sanity] FAIL: combo probe — queued just chain did not fire step 2 with the just flag")
		_after(QUIT_GRACE, func() -> void: get_tree().quit(1))
		return
	print("[sanity] checkpoint: combo probe — step 2 fired with just bonus (#155)")

	# Case 3: no further press — swing 2 ending un-queued breaks to IDLE.
	var broke := await _combo_await(func() -> bool: return p.get_state() == states["IDLE"])
	if not broke or p.combo_state != 0:
		print("[sanity] FAIL: combo probe — un-queued swing did not break the combo to IDLE")
		_after(QUIT_GRACE, func() -> void: get_tree().quit(1))
		return
	print("[sanity] checkpoint: combo probe — un-queued swing broke to IDLE")
	print("[sanity] DONE ok")
	_after(QUIT_GRACE, func() -> void: get_tree().quit(0))


func _commitment_dodge_phase(p, states: Dictionary) -> void:
	print("[sanity] checkpoint: commitment probe — starting dodge, pressing attack mid-roll")
	p._start_dodge()
	if p.get_state() != states["DODGING"]:
		_commitment_fail("_start_dodge did not enter DODGING")
		return
	_after(0.1, func() -> void:
		# Both attack entry points, called directly so the assert doesn't
		# depend on the palette layout of the staged save.
		p._start_attack()
		p._start_strong_attack()
		_after(0.05, func() -> void:
			if p.get_state() != states["DODGING"]:
				_commitment_fail("attack press canceled the roll (#377)")
				return
			print("[sanity] checkpoint: commitment probe — roll held through attack press")
			_commitment_wait_leave(p, states["DODGING"], func() -> void:
				print("[sanity] DONE ok")
				_after(QUIT_GRACE, func() -> void: get_tree().quit(0)))))


# ── Enemy attack-recovery probe (#477, spec /states/enemies) ───────────────
## PSZ_AUTOPILOT_ENEMY_FREEZE=1: in the first field cell, spawn Hildegigas
## (gorilla rig — its attack clip is "b_014_atk1", the wedge case) in contact
## with the player, let it attack, and require ATTACKING to end with the
## player never swinging back. Runs instead of the cell plan and ends the run
## with DONE ok / FAIL.

func _enemy_freeze_fail(msg: String) -> void:
	_fail_and_quit("enemy-freeze probe — %s" % msg)


func _run_enemy_freeze_probe(attempt: int = 0) -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		if attempt < 60:
			_after(STEP_DELAY, func() -> void: _run_enemy_freeze_probe(attempt + 1))
		else:
			_enemy_freeze_fail("no player in field")
		return
	var p: Node3D = players[0]
	var edata = EnemyRegistry.get_enemy(_enemy_freeze_id)
	if edata == null:
		_enemy_freeze_fail("%s missing from EnemyRegistry" % _enemy_freeze_id)
		return
	var enemy := EnemyBase.new()
	enemy.enemy_data = edata
	var col_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = edata.collision_radius
	capsule.height = edata.collision_height
	col_shape.shape = capsule
	col_shape.position.y = capsule.height / 2
	enemy.add_child(col_shape)
	enemy.collision_layer = 8
	enemy.collision_mask = 1
	p.get_parent().add_child(enemy)
	enemy.global_position = p.global_position + p.global_transform.basis.z * 1.2
	print("[sanity] checkpoint: enemy-freeze probe — %s spawned in contact with player" % _enemy_freeze_id)
	_enemy_freeze_watch(enemy, {"attacked": false}, 0)


## Poll the spawned enemy ~5/s: it must reach ATTACKING, then leave it for
## LOAFING/CHASING with no damage event. ~20s budget before calling it wedged.
func _enemy_freeze_watch(enemy: EnemyBase, seen: Dictionary, tick: int) -> void:
	if not is_instance_valid(enemy):
		_enemy_freeze_fail("enemy freed mid-probe")
		return
	var s: int = enemy.current_state
	if s == EnemyBase.EnemyState.ATTACKING:
		if not seen["attacked"]:
			# Resolved clip visibility: '' = no attack clip → fallback-duration
			# path. The harness greps this to pin per-rig resolution.
			print("[sanity] checkpoint: enemy-freeze probe — ATTACKING (attack_anim='%s')" % enemy._attack_anim)
		seen["attacked"] = true
	elif seen["attacked"] and (s == EnemyBase.EnemyState.LOAFING or s == EnemyBase.EnemyState.CHASING):
		print("[sanity] checkpoint: enemy-freeze probe — attack cycle ended (state=%d) without a hit" % s)
		enemy.queue_free()
		print("[sanity] DONE ok")
		_after(QUIT_GRACE, func() -> void: get_tree().quit(0))
		return
	if tick >= 100:
		if seen["attacked"]:
			_enemy_freeze_fail("wedged in ATTACKING (is_attacking=%s anim_playing=%s) — the #477 freeze" % [
				str(enemy.is_attacking),
				str(enemy.animation_player.is_playing()) if enemy.animation_player else "n/a"])
		else:
			_enemy_freeze_fail("enemy never entered ATTACKING (state=%d)" % s)
		return
	_after(0.2, func() -> void: _enemy_freeze_watch(enemy, seen, tick + 1))


func _on_field_cell_loaded(field: Node) -> void:
	_stop_field_walk()
	# Defeat probe: in the first field cell, kill the player instead of running
	# the cell plan. Everything after this is the defeat flow (spec
	# /states/player-death), driven by _run_defeat_probe.
	if _defeat_probe and not _defeat_triggered:
		_defeat_triggered = true
		_run_defeat_probe()
		return
	# Commitment probe (#377/#428): in the first field cell, drive a real
	# swing + dodge press (and the mirror case) instead of the cell plan.
	if _commitment_probe and not _commitment_triggered:
		_commitment_triggered = true
		_run_commitment_probe()
		return
	# Combo probe (#155): three-tier windows on a real swing chain.
	if _combo_probe and not _combo_triggered:
		_combo_triggered = true
		_run_combo_probe()
		return
	# Enemy-freeze probe (#477): spawn a big atk1 rig on the player and
	# require its attack cycle to end without a damage event.
	if _enemy_freeze_probe and not _enemy_freeze_triggered:
		_enemy_freeze_triggered = true
		_run_enemy_freeze_probe()
		return
	var key: String = _get_current_cell_key(field)
	var stage_id: String = ""
	var current_cell = field.get("_current_cell") if field else null
	if typeof(current_cell) == TYPE_DICTIONARY:
		stage_id = str(current_cell.get("stage_id", ""))
	if key.is_empty():
		print("[sanity] WARN: cell load #%d couldn't compute cell key (stage=%s)" % [_field_cells_visited, stage_id])
		_current_step = {}
		return
	# Drift check: did we land on the cell the previous _walk_to_exit aimed at?
	if not _expected_next_cell_key.is_empty() and _expected_next_cell_key != key:
		print("[sanity] CELL DRIFT: expected %s, got %s (load #%d, stage=%s)" % [
			_expected_next_cell_key, key, _field_cells_visited, stage_id])
	_expected_next_cell_key = ""
	# Premature-telepipe check: if a Telepipe is in the scene at suspicious
	# coords (near world origin) AND the quest isn't marked complete yet,
	# log a WARN. Real telepipes spawn from a dialog action at the dialog's
	# trigger position; one at (0,0) with quest still in progress suggests
	# the engine spawned it on the default Vector3 — a bug worth tracking
	# across quests for fix triage. See discussion in commit log.
	_check_premature_telepipe(field, key, stage_id)
	# Visit counter — picks the right plan entry for re-visits (key gate returns).
	var visit_n: int = int(_cell_visit_count.get(key, 0)) + 1
	_cell_visit_count[key] = visit_n
	var entries: Array = _steps_by_cell.get(key, [])
	if entries.is_empty():
		print("[sanity] WARN: no plan entry for cell %s visit=%d (load #%d, stage=%s) — autopilot will idle this cell" % [
			key, visit_n, _field_cells_visited, stage_id])
		_current_step = {}
		return
	if visit_n - 1 >= entries.size():
		print("[sanity] WARN: visit %d exceeds plan for cell %s (have %d) — replaying last entry (load #%d, stage=%s)" % [
			visit_n, key, entries.size(), _field_cells_visited, stage_id])
		_current_step = entries[entries.size() - 1]
	else:
		_current_step = entries[visit_n - 1]
	# Maintain _quest_step_idx for legacy consumers (telepipe poll uses it to label).
	if _current_step.has("_step_idx"):
		_quest_step_idx = int(_current_step["_step_idx"])
	print("[sanity] cell-load %s visit=%d stage=%s (load #%d): plan label='%s' do=%s exit='%s' portal_id='%s'" % [
		key, visit_n, stage_id, _field_cells_visited,
		str(_current_step.get("label", "?")), str(_current_step.get("do", [])),
		str(_current_step.get("exit", "")), str(_current_step.get("exit_portal_id", ""))])
	_step_action_idx = 0
	_after(CELL_SETTLE_DELAY, func() -> void: _run_next_action(field))


func _run_next_action(field: Node) -> void:
	# A cell transition can fire mid-action; the new _on_field_cell_loaded
	# resets state, so just no-op here.
	if not is_instance_valid(field) or field != get_tree().current_scene:
		return
	if _current_step.is_empty():
		return
	var step: Dictionary = _current_step
	var actions: Array = step.get("do", [])
	if _step_action_idx >= actions.size():
		_walk_to_exit(field, step)
		return
	var action: String = str(actions[_step_action_idx])
	_step_action_idx += 1
	print("[sanity] action %d/%d: %s" % [_step_action_idx, actions.size(), action])
	# `open_gate:<dir>` carries the spoke direction for multi-gate hubs
	# (finding_ogi B 3,2). Stripped here so the match below stays exhaustive.
	var open_gate_dir := ""
	if action.begins_with("open_gate:"):
		open_gate_dir = action.substr("open_gate:".length())
		action = "open_gate"
	match action:
		"kill_all":
			_do_kill_all(field)
		"dismiss_dialog":
			_do_dismiss_dialog(field)
		"pickup_key":
			_do_pickup_key(field)
		"pickup_quest_item":
			_do_pickup_quest_item(field)
		"flip_switch":
			_do_flip_switch(field)
		"open_gate":
			_do_open_gate(field, open_gate_dir)
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
	_minimap_enemy_probe(field)
	_kill_all_wave(field, 0)


## #422 minimap enemy-marker probe: the room minimap's live dot count MUST
## match the alive count of the cell's enemy roster (spec /states/enemies —
## minimap markers). Reads the field's privates via node.get(), same as the
## other screen probes. Cheap — one pass over _room_enemies per kill_all.
func _minimap_enemy_probe(field: Node) -> void:
	var minimap: Variant = field.get("_room_minimap")
	var room_enemies: Variant = field.get("_room_enemies")
	if minimap == null or not (room_enemies is Array):
		return
	if not minimap.has_method("get_enemy_marker_count"):
		return
	var alive: int = 0
	for enemy in room_enemies:
		if not is_instance_valid(enemy):
			continue
		# EnemyBase carries is_alive; legacy EnemySpawn carries element_state.
		var alive_flag: Variant = enemy.get("is_alive")
		if alive_flag != null:
			if bool(alive_flag):
				alive += 1
		elif str(enemy.get("element_state")) != "dead":
			alive += 1
	var markers: int = minimap.get_enemy_marker_count()
	if markers == alive:
		print("[sanity] minimap-probe: enemy markers=%d alive=%d ok" % [markers, alive])
	else:
		print("[sanity] FAIL: minimap enemy markers=%d != alive=%d" % [markers, alive])


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


func _do_pickup_quest_item(field: Node) -> void:
	# Quest items in the field are QuestItemPickup nodes
	# (scripts/3d/elements/quest_item_pickup.gd). Walking onto them
	# auto-collects (DropBase pickup), which fires the cell's
	# remaining_dialog with condition.item_count matching the new count.
	# The dialog may carry actions like "complete_quest" / "telepipe" on
	# its final page (paru pact's 4th mag_fragment is the trigger for
	# both), so after the pickup we press ui_accept several times to walk
	# past any dialog pages and let the actions execute.
	var item := _find_quest_item_pickup(field)
	if item == null:
		print("[sanity] WARN: pickup_quest_item — no QuestItemPickup in cell")
		_run_next_action(field)
		return
	var item_id: String = str(item.get("item_id") if "item_id" in item else "?")
	print("[sanity] walking to quest_item id=%s at (%.1f, %.1f, %.1f)" % [
		item_id, item.global_position.x, item.global_position.y, item.global_position.z])
	# QuestItemPickup._show_pickup_dialog only calls SessionManager.
	# collect_quest_item() AFTER the dialog's dialog_complete signal fires
	# (see quest_item_pickup.gd:152). The dialog box is a child of the
	# field's HUD — cell transition reloads the scene and frees HUD +
	# dialog box, severing the dialog_complete callback before it can run.
	# So we have to DWELL in the cell long enough for the dialog to fully
	# advance through every page. POST_QUEST_ITEM_SETTLE replaces the
	# normal POST_INTERACT_SETTLE here.
	#
	# Walk to the item, then directly invoke its _on_interact rather than
	# routing through Player._try_interact. Player.nearest_interactable
	# depends on the area_entered signal chain (player interaction_area
	# vs item interaction_area collision masks); empirically this didn't
	# resolve to the quest_item even after step-on in A 3,2's pickup, so
	# the indirect path is unreliable. We already have the
	# QuestItemPickup node from _find_quest_item_pickup — call its
	# DropBase._on_interact(player) directly. After that, dwell for the
	# multi-page dialog and press ui_accept to advance it.
	if _skip_pickup_dialog:
		_pickup_skip_dialog(field, item)
		return
	if _menu_during_pickup:
		_pickup_menu_toggle(field, item)
		return
	_walk_then_interact(field, item.global_position, "quest_item", POST_QUEST_ITEM_SETTLE, true)
	# After step-on lands, fire the item's _on_interact directly. We can't
	# tell WHEN step-on completes from here, so schedule the direct
	# invocation a few times across the walk window; the QuestItemPickup
	# sets element_state="collected" on the first successful pickup, so
	# subsequent calls no-op.
	var item_ref := item
	for i in range(8):
		_after(2.0 + i * 1.5, func() -> void:
			if is_instance_valid(item_ref) and item_ref.has_method("_on_interact"):
				var pl: Node3D = get_tree().get_first_node_in_group("player")
				if pl != null:
					print("[sanity] direct-interact quest_item")
					item_ref._on_interact(pl))
	# ui_accept train advances the multi-page dialog after pickup so
	# dialog_complete fires (which is what calls
	# SessionManager.collect_quest_item).
	for i in range(25):
		_after(3.0 + i * 0.7, func() -> void: _press_action("ui_accept"))


## PSZ_AUTOPILOT_SKIP_PICKUP_DIALOG probe — adversarial repro of the dialogue
## bug (#239): walk ONTO the quest item (via the waypoint graph) and leave
## WITHOUT confirming the "Picked up X" dialog. On the unfixed code registration
## hung off dialog_complete, so the fragment was consumed yet never counted and
## the quest bricked. The fix registers on contact; the final fragment then
## roots the player and gates the telepipe on the finale dialogue, which a
## rooted real player can only advance — so we advance it here to spawn the pipe.
func _pickup_skip_dialog(field: Node, item: Node) -> void:
	var item_skip := item
	print("[sanity] SKIP_PICKUP_DIALOG: walking onto quest_item, will leave the dialog unconfirmed")
	_walk_then_interact(field, item.global_position, "quest_item", 0.0, false, func() -> void:
		var psk: Node3D = get_tree().get_first_node_in_group("player")
		if is_instance_valid(item_skip) and item_skip.has_method("_on_interact") and psk != null:
			item_skip._on_interact(psk)
			print("[sanity] SKIP_PICKUP_DIALOG: consumed quest_item; mag_fragment registered=%d (dialog left unconfirmed)" % SessionManager.get_quest_item_count("mag_fragment"))
		if SessionManager.are_objectives_complete():
			# Final fragment — advance the finale so the telepipe spawns. (On the
			# UNFIXED code this branch is never reached: earlier fragments never
			# registered, so the count can't hit target and the run wedges first.)
			print("[sanity] SKIP_PICKUP_DIALOG: final fragment — advancing finale dialogue so the telepipe spawns")
			for i in range(14):
				_after(0.8 + i * 0.8, func() -> void: _press_action("ui_accept"))
			_after(13.0, func() -> void: _run_next_action(field))
		else:
			# Intermediate fragment: leave WITHOUT confirming — the brick scenario.
			_after(1.5, func() -> void: _run_next_action(field)))


## PSZ_AUTOPILOT_MENU_DURING_PICKUP probe — adversarial repro of the
## toast-persistence bug: pick up, CONFIRM the dialog (closes the "Picked up X"
## box), then toggle the PSO start menu. On the bug restore_after_menu re-shows
## the closed box with its stale text. The probe logs DialogBox visible/active
## after the toggle — the bug is a CLOSED box still painted (visible AND not
## active); an active box (the finale's narration page) is correctly visible.
func _pickup_menu_toggle(field: Node, item: Node) -> void:
	var item_menu := item
	print("[sanity] MENU_DURING_PICKUP: walk on, pick up, confirm, then toggle the start menu")
	_walk_then_interact(field, item.global_position, "quest_item", 0.0, false, func() -> void:
		var pm: Node3D = get_tree().get_first_node_in_group("player")
		if is_instance_valid(item_menu) and item_menu.has_method("_on_interact") and pm != null:
			item_menu._on_interact(pm)
		_after(1.2, func() -> void: _press_action("ui_accept"))
		var t := 2.8
		for i in range(3):
			_after(t, func() -> void: PsoStartMenu.open())
			_after(t + 1.3, func() -> void: PsoStartMenu.close())
			t += 3.0
		_after(t + 0.5, func() -> void:
			var hud_node := get_tree().root.find_child("FieldHud", true, false)
			var dbox: Node = hud_node.get_node_or_null("DialogBox") if hud_node else null
			var vis: bool = dbox != null and dbox.visible
			var act: bool = dbox != null and dbox.has_method("is_active") and dbox.is_active()
			var stuck: bool = vis and not act
			print("[sanity] MENU_DURING_PICKUP: after menu toggle DialogBox visible=%s active=%s — toast %s" % [str(vis), str(act), ("STUCK (BUG)" if stuck else "cleared (ok)")]))
		_after(t + 3.0, func() -> void: _run_next_action(field)))


func _do_flip_switch(field: Node) -> void:
	# Two switch types in valley field: InteractSwitch (player presses
	# interact while in range) and StepSwitch (auto-collects when the player
	# physically enters its area, no input needed — auto_collect=true on
	# scripts/3d/elements/step_switch.gd). search_and_rescue uses StepSwitch
	# at A 2,2 (cell config object type "step_switch"), so just walk onto it.
	var sw := _find_interact_switch(field)
	var auto_collect := false
	if sw == null:
		sw = _find_step_switch(field)
		auto_collect = (sw != null)
	if sw == null:
		_fail_with_reason("flip_switch — no switch in cell (looked for InteractSwitch + StepSwitch)")
		return
	_walk_then_interact(field, sw.global_position, "switch", POST_INTERACT_SETTLE, auto_collect)


func _do_open_gate(field: Node, direction: String = "") -> void:
	# Multi-gate hubs (finding_ogi B 3,2) carry three KeyGate children, each
	# named KeyGate_<dir> by valley_field_controller. When `direction` is
	# provided, target that specific one; otherwise fall back to the legacy
	# "first KeyGate found" behaviour so single-gate cells stay unchanged.
	var gate: Node = null
	if direction != "":
		gate = _find_key_gate_by_direction(field, direction)
	if gate == null:
		gate = _find_key_gate(field)
	if gate == null:
		print("[sanity] WARN: open_gate — no KeyGate in cell (direction='%s')" % direction)
		_run_next_action(field)
		return
	_walk_then_interact(field, gate.global_position, "gate", POST_GATE_SETTLE)


func _do_wait_quest_complete(_field: Node) -> void:
	print("[sanity] final cell: kill_all + advance any active dialogs ~12s, then force-complete")
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("_debug_kill_all"):
		player._debug_kill_all()
	# Two natural completion paths land here:
	#   (a) SR's B 3,0 room_clear dialog fires complete_quest if objectives
	#       are met (autopilot's bypass logic often skips key drops, so this
	#       path frequently misses and we fall through to force-complete).
	#   (b) paru pact's mag_fragment quest_item, on its 4th pickup, fires
	#       a 6-page dialog whose final-page actions are
	#       [dismiss_companion, complete_quest, telepipe] — this is the only
	#       path that spawns a Telepipe for the return-to-city warp.
	# Path (b) needs the full 6 pages to be advanced before complete_quest
	# AND telepipe fire. Press ui_accept 12 times over ~12s (so multi-page
	# dialogs of any plausible length advance) before force-completing.
	# Under SKIP_PICKUP_DIALOG (dialogue-bug probe) we must NOT confirm dialogs
	# or force-complete — the whole point is to show the quest CANNOT clear when
	# pickups go unconfirmed. Let it sit so the brick is visible and assertable.
	if not _skip_pickup_dialog:
		for i in range(12):
			_after(1.0 + i * 1.0, func() -> void: _press_action("ui_accept"))
	_after(13.5, func() -> void:
		if SessionManager.has_completed_quest():
			return
		if _skip_pickup_dialog:
			print("[sanity] SKIP_PICKUP_DIALOG: objectives unmet — NOT force-completing; quest is bricked (dialogue-bug repro)")
		else:
			print("[sanity] dialog didn't fire complete_quest (objectives unmet from bypassed cells) — calling SessionManager.complete_quest() directly")
			SessionManager.complete_quest())
	# NOTE: the natural completion path is the room_clear dialog firing its
	# "telepipe" action, which spawns a Telepipe (scripts/3d/elements/telepipe.gd)
	# the player walks into for the scene change to city_warp. Walking to the
	# spawned telepipe is a follow-up — without it, _poll_quest_complete will
	# time out and FAIL the run (per the "no warps" rule). For now the dialog's
	# complete_quest action does flip has_completed_quest, so we at least see
	# that checkpoint before the timeout.
	_poll_quest_complete(0)


func _poll_quest_complete(n: int) -> void:
	if n > QUEST_COMPLETE_POLL_MAX:
		print("[sanity] WARN: quest_complete poll timeout (%d ticks)" % n)
		return
	if SessionManager.has_completed_quest():
		var done: Dictionary = SessionManager.get_completed_quest() if SessionManager.has_method("get_completed_quest") else {}
		print("[sanity] checkpoint: quest_completed (%s)" % str(done))
		# Walk to the room_clear-spawned Telepipe and interact so the scene
		# transitions to city_warp → _drive_scene's post-quest handler takes over.
		_after(STEP_DELAY * 2.0, _drive_walk_to_telepipe)
		return
	_after(QUEST_COMPLETE_POLL, func() -> void: _poll_quest_complete(n + 1))


func _drive_walk_to_telepipe(attempt: int = 0) -> void:
	var field := get_tree().current_scene
	if field == null or field.scene_file_path != VALLEY_FIELD:
		print("[sanity] WARN: not in valley_field for telepipe walk (path=%s)" % str(field.scene_file_path if field else "<null>"))
		return
	var telepipe := _find_telepipe(field)
	if telepipe == null:
		print("[sanity] WARN: no Telepipe in scene — quest finished but no warp out")
		return
	if attempt == 0:
		print("[sanity] walking to telepipe at (%.1f, %.1f, %.1f)" % [telepipe.global_position.x, telepipe.global_position.y, telepipe.global_position.z])
	else:
		print("[sanity] telepipe retry %d/%d — scene didn't change (likely picked up an item drop on the previous interact)" % [attempt + 1, TELEPIPE_RETRY_MAX])
	_walk_then_interact(field, telepipe.global_position, "telepipe", POST_INTERACT_SETTLE)
	_after(TELEPIPE_RETRY_DELAY, func() -> void: _check_telepipe_advance(attempt))


func _check_telepipe_advance(attempt: int) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path != VALLEY_FIELD:
		# Scene transitioned — telepipe fired.
		return
	if attempt + 1 >= TELEPIPE_RETRY_MAX:
		print("[sanity] WARN: telepipe didn't transition after %d attempts — giving up" % TELEPIPE_RETRY_MAX)
		return
	_drive_walk_to_telepipe(attempt + 1)


## Snapshot the scene for a Telepipe at suspicious coords (within
## TELEPIPE_PREMATURE_RADIUS of world origin) while the quest hasn't
## fired complete_quest yet. Triggers a one-line [sanity] WARN per
## occurrence so we can grep across quest runs to see the bug's
## frequency + per-quest hot spots without taking action (just
## tracking).
const TELEPIPE_PREMATURE_RADIUS := 2.0
func _check_premature_telepipe(field: Node, cell_key: String, stage_id: String) -> void:
	if SessionManager and SessionManager.has_method("has_completed_quest") and SessionManager.has_completed_quest():
		return
	var t := _find_telepipe(field)
	if t == null:
		return
	var p: Vector3 = t.global_position
	if abs(p.x) <= TELEPIPE_PREMATURE_RADIUS and abs(p.z) <= TELEPIPE_PREMATURE_RADIUS:
		print("[sanity] WARN: premature telepipe — found at (%.2f, %.2f, %.2f) in cell %s (stage=%s) before quest_completed fired" % [
			p.x, p.y, p.z, cell_key, stage_id])


func _find_telepipe(root: Node) -> Node3D:
	for child in root.get_children():
		if child.get_class() == "Node3D" or child is Node3D:
			if "Telepipe" in child.name or (child.has_method("_on_interact") and child.get_script() and str(child.get_script().get_path()).ends_with("telepipe.gd")):
				return child
		var found := _find_telepipe(child)
		if found != null:
			return found
	return null


# ── Action helpers ─────────────────────────────────────────────

func _walk_then_interact(field: Node, target: Vector3, label: String, settle: float, auto_collect: bool = false, on_arrive: Callable = Callable()) -> void:
	# Route via the authored / computed waypoint graph too, not just direct —
	# key pickups, switches, and gates are inside the cell, and L-bend stages
	# need the same multi-leg approach as exit walks. `auto_collect=true`
	# skips the interact press on the last leg (StepSwitch / step-pickups).
	var portal_data = field.get("_portal_data") if field else null
	if typeof(portal_data) != TYPE_DICTIONARY:
		portal_data = {}
	var path: Array = _find_walk_path(field, portal_data, target)
	if path.size() <= 1:
		print("[sanity] walk to %s direct (%.2f, %.2f, %.2f)" % [label, target.x, target.y, target.z])
	else:
		var leg_str := ""
		for p in path:
			leg_str += " → (%.1f, %.1f)" % [p.x, p.z]
		print("[sanity] walk to %s via %d waypoint(s):%s" % [label, path.size() - 1, leg_str])
	_walk_path_then_interact(field, path, label, settle, 0, auto_collect, on_arrive)


func _walk_path_then_interact(field: Node, path: Array, label: String, settle: float, leg: int, auto_collect: bool, on_arrive: Callable = Callable()) -> void:
	if leg >= path.size():
		return
	var target: Vector3 = path[leg]
	var is_last: bool = (leg == path.size() - 1)
	# For step-on targets we need to physically enter a tight collision box,
	# not just get close — use a tighter arrive distance on the final leg.
	# on_arrive fires _on_interact directly (range-independent), so it only needs
	# the looser "interact" approach distance — the tight step-on box is for
	# auto_collect step-on pickups, and demanding it for on_arrive risks a
	# never-arrives wedge on stages whose waypoint endpoint isn't dead-on.
	var arrive: float = WALK_ARRIVE_DIST_INTERACT
	if is_last and auto_collect and not on_arrive.is_valid():
		arrive = WALK_ARRIVE_DIST_STEP_ON
	_start_field_walk(target, func() -> void:
		if not is_instance_valid(field) or field != get_tree().current_scene:
			return
		if is_last:
			# A caller-supplied on_arrive owns everything after arrival (custom
			# pickup / menu sequences) — it runs only once the player is
			# physically on the target via the waypoint graph, so the pickup
			# looks natural instead of firing mid-walk.
			if on_arrive.is_valid():
				print("[sanity] arrived at %s" % label)
				on_arrive.call()
			elif auto_collect:
				print("[sanity] stepped on %s" % label)
				_after(settle, func() -> void: _run_next_action(field))
			else:
				_after(0.4, func() -> void:
					print("[sanity] interact %s" % label)
					_press_action("interact")
					_after(settle, func() -> void: _run_next_action(field)))
		else:
			print("[sanity] waypoint %d/%d reached — next leg" % [leg + 1, path.size() - 1])
			_after(0.1, func() -> void: _walk_path_then_interact(field, path, label, settle, leg + 1, auto_collect, on_arrive)),
		arrive)


func _walk_to_exit(field: Node, step: Dictionary) -> void:
	var exit_dir: String = str(step.get("exit", ""))
	if exit_dir == "":
		# No exit (final cell). wait_quest_complete should have handled it.
		return
	var portal_data = field.get("_portal_data")
	# Prefer ID-based lookup: the step's exit_portal_id was captured from
	# cell.portals at step-generation time and is invariant across rotations
	# and direction-label changes in the engine. Falls back to direction-key
	# lookup for cells without portal IDs in their config.
	var exit_portal_id: String = str(step.get("exit_portal_id", ""))
	var trigger_pos: Vector3 = Vector3.ZERO
	var resolved_via: String = ""
	if typeof(portal_data) == TYPE_DICTIONARY:
		if not exit_portal_id.is_empty():
			for dir_key in portal_data:
				var entry = portal_data[dir_key]
				if typeof(entry) == TYPE_DICTIONARY and str(entry.get("id", "")) == exit_portal_id:
					trigger_pos = entry.get("trigger_pos", Vector3.ZERO)
					resolved_via = "id=%s found at dir='%s'" % [exit_portal_id, str(dir_key)]
					break
		if resolved_via.is_empty() and portal_data.has(exit_dir):
			trigger_pos = portal_data[exit_dir].get("trigger_pos", Vector3.ZERO)
			resolved_via = "direction='%s' (fallback)" % exit_dir
	if resolved_via.is_empty():
		var have_keys: Array = []
		var have_ids: Array = []
		if typeof(portal_data) == TYPE_DICTIONARY:
			for k in portal_data:
				have_keys.append(str(k))
				if typeof(portal_data[k]) == TYPE_DICTIONARY:
					have_ids.append(str(portal_data[k].get("id", "")))
		_fail_with_reason("cell missing '%s' portal (step %d/%d %s) — looked for id='%s', portal_data has dirs=%s ids=%s" % [
			exit_dir, _quest_step_idx + 1, _quest_steps.size(), str(step.get("label", "?")),
			exit_portal_id, str(have_keys), str(have_ids)])
		return
	print("[sanity] exit portal resolved: %s → trigger=%s" % [resolved_via, trigger_pos])
	# Record the cell we expect to land in next, so the next _on_field_cell_loaded
	# can detect drift (transition warped us elsewhere, etc.). target is the
	# next cell's pos within the same section; for section-warp exits the
	# target is "" and we skip — drift detection only matters within a section.
	var target_pos: String = str(step.get("target", ""))
	if not target_pos.is_empty():
		var sec_idx: int = int(step.get("_section_idx", -1))
		if sec_idx >= 0:
			_expected_next_cell_key = "%d:%s" % [sec_idx, target_pos]
		else:
			_expected_next_cell_key = ""
	# Build a walkable path through the cell's spawn waypoints. If straight-
	# line raycast from the player to the trigger is clear, the path is just
	# [trigger]; otherwise BFS tries via spawn points + center to find a
	# clear multi-leg route. Watchdog → FAIL (no force-advance fallback —
	# the autopilot is checking whether a real player could traverse this).
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
## the last point, that's it — the controller's gate-trigger body_entered
## fires when the player enters the trigger Area3D (a 6m box around
## trigger_pos), which usually happens at the same time as our "arrived"
## callback because we use WALK_ARRIVE_DIST_TRIGGER (3.5m) for the last leg.
## Intermediate legs use the tighter WALK_ARRIVE_DIST_INTERACT so we land
## squarely on each navigation waypoint.
func _walk_path(field: Node, path: Array, exit_dir: String, leg: int) -> void:
	if leg >= path.size():
		return
	var target: Vector3 = path[leg]
	var is_last: bool = (leg == path.size() - 1)
	var arrive: float = WALK_ARRIVE_DIST_TRIGGER if is_last else WALK_ARRIVE_DIST_INTERACT
	_start_field_walk(target, func() -> void:
		if not is_instance_valid(field) or field != get_tree().current_scene:
			return
		if is_last:
			print("[sanity] arrived at %s trigger (cell transition imminent)" % exit_dir)
		else:
			print("[sanity] waypoint %d/%d reached — next leg" % [leg + 1, path.size() - 1])
			_after(0.1, func() -> void: _walk_path(field, path, exit_dir, leg + 1)),
		arrive)


# ── Failure handling ───────────────────────────────────────────
## The user-visible contract: any leg of the autopilot that can't be walked
## ends the run as FAIL. The intent is to verify a real player could traverse
## the level — masking that with teleports / direct-scene-transitions defeats
## the test. Pair this with the printed cell/stage so the user can open the
## offending stage in the waypoint editor and author a nav graph.
##
## Reports the current cell/stage from the field controller's _current_cell.
func _fail_walk_stuck(pos: Vector3, dist: float) -> void:
	var cell_pos := "?"
	var stage_id := "?"
	var cs := get_tree().current_scene
	if cs != null:
		var cur = cs.get("_current_cell")
		if typeof(cur) == TYPE_DICTIONARY:
			cell_pos = str(cur.get("pos", "?"))
			stage_id = str(cur.get("stage_id", "?"))
	var label := "?"
	if _quest_step_idx > 0 and _quest_step_idx <= _quest_steps.size():
		label = str(_quest_steps[_quest_step_idx - 1].get("label", "?"))
	_fail_with_reason("walk stuck at dist=%.2f from (%.1f, %.1f, %.1f) in cell %s (stage %s, %s) — author waypoints for this stage" % [
		dist, pos.x, pos.y, pos.z, cell_pos, stage_id, label])


func _fail_with_reason(reason: String) -> void:
	if _failed:
		return
	_failed = true
	print("[sanity] FAIL: %s" % reason)
	# Quit with non-zero exit — the recording scripts mark this run as fail
	# in its sidecar JSON, and the /autopilot table renders the red ✗.
	_after(QUIT_GRACE, func() -> void: get_tree().quit(1))


## Cast the same 3 downward rays the player's _can_move_to uses (center,
## left, right at FLOOR_CHECK_DISTANCE ahead of the player) and log which
## ones hit floor. Mirrors player.gd:1081 so the result tells the stage
## author exactly which sample point is dropping into a hole.
func _log_floor_samples(pos: Vector3, dir: Vector3) -> void:
	# Match player.gd constants exactly — if those change, update here too.
	const FLOOR_CHECK_DISTANCE := 1.0
	const FLOOR_CHECK_SIDE := 0.5
	const FLOOR_RAY_LENGTH := 5.0
	var center := pos + dir * FLOOR_CHECK_DISTANCE
	# Perpendicular: 90° rotation in the XZ plane (-z, 0, x), matching
	# player.gd:1087.
	var side := Vector3(-dir.z, 0.0, dir.x)
	var left := center + side * FLOOR_CHECK_SIDE
	var right := center - side * FLOOR_CHECK_SIDE
	var hit_c := _ray_floor_hit(center, pos.y, FLOOR_RAY_LENGTH)
	var hit_l := _ray_floor_hit(left, pos.y, FLOOR_RAY_LENGTH)
	var hit_r := _ray_floor_hit(right, pos.y, FLOOR_RAY_LENGTH)
	var hits: int = (1 if hit_c else 0) + (1 if hit_l else 0) + (1 if hit_r else 0)
	print("[sanity] floor samples ahead of player (FLOOR_CHECK_DISTANCE=%.1f, FLOOR_CHECK_SIDE=%.1f):" % [FLOOR_CHECK_DISTANCE, FLOOR_CHECK_SIDE])
	print("[sanity]   center=(%.3f, %.3f) floor=%s" % [center.x, center.z, hit_c])
	print("[sanity]   left  =(%.3f, %.3f) floor=%s" % [left.x, left.z, hit_l])
	print("[sanity]   right =(%.3f, %.3f) floor=%s" % [right.x, right.z, hit_r])
	print("[sanity]   hits=%d/3 → all-3=%s, 2-of-3=%s, 1-of-3=%s" % [
		hits, "PASS" if hits == 3 else "BLOCK",
		"PASS" if hits >= 2 else "BLOCK", "PASS" if hits >= 1 else "BLOCK"])


## Single downward raycast, mirroring player.gd:_has_floor_at.
func _ray_floor_hit(check_pos: Vector3, base_y: float, ray_length: float) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var ray_origin := Vector3(check_pos.x, base_y + 1.0, check_pos.z)
	var ray_end := Vector3(check_pos.x, base_y - ray_length, check_pos.z)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1
	var result: Dictionary = space_state.intersect_ray(query)
	return not result.is_empty()


# ── Scene-tree finders for interactables ───────────────────────

func _find_key_pickup(root: Node) -> Node:
	if root is KeyPickup:
		return root
	for c in root.get_children():
		var found := _find_key_pickup(c)
		if found != null:
			return found
	return null


func _find_quest_item_pickup(root: Node) -> Node:
	if root is QuestItemPickup:
		return root
	for c in root.get_children():
		var found := _find_quest_item_pickup(c)
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


func _find_step_switch(root: Node) -> Node:
	if root is StepSwitch:
		return root
	for c in root.get_children():
		var found := _find_step_switch(c)
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


# Find a KeyGate by direction. Field cells name multi-gate hub children
# "KeyGate_<dir>" (valley_field_controller.gd:2010). Match by node name
# first; fall back to nearest-locked-gate if naming convention drifts. Skip
# already-opened gates so a repeat call walks to a still-locked target
# instead of bouncing off the one we just opened.
func _find_key_gate_by_direction(root: Node, direction: String) -> Node:
	var expected_name := "KeyGate_%s" % direction
	var locked_gates: Array = []
	_collect_key_gates(root, locked_gates)
	for g in locked_gates:
		if g.name == expected_name:
			return g
	# Fallback: any still-locked gate. _do_open_gate's outer fallback covers
	# the "no locked gates at all" case.
	for g in locked_gates:
		return g
	return null


func _collect_key_gates(root: Node, out: Array) -> void:
	if root is KeyGate:
		var kg := root as KeyGate
		if kg.element_state == "locked":
			out.append(kg)
	for c in root.get_children():
		_collect_key_gates(c, out)


# ── Field walk primitive ───────────────────────────────────────
## Drive the player toward an XZ position by holding camera-relative move_*
## actions. Bypasses no physics — same code path the human's keystrokes drive.

func _start_field_walk(target: Vector3, on_arrive: Callable = Callable(), arrive_dist: float = WALK_ARRIVE_DIST_INTERACT) -> void:
	_walk_target = target
	_walk_on_arrive = on_arrive
	_walk_arrive_dist = arrive_dist
	_walking = true
	_walk_started_at_ms = Time.get_ticks_msec()
	_walk_diag_tick = 0
	# Refresh the floor-only player-identity guard: anchor to whichever player
	# is current at walk-start so the next tick doesn't trigger a stale-cell
	# bailout against the player we're DELIBERATELY walking.
	var pl := get_tree().get_first_node_in_group("player")
	_last_walk_player_id = pl.get_instance_id() if pl != null else 0
	# Note: _walk_on_watchdog is set by the caller BEFORE this (for exit-trigger
	# walks) or left as Callable() so the watchdog falls back to plain teleport.


func _stop_field_walk() -> void:
	_walking = false
	# Move the floor-only pin to wherever the player landed so the post-walk
	# pin doesn't yank them back to a stale anchor.
	if _floor_only:
		var pl := get_tree().get_first_node_in_group("player")
		if pl != null:
			_floor_only_pin_pos = pl.global_position
	for action in ["move_forward", "move_backward", "move_left", "move_right"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


var _last_walk_tick_ms: int = 0
var _last_walk_player_id: int = 0
func _tick_field_walk() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		# Likely between cells — drop the held inputs so the next player spawn
		# doesn't see stale state.
		_stop_field_walk()
		return

	# Floor-only mode: teleport-along-path with a downward floor raycast at
	# each step. Skips the player's normal input/physics path so wall geometry
	# and decoration colliders can't block us — purely tests "is there floor?"
	if _floor_only:
		# If the active player node changed since the last tick, a cell load
		# just happened: the walk_target is stale (it was anchored to the old
		# cell). Stop the walk; the autopilot's cell-load handler will start a
		# fresh walk against the new cell's geometry.
		if _last_walk_player_id != 0 and player.get_instance_id() != _last_walk_player_id:
			_stop_field_walk()
			_last_walk_player_id = 0
			return
		_last_walk_player_id = player.get_instance_id()
		var now_ms := Time.get_ticks_msec()
		var dt := now_ms - _last_walk_tick_ms if _last_walk_tick_ms > 0 else 16
		_last_walk_tick_ms = now_ms
		if not _floor_only_walk_step(player, _walk_target, dt):
			print("[sanity]  walk @ (%.1f,%.1f,%.1f) → (%.1f,%.1f,%.1f) NO FLOOR" % [
				player.global_position.x, player.global_position.y, player.global_position.z,
				_walk_target.x, _walk_target.y, _walk_target.z])
			_stop_field_walk()
			_fail_walk_stuck(player.global_position, 0.0)
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

	# Watchdog: stuck walks are a HARD FAIL — the point of the autopilot is to
	# verify a real player could traverse this. If the walker can't reach the
	# target, the stage either needs an authored waypoint graph or a real
	# walkability fix in the level. Surface the offending cell + stage so it
	# can be opened in the waypoint editor.
	if Time.get_ticks_msec() - _walk_started_at_ms > WALK_WATCHDOG_MS:
		# Surface the exact stuck geometry: player position, walk target,
		# normalized direction, and the floor-sample results at the three
		# can_move_to check points. Makes the editor fix obvious — "ah,
		# the center+left rays land in the void at (0.21, 8.8); add a
		# waypoint that routes around the (0.17,8.5)-(0.25,9.1) hole."
		var dir := (_walk_target - pos)
		dir.y = 0.0
		if dir.length() > 0.0:
			dir = dir.normalized()
		print("[sanity] stuck-walk diagnostic: player=(%.3f, %.3f, %.3f) target=(%.3f, %.3f, %.3f) dir=(%.3f, %.3f, %.3f) dist=%.2f" % [
			pos.x, pos.y, pos.z, _walk_target.x, _walk_target.y, _walk_target.z, dir.x, dir.y, dir.z, dist])
		_log_floor_samples(pos, dir)
		_stop_field_walk()
		_fail_walk_stuck(pos, dist)
		return

	if dist < _walk_arrive_dist:
		var cb := _walk_on_arrive
		_stop_field_walk()
		if cb.is_valid():
			cb.call()
		return

	# Floor-only mode already moved the player above — skip the camera/input
	# driver below (it would just press keys at no-op physics).
	if _floor_only:
		return

	# Snap the orbit camera so its forward vector points at the leg target.
	# Without this, the autopilot has to drive diagonal inputs (forward+right)
	# in camera-relative coordinates, and the player drifts ~20% off-axis per
	# meter because input-to-world mapping isn't exact for diagonals. With the
	# camera aligned, we only ever press "forward" and the player walks the
	# exact straight line toward the target.
	_align_camera_to_target(_walk_target)

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


## Rotate the third-person orbit camera so its forward vector points from the
## player's current position toward `target` (XZ only). Keeps the autopilot's
## "press forward" mapping equal to "walk toward target" — otherwise diagonal
## inputs drift in camera-relative coords. Looks up the OrbitCamera by name
## (scenes/3d/camera/orbit_camera.tscn instantiates as "OrbitCamera").
func _align_camera_to_target(target: Vector3) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	# Walk up the scene tree from the active camera to find the OrbitCamera root
	# (which owns `camera_rotation`). The Camera3D itself is a child whose
	# transform is overwritten by the orbit script every frame, so setting
	# its rotation directly does nothing.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var orbit: Node = cam
	while orbit != null and not ("camera_rotation" in orbit):
		orbit = orbit.get_parent()
	if orbit == null:
		return
	var dx: float = target.x - player.global_position.x
	var dz: float = target.z - player.global_position.z
	if dx * dx + dz * dz < 0.01:
		return
	# OrbitCamera positions camera at target + (sin(rot)*horiz, _, cos(rot)*horiz)
	# and looks back at target. So camera forward = (-sin(rot), 0, -cos(rot)).
	# We want camera forward = (dx, 0, dz).normalized() →
	#   sin(rot) = -dx, cos(rot) = -dz → rot = atan2(dx, dz) + PI.
	orbit.set("camera_rotation", atan2(dx, dz) + PI)


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
## How far INTO the cell to push each spawn-derived waypoint, away from the
## gate the spawn sits next to. The raw spawn_pos is in the tight corridor
## right at the gate edge; landing there with arrive_dist=1.5m means the
## player overshoots and runs into gate collision. Pushing 4m toward center
## gives breathing room.
const SAFE_SPAWN_PUSH := 4.0

## Conservative "can the character walk this straight line?" check. Two
## independent failure modes:
##   1. Floor edge — the cells are L-shaped FLOORS in open space (each has its
##      own *-floor.glb mesh); walking off the floor edge stops the player.
##      Detected by sampling along the line and casting DOWN at each sample.
##   2. Wall — there's a vertical wall mesh standing on the floor in the path.
##      Detected by casting horizontally at chest height (Y+1.0) from end to
##      end. The player + enemies are excluded so we only hit static geometry.
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
	# Wall check — horizontal rays at multiple heights. A single ray can miss
	# walls whose collider is thin in Y, or whose lower edge is above the ray.
	# The player capsule extends ~Y=0..2, so checking 0.3 / 1.0 / 1.7 covers
	# the player's full vertical span.
	for eye_y in [0.3, 1.0, 1.7]:
		var wall_from := Vector3(from.x, from.y + eye_y, from.z)
		var wall_to := Vector3(to.x, to.y + eye_y, to.z)
		var wq := PhysicsRayQueryParameters3D.create(wall_from, wall_to)
		wq.exclude = excludes
		if not space.intersect_ray(wq).is_empty():
			return false  # Wall hit at this height.
	# Floor edge check — sample the line and cast DOWN at each sample.
	var dist: float = from.distance_to(to)
	var samples: int = max(int(ceil(dist / FLOOR_SAMPLE_STEP)), 2)
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


## Build the candidate waypoint list for the current cell. Two kinds of
## points get added:
##   • the cell center (Map node's origin in world space), useful as the
##     L-bend pivot,
##   • a "safe" version of each portal_data[dir]["spawn_pos"], pushed
##     SAFE_SPAWN_PUSH metres toward center. Without the push, the spawn
##     waypoint sits in the tight corridor right at the gate; walks that
##     end on it overshoot 1-2m past arrive_dist and the player wedges into
##     the gate. With the push, the waypoint is in open cell space and the
##     LAST leg (waypoint → trigger) crosses the gate from a clean angle.
func _collect_cell_waypoints(field: Node, portal_data: Dictionary) -> Array:
	var pts: Array = []
	var center := Vector3.ZERO
	var has_center := false
	var map_root := field.get_node_or_null("Map")
	if map_root != null and map_root is Node3D:
		center = (map_root as Node3D).to_global(Vector3.ZERO)
		has_center = true
		pts.append(center)
	for k in portal_data.keys():
		if String(k) == "default":
			continue
		var pd: Dictionary = portal_data[k]
		var sp = pd.get("spawn_pos", null)
		if sp == null or not (sp is Vector3):
			continue
		var safe: Vector3 = sp
		if has_center:
			var to_center: Vector3 = center - sp
			to_center.y = 0
			var d: float = to_center.length()
			if d > 0.1:
				# Push toward center, but never PAST center.
				safe = sp + to_center.normalized() * min(SAFE_SPAWN_PUSH, d - 0.5)
		pts.append(safe)
	return pts


## BFS through candidate waypoints to find a clear path from the player's
## current position to `target`. Returns Array[Vector3] ending in `target`;
## empty Array on hard miss. A path of size 1 means straight-line is clear.
##
## Priority order:
##   1. Authored waypoints + edges from unified-stage-configs.json for the
##      current cell's stage_id, IF authored. The user hand-places these in
##      the waypoint editor with knowledge of geometry the autopilot's
##      raycasts can't reliably read; their detours always win.
##   2. Direct line of sight (cheap raycast check at floor + chest height).
##   3. BFS over computed safe-spawn waypoints + center (fallback when
##      nothing is authored for this stage).
func _find_walk_path(field: Node, portal_data: Dictionary, target: Vector3) -> Array:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return [target]
	var start: Vector3 = player.global_position
	# (1) Authored waypoints for this stage win — the user knows the geometry.
	var stage_id := ""
	var cur = field.get("_current_cell") if field else null
	if typeof(cur) == TYPE_DICTIONARY:
		stage_id = str(cur.get("stage_id", ""))
	if stage_id != "":
		var authored: Array = _path_via_authored_waypoints(stage_id, start, target)
		if not authored.is_empty():
			return authored
	# (2) Direct line of sight as a fallback when nothing is authored.
	# In floor-only mode the LOS check's 1.5m floor-sample stride can step
	# right over sub-meter holes (e.g. paru's T-junction voids), and the
	# teleport walk then fails on the first cast inside the hole. Force the
	# BFS path through known waypoints so the via-points keep the route off
	# the bad geometry.
	if not _floor_only and _raycast_walkable(start, target):
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
		var cur_idx: int = queue.pop_front()
		if _raycast_walkable(candidates[cur_idx], target):
			found = cur_idx
			break
		for j in range(n):
			if visited.has(j):
				continue
			if _raycast_walkable(candidates[cur_idx], candidates[j]):
				visited[j] = true
				parent[j] = cur_idx
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


# ── Authored waypoints (from the waypoint editor) ──────────────
## Stages can ship their own waypoint graph via the waypoint editor; the
## graph is persisted into data/stage_configs/unified-stage-configs.json
## under the stage's entry as `waypoints[]` (each `{id, position, kind?,
## label?}`) and `waypointEdges[]` (each `[id, id]`). When present, the
## autopilot prefers this hand-authored graph over its computed safe-spawn
## fallback — the editor lets a human capture corridor corners and gate
## offsets that geometry-sniffing can't reliably find.
const STAGE_CONFIGS_PATH := "res://data/stage_configs/unified-stage-configs.json"
## Loaded lazily on first cell entry; one-time cost amortised across the run.
var _stage_configs_cache: Dictionary = {}
var _stage_configs_loaded: bool = false


func _stage_configs() -> Dictionary:
	if _stage_configs_loaded:
		return _stage_configs_cache
	_stage_configs_loaded = true
	var f := FileAccess.open(STAGE_CONFIGS_PATH, FileAccess.READ)
	if f == null:
		print("[sanity] WARN: couldn't open %s" % STAGE_CONFIGS_PATH)
		return _stage_configs_cache
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY:
		_stage_configs_cache = data
	return _stage_configs_cache


## Returns a multi-leg path through the authored waypoint graph for `stage_id`,
## or [] if no authored graph exists (or no path can be found). The path ends
## in `target` so the caller doesn't need to add it.
func _path_via_authored_waypoints(stage_id: String, start: Vector3, target: Vector3) -> Array:
	var configs := _stage_configs()
	var stage = configs.get(stage_id, null)
	if typeof(stage) != TYPE_DICTIONARY:
		return []
	var waypoints = stage.get("waypoints", [])
	var edges = stage.get("waypointEdges", [])
	if typeof(waypoints) != TYPE_ARRAY or waypoints.is_empty():
		return []
	# Waypoint positions in the stage config are STAGE-LOCAL — they're shared
	# across every cell that loads this stage and don't know about the cell's
	# rotation. The current cell's Map root applies that rotation, so use its
	# global transform to convert each stage-local position to world. Without
	# this, cells with non-zero rotation (e.g. paru pact A 3,4 rotation 180)
	# would compare stage-local waypoints against the world-space player
	# position and never find a "nearest" match.
	var map_root: Node3D = null
	var field := get_tree().current_scene
	if field != null:
		var m := field.get_node_or_null("Map")
		if m != null and m is Node3D:
			map_root = m as Node3D
	# Build id → position map (converted to world).
	var pos_by_id := {}
	for wp in waypoints:
		if typeof(wp) != TYPE_DICTIONARY:
			continue
		var id := str(wp.get("id", ""))
		var pos_arr = wp.get("position", null)
		if id == "" or typeof(pos_arr) != TYPE_ARRAY or pos_arr.size() < 3:
			continue
		var local_pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		pos_by_id[id] = (map_root.to_global(local_pos)) if map_root != null else local_pos
	if pos_by_id.is_empty():
		return []
	# Build undirected adjacency from edge pairs.
	var adj := {}
	if typeof(edges) == TYPE_ARRAY:
		for edge in edges:
			if typeof(edge) != TYPE_ARRAY or edge.size() < 2:
				continue
			var a := str(edge[0])
			var b := str(edge[1])
			if not pos_by_id.has(a) or not pos_by_id.has(b):
				continue
			if not adj.has(a):
				adj[a] = []
			if not adj.has(b):
				adj[b] = []
			adj[a].append(b)
			adj[b].append(a)
	# Nearest waypoint to start (entry node) and to target (exit node), XZ only.
	var nearest_start := ""
	var nearest_target := ""
	var best_start_d := INF
	var best_target_d := INF
	for id in pos_by_id:
		var p: Vector3 = pos_by_id[id]
		var ds := Vector2(p.x - start.x, p.z - start.z).length()
		var dt := Vector2(p.x - target.x, p.z - target.z).length()
		if ds < best_start_d:
			best_start_d = ds
			nearest_start = id
		if dt < best_target_d:
			best_target_d = dt
			nearest_target = id
	if nearest_start == "" or nearest_target == "":
		return []
	# BFS over the authored adjacency, but expand each node's neighbours in
	# order of distance-to-target. This breaks ties when multiple equal-hop
	# paths exist (e.g. two corner waypoints between a spawn and the target),
	# picking the corner the user intended — the one closer to the
	# destination — instead of an arbitrary first-visited one.
	var target_pos: Vector3 = pos_by_id[nearest_target]
	var visited := {}
	var parent := {}
	visited[nearest_start] = true
	parent[nearest_start] = ""
	var queue: Array = [nearest_start]
	var found: bool = (nearest_start == nearest_target)
	while not found and not queue.is_empty():
		var cur: String = queue.pop_front()
		var neighbours: Array = adj.get(cur, []).duplicate()
		neighbours.sort_custom(func(a, b):
			return pos_by_id[a].distance_squared_to(target_pos) < pos_by_id[b].distance_squared_to(target_pos))
		for nb in neighbours:
			if visited.has(nb):
				continue
			visited[nb] = true
			parent[nb] = cur
			if nb == nearest_target:
				found = true
				break
			queue.append(nb)
	if not found:
		return []
	# Reconstruct chain start→…→target waypoints, then append the final target.
	var chain: Array = []
	var n: String = nearest_target
	while n != "":
		chain.append(pos_by_id[n])
		n = str(parent.get(n, ""))
	chain.reverse()
	chain.append(target)
	# Drop the last waypoint if it's "past" the target — that happens when
	# the nearest authored waypoint to the target sits on the far side of an
	# obstacle (e.g. a locked KeyGate where spawn_south is just past the
	# gate the player is trying to walk up to). Detection: the vector from
	# the previous waypoint to the last waypoint and the vector from the
	# last waypoint to the target point in opposite directions (dot < 0).
	if chain.size() >= 3:
		var prev: Vector3 = chain[chain.size() - 3]
		var last_wp: Vector3 = chain[chain.size() - 2]
		var v_in: Vector3 = (last_wp - prev)
		var v_out: Vector3 = (target - last_wp)
		v_in.y = 0
		v_out.y = 0
		if v_in.length_squared() > 0.01 and v_out.length_squared() > 0.01:
			if v_in.normalized().dot(v_out.normalized()) < -0.2:
				chain.remove_at(chain.size() - 2)
	return chain

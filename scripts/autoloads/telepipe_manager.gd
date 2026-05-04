## TelepipeManager — tracks the player's currently-active telepipe.
##
## At most ONE telepipe ever exists. Dropping a new one cancels the old.
## State is in-memory only: app close, title return, quest accept/complete,
## or any explicit cancel reason wipes it. Per spec there are no special
## cases for cutscenes or scripted beats — those can be added later.
##
## Lifecycle (from spec):
##   1. Player uses telepipe consumable in field
##      → place(): cancels any prior, records area/section/cell/world_pos.
##      → A Telepipe element is spawned at player position in the field.
##      → A Telepipe element is also spawned at (0,0) in city_counter on
##        first arrival there (and on every subsequent visit).
##
##   2. Player walks into the field-side telepipe and presses E
##      → travel to city_counter (suspend session, preserve section state).
##      → Telepipe stays active. Coming back via teleporter still works.
##
##   3. Player walks into the city-side telepipe and presses E
##      → consume_return() returns the saved location, then clears state.
##      → Field scene loads at the saved world_pos. Telepipe is gone in
##        both city and field after this — one-shot return.
##
##   4. Player uses city's main teleporter to pick the same area:
##      → resume_session() restores the suspended session, telepipe stays
##        active, field _ready re-spawns the telepipe at saved world_pos.
##      → Player can use city telepipe to bounce back, OR walk to where
##        they used the telepipe and step into it again.
##
##   5. Player uses city's main teleporter to pick a DIFFERENT area:
##      → cancel("area_changed") — the suspended session is being replaced
##        by a fresh expedition, telepipe is no longer reachable.
##
## Cancellation reasons (for telemetry / debugging):
##   "replaced"        — new telepipe placed, old one wiped
##   "returned"        — player walked through city-side, completed round trip
##   "title_return"    — went back to title screen
##   "quest_accepted"  — picked up a new quest
##   "quest_ended"     — quest completed or aborted
##   "area_changed"    — picked a different field area from the city teleporter

extends Node

signal placed(state)        # emitted on successful place()
signal canceled(reason)     # emitted on cancel(), consume_return(), or replace

# Active telepipe state. Empty dict means inactive.
# Populated by place(); cleared by cancel() / consume_return().
var _state: Dictionary = {}

# ── State accessors ────────────────────────────────────────────────────────

func is_active() -> bool:
	return not _state.is_empty()


func get_state() -> Dictionary:
	# Returns a copy so callers can't mutate internal state.
	return _state.duplicate(true)


# ── Lifecycle ─────────────────────────────────────────────────────────────

## Drop a telepipe at the player's current location in the field.
##   area_id      — e.g. "gurhacia" — used to match the city teleporter
##   section_idx  — current section within the field session
##   cell_pos     — current cell key (e.g. "0,0") so we can spawn a Telepipe
##                  element on field re-entry into the same room
##   world_pos    — exact Vector3 in the cell where the player was standing
##   field_scene  — scene path to load when returning from city via telepipe
func place(area_id: String, section_idx: int, cell_pos: String,
		world_pos: Vector3, field_scene: String) -> void:
	if not _state.is_empty():
		# Spec rule: only one telepipe ever exists.
		canceled.emit("replaced")
	_state = {
		"area_id": area_id,
		"section_idx": section_idx,
		"cell_pos": cell_pos,
		"world_pos": world_pos,
		"field_scene": field_scene,
	}
	print("[TelepipeManager] placed area=%s section=%d cell=%s pos=%s" %
		[area_id, section_idx, cell_pos, world_pos])
	placed.emit(_state.duplicate(true))


## Wipe the active telepipe. No-op if already inactive.
## `reason` is an opaque string used for logging / signal payload.
func cancel(reason: String) -> void:
	if _state.is_empty():
		return
	print("[TelepipeManager] canceled (%s)" % reason)
	_state.clear()
	canceled.emit(reason)


## City-side telepipe interaction: returns the saved state and wipes it.
## Caller is responsible for using the returned dict to perform the actual
## scene transition + session resume. If no telepipe is active, returns {}.
func consume_return() -> Dictionary:
	if _state.is_empty():
		return {}
	var snapshot := _state.duplicate(true)
	print("[TelepipeManager] consumed return to area=%s section=%d cell=%s" %
		[snapshot.get("area_id", "?"),
		 snapshot.get("section_idx", -1),
		 snapshot.get("cell_pos", "?")])
	_state.clear()
	canceled.emit("returned")
	return snapshot


# ── Convenience predicates for scene controllers ──────────────────────────

## True if the active telepipe was dropped in the given area + section.
## Used by the field controller to decide whether to re-spawn the Telepipe
## element at the saved world_pos when the room loads.
func matches_field(area_id: String, section_idx: int, cell_pos: String) -> bool:
	if _state.is_empty():
		return false
	return _state.get("area_id", "") == area_id \
		and int(_state.get("section_idx", -1)) == section_idx \
		and str(_state.get("cell_pos", "")) == cell_pos

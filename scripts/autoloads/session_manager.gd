extends Node
## SessionManager — manages field/mission sessions, stage/wave progression.
## Ported from psz-sketch/src/api/location.ts

signal session_started(data: Dictionary)
signal stage_advanced(stage: int)
signal wave_advanced(wave: int)
signal session_ended()
signal quest_item_collected(item_id: String, new_count: int, target: int)
signal quest_completed()

const MAX_STAGES := 3
const MAX_WAVES := 3

## Warp pad area_id → quest/field area_id mapping
const WARP_TO_AREA := {
	"gurhacia-valley": "gurhacia",
	"ozette-wetland": "ozette",
	"rioh-snowfield": "rioh",
	"makara-ruins": "makara",
	"oblivion-city-paru": "paru",
	"arca-plant": "arca",
	"dark-shrine": "dark",
	"eternal-tower": "tower",
}

## Stage prefix → area_id (reverse of GridGenerator.AREA_CONFIG prefix)
const STAGE_PREFIX_TO_AREA := {
	"s01": "gurhacia",
	"s02": "ozette",
	"s03": "rioh",
	"s04": "makara",
	"s05": "paru",
	"s06": "arca",
	"s07": "dark",
	"s08": "tower",
}

var _session: Dictionary = {}
var _suspended_session: Dictionary = {}
var _location: String = "city"
var _accepted_quest: Dictionary = {}   # {quest_id, area_id, difficulty, name}
var _completed_quest: Dictionary = {}  # {quest_id, area_id, name} — awaiting guild report
var _quest_objectives: Array = []      # [{item_id, label, target}] — loaded from quest JSON
var _quest_item_counts: Dictionary = {} # {item_id: count} — runtime collection state
var _quest_accepted_shown: bool = false # true after "Quest accepted" log shown once
var _action_log: Array = []            # [{text, color}] — persists across room transitions
var _section_cell_states: Dictionary = {} # section_idx → {cell_states, keys_collected, gates_opened, visited_cells}
var _activated_links: Dictionary = {} # link_id → true (cross-room fence-switch links, persists across cell transitions)


func is_link_activated(link_id: String) -> bool:
	return _activated_links.has(link_id)


func set_link_activated(link_id: String) -> void:
	_activated_links[link_id] = true


## Enter a field area
func enter_field(area_id: String, difficulty: String) -> Dictionary:
	# A fresh expedition starts here, so any in-flight telepipe is no longer
	# reachable. (Same-area "go back to where I dropped my telepipe" is
	# routed through resume_session() in warp_teleporter._warp_to_field —
	# that path skips enter_field entirely.)
	TelepipeManager.cancel("enter_field")
	clear_section_states()
	_session = {
		"type": "field",
		"area_id": area_id,
		"difficulty": difficulty,
		"stage": 1,
		"wave": 1,
		"total_exp": 0,
		"total_meseta": 0,
		"items_collected": [],
	}
	_location = "field"
	session_started.emit(_session)
	return _session


## Enter a quest (hand-authored fixed layout)
func enter_quest(quest_id: String, difficulty: String) -> Dictionary:
	TelepipeManager.cancel("enter_quest")
	clear_section_states()
	var quest := QuestLoader.load_quest(quest_id)
	if quest.is_empty():
		return {}
	_session = {
		"type": "quest",
		"quest_id": quest_id,
		"area_id": quest.get("area_id", "gurhacia"),
		"difficulty": difficulty,
		"stage": 1,
		"wave": 1,
		"total_exp": 0,
		"total_meseta": 0,
		"items_collected": [],
		"companions": quest.get("companions", []),
		"weather": quest.get("weather", ""),
	}
	set_field_sections(quest["sections"])
	# Load quest objectives if present
	_quest_objectives = quest.get("objectives", [])
	_quest_item_counts.clear()
	_quest_accepted_shown = false
	for obj in _quest_objectives:
		_quest_item_counts[str(obj.get("item_id", ""))] = 0
	_location = "field"
	session_started.emit(_session)
	return _session


## Convert display area name to spawner area_id
## Advance to next wave. Returns true if there's a next wave, false if stage complete.
func next_wave() -> bool:
	if _session.is_empty():
		return false
	var wave: int = int(_session.get("wave", 1))
	if wave < MAX_WAVES:
		_session["wave"] = wave + 1
		wave_advanced.emit(int(_session["wave"]))
		return true
	return false


## Advance to next stage. Returns true if there's a next stage, false if session complete.
func next_stage() -> bool:
	if _session.is_empty():
		return false
	var stage: int = int(_session.get("stage", 1))
	if stage < MAX_STAGES:
		_session["stage"] = stage + 1
		_session["wave"] = 1
		stage_advanced.emit(int(_session["stage"]))
		return true
	return false


## Add rewards to running session totals
func add_rewards(exp_amount: int, meseta: int) -> void:
	_session["total_exp"] = int(_session.get("total_exp", 0)) + exp_amount
	_session["total_meseta"] = int(_session.get("total_meseta", 0)) + meseta


## Return to city and end session
func return_to_city() -> Dictionary:
	# Full session end → no longer reachable via the in-flight telepipe.
	# Covers StartWarp, boss-clear, complete_quest, and any explicit "I'm
	# done with this expedition" path. Telepipe-style suspends use
	# suspend_session() instead, which intentionally leaves the manager
	# state alone.
	TelepipeManager.cancel("return_to_city")
	var summary: Dictionary = _session.duplicate()
	_session.clear()
	_quest_objectives.clear()
	_quest_item_counts.clear()
	_action_log.clear()
	clear_section_states()
	_location = "city"
	session_ended.emit()
	return summary


## Get current session data
func get_session() -> Dictionary:
	return _session


## Get companion IDs for the current quest
func get_companions() -> Array:
	return _session.get("companions", [])


## Get current location
func get_location() -> String:
	return _location


## Force-set the current location. Called by scene controllers on _ready
## because going to title and back doesn't reset it otherwise — a player who
## went field → title → Dairon would leave _location = "field" and the HUD
## would think they're still in combat.
func set_location(loc: String) -> void:
	_location = loc


## Get area_id for the current section (supports multi-area quests).
## Derives area from the first cell's stage prefix; falls back to session area_id.
func get_current_area_id() -> String:
	var sections: Array = get_field_sections()
	var section_idx: int = get_current_section()
	if section_idx < sections.size():
		var cells: Array = sections[section_idx].get("cells", [])
		if cells.size() > 0:
			var stage_id: String = str(cells[0].get("stage_id", ""))
			if stage_id.length() >= 3:
				var prefix: String = stage_id.substr(0, 3)
				if STAGE_PREFIX_TO_AREA.has(prefix):
					return STAGE_PREFIX_TO_AREA[prefix]
	return str(_session.get("area_id", "gurhacia"))


## Suspend current session (telepipe — return to city but keep session)
func suspend_session() -> Dictionary:
	_suspended_session = _session.duplicate(true)
	_suspended_session["_quest_objectives"] = _quest_objectives.duplicate(true)
	_suspended_session["_quest_item_counts"] = _quest_item_counts.duplicate(true)
	var summary: Dictionary = _session.duplicate()
	_session.clear()
	_location = "city"
	session_ended.emit()
	return summary


## Resume a suspended session
func resume_session() -> Dictionary:
	if _suspended_session.is_empty():
		return {}
	_session = _suspended_session.duplicate(true)
	_quest_objectives = _session.get("_quest_objectives", [])
	_quest_item_counts = _session.get("_quest_item_counts", {})
	_session.erase("_quest_objectives")
	_session.erase("_quest_item_counts")
	_suspended_session.clear()
	_location = "field"
	session_started.emit(_session)
	return _session


## Check if there is a suspended session to resume
func has_suspended_session() -> bool:
	return not _suspended_session.is_empty()


## True only when the suspended session is a QUEST run. A suspended
## free-field session must NOT lock the guild counter into cancel-only
## (#239 bug 2) — the player can accept a quest, which abandons the
## field run (see accept_quest).
func has_suspended_quest() -> bool:
	return _suspended_session.get("type", "") == "quest"


## Check if a session is active
func has_active_session() -> bool:
	return not _session.is_empty()


## Store field sections (a→e→b→z progression)
func set_field_sections(sections: Array) -> void:
	_session["sections"] = sections
	_session["current_section"] = 0


## Get field sections
func get_field_sections() -> Array:
	return _session.get("sections", [])


## Returns the sections array of the SUSPENDED session (or {} if none).
## Used by the warp-teleporter section picker which renders while
## _session is empty (the player is back in city after a telepipe /
## StartWarp suspend). Don't confuse with get_field_sections() above
## which reads from the active _session.
func get_suspended_field_sections() -> Array:
	return _suspended_session.get("sections", [])


## area_id of the suspended session (or "" if none).
func get_suspended_area_id() -> String:
	return str(_suspended_session.get("area_id", ""))


## Get current section index
func get_current_section() -> int:
	return int(_session.get("current_section", 0))


## Set current section index (used by debug warp points)
func set_current_section(idx: int) -> void:
	_session["current_section"] = idx


## Advance to next section. Returns true if there is a next section.
func advance_section() -> bool:
	var idx: int = get_current_section()
	var sections: Array = get_field_sections()
	if idx + 1 < sections.size():
		_session["current_section"] = idx + 1
		return true
	return false


# ── Section Cell State Persistence ──────────────────────────────

func save_section_state(section_idx: int, cell_states: Dictionary, keys_collected: Dictionary, gates_opened: Dictionary, visited_cells: Dictionary) -> void:
	_section_cell_states[section_idx] = {
		"cell_states": cell_states.duplicate(true),
		"keys_collected": keys_collected.duplicate(true),
		"gates_opened": gates_opened.duplicate(true),
		"visited_cells": visited_cells.duplicate(true),
	}

func get_section_state(section_idx: int) -> Dictionary:
	return _section_cell_states.get(section_idx, {})


## Section indices the player has entered during the current/suspended
## expedition, in ascending order. Used by the warp-teleporter section
## picker so the player can backtrack to any sub-area they've reached.
##
## Sections appear here once their cell state has been flushed via
## `save_section_state()` — happens on cell transitions, on section
## advance (`_on_end_reached`), and on the suspend paths (telepipe drop,
## StartWarp). The current section is always included since suspend
## always saves before clearing _session.
##
## Resets when `_section_cell_states` resets — i.e. on `enter_field`,
## `enter_quest`, `return_to_city`, and `reset_all_state`.
func get_visited_section_indices() -> Array:
	var keys: Array = _section_cell_states.keys()
	keys.sort()
	return keys

func clear_section_states() -> void:
	_section_cell_states.clear()
	_activated_links.clear()


## Wipe all in-memory session and quest state — call when returning to title
## screen so a player who completed a quest in field but hadn't reported it
## yet doesn't have the guild counter still showing the report option after
## the title round-trip. Reported as a bug by Rozalin.
func reset_all_state() -> void:
	# Title-screen path lands here. Telepipes are session-only by spec
	# (app close, title return, quest accept/end all wipe), so cancel.
	TelepipeManager.cancel("reset_all_state")
	_session.clear()
	_suspended_session.clear()
	_accepted_quest.clear()
	_completed_quest.clear()
	_quest_objectives.clear()
	_quest_item_counts.clear()
	_quest_accepted_shown = false
	_section_cell_states.clear()
	_activated_links.clear()
	# Reset HUD/log state too — otherwise the field action log carries
	# across into the next session and the location flag stays "field"
	# (per Copilot review on PR #194).
	_location = "city"
	_action_log.clear()
	print("[SessionManager] reset_all_state — quest + session + HUD state wiped")


# ── Quest Lifecycle ─────────────────────────────────────────────

## Accept a quest at the guild counter (does NOT start the session yet).
func accept_quest(quest_id: String, difficulty: String) -> Dictionary:
	var quest := QuestLoader.load_quest(quest_id)
	if quest.is_empty():
		return {}
	# Per spec: accepting a quest cancels any active telepipe — the player
	# is committing to a new expedition, the old field run is over. A
	# suspended free-field session is abandoned with it (#239 bug 2);
	# without this it lingers and re-locks the guild counter forever.
	TelepipeManager.cancel("accept_quest")
	if _suspended_session.get("type", "") == "field":
		_suspended_session.clear()
	_accepted_quest = {
		"quest_id": quest_id,
		"area_id": quest.get("area_id", "gurhacia"),
		"difficulty": difficulty,
		"name": quest.get("name", quest_id),
	}
	return _accepted_quest


func has_accepted_quest() -> bool:
	return not _accepted_quest.is_empty()


func get_accepted_quest() -> Dictionary:
	return _accepted_quest


func get_accepted_quest_area() -> String:
	return str(_accepted_quest.get("area_id", ""))


func cancel_accepted_quest() -> void:
	_accepted_quest.clear()
	# Also clear any suspended session from this quest
	if not _suspended_session.is_empty() and _suspended_session.get("type") == "quest":
		_suspended_session.clear()
	# Per spec: cancelling a quest closes any active telepipe (it was
	# anchored to the suspended quest session we just wiped).
	TelepipeManager.cancel("cancel_accepted_quest")


## Start the accepted quest — calls enter_quest() and clears acceptance.
func start_accepted_quest() -> Dictionary:
	if _accepted_quest.is_empty():
		return {}
	var quest_id: String = str(_accepted_quest["quest_id"])
	var difficulty: String = str(_accepted_quest["difficulty"])
	_accepted_quest.clear()
	return enter_quest(quest_id, difficulty)


## Mark quest objectives as fulfilled — stores completion data but keeps session active.
## The player can keep exploring; they return to city on their own terms.
func mark_quest_complete() -> void:
	if _session.is_empty() or _session.get("type") != "quest":
		return
	if not _completed_quest.is_empty():
		return  # Already marked
	_completed_quest = {
		"quest_id": str(_session.get("quest_id", "")),
		"area_id": str(_session.get("area_id", "")),
		"name": str(_session.get("quest_id", "")),
		"difficulty": str(_session.get("difficulty", "normal")),
		"total_exp": int(_session.get("total_exp", 0)),
		"total_meseta": int(_session.get("total_meseta", 0)),
		"items_collected": _session.get("items_collected", []),
		# Snapshot the objective-item counts — the live dict is cleared on
		# return_to_city, but completion-scaled rewards (#190) need them
		# at guild report time.
		"quest_item_counts": _quest_item_counts.duplicate(true),
	}
	quest_completed.emit()


## Mark quest as complete and return to city immediately.
func complete_quest() -> void:
	mark_quest_complete()
	return_to_city()


func has_completed_quest() -> bool:
	return not _completed_quest.is_empty()


func get_completed_quest() -> Dictionary:
	return _completed_quest


## Report quest completion at guild — grants the quest's per-difficulty
## rewards, returns completion data (with "rewards_granted"), clears state.
func report_quest() -> Dictionary:
	var data: Dictionary = _completed_quest.duplicate()
	_completed_quest.clear()
	if data.is_empty():
		return data
	data["rewards_granted"] = _grant_quest_rewards(
		str(data.get("quest_id", "")), str(data.get("difficulty", "normal")),
		data.get("quest_item_counts", {}))
	return data


## Grant the rewards a quest defines for the given difficulty (spec:
## /states/story-progression — report MUST grant rewards), plus the
## completion-scaled tier when the quest defines one (#190: reward
## quality scales with optional objective items collected). Returns what
## was actually granted: {meseta: int, items: [{id, quantity}]}, or {}
## when the quest defines nothing for this difficulty.
func _grant_quest_rewards(quest_id: String, difficulty: String,
		quest_item_counts: Dictionary = {}) -> Dictionary:
	if quest_id.is_empty():
		return {}
	var quest: Dictionary = QuestLoader.load_quest(quest_id)
	var rewards: Dictionary = quest.get("rewards", {})
	var tier: Dictionary = rewards.get(difficulty, {})
	if tier.is_empty():
		return {}
	var granted: Dictionary = {}
	var meseta: int = int(tier.get("meseta", 0))
	if meseta > 0:
		GameState.add_meseta(meseta)
		granted["meseta"] = meseta
	var granted_items: Array = _grant_reward_items(tier.get("items", []))
	granted_items.append_array(_grant_reward_items(
		_pick_scaled_tier(rewards.get("scaled", {}), quest_item_counts).get("items", [])))
	if not granted_items.is_empty():
		granted["items"] = granted_items
	return granted


## Grant a rewards items list into the inventory; returns what landed.
## Items that don't fit are dropped with a warning rather than blocking
## the turn-in.
func _grant_reward_items(entries: Array) -> Array:
	var granted: Array = []
	for entry in entries:
		var item_id: String = str(entry.get("id", ""))
		var quantity: int = int(entry.get("quantity", 1))
		if item_id.is_empty() or quantity <= 0:
			continue
		if Inventory.add_item(item_id, quantity):
			granted.append({"id": item_id, "quantity": quantity})
		else:
			push_warning("Quest reward dropped (inventory full): %dx %s" % [quantity, item_id])
	return granted


## Pick the highest completion-scaled reward tier the player earned
## (#190). `scaled` is the quest's rewards.scaled block: tiers keyed by
## "min" total objective items collected. Returns {} when no tier (or no
## scaled block) applies.
func _pick_scaled_tier(scaled: Dictionary, quest_item_counts: Dictionary) -> Dictionary:
	if scaled.is_empty():
		return {}
	var collected := 0
	for v in quest_item_counts.values():
		collected += int(v)
	var best: Dictionary = {}
	for t in scaled.get("tiers", []):
		var tier_min: int = int(t.get("min", 0))
		if collected >= tier_min and tier_min >= int(best.get("min", -1)):
			best = t
	return best


# ── Quest Item Objectives ──────────────────────────────────────

## Collect a quest item — increment count, emit signal, auto-complete if all met.
func collect_quest_item(item_id: String) -> void:
	var count: int = int(_quest_item_counts.get(item_id, 0)) + 1
	_quest_item_counts[item_id] = count
	var target: int = _get_objective_target(item_id)
	quest_item_collected.emit(item_id, count, target)
	if are_objectives_complete():
		mark_quest_complete()


func get_quest_item_count(item_id: String) -> int:
	return int(_quest_item_counts.get(item_id, 0))


func get_quest_objectives() -> Array:
	return _quest_objectives


func are_objectives_complete() -> bool:
	for obj in _quest_objectives:
		var item_id: String = str(obj.get("item_id", ""))
		var target: int = int(obj.get("target", 1))
		if get_quest_item_count(item_id) < target:
			return false
	return true


func _get_objective_target(item_id: String) -> int:
	for obj in _quest_objectives:
		if str(obj.get("item_id", "")) == item_id:
			return int(obj.get("target", 1))
	return 0

class_name CellObjectSpawner
extends RefCounted

## Cell-object spawning + save/restore, extracted from ValleyFieldController.
##
## Holds a back-reference to the controller (`_c`) and delegates all
## controller-state access through it. Behavior is identical to the original
## inline implementation — this is a relocation refactor, not a logic change.

const BoxScript := preload("res://scripts/3d/elements/box.gd")
const FenceScript := preload("res://scripts/3d/elements/fence.gd")
const WallScript := preload("res://scripts/3d/elements/wall.gd")
const StepSwitchScript := preload("res://scripts/3d/elements/step_switch.gd")
const EnemySpawnScript := preload("res://scripts/3d/elements/enemy_spawn.gd")
const DropMesetaScript := preload("res://scripts/3d/elements/drop_meseta.gd")
const DropItemScript := preload("res://scripts/3d/elements/drop_item.gd")
const DropMaterialScript := preload("res://scripts/3d/elements/drop_material.gd")
const MessagePackScript := preload("res://scripts/3d/elements/message_pack.gd")
const StoryPropScript := preload("res://scripts/3d/elements/story_prop.gd")
const DialogTriggerScript := preload("res://scripts/3d/elements/dialog_trigger.gd")
const FieldNpcScript := preload("res://scripts/3d/elements/field_npc.gd")
const WarpPointScript := preload("res://scripts/3d/elements/warp_point.gd")
const QuestItemPickupScript := preload("res://scripts/3d/elements/quest_item_pickup.gd")

## Back-reference to the ValleyFieldController that owns this spawner.
var _c

## Temp state for enemy alive tracking during save (reset per save call)
var _room_enemy_alive_ids: Array = []
var _room_enemy_alive_ids_built: bool = false


func _init(controller) -> void:
	_c = controller


func _spawn_quest_item(pos: Vector3, item_id: String, item_label: String, dlg: Array = [], actions: Array = [], rem_dlg: Array = []) -> void:
	var qi := QuestItemPickupScript.new()
	qi.quest_item_id = item_id
	qi.quest_item_label = item_label
	qi.pickup_dialog = dlg
	qi.pickup_actions = actions
	qi.remaining_dialog = rem_dlg
	if _c._companion and is_instance_valid(_c._companion):
		qi.companion_node = _c._companion
	_c._map_root.add_child(qi)
	qi.position = pos
	_c._room_quest_items.append(qi)


## Spawn placed objects (boxes, enemies, fences, switches, messages) from quest cell data.
## If the cell was previously visited, restore saved state instead.
func _spawn_cell_objects() -> void:
	var cell_pos: String = str(_c._current_cell.get("pos", ""))
	var saved: Dictionary = _c._cell_states.get(cell_pos, {})
	var objects: Array = _c._current_cell.get("objects", [])
	print("[TelepipeDEBUG] _spawn_cell_objects cell_pos=%s, saved keys=%s, _cell_states all keys=%s" % [
		cell_pos, str(saved.keys()), str(_c._cell_states.keys())])

	# Reset room tracking arrays
	_c._room_messages.clear()
	_c._room_props.clear()
	_c._room_triggers.clear()
	_c._room_npcs.clear()
	_c._room_quest_items.clear()
	_c._room_walls.clear()
	_c._deferred_telepipe = {}
	_c._deferred_quest_complete_telepipe = {}
	_c._deferred_room_clear_items.clear()

	if objects.is_empty() and saved.is_empty():
		return

	if not saved.is_empty():
		_restore_cell_objects(saved)
	else:
		_spawn_fresh_cell_objects(objects)

	# Wire fence↔switch links
	_c._wire_fence_links()

	# Count living enemies for gate locking
	var alive_enemies: int = 0
	for e in _c._room_enemies:
		if not is_instance_valid(e):
			continue
		if e is EnemyBase:
			if e.is_alive:
				alive_enemies += 1
		elif e.get("element_state") != "dead":
			alive_enemies += 1

	if alive_enemies > 0:
		_c._lock_gates_for_enemies()
	elif _c._needs_telepipe:
		# No enemies on end cell — spawn telepipe immediately
		_c._needs_telepipe = false
		_c._spawn_telepipe(Vector3.ZERO)


## Spawn objects fresh (first visit to a cell).
func _spawn_fresh_cell_objects(objects: Array) -> void:
	print("[CellObjects] Spawning %d objects (fresh)" % objects.size())
	_c._wave_enemy_data.clear()
	_c._current_wave = 1
	_c._max_wave = 1

	for obj in objects:
		var obj_type: String = str(obj.get("type", ""))
		var pos_arr: Array = obj.get("position", [0, 0, 0])
		var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		var obj_rot: float = float(obj.get("rotation", 0))

		match obj_type:
			"box", "rare_box":
				_spawn_box(pos, obj_type == "rare_box")
			"enemy":
				var wave: int = int(obj.get("wave", 1))
				if wave < 1:
					wave = 1
				if wave > _c._max_wave:
					_c._max_wave = wave
				if wave == 1:
					var enemy_id: String = str(obj.get("enemy_id", "lizard"))
					_spawn_enemy(pos, enemy_id)
				else:
					if not _c._wave_enemy_data.has(wave):
						_c._wave_enemy_data[wave] = []
					_c._wave_enemy_data[wave].append(obj)
			"fence":
				var link_id: String = str(obj.get("link_id", ""))
				var f_scale_x: float = float(obj.get("scale_x", 1.0))
				_spawn_fence(pos, obj_rot, link_id, f_scale_x)
			"step_switch":
				var link_id: String = str(obj.get("link_id", ""))
				_spawn_switch(pos, link_id)
			"message":
				var text: String = str(obj.get("text", ""))
				var msg_locked: bool = obj.get("locked", false)
				var reaction: Array = obj.get("reaction_dialog", [])
				var init_state: String = "locked" if msg_locked else "available"
				var msg_objective_id: String = str(obj.get("objective_item_id", ""))
				_spawn_message(pos, text, init_state, reaction, msg_objective_id)
			"story_prop":
				var prop_path: String = str(obj.get("prop_path", ""))
				var prop_scale: float = float(obj.get("prop_scale", 1.0))
				var prop_no_collision: bool = bool(obj.get("no_collision", false))
				_spawn_story_prop(pos, prop_path, obj_rot, prop_scale, prop_no_collision)
			"dialog_trigger":
				var trigger_id: String = str(obj.get("trigger_id", ""))
				var dlg: Array = obj.get("dialog", [])
				var condition: String = str(obj.get("trigger_condition", "enter"))
				var act: Array = obj.get("actions", [])
				var tsize_arr: Array = obj.get("trigger_size", [])
				var tsize := Vector3.ZERO
				if tsize_arr.size() == 3:
					tsize = Vector3(float(tsize_arr[0]), float(tsize_arr[1]), float(tsize_arr[2]))
				_spawn_dialog_trigger(pos, trigger_id, dlg, "ready", condition, act, tsize)
			"npc":
				var npc_id: String = str(obj.get("npc_id", ""))
				var npc_name: String = str(obj.get("npc_name", ""))
				var dlg: Array = obj.get("dialog", [])
				var npc_anim: String = str(obj.get("animation", ""))
				_spawn_field_npc(pos, npc_id, npc_name, dlg, obj_rot, npc_anim)
			"telepipe":
				var spawn_cond: String = str(obj.get("spawn_condition", "immediate"))
				if spawn_cond == "room_clear":
					# Defer — store data for _check_room_clear
					_c._deferred_telepipe = { "position": pos }
				elif spawn_cond == "quest_complete":
					# Defer until SessionManager.quest_completed fires. If
					# the player saved and reloaded after the quest already
					# completed (e.g. exited and came back), spawn now.
					if SessionManager.are_objectives_complete():
						_c._spawn_telepipe(pos)
					else:
						_c._deferred_quest_complete_telepipe = { "position": pos }
				else:
					_c._spawn_telepipe(pos)
			"warp":
				var w_section: int = int(obj.get("warp_section", 0))
				var w_cell: String = str(obj.get("warp_cell", ""))
				var w_pos_arr: Array = obj.get("warp_position", [0, 0, 0])
				var w_pos := Vector3(w_pos_arr[0], w_pos_arr[1], w_pos_arr[2])
				_spawn_warp_point(pos, w_section, w_cell, w_pos)
			"area_warp":
				pass  # Area warps are auto-generated from portal data, not from objects
			"quest_item":
				var qi_id: String = str(obj.get("item_id", ""))
				var qi_label: String = str(obj.get("item_label", ""))
				var qi_dlg: Array = obj.get("dialog", [])
				var qi_act: Array = obj.get("actions", [])
				var qi_rem: Array = obj.get("remaining_dialog", [])
				var qi_spawn: String = str(obj.get("spawn_condition", ""))
				if qi_spawn == "room_clear":
					# Defer until enemies are cleared (e.g. the hildegao ate it).
					_c._deferred_room_clear_items.append({
						"pos": pos, "id": qi_id, "label": qi_label,
						"dialog": qi_dlg, "actions": qi_act, "remaining_dialog": qi_rem,
					})
				else:
					_spawn_quest_item(pos, qi_id, qi_label, qi_dlg, qi_act, qi_rem)
			"needle_trap":
				_spawn_needle_trap(pos)
			"bear_trap":
				_spawn_bear_trap(pos)
			"wall":
				var w_destructible: bool = bool(obj.get("destructible", true))
				_spawn_wall(pos, obj_rot, w_destructible)

	if _c._max_wave > 1:
		print("[CellObjects] Wave system: %d waves, wave 1 spawned" % _c._max_wave)


## Restore objects from saved cell state (revisiting a cell).
func _restore_cell_objects(saved: Dictionary) -> void:
	var obj_states: Array = saved.get("objects", [])
	var drop_states: Array = saved.get("drops", [])
	_c._current_wave = int(saved.get("current_wave", 1))
	_c._max_wave = int(saved.get("max_wave", 1))
	print("[CellObjects] Restoring %d objects + %d drops from saved state (wave %d/%d)" % [
		obj_states.size(), drop_states.size(), _c._current_wave, _c._max_wave])

	# Rebuild wave enemy data from original cell objects so _spawn_wave works on restore
	_c._wave_enemy_data.clear()
	for obj in _c._current_cell.get("objects", []):
		if str(obj.get("type", "")) == "enemy":
			var wave: int = int(obj.get("wave", 1))
			if wave > 1:
				if not _c._wave_enemy_data.has(wave):
					_c._wave_enemy_data[wave] = []
				_c._wave_enemy_data[wave].append(obj)

	for obj in obj_states:
		var obj_type: String = str(obj.get("type", ""))
		var pos := Vector3(float(obj.get("px", 0)), float(obj.get("py", 0)), float(obj.get("pz", 0)))
		var state: String = str(obj.get("state", ""))
		var obj_rot: float = float(obj.get("rotation", 0))

		match obj_type:
			"box", "rare_box":
				_spawn_box(pos, obj_type == "rare_box", state,
					str(obj.get("drop_type", "")), str(obj.get("drop_value", "")))
			"enemy":
				var enemy_wave: int = int(obj.get("wave", 1))
				if enemy_wave > _c._current_wave:
					continue  # Future wave — don't spawn yet
				_spawn_enemy(pos, str(obj.get("enemy_id", "lizard")), state)
			"fence":
				var link_id: String = str(obj.get("link_id", ""))
				var r_scale_x: float = float(obj.get("scale_x", 1.0))
				_spawn_fence(pos, obj_rot, link_id, r_scale_x)
				# Restore fence state if disabled
				if state == "disabled" and not _c._fence_links.is_empty():
					for lid in _c._fence_links:
						for f in _c._fence_links[lid]["fences"]:
							if (f as Fence).position.distance_to(pos) < 0.1:
								(f as Fence).disable()
			"step_switch":
				var link_id: String = str(obj.get("link_id", ""))
				_spawn_switch(pos, link_id)
				# Restore switch state
				if state == "on":
					if not link_id.is_empty():
						SessionManager.set_link_activated(link_id)
					for lid in _c._fence_links:
						for s in _c._fence_links[lid]["switches"]:
							if (s as StepSwitch).position.distance_to(pos) < 0.1:
								(s as StepSwitch).set_state("on")
			"message":
				var text: String = str(obj.get("text", ""))
				var msg_state: String = state if not state.is_empty() else "available"
				var reaction: Array = obj.get("reaction_dialog", [])
				var msg_objective_id: String = str(obj.get("objective_item_id", ""))
				_spawn_message(pos, text, msg_state, reaction, msg_objective_id)
				# A message that was already read counts as objective-counted
				# so re-entering the room doesn't re-tick the objective.
				if msg_state == "read" and not msg_objective_id.is_empty() and not _c._room_messages.is_empty():
					_c._room_messages[-1].set_meta("objective_counted", true)
			"story_prop":
				var prop_path: String = str(obj.get("prop_path", ""))
				var prop_scale: float = float(obj.get("prop_scale", 1.0))
				var prop_no_collision: bool = bool(obj.get("no_collision", false))
				_spawn_story_prop(pos, prop_path, obj_rot, prop_scale, prop_no_collision)
			"dialog_trigger":
				var trigger_id: String = str(obj.get("trigger_id", ""))
				var dlg: Array = obj.get("dialog", [])
				var condition: String = str(obj.get("trigger_condition", "enter"))
				var act: Array = obj.get("actions", [])
				var tsize_arr: Array = obj.get("trigger_size", [])
				var tsize := Vector3.ZERO
				if tsize_arr.size() == 3:
					tsize = Vector3(float(tsize_arr[0]), float(tsize_arr[1]), float(tsize_arr[2]))
				_spawn_dialog_trigger(pos, trigger_id, dlg, state, condition, act, tsize)
			"npc":
				var npc_id: String = str(obj.get("npc_id", ""))
				var npc_name: String = str(obj.get("npc_name", ""))
				var dlg: Array = obj.get("dialog", [])
				var npc_anim: String = str(obj.get("animation", ""))
				_spawn_field_npc(pos, npc_id, npc_name, dlg, obj_rot, npc_anim)
			"telepipe":
				# Telepipes are always spawned on restore (player already cleared the room)
				_c._spawn_telepipe(pos)
			"warp":
				var w_section: int = int(obj.get("warp_section", 0))
				var w_cell: String = str(obj.get("warp_cell", ""))
				var w_pos_arr: Array = obj.get("warp_position", [0, 0, 0])
				var w_pos := Vector3(w_pos_arr[0], w_pos_arr[1], w_pos_arr[2])
				_spawn_warp_point(pos, w_section, w_cell, w_pos)
			"area_warp":
				pass  # Area warps are auto-generated from portal data, not from objects
			"quest_item":
				if state != "collected":
					var qi_id: String = str(obj.get("item_id", ""))
					var qi_label: String = str(obj.get("item_label", ""))
					# Look up full dialog/actions/remaining_dialog from original cell data
					var qi_dlg: Array = []
					var qi_act: Array = []
					var qi_rem: Array = []
					var qi_spawn: String = ""
					for orig_obj in _c._current_cell.get("objects", []):
						if str(orig_obj.get("type", "")) == "quest_item" and str(orig_obj.get("item_id", "")) == qi_id:
							qi_dlg = orig_obj.get("dialog", [])
							qi_act = orig_obj.get("actions", [])
							qi_rem = orig_obj.get("remaining_dialog", [])
							qi_spawn = str(orig_obj.get("spawn_condition", ""))
							break
					if qi_spawn == "room_clear":
						# Room was previously cleared if no enemy is alive in the
						# saved state — spawn the item now so re-entry works.
						# Otherwise defer for this run's room-clear pass.
						var room_was_cleared := true
						for s_obj in obj_states:
							if str(s_obj.get("type", "")) == "enemy" and str(s_obj.get("state", "")) == "alive":
								room_was_cleared = false
								break
						if room_was_cleared:
							_spawn_quest_item(pos, qi_id, qi_label, qi_dlg, qi_act, qi_rem)
						else:
							_c._deferred_room_clear_items.append({
								"pos": pos, "id": qi_id, "label": qi_label,
								"dialog": qi_dlg, "actions": qi_act, "remaining_dialog": qi_rem,
							})
					else:
						_spawn_quest_item(pos, qi_id, qi_label, qi_dlg, qi_act, qi_rem)
			"needle_trap":
				_spawn_needle_trap(pos)
			"bear_trap":
				_spawn_bear_trap(pos)
			"wall":
				var w_destructible: bool = bool(obj.get("destructible", true))
				_spawn_wall(pos, obj_rot, w_destructible)
				if state == "destroyed":
					for w in _c._room_walls:
						if is_instance_valid(w) and (w as Node3D).position.distance_to(pos) < 0.1:
							(w as Wall).set_state("destroyed")

	# Restore uncollected drops
	for d in drop_states:
		var pos := Vector3(float(d.get("px", 0)), float(d.get("py", 0)), float(d.get("pz", 0)))
		var drop_kind: String = str(d.get("kind", ""))
		var drop: DropBase = null
		match drop_kind:
			"meseta":
				var dm := DropMesetaScript.new()
				dm.amount = int(d.get("amount", 10))
				drop = dm
			"material":
				var dmat := DropMaterialScript.new()
				dmat.item_id = str(d.get("item_id", ""))
				dmat.amount = int(d.get("amount", 1))
				drop = dmat
			"item":
				var di := DropItemScript.new()
				di.item_id = str(d.get("item_id", ""))
				di.amount = int(d.get("amount", 1))
				drop = di
		if drop:
			_c._map_root.add_child(drop)
			drop.position = pos
			_c._room_drops.append(drop)

	# Re-drop key if room was cleared but key wasn't collected
	var key_drop_target: String = str(_c._current_cell.get("key_drop", ""))
	if not key_drop_target.is_empty():
		var current_pos: String = str(_c._current_cell.get("pos", ""))
		var drop_tracking_key := current_pos + ">" + key_drop_target
		if not _c._keys_collected.has(drop_tracking_key):
			# Check if room is actually cleared (no alive enemies in saved state)
			var has_alive := false
			for obj in obj_states:
				if str(obj.get("type", "")) == "enemy" and str(obj.get("state", "")) == "alive":
					has_alive = true
					break
			# When the room was previously cleared, decide what to spawn:
			# - quest complete → telepipe at the drop position (player returns
			#   to a cleared room after finishing elsewhere; still want them to
			#   be able to leave from here);
			# - quest not complete and key not yet collected → drop the key.
			if not has_alive:
				var has_objs := SessionManager.get_quest_objectives().size() > 0
				if has_objs and SessionManager.are_objectives_complete():
					_c._spawn_telepipe(_c._compute_drop_position())
				else:
					_c._gate_mgr._drop_key_on_clear(key_drop_target, drop_tracking_key)


## Save current cell's object states before transitioning away.
func _save_cell_state() -> void:
	_room_enemy_alive_ids_built = false
	var cell_pos: String = str(_c._current_cell.get("pos", ""))
	if cell_pos.is_empty():
		return

	var obj_states: Array = []
	var drop_states: Array = []

	# Save box states
	for box in _c._room_boxes:
		if not is_instance_valid(box):
			# Instance gone — skip it here; its destroyed state is recorded
			# later by diffing the surviving boxes against the original config.
			continue
		var b: Box = box as Box
		obj_states.append({
			"type": "rare_box" if b.is_rare else "box",
			"px": b.position.x, "py": b.position.y, "pz": b.position.z,
			"state": b.element_state,
			"drop_type": b.drop_type,
			"drop_value": b.drop_value,
		})
	# Also record destroyed boxes from the original quest data
	var objects: Array = _c._current_cell.get("objects", [])
	var intact_box_positions: Array = []
	for box in _c._room_boxes:
		if is_instance_valid(box):
			intact_box_positions.append(box.position)
	for obj in objects:
		var obj_type: String = str(obj.get("type", ""))
		if obj_type in ["box", "rare_box"]:
			var pos_arr: Array = obj.get("position", [0, 0, 0])
			var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
			var found := false
			for intact_pos in intact_box_positions:
				if intact_pos.distance_to(pos) < 0.1:
					found = true
					break
			if not found:
				obj_states.append({
					"type": obj_type,
					"px": pos.x, "py": pos.y, "pz": pos.z,
					"state": "destroyed",
				})

	# Save enemy states (current wave enemies that have been spawned)
	for obj in objects:
		if str(obj.get("type", "")) == "enemy":
			var wave: int = int(obj.get("wave", 1))
			var pos_arr: Array = obj.get("position", [0, 0, 0])
			var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
			var enemy_id: String = str(obj.get("enemy_id", "lizard"))
			if wave > _c._current_wave:
				# Future wave — not yet spawned, save as alive
				obj_states.append({
					"type": "enemy",
					"px": pos.x, "py": pos.y, "pz": pos.z,
					"state": "alive",
					"enemy_id": enemy_id,
					"wave": wave,
				})
			elif wave < _c._current_wave:
				# Past wave — already cleared
				obj_states.append({
					"type": "enemy",
					"px": pos.x, "py": pos.y, "pz": pos.z,
					"state": "dead",
					"enemy_id": enemy_id,
					"wave": wave,
				})
			else:
				# Current wave — match spawned enemies by enemy_id + alive status
				# Build a list of alive enemy_ids from _room_enemies (consumed as matched)
				if not _room_enemy_alive_ids_built:
					_room_enemy_alive_ids.clear()
					for e in _c._room_enemies:
						if not is_instance_valid(e):
							continue
						var alive: bool = false
						var eid: String = ""
						if e is EnemyBase:
							alive = e.is_alive
							eid = e.enemy_data.id if e.enemy_data else ""
						else:
							alive = e.get("element_state") != "dead"
							eid = str(e.get("enemy_id", ""))
						if alive:
							_room_enemy_alive_ids.append(eid)
					_room_enemy_alive_ids_built = true
				# Check if this specific enemy_id is still in the alive list
				var is_dead: bool = true
				var match_idx: int = _room_enemy_alive_ids.find(enemy_id)
				if match_idx >= 0:
					is_dead = false
					_room_enemy_alive_ids.remove_at(match_idx)
				obj_states.append({
					"type": "enemy",
					"px": pos.x, "py": pos.y, "pz": pos.z,
					"state": "dead" if is_dead else "alive",
					"enemy_id": enemy_id,
					"wave": wave,
				})

	# Save fence/switch states
	for obj in objects:
		var obj_type: String = str(obj.get("type", ""))
		if obj_type in ["fence", "step_switch"]:
			var pos_arr: Array = obj.get("position", [0, 0, 0])
			var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
			var state: String = ""
			if obj_type == "fence":
				for lid in _c._fence_links:
					for f in _c._fence_links[lid]["fences"]:
						if is_instance_valid(f) and (f as Node3D).position.distance_to(pos) < 0.5:
							state = (f as Fence).element_state
			elif obj_type == "step_switch":
				for lid in _c._fence_links:
					for s in _c._fence_links[lid]["switches"]:
						if is_instance_valid(s) and (s as Node3D).position.distance_to(pos) < 0.5:
							state = (s as StepSwitch).element_state
			obj_states.append({
				"type": obj_type,
				"px": pos.x, "py": pos.y, "pz": pos.z,
				"state": state,
				"rotation": float(obj.get("rotation", 0)),
				"link_id": str(obj.get("link_id", "")),
			})

	# Save uncollected drops
	for drop in _c._room_drops:
		if is_instance_valid(drop) and drop.element_state == "available":
			var d: DropBase = drop as DropBase
			var kind := "meseta"
			if d is DropMaterial:
				kind = "material"
			elif d is DropMeseta:
				kind = "meseta"
			else:
				kind = "item"
			var entry := {
				"kind": kind,
				"px": d.position.x, "py": d.position.y, "pz": d.position.z,
				"amount": d.amount,
			}
			if kind in ["item", "material"]:
				entry["item_id"] = d.item_id
			drop_states.append(entry)

	# Save message states
	for msg in _c._room_messages:
		if is_instance_valid(msg):
			var msg_entry := {
				"type": "message",
				"px": msg.position.x, "py": msg.position.y, "pz": msg.position.z,
				"state": msg.element_state,
				"text": msg.message_text,
			}
			if not msg.reaction_dialog.is_empty():
				msg_entry["reaction_dialog"] = msg.reaction_dialog
			if not msg.objective_item_id.is_empty():
				msg_entry["objective_item_id"] = msg.objective_item_id
			obj_states.append(msg_entry)

	# Save story prop states
	for prop in _c._room_props:
		if is_instance_valid(prop):
			var prop_entry := {
				"type": "story_prop",
				"px": prop.position.x, "py": prop.position.y, "pz": prop.position.z,
				"state": prop.element_state,
				"prop_path": prop.prop_path,
				"prop_scale": prop.prop_scale,
			}
			if prop.no_collision:
				prop_entry["no_collision"] = true
			obj_states.append(prop_entry)

	# Save dialog trigger states
	for trigger in _c._room_triggers:
		if is_instance_valid(trigger):
			var tdata := {
				"type": "dialog_trigger",
				"px": trigger.position.x, "py": trigger.position.y, "pz": trigger.position.z,
				"state": trigger.element_state,
				"trigger_id": trigger.trigger_id,
				"dialog": trigger.dialog,
				"trigger_condition": trigger.trigger_condition,
				"actions": trigger.actions,
			}
			var cs: Vector3 = trigger.collision_size
			if cs != Vector3(4.0, 3.0, 4.0):
				tdata["trigger_size"] = [cs.x, cs.y, cs.z]
			obj_states.append(tdata)

	# Save NPC states
	for npc in _c._room_npcs:
		if is_instance_valid(npc):
			obj_states.append({
				"type": "npc",
				"px": npc.position.x, "py": npc.position.y, "pz": npc.position.z,
				"state": npc.element_state,
				"npc_id": npc.npc_id,
				"npc_name": npc.npc_name,
				"dialog": npc.dialog,
			})

	# Save quest item states
	for qi in _c._room_quest_items:
		if is_instance_valid(qi):
			obj_states.append({
				"type": "quest_item",
				"px": qi.position.x, "py": qi.position.y, "pz": qi.position.z,
				"state": qi.element_state,
				"item_id": qi.quest_item_id,
				"item_label": qi.quest_item_label,
			})

	# Save wall states
	for wall in _c._room_walls:
		if is_instance_valid(wall):
			var w: Wall = wall as Wall
			obj_states.append({
				"type": "wall",
				"px": w.position.x, "py": w.position.y, "pz": w.position.z,
				"state": w.element_state,
				"rotation": rad_to_deg(w.rotation.y),
				"destructible": w.is_destructible,
			})

	# Save telepipe from original quest data (telepipes are procedural, just preserve placement)
	for obj in objects:
		if str(obj.get("type", "")) == "telepipe":
			var pos_arr: Array = obj.get("position", [0, 0, 0])
			obj_states.append({
				"type": "telepipe",
				"px": float(pos_arr[0]), "py": float(pos_arr[1]), "pz": float(pos_arr[2]),
				"state": "spawned",
				"spawn_condition": str(obj.get("spawn_condition", "immediate")),
			})

	_c._cell_states[cell_pos] = {
		"objects": obj_states, "drops": drop_states,
		"current_wave": _c._current_wave, "max_wave": _c._max_wave,
	}
	print("[CellObjects] Saved state for cell %s: %d objects, %d drops (wave %d/%d)" % [
		cell_pos, obj_states.size(), drop_states.size(), _c._current_wave, _c._max_wave])
	# Autopilot field oracle (#423 + full persistence contract,
	# /states/field-lifecycle §Persistence): tally how much progress this
	# exit-flush snapshotted, so a probe can assert that clearing a room then
	# warping out persists it. The autopilot oracle (Autopilot.observe_cell_flush)
	# then fails the run if any of these regress on a cell re-visit (a respawn).
	# Guarded so normal runs don't get the extra line.
	if OS.has_environment("PSZ_AUTOPILOT"):
		var _tally := {
			"dead": 0,          # enemies killed (MUST NOT respawn)
			"boxes_destroyed": 0,  # broken boxes (MUST NOT reappear / re-drop)
			"drops_pending": drop_states.size(),  # ground loot (MUST stay put until picked up)
			"msgs_read": 0,     # read messages (stay read)
			"items_collected": 0,  # collected quest items (MUST NOT reappear)
		}
		for _o in obj_states:
			var _t: String = str(_o.get("type", ""))
			var _s: String = str(_o.get("state", ""))
			if _t == "enemy" and _s == "dead":
				_tally["dead"] += 1
			elif (_t == "box" or _t == "rare_box") and _s == "destroyed":
				_tally["boxes_destroyed"] += 1
			elif _t == "message" and _s == "read":
				_tally["msgs_read"] += 1
			elif _t == "quest_item" and _s == "collected":
				_tally["items_collected"] += 1
		# Key by SECTION + pos: the same row,col grid label exists in different
		# sections as unrelated cells (e.g. A 3,1 'na1' vs B 3,1 'tb3'), so the
		# re-visit oracle must only compare a cell against its own prior flush.
		var _sec: int = int(SessionManager.get_current_section()) if SessionManager else 0
		var _cell_key: String = "%d:%s" % [_sec, cell_pos]
		print("[sanity] checkpoint: cell-flush cell=%s dead=%d boxes_destroyed=%d drops_pending=%d msgs_read=%d items_collected=%d" % [
			_cell_key, _tally["dead"], _tally["boxes_destroyed"], _tally["drops_pending"],
			_tally["msgs_read"], _tally["items_collected"]])
		# Hand the tally to the autopilot oracle for the cross-visit
		# non-regression check. Autopilot is an autoload, so the global is
		# always resolvable here under PSZ_AUTOPILOT.
		Autopilot.observe_cell_flush(_cell_key, _tally)


func _spawn_box(pos: Vector3, is_rare: bool, state: String = "intact", drop_type: String = "", drop_value: String = "") -> void:
	if state == "destroyed":
		return  # Don't spawn destroyed boxes
	# PSZ_AUTOPILOT_NO_BOXES=1 skips box spawning entirely. Used while
	# iterating on the autopilot's waypoint graph so the autopilot doesn't
	# wedge against a box sitting on the authored backbone.
	if OS.has_environment("PSZ_AUTOPILOT_NO_BOXES"):
		return
	var box := BoxScript.new()
	box.is_rare = is_rare
	box.drop_type = drop_type if not drop_type.is_empty() else "meseta"
	box.drop_value = drop_value if not drop_value.is_empty() else (str(randi_range(10, 50)) if not is_rare else str(randi_range(50, 200)))
	_c._map_root.add_child(box)
	box.position = pos
	_c._fixup_element_materials(box)
	_c._room_boxes.append(box)
	# Track drops spawned from this box
	box.destroyed_box.connect(func() -> void:
		# Find new drop children added after destruction
		await _c.get_tree().process_frame
		for child in _c._map_root.get_children():
			if child is DropBase and not _c._room_drops.has(child):
				_c._room_drops.append(child)
	)
	print("[CellObjects] Box at %s (rare=%s)" % [pos, is_rare])


## Minimap enemy dot (#422). Cell-entry spawns run before the minimap is
## created — the field controller registers that roster itself after setup —
## so this only catches later spawns (wave 2+ via _spawn_wave).
func _track_on_minimap(enemy: Node3D) -> void:
	if _c._room_minimap:
		_c._room_minimap.track_enemy(enemy)


func _spawn_enemy(pos: Vector3, enemy_id: String, state: String = "alive") -> void:
	if state == "dead":
		return  # Don't spawn dead enemies

	# Look up enemy data from registry
	var edata = EnemyRegistry.get_enemy(enemy_id)

	# Use specialized scripts for specific enemy types
	if edata and enemy_id == "poison_lily":
		if not _c.PoisonLilyScript:
			_c.PoisonLilyScript = load("res://scripts/3d/enemies/poison_lily.gd")
		if not _c.PoisonLilyScript:
			push_error("[CellObjects] Failed to load PoisonLily script")
			return
		var enemy: EnemyBase = _c.PoisonLilyScript.new()
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
		_c._map_root.add_child(enemy)
		enemy.position = pos
		_c._room_enemies.append(enemy)
		_track_on_minimap(enemy)
		var spawn_id := enemy_id
		enemy.died.connect(func(e: EnemyBase) -> void:
			_spawn_enemy_drops(e.global_position, spawn_id)
			_c._check_room_clear()
		)
		print("[CellObjects] PoisonLily at %s" % pos)
		return

	# Use EnemyBase (AI enemies) when enemy_data exists, otherwise fall back to EnemySpawn
	if edata:
		var enemy := EnemyBase.new()
		enemy.enemy_data = edata

		# Collision shape
		var col_shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = edata.collision_radius
		capsule.height = edata.collision_height
		col_shape.shape = capsule
		col_shape.position.y = capsule.height / 2
		enemy.add_child(col_shape)
		enemy.collision_layer = 8
		enemy.collision_mask = 1

		_c._map_root.add_child(enemy)
		enemy.position = pos
		_c._room_enemies.append(enemy)
		_track_on_minimap(enemy)
		var spawn_id := enemy_id
		enemy.died.connect(func(e: EnemyBase) -> void:
			_spawn_enemy_drops(e.global_position, spawn_id)
			_c._check_room_clear()
		)
		print("[CellObjects] EnemyBase '%s' at %s" % [enemy_id, pos])
	else:
		# Fallback to static EnemySpawn for unknown enemies
		var enemy := EnemySpawnScript.new()
		enemy.enemy_id = enemy_id
		_c._map_root.add_child(enemy)
		enemy.position = pos
		_c._room_enemies.append(enemy)
		_track_on_minimap(enemy)
		var enemy_ref := enemy
		var spawn_id := enemy_id
		enemy.defeated.connect(func() -> void:
			var drop_pos: Vector3 = enemy_ref.global_position if is_instance_valid(enemy_ref) else pos
			_spawn_enemy_drops(drop_pos, spawn_id)
			_c._check_room_clear()
		)
		print("[CellObjects] EnemySpawn '%s' at %s (no registry data)" % [enemy_id, pos])


func _spawn_fence(pos: Vector3, rotation_deg: float, link_id: String, scale_x: float = 1.0) -> void:
	var fence := FenceScript.new()
	_c._map_root.add_child(fence)
	fence.position = pos
	fence.rotation.y = deg_to_rad(rotation_deg)
	if scale_x != 1.0:
		fence.scale.x = scale_x
		fence.collision_size.x = fence.collision_size.x * scale_x
	_c._fixup_element_materials(fence)
	# Re-run laser material setup after fixup replaced materials (storybook pattern)
	fence._setup_laser_materials()
	if not link_id.is_empty():
		if not _c._fence_links.has(link_id):
			_c._fence_links[link_id] = {"fences": [], "switches": []}
		_c._fence_links[link_id]["fences"].append(fence)
		if SessionManager.is_link_activated(link_id):
			fence.disable()
			print("[CellObjects] Fence at %s link='%s' already activated — disabled" % [pos, link_id])
			return
	print("[CellObjects] Fence at %s rot=%.0f° link='%s'" % [pos, rotation_deg, link_id])


func _spawn_switch(pos: Vector3, link_id: String) -> void:
	var sw := StepSwitchScript.new()
	_c._map_root.add_child(sw)
	sw.position = pos
	_c._fixup_element_materials(sw)
	if not link_id.is_empty():
		if not _c._fence_links.has(link_id):
			_c._fence_links[link_id] = {"fences": [], "switches": []}
		_c._fence_links[link_id]["switches"].append(sw)
	print("[CellObjects] Switch at %s link='%s'" % [pos, link_id])


## Spawn drops when an enemy is defeated.
func _spawn_enemy_drops(pos: Vector3, enemy_id: String) -> void:
	var enemy_data = EnemyRegistry.get_enemy(enemy_id)
	var meseta_min: int = 5
	var meseta_max: int = 20
	var enemy_name: String = enemy_id.capitalize()
	if enemy_data:
		meseta_min = int(enemy_data.meseta_min) if int(enemy_data.meseta_min) > 0 else 5
		meseta_max = int(enemy_data.meseta_max) if int(enemy_data.meseta_max) > 0 else 20
		enemy_name = str(enemy_data.name)

	# Grant EXP
	var exp_amount: int = int(enemy_data.exp_reward) if enemy_data else 0
	if exp_amount > 0:
		var result := CharacterManager.add_experience(exp_amount)
		print("[EnemyDrop] +%d EXP for %s" % [exp_amount, enemy_name])
		if _c._field_hud:
			_c._field_hud.log_entry("+%d EXP" % exp_amount, Color(0.4, 0.9, 1.0))
		if result.leveled_up:
			print("[EnemyDrop] LEVEL UP! Now level %d" % result.new_level)
			if _c._field_hud:
				_c._field_hud.log_entry("LEVEL UP! Lv. %d" % result.new_level, Color(1.0, 0.9, 0.3))
				_c._field_hud._stats_panel.char_level = result.new_level
				_c._field_hud._stats_panel.queue_redraw()

	# Roll for any drop at all
	if randf() >= DropConfig.DROP_CHANCE:
		return

	# Determine what drops — roll item first, fall back to meseta
	var area_id: String = SessionManager.get_current_area_id()
	var difficulty: String = str(SessionManager.get_session().get("difficulty", "normal"))
	var drop_area: String = _c.AREA_DROP_KEYS.get(area_id, "gurhacia-valley")
	var drop_list: Array = DropRegistry.get_enemy_drops(difficulty, drop_area, enemy_name)

	# Filter drop list to only materials and recipe boards
	var material_drops: Array = []
	for drop_name in drop_list:
		var did: String = str(drop_name).to_lower().replace(" ", "_").replace("/", "_")
		if MaterialRegistry.get_material(did) or RecipeRegistry.get_recipe(did):
			material_drops.append(drop_name)

	if not material_drops.is_empty() and randf() < DropConfig.ITEM_VS_MESETA:
		var item_name: String = str(material_drops[randi() % material_drops.size()])
		var item_id: String = item_name.to_lower().replace(" ", "_").replace("/", "_")
		var di := DropMaterialScript.new()
		di.item_id = item_id
		di.amount = 1
		var item_offset := Vector3(randf_range(-0.8, 0.8), 0.5, randf_range(-0.8, 0.8))
		_c._map_root.add_child(di)
		di.position = pos + item_offset
		_c._room_drops.append(di)
		print("[EnemyDrop] Material '%s' (id=%s) at %s" % [item_name, item_id, di.position])
	else:
		var dm := DropMesetaScript.new()
		dm.amount = randi_range(meseta_min, meseta_max)
		var offset := Vector3(randf_range(-0.8, 0.8), 0.5, randf_range(-0.8, 0.8))
		_c._map_root.add_child(dm)
		dm.position = pos + offset
		_c._room_drops.append(dm)
		print("[EnemyDrop] Meseta %d at %s" % [dm.amount, dm.position])


## Spawn a message pack element.
func _spawn_message(pos: Vector3, text: String, state: String = "available", reaction: Array = [], objective_item_id: String = "") -> void:
	var msg := MessagePackScript.new()
	msg.message_text = text
	msg.objective_item_id = objective_item_id
	_c._map_root.add_child(msg)
	msg.position = pos
	_c._fixup_element_materials(msg)
	# Re-run scroll material setup after fixup replaced materials
	msg._setup_scroll_material()
	if state != "available":
		msg.set_state(state)
	# Store and connect reaction dialog — companion speech bubble plays after reading
	msg.reaction_dialog = reaction
	if not reaction.is_empty() and _c._companion and is_instance_valid(_c._companion):
		msg.message_read.connect(_on_message_read_reaction.bind(reaction))
	# Wire to SessionManager objective tracking — only fires when the message
	# is read for the first time (state transition available → read), and only
	# if objective_item_id is set on the message in the quest JSON. Lets a
	# quest declare "read N message logs" without inventing a new pickup type.
	if not objective_item_id.is_empty():
		msg.message_read.connect(_on_message_read_objective.bind(objective_item_id, msg))
	_c._room_messages.append(msg)
	print("[CellObjects] Message at %s (text=%d chars, state=%s, reaction=%d pages, objective=%s)" % [pos, text.length(), state, reaction.size(), objective_item_id])


func _on_message_read_objective(_text: String, item_id: String, msg: MessagePack) -> void:
	# Only count the first read — the message_read signal fires every time the
	# popup closes, but objectives should tick once per message. Track via
	# msg metadata so re-reading a message doesn't double-count.
	if msg.has_meta("objective_counted"):
		return
	msg.set_meta("objective_counted", true)
	SessionManager.collect_quest_item(item_id)


func _on_message_read_reaction(_text: String, reaction: Array) -> void:
	if not _c._companion or not is_instance_valid(_c._companion):
		return
	# Play each reaction page as a speech bubble with delay between pages
	var delay := 0.0
	for page in reaction:
		var speech_text: String = str(page.get("text", ""))
		var speaker: String = str(page.get("speaker", ""))
		var duration: float = maxf(3.0, speech_text.length() / 20.0)
		if delay > 0:
			_c.get_tree().create_timer(delay).timeout.connect(
				_c._companion.show_speech.bind(speech_text, speaker, duration)
			)
		else:
			_c._companion.show_speech(speech_text, speaker, duration)
		delay += duration + 0.5


func _spawn_story_prop(pos: Vector3, prop_path: String, rot_deg: float = 0, prop_scale: float = 1.0, no_collision: bool = false) -> void:
	var prop := StoryPropScript.new()
	prop.prop_path = prop_path
	prop.prop_scale = prop_scale
	prop.no_collision = no_collision
	_c._map_root.add_child(prop)
	prop.position = pos
	if rot_deg != 0:
		prop.rotation.y = deg_to_rad(rot_deg)
	_c._room_props.append(prop)
	print("[CellObjects] StoryProp at %s (path=%s)" % [pos, prop_path])


func _spawn_needle_trap(pos: Vector3) -> void:
	var trap: Node3D = load("res://scripts/3d/elements/needle_trap.gd").new()
	_c._map_root.add_child(trap)
	trap.position = pos
	trap.call("set_state", "on")
	print("[CellObjects] NeedleTrap at %s" % pos)


func _spawn_bear_trap(pos: Vector3) -> void:
	var trap: Node3D = load("res://scripts/3d/elements/bear_trap.gd").new()
	_c._map_root.add_child(trap)
	trap.position = pos
	trap.call("set_state", "on")
	print("[CellObjects] BearTrap at %s" % pos)


func _spawn_wall(pos: Vector3, rotation_deg: float, is_destructible: bool = true) -> void:
	var wall := WallScript.new()
	wall.is_destructible = is_destructible
	_c._map_root.add_child(wall)
	wall.position = pos
	wall.rotation.y = deg_to_rad(rotation_deg)
	_c._fixup_element_materials(wall)
	_c._room_walls.append(wall)
	print("[CellObjects] Wall at %s rot=%.0f° destructible=%s" % [pos, rotation_deg, is_destructible])


func _spawn_dialog_trigger(pos: Vector3, trigger_id: String, dlg: Array, state: String = "ready", condition: String = "enter", act: Array = [], size: Vector3 = Vector3.ZERO) -> void:
	if state == "triggered":
		return  # Already triggered — don't respawn
	var trigger := DialogTriggerScript.new()
	trigger.trigger_id = trigger_id
	trigger.dialog = dlg
	trigger.trigger_condition = condition
	trigger.actions = act
	if size != Vector3.ZERO:
		trigger.collision_size = size
	# Route companion-speaker dialogs to speech bubble
	var is_comp_dlg: bool = _c._is_companion_dialog(dlg)
	print("[DialogTrigger] companion=%s valid=%s is_comp_dialog=%s" % [_c._companion != null, is_instance_valid(_c._companion) if _c._companion else false, is_comp_dlg])
	if _c._companion and is_instance_valid(_c._companion) and is_comp_dlg:
		trigger.companion_node = _c._companion
		print("[DialogTrigger] → Routed '%s' to companion speech bubble" % trigger_id)
	_c._map_root.add_child(trigger)
	trigger.position = pos
	_c._room_triggers.append(trigger)
	print("[CellObjects] DialogTrigger at %s (id=%s, condition=%s, pages=%d, actions=%s, companion=%s)" % [pos, trigger_id, condition, dlg.size(), str(act), trigger.companion_node != null])


func _spawn_field_npc(pos: Vector3, npc_id: String, npc_name: String, dlg: Array, rot_deg: float = 0, anim: String = "") -> void:
	var npc := FieldNpcScript.new()
	npc.npc_id = npc_id
	npc.npc_name = npc_name
	npc.dialog = dlg
	npc.npc_animation = anim
	_c._map_root.add_child(npc)
	npc.position = pos
	if rot_deg != 0:
		npc.rotation.y = deg_to_rad(rot_deg)
	_c._room_npcs.append(npc)
	print("[CellObjects] FieldNpc '%s' (%s) at %s (dialog=%d pages, anim='%s')" % [npc_name, npc_id, pos, dlg.size(), anim])


func _spawn_warp_point(pos: Vector3, target_section: int, target_cell: String, target_position: Vector3) -> void:
	var wp := WarpPointScript.new()
	wp.warp_section = target_section
	wp.warp_cell = target_cell
	wp.warp_position = target_position
	wp.name = "WarpPoint"
	_c._map_root.add_child(wp)
	wp.position = pos
	wp.activated.connect(func() -> void:
		print("[ValleyField] Warp activated → section %d, cell %s, position %s" % [target_section, target_cell, target_position])
		_save_cell_state()
		SessionManager.save_section_state(SessionManager.get_current_section(), _c._cell_states, _c._keys_collected, _c._gates_opened, _c._visited_cells)
		var target_state: Dictionary = SessionManager.get_section_state(target_section)
		SessionManager.set_current_section(target_section)
		SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
			"current_cell_pos": target_cell,
			"spawn_edge": "",
			"spawn_position": [target_position.x, target_position.y, target_position.z],
			"keys_collected": target_state.get("keys_collected", {}),
			"gates_opened": target_state.get("gates_opened", {}),
			"visited_cells": target_state.get("visited_cells", {}),
			"cell_states": target_state.get("cell_states", {}),
			"map_overlay_visible": _c._map_overlay.visible if _c._map_overlay else false,
			"grid_minimap_visible": _c._grid_minimap.visible if _c._grid_minimap else true,
		})
	)
	print("[CellObjects] WarpPoint at %s → section %d, cell %s, position %s" % [pos, target_section, target_cell, target_position])

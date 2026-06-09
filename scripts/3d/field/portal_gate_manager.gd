class_name PortalGateManager
extends RefCounted

## Portal data + gate/trigger handling, extracted from ValleyFieldController.
##
## Holds a back-reference to the controller (`_c`) and delegates all
## controller-state access through it. Behavior is identical to the original
## inline implementation — this is a relocation refactor, not a logic change.

const KeyPickupScript := preload("res://scripts/3d/elements/key_pickup.gd")

## Direction base rotations for portal position math (matches quest-io.ts DIRECTION_ROTATIONS).
## north=0, south=PI, east=-PI/2, west=PI/2.
const DIRECTION_ROTATIONS := {
	"north": 0.0,
	"south": PI,
	"east": -PI / 2.0,
	"west": PI / 2.0,
}

## Back-reference to the ValleyFieldController that owns this manager.
var _c


func _init(controller) -> void:
	_c = controller


## Parse portal data from quest JSON cell["portals"].
## Supports two formats:
##   v1 (reference): { "south": "portal_id_xxx" } — looks up position from stage config
##   legacy (baked): { "south": { "gate": [...], "spawn": [...], ... } } — uses inline positions
func _parse_baked_portals(baked: Dictionary) -> Dictionary:
	var result := {}
	# Build a lookup from portal_id → config portal for v1 references
	var config_portals_by_id := {}
	for cp in _c._stage_config.get("portals", []):
		config_portals_by_id[str(cp.get("id", ""))] = cp

	for dir_key in baked:
		var value = baked[dir_key]

		# v1 format: value is a portal_id string
		if value is String:
			var portal_id: String = value
			if dir_key == "default":
				# "default" references the defaultSpawn in stage config
				var ds: Dictionary = _c._stage_config.get("defaultSpawn", {})
				if not ds.is_empty():
					var ds_pos_arr: Array = ds.get("position", [0, 0, 0])
					var ds_pos := Vector3(float(ds_pos_arr[0]), 1.0, float(ds_pos_arr[2]))
					var ds_dir: String = str(ds.get("direction", "north"))
					var ds_rot: float = DIRECTION_ROTATIONS.get(ds_dir, 0.0)
					result["default"] = {
						"spawn_pos": ds_pos,
						"trigger_pos": ds_pos,
						"default_rotation": ds_rot,
					}
			elif config_portals_by_id.has(portal_id):
				result[dir_key] = _compute_portal_from_config(config_portals_by_id[portal_id], dir_key)
			else:
				# Portal ID not in config — match by direction instead.
				# dir_key is the game direction (after rotation). Find the config
				# portal whose base direction rotates to dir_key.
				var matched := false
				for cp in _c._stage_config.get("portals", []):
					var base_dir: String = str(cp.get("direction", ""))
					var rotated_dir: String = StageRotation.rotate_dir(base_dir, _c._rotation_deg)
					if rotated_dir == dir_key:
						result[dir_key] = _compute_portal_from_config(cp, dir_key)
						matched = true
						break
				if not matched:
					print("[sanity] portal MISS: dir='%s' id='%s' rot=%d — no config portal matched" % [dir_key, portal_id, _c._rotation_deg])
					var avail_ids: Array = []
					for cp in _c._stage_config.get("portals", []):
						avail_ids.append("%s(%s)" % [str(cp.get("id", "")), str(cp.get("direction", ""))])
					print("[sanity] portal MISS: stage_config portal IDs available: %s" % str(avail_ids))
					push_warning("[ValleyField] No portal found for dir '%s' in stage config (rot=%d)" % [dir_key, _c._rotation_deg])
			if result.has(dir_key):
				print("[ValleyField]   v1 portal: '%s' (id=%s) → gate=%s spawn=%s trigger=%s" % [
					dir_key, portal_id,
					result[dir_key].get("gate_pos", "n/a"),
					result[dir_key]["spawn_pos"],
					result[dir_key]["trigger_pos"]])
			continue

		# Legacy format: value is a dictionary with baked positions
		var pd: Dictionary = value
		if dir_key == "default":
			var sp: Array = pd.get("spawn", [0, 1, 0])
			result["default"] = {
				"spawn_pos": Vector3(float(sp[0]), float(sp[1]), float(sp[2])),
				"trigger_pos": Vector3(float(sp[0]), float(sp[1]), float(sp[2])),
			}
			if pd.has("default_rotation"):
				result["default"]["default_rotation"] = float(pd["default_rotation"])
		else:
			var gate: Array = pd.get("gate", [0, 0, 0])
			var spawn: Array = pd.get("spawn", [0, 1, 0])
			var trigger: Array = pd.get("trigger", [0, 0, 0])
			var gr: Array = pd.get("gate_rot", [0, 0, 0])
			result[dir_key] = {
				"gate_pos": Vector3(float(gate[0]), float(gate[1]), float(gate[2])),
				"spawn_pos": Vector3(float(spawn[0]), float(spawn[1]), float(spawn[2])),
				"trigger_pos": Vector3(float(trigger[0]), float(trigger[1]), float(trigger[2])),
				"gate_rot": Vector3(float(gr[0]), float(gr[1]), float(gr[2])),
				"compass_label": pd.get("compass_label", dir_key.substr(0, 1).to_upper()),
			}
		print("[ValleyField]   baked portal: '%s' → gate=%s spawn=%s trigger=%s" % [
			dir_key,
			result[dir_key].get("gate_pos", "n/a"),
			result[dir_key]["spawn_pos"],
			result[dir_key]["trigger_pos"]])
	# Summary for [sanity] tail — shows final _portal_data direction keys so
	# we can match against what the autopilot asks for.
	var dirs: Array = []
	for k in result:
		dirs.append(str(k))
	print("[sanity] _parse_baked_portals: final keys=%s (rot=%d)" % [str(dirs), _c._rotation_deg])
	return result


## Compute portal positions from a config portal entry.
## Gate rotation and spawn/trigger offsets use the config direction (physical orientation).
## Only the compass label uses the game direction (rotated label).
func _compute_portal_from_config(portal: Dictionary, game_dir: String) -> Dictionary:
	var pos_arr: Array = portal.get("position", [0, 0, 0])
	var gate_pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))

	# Use the config direction for gate rotation and outward vector. Add the
	# authored rotationOffset (in degrees) so angled gates like the s07e_ia1
	# south portal render the same direction here as in the stage editor.
	var config_dir: String = str(portal.get("direction", "north"))
	var base_rot: float = DIRECTION_ROTATIONS.get(config_dir, 0.0)
	var offset_deg: float = float(portal.get("rotationOffset", 0))
	var rotation: float = base_rot + deg_to_rad(offset_deg)
	var gate_rot := Vector3(0.0, rotation, 0.0)
	var outward := Vector2(-sin(rotation), -cos(rotation))

	var spawn_pos := Vector3(gate_pos.x + outward.x * 3.0, 1.0, gate_pos.z + outward.y * 3.0)
	var trigger_pos := Vector3(gate_pos.x + outward.x * 7.0, 0.0, gate_pos.z + outward.y * 7.0)

	return {
		"gate_pos": gate_pos,
		"spawn_pos": spawn_pos,
		"trigger_pos": trigger_pos,
		"gate_rot": gate_rot,
		"compass_label": game_dir.substr(0, 1).to_upper(),
		"id": str(portal.get("id", "")),
	}


## Build portal data from config JSON portals[] and defaultSpawn (fallback for non-quest sessions).
## Computes spawn/trigger/gate positions using the same math as ExportTab.tsx computePortalPositions.
## Positions are in stage-local space — caller transforms via _map_root.to_global() after add_child.
func _build_portal_data_from_config(config: Dictionary) -> Dictionary:
	var portals_arr: Array = config.get("portals", [])
	if portals_arr.is_empty() and not config.has("defaultSpawn"):
		return {}

	var result := {}
	for portal in portals_arr:
		var dir: String = str(portal.get("direction", ""))
		if dir.is_empty():
			continue
		var pos_arr: Array = portal.get("position", [0, 0, 0])
		# Positions match GLB geometry directly — no mirroring or rotation needed.
		var gate_pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))

		# Gate rotation for visual placement (Y-axis only)
		var base_rot: float = DIRECTION_ROTATIONS.get(dir, 0.0)
		var offset_deg: float = float(portal.get("rotationOffset", 0))
		var rotation: float = base_rot + deg_to_rad(offset_deg)
		var gate_rot := Vector3(0.0, rotation, 0.0)

		# Outward direction: cardinal axis based on portal direction label
		# Matches computePortalPositions() in quest-io.ts: offset = [-sin(rot), -cos(rot)]
		var outward := Vector2(-sin(rotation), -cos(rotation))

		# Spawn = 3 units outside gate (in corridor), y=1.0
		var spawn_pos := Vector3(gate_pos.x + outward.x * 3.0, 1.0, gate_pos.z + outward.y * 3.0)
		# Trigger = 7 units outside gate (deeper in corridor), y=0.0
		var trigger_pos := Vector3(gate_pos.x + outward.x * 7.0, 0.0, gate_pos.z + outward.y * 7.0)

		# Key by config direction — rotation remapping happens in the caller
		result[dir] = {
			"spawn_pos": spawn_pos,
			"trigger_pos": trigger_pos,
			"gate_pos": gate_pos,
			"gate_rot": gate_rot,
			"id": str(portal.get("id", "")),
		}
		print("[ValleyField]   portal: config dir='%s' gate=%s spawn=%s trigger=%s" % [
			dir, gate_pos, spawn_pos, trigger_pos])

	# Default spawn point (boss rooms / gateless areas)
	if config.has("defaultSpawn"):
		var ds: Dictionary = config["defaultSpawn"]
		var ds_pos_arr: Array = ds.get("position", [0, 0, 0])
		var ds_pos := Vector3(float(ds_pos_arr[0]), 1.0, float(ds_pos_arr[2]))
		var ds_dir: String = str(ds.get("direction", "north"))
		var ds_rot: float = DIRECTION_ROTATIONS.get(ds_dir, 0.0)
		result["default"] = {
			"spawn_pos": ds_pos,
			"trigger_pos": ds_pos,
			"default_rotation": ds_rot,
		}

	print("[ValleyField] Built portal data from config: %d portals, default=%s" % [
		portals_arr.size(), str(config.has("defaultSpawn"))])
	return result


func _create_gate_trigger(direction: String, target_cell_pos: String, _portal: Dictionary, delayed: bool = false, locked: bool = false) -> void:
	var entry_edge: String = _c.OPPOSITE[direction]
	var callback := func(_body: Node3D) -> void:
		if _body.is_in_group("player"):
			print("[ValleyField] ▶ TRIGGER: grid_dir=%s → cell %s (entry_edge=%s)" % [
				direction, target_cell_pos, entry_edge])
			_c._transition_to_cell(target_cell_pos, entry_edge)

	print("[ValleyField]   trigger: dir=%s  target=%s  delayed=%s  locked=%s  pos=%s" % [
		direction, target_cell_pos, delayed, locked, _portal["trigger_pos"]])
	# Locked triggers stay disabled until key gate opens; delayed triggers auto-enable after 1s
	_create_fallback_trigger("GateTrigger_%s" % direction, _portal["trigger_pos"], callback, delayed and not locked, locked)

	# DEBUG: Add floating direction label at gate position
	_add_gate_label(direction, _portal["gate_pos"] if _portal.has("gate_pos") else _portal["trigger_pos"], target_cell_pos, str(_portal.get("id", "")))


## Create a programmatic Area3D trigger at the given position.
func _create_fallback_trigger(trigger_name: String, pos: Vector3, callback: Callable, delayed: bool = false, locked: bool = false) -> void:
	var trigger := Area3D.new()
	trigger.name = trigger_name
	trigger.collision_layer = 0
	trigger.collision_mask = 2
	if delayed or locked:
		trigger.monitoring = false

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 3, 6)
	shape.shape = box
	shape.position.y = 1.5
	trigger.add_child(shape)

	trigger.body_entered.connect(callback)
	_c.add_child(trigger)
	trigger.global_position = pos

	if delayed and not locked:
		_c.get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if is_instance_valid(trigger):
				trigger.monitoring = true
		)


## DEBUG: Add a floating 3D text label at gate position showing compass label + target cell.
## Also adds colored sphere markers for gate (yellow), spawn (green), and trigger (red).
func _add_gate_label(direction: String, pos: Vector3, target_cell: String, portal_id: String = "") -> void:
	var label := Label3D.new()
	label.name = "GateLabel_%s" % direction
	# Show grid direction (matches minimap labels) plus a suffix of the
	# portal id so the player can grep the unified-stage-config for the
	# exact gate. The id format is portal_<13digit-ts>_<11char-rand>; the
	# trailing random suffix is unique inside a stage, so taking the last
	# 6 chars is enough to disambiguate.
	var compass: String = direction.substr(0, 1).to_upper()
	var id_suffix: String = portal_id.right(6) if not portal_id.is_empty() else ""
	if id_suffix.is_empty():
		label.text = "%s\n→ %s" % [compass, target_cell]
	else:
		label.text = "%s (%s)\n→ %s" % [compass, id_suffix, target_cell]
	label.font_size = 48
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(1, 1, 0, 1)  # Bright yellow
	label.outline_modulate = Color(0, 0, 0, 1)
	label.outline_size = 8
	_c.add_child(label)
	label.global_position = Vector3(pos.x, 3.5, pos.z)

	# DEBUG: Sphere markers — gate=yellow, spawn=green, trigger=red
	var clean_dir: String = direction.split(" ")[0]  # Strip "(EXIT)" suffix
	if _c._portal_data.has(clean_dir):
		var pd: Dictionary = _c._portal_data[clean_dir]
		_c._add_debug_sphere(pd["gate_pos"] if pd.has("gate_pos") else pos, Color(1, 1, 0), "GateMark_%s" % direction)
		_c._add_debug_sphere(pd["spawn_pos"], Color(0, 1, 0), "SpawnMark_%s" % direction)
		_c._add_debug_sphere(pd["trigger_pos"], Color(1, 0, 0), "TriggerMark_%s" % direction)


func _create_key_pickup(key_for_cell: String) -> void:
	# Use proper KeyPickup element with o0c_key.glb model
	var key_item_id := "key_%s" % key_for_cell.replace(",", "_")
	var key := KeyPickupScript.new()
	key.key_id = key_item_id
	key.name = "KeyPickup_%s" % key_for_cell

	# Place key at authored position from quest editor, or fall back to heuristic
	var key_pos := Vector3.ZERO
	var authored_pos: Array = _c._current_cell.get("key_position", [])
	if authored_pos.size() == 3:
		# Use authored position from quest editor (stage-local coordinates)
		key_pos = Vector3(float(authored_pos[0]), float(authored_pos[1]), float(authored_pos[2]))
		print("[ValleyField] Key using authored position: %s (rotation handled by _map_root)" % key_pos)
	else:
		# Fallback: midpoint between portal spawns
		var portal_positions: Array[Vector3] = []
		for dir in _c._portal_data:
			if dir != "default":
				portal_positions.append(_c._portal_data[dir]["spawn_pos"])
		if portal_positions.size() >= 2:
			var sum := Vector3.ZERO
			for p in portal_positions:
				sum += p
			key_pos = sum / float(portal_positions.size())
		elif portal_positions.size() == 1:
			key_pos = portal_positions[0]
		key_pos.y = 0.5
		print("[ValleyField] Key using fallback midpoint: %s" % key_pos)

	_c._map_root.add_child(key)
	key.position = key_pos

	# Track collection for grid state and update HUD
	key.interacted.connect(func(_player: Node3D) -> void:
		_c._keys_collected[key_for_cell] = true
		_c._update_key_hud()
	)
	print("[ValleyField] Key pickup spawned for cell %s at %s (id=%s)" % [
		key_for_cell, key_pos, key_item_id])


func _drop_key_on_clear(target_cell: String, tracking_key: String) -> void:
	var key_item_id := "key_%s" % target_cell.replace(",", "_")
	var key := KeyPickupScript.new()
	key.key_id = key_item_id
	key.name = "KeyDrop_%s" % target_cell

	var key_pos: Vector3 = _c._compute_drop_position()

	_c._map_root.add_child(key)
	key.position = key_pos

	key.interacted.connect(func(_player: Node3D) -> void:
		_c._keys_collected[tracking_key] = true
		_c._update_key_hud()
	)
	print("[ValleyField] Key dropped on room clear for gate %s at %s (id=%s)" % [
		target_cell, key_pos, key_item_id])


## Apply storybook-style material fixup to gate elements.
## Duplicates all materials (prevents shared-resource mutation) and applies
## UV scale/offset correction for the o0c_0_gatet frame texture.
func _fixup_gate_materials(element: GameElement) -> void:
	if not element.model:
		return
	_fixup_gate_recursive(element.model)


func _fixup_gate_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if not mat is StandardMaterial3D:
				continue
			var std_mat := mat as StandardMaterial3D
			var dup := std_mat.duplicate() as StandardMaterial3D
			mesh_inst.set_surface_override_material(i, dup)
			# UV fixup for gate frame texture (matches storybook TEXTURE_FIXUPS)
			if dup.albedo_texture and "o0c_0_gatet" in dup.albedo_texture.resource_path:
				dup.uv1_scale = Vector3(1, 2, 1)
				dup.uv1_offset = Vector3(0.56, 0.8, 0)
	for child in node.get_children():
		_fixup_gate_recursive(child)


## Force all materials on a gate element to opaque depth draw so they don't
## break depth buffer for geometry behind/below them (e.g. water plane).
## GLB textures often have alpha channels causing auto-imported transparency.
func _fix_gate_depth(gate: Node3D) -> void:
	if not gate is GameElement:
		return
	var ge: GameElement = gate as GameElement
	ge.apply_to_all_materials(func(mat: Material, _mesh: MeshInstance3D, _surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			# Skip the laser material (identified by texture name)
			if std_mat.albedo_texture and "o0c_1_gate" in std_mat.albedo_texture.resource_path:
				return
			# Force fully opaque rendering
			std_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			std_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	)


func _unlock_objective_exits() -> void:
	# Unlock objective-locked AreaWarps (red beam → blue beam)
	for warp in _c._objective_locked_exits:
		if is_instance_valid(warp):
			warp.set_state("open")
	_c._objective_locked_exits.clear()

	# Update minimap
	var we: String = str(_c._current_cell.get("warp_edge", ""))
	if not we.is_empty() and _c._room_minimap:
		_c._room_minimap.set_gate_locked(we, false)
	if not we.is_empty() and _c._grid_minimap:
		_c._grid_minimap.set_gate_state(str(_c._current_cell.get("pos", "")), we, "exit")


func _get_locked_gates(cell: Dictionary) -> Array:
	# Editor writes both fields: prefer the array, fall back to the singular.
	var arr: Variant = cell.get("key_gate_directions", null)
	if arr is Array and arr.size() > 0:
		var out: Array = []
		for d in arr:
			var ds := str(d)
			if not ds.is_empty():
				out.append(ds)
		return out
	var single: String = str(cell.get("key_gate_direction", ""))
	if single.is_empty():
		return []
	return [single]

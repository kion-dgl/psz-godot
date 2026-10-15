extends "res://scripts/tools/probe_checks.gd"
## Run: godot --headless --path . res://scripts/tools/key_collection_probe.tscn
## Real pickups and gate, with room teardown and JSON state round-trip.
const VF := preload("res://scripts/3d/field/valley_field_controller.gd")
const PGM := preload("res://scripts/3d/field/portal_gate_manager.gd")
var field
var player: Node3D

func _run() -> void:
	probe_label = "key-collection"
	field = VF.new()
	field._gate_mgr = PGM.new(field)
	field._map_root = Node3D.new()
	add_child(field._map_root)
	player = Node3D.new()
	add_child(player)
	field._keys_collected = {"2,1": true}
	await _visit("1,1", 1)
	_check(_pickups().size() == 1, "legacy save recovers first holder")
	_pickups()[0].interact(player)
	await get_tree().process_frame
	_check(Inventory.get_key_count("key_2_1") == 1, "first actual pickup adds one key")
	await _visit("2,1", 1)
	_check(_pickups().size() == 1, "second room still spawns its copy")
	var gate := KeyGate.new()
	gate.required_key_id = "key_2_1"
	gate.required_keys = 2
	add_child(gate)
	gate.interact(player)
	_check(gate.element_state == "locked", "one copy cannot open two-key gate")
	_pickups()[0].interact(player)
	gate.interact(player)
	_check(gate.element_state == "open", "both holders unlock actual gate")
	_check(Inventory.get_key_count("key_2_1") == 0, "gate spends both copies")
	await _visit("1,1", 1)
	_check(_pickups().is_empty(), "spent key cannot respawn in first holder")
	await _visit("2,1", 1)
	_check(_pickups().is_empty(), "spent key cannot respawn in second holder")
	await _partial_batch()
	field._map_root.queue_free()
	field.free()
	print("[key-collection] DONE %s" % ("ok" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _partial_batch() -> void:
	await _visit("3,1", 2)
	_check(_pickups().size() == 2, "two-copy batch spawns")
	var untaken_position: Vector3 = _pickups()[0].position
	_pickups()[1].interact(player)
	await get_tree().process_frame
	field._keys_collected = JSON.parse_string(JSON.stringify(field._keys_collected))
	await _visit("3,1", 2)
	_check(_pickups().size() == 1, "partial batch restores only untaken copy after reload")
	_check(_pickups()[0].position == untaken_position, "untaken copy keeps its authored slot")
	_pickups()[0].interact(player)
	await get_tree().process_frame
	await _visit("3,1", 2)
	_check(_pickups().is_empty(), "fully collected batch cannot duplicate")

func _visit(holder: String, count: int) -> void:
	for child in field._map_root.get_children():
		child.queue_free()
	await get_tree().process_frame
	field._room_keys.clear()
	field._current_cell = {"pos": holder, "key_slots": [[-3, 0, 0], [3, 0, 0]]}
	field._apply_key_spawn_policy("2,1", count)
	await get_tree().physics_frame

func _pickups() -> Array:
	return field._map_root.get_children().filter(func(n): return n is KeyPickup and not n.is_queued_for_deletion())

extends RefCounted
## Seeded spatial/snapshot checks plus independent source-reference comparisons.
static func run(t: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 761
	for i in 80:
		var angle := rng.randf_range(-PI / 3.0 + 0.01, PI / 3.0 - 0.01)
		var direction := Vector3(sin(angle), 0, cos(angle))
		t.assert_true(FieldHazard.in_cone(direction * 11.99, 12.0), "Needler inside cone/range %d" % i)
		t.assert_true(not FieldHazard.in_cone(direction * 12.01, 12.0), "Needler outside range %d" % i)
		t.assert_true(not FieldHazard.in_cone(-direction * 2.0, 12.0), "Needler behind is safe %d" % i)
	var edge := PI / 3.0 + 0.001
	t.assert_true(not FieldHazard.in_cone(Vector3(sin(edge), 0, cos(edge)) * 2.0, 12.0), "outside cone angle is safe")
	t.assert_true(not FieldHazard.in_cone(Vector3(0, 2.01, 1), 12.0), "vertically separated target is safe")
	var source_doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/environment_traps.json"))
	t.assert_eq(NeedlerTrap.RANGE, float(source_doc.needler.sweep_radius), "source Needler sweep range")
	for texture in PoisonTrap.GAS_PROFILES:
		for key in PoisonTrap.GAS_PROFILES[texture]:
			var value = source_doc.materials.o0c_poisonm[texture][key]
			if value is Array: value = Vector2(value[0], value[1])
			t.assert_eq(PoisonTrap.GAS_PROFILES[texture][key], value, "gas source transform " + texture + key)
	var root := Node3D.new()
	for kind in ["gun_trap", "burn_trap", "needler_trap", "poison_trap", "needle_trap", "capture_trap"]:
		var trap := PlacedTraps.build(kind, "off", {"rotation": 90.0, "model": "o0c_gun02", "timer": 3.25})
		root.add_child(trap) # Detached: snapshot tests do not require imported assets.
		trap.position = Vector3(2, 1, 4)
	var rows := PlacedTraps.snapshots(root)
	t.assert_eq(rows.size(), 6, "each distinct trap participates in room snapshots")
	for row in rows:
		var restored := PlacedTraps.build(row.type, row.state, row)
		t.assert_eq(restored.element_state, "off", row.type + " remains off")
		t.assert_true(is_equal_approx(restored.rotation.y, PI/2), row.type + " keeps authored facing")
		t.assert_eq(restored.model_path.get_file().get_basename(), row.model, row.type + " keeps source mesh")
		if restored is FieldHazard: t.assert_eq(restored.timer, 3.25, row.type + " keeps remaining timer")
		restored.free()
	root.free()
	var needler := NeedlerTrap.new()
	needler.element_state = "active"
	t.assert_eq(needler.save_hazard().state, "cooldown", "revisit cannot repeat an already-active Needler wave")
	needler.free()
	var rooms: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/re_reference/room_objects.json"))
	var models := {}
	for room in rooms.rooms.values():
		for obj in room.objects:
			if obj.k == "gun_trap": models[obj.m] = true
	t.assert_true(models.has("o0c_gun01") and models.has("o0c_gun02"), "authored data retains both gun variants")

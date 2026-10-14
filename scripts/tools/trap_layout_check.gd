extends RefCounted
## Spawn selected authored pools in their real rooms, then compare every trap.
static func run(tree: SceneTree) -> bool:
	var ok := true
	var rng := RandomNumberGenerator.new()
	for room in ["s02a_nc2", "s03a_lc1", "s03a_lc2", "s03a_tc3", "s01a_tb3", "s06a_ib1", "s05a_ib1", "s05a_lb1", "s07a_lb3"]:
		for seed_value in [1, 2, 14, 17, 42]:
			rng.seed = seed_value
			var mask := FieldPopulation.drawn_mask(room, 5, rng)
			var objects := FieldPopulation.authored_objects(room, 5, rng, mask)
			var expected := objects.filter(func(o): return str(o.type).ends_with("_trap"))
			SessionManager.enter_quest("debug_coliseum", "normal")
			SessionManager.set_field_sections(ColiseumRoster._one_cell_section(room, "a", "city", objects, false))
			await SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", ColiseumRoster.warp_data())
			var field := tree.current_scene
			# Field setup yields for collision before spawning authored objects.
			for frame in 120:
				if is_instance_valid(field._room_minimap): break
				await tree.physics_frame
			if not is_instance_valid(field._room_minimap):
				push_error("Trap layout field setup timed out: " + room)
				return false
			var actual: Array = []
			for node in field._map_root.get_children():
				if node is TrapBall:
					node.disarmed = true
					actual.append({"type":node.trap_id, "position":node.position})
				elif node is BearTrap:
					node.set_state("spent")
					actual.append({"type":"capture_trap", "position":node.position})
				elif node is NeedleTrap or node is FieldHazard:
					node.set_state("off")
					actual.append({"type":node.trap_kind, "position":node.position})
			var matched := actual.size() == expected.size()
			for record in expected:
				var at := Vector3(float(record.position[0]), float(record.position[1]), float(record.position[2]))
				var index := -1
				for i in actual.size():
					if actual[i].type == record.type and actual[i].position.distance_to(at) < 0.02:
						index = i
						break
				if index < 0: matched = false
				else: actual.remove_at(index)
			ok = matched and ok
			print("[trap-layout] %s room=%s seed=%d mask=%d expected=%s unmatched=%s" % ["PASS" if matched else "FAIL", room, seed_value, mask, JSON.stringify(expected), str(actual)])
	return ok

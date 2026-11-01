extends RefCounted
const PGM := preload("res://scripts/3d/field/portal_gate_manager.gd")

static func run(t) -> void:
	generated_split(t)
	var state := {"2,1": true}
	var a := PGM.key_tracking_id("1,1", "2,1")
	var b := PGM.key_tracking_id("2,1", "2,1")
	t.assert_eq(PGM.pending_key_indices(state, a, 1), [0], "legacy gate flag cannot suppress holder A")
	PGM.record_key_collection(state, a, 0, 1)
	t.assert_eq(PGM.pending_key_indices(state, a, 1), [], "collected holder stays collected")
	t.assert_eq(PGM.pending_key_indices(state, b, 1), [0], "second holder still supplies two-key gate")
	PGM.record_key_collection(state, b, 1, 2)
	state = JSON.parse_string(JSON.stringify(state))
	t.assert_eq(PGM.pending_key_indices(state, b, 2), [0], "partial batch survives JSON reload without duplicates")
	PGM.record_key_collection(state, b, 0, 2)
	t.assert_eq(PGM.pending_key_indices(state, b, 2), [], "completed batch cannot respawn")
	t.assert_true(state[b], "completed composite remains compatible with quest-plan guard")

static func generated_split(t) -> void:
	const Grid := preload("res://scripts/3d/field/grid_generator.gd")
	var splits := 0
	for seed_value in range(20):
		var generator = Grid.new()
		generator.set_seed(seed_value)
		for section in generator.generate_field("normal", "rioh")["sections"]:
			var holders := {}
			for cell in section.get("cells", []):
				if not cell.get("has_key", false):
					continue
				var target: String = cell.get("key_for_cell", "")
				var tracking := PGM.key_tracking_id(cell["pos"], target)
				if holders.has(target):
					var state := {str(holders[target]): true}
					t.assert_true(not PGM.pending_key_indices(state, tracking, cell.get("key_count", 1)).is_empty(),
						"seed %d: collecting first holder preserves second" % seed_value)
					splits += 1
				holders[target] = tracking
	t.assert_true(splits > 0, "seeded Rioh sweep exercises split two-key gates")

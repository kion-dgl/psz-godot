extends RefCounted
static func run(runner: Node) -> void:
	var rules = load("res://scripts/3d/field/section_entry.gd")
	var section := {"start_pos": "6,3", "entry_direction": "south"}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1101
	for i in range(16):
		var direction: String = ["north", "south", "east", "west"][rng.randi_range(0, 3)]
		runner.assert_eq(rules.resolve(direction, "6,3", section), direction, "explicit entry survives section fallback")
	runner.assert_eq(rules.resolve("", "6,3", section), "south", "section-selector entry uses south")
	runner.assert_eq(rules.resolve("", "5,3", section), "", "interior cells do not inherit section entry")
	runner.assert_eq(rules.resolve("", "6,3", {"start_pos": "6,3"}), "", "legacy section without entry stays compatible")

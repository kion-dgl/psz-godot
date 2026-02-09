extends Node
## Test launcher for valley field — uses GridGenerator to create a full
## multi-section field (a→e→b→z) and transitions to the 3D valley field scene.

const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")

func _ready() -> void:
	# Set up a field session
	SessionManager.enter_field("gurhacia", "normal")

	# Generate a full field with 4 sections
	var gen := GridGenerator.new()
	var field: Dictionary = gen.generate_field("normal")
	var sections: Array = field["sections"]

	print("[ValleyFieldTest] Generated %d sections:" % sections.size())
	for i in range(sections.size()):
		var s: Dictionary = sections[i]
		var cell_count: int = s.get("cells", []).size()
		print("  Section %d: type=%s area=%s cells=%d start=%s" % [
			i, s.get("type", "?"), s.get("area", "?"), cell_count, s.get("start_pos", "?")])

	SessionManager.set_field_sections(sections)

	# Start at the first section's start cell
	var first_section: Dictionary = sections[0]
	SceneManager.goto_scene("res://scenes/3d/field/valley_field.tscn", {
		"current_cell_pos": str(first_section["start_pos"]),
		"spawn_edge": "",
		"keys_collected": {},
	})

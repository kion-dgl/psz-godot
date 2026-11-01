extends Node
const Generator := preload("res://scripts/3d/field/grid_generator.gd")
const Variants := preload("res://scripts/utils/stage_mirror_variants.gd")
const FIELD := preload("res://scenes/3d/field/valley_field.tscn")
func _ready() -> void:
	CharacterManager.create_character(0, "humar", "Stage Smoke")
	CharacterManager.set_active_slot(0)
	var checked := 0
	var failed := 0
	for area in ["gurhacia", "ozette", "rioh", "makara", "paru", "arca", "dark", "tower"]:
		SessionManager.enter_field(area, "normal")
		var generator := Generator.new()
		generator.set_seed(381)
		var sections: Array = generator.generate_tower_field("normal")["sections"] if area == "tower" else generator.generate_field("normal", area)["sections"]
		SessionManager.set_field_sections(sections)
		for section in range(sections.size()):
			SessionManager.set_current_section(section)
			SceneManager._transition_data = {"current_cell_pos": str(sections[section]["start_pos"]), "spawn_edge": "", "keys_collected": {}}
			var field := FIELD.instantiate()
			add_child(field)
			for frame in range(6):
				await get_tree().process_frame
			var model: Node = field.get("_map_root")
			var expected: bool = model != null and Variants.manifest().stages.has(model.scene_file_path)
			var applied: bool = model != null and model.has_meta("native_mirror_applied")
			if model == null or (expected and not applied and not OS.has_environment("PSZ_NATIVE_MIRROR_DISABLE")):
				failed += 1
			checked += 1
			print("[stage-smoke] %s section %d: expected=%s applied=%s" % [area, section, expected, applied])
			field.queue_free()
			await get_tree().process_frame
	print("[stage-smoke] %d section entries; %d failures" % [checked, failed])
	get_tree().quit(1 if failed else 0)

extends Node3D
## Isolated entry diagnostic: real Valley B controller, no live-save mutations.
var field: Node3D

func _ready() -> void:
	if ProjectSettings.get_setting("application/config/name") != "PSZ Playtest Verification":
		push_error("Run this diagnostic in the isolated PSZ Playtest Verification project.")
		get_tree().quit(1)
		return
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "EntryDebug")
	CharacterManager.set_active_slot(0)
	var generator := preload("res://scripts/3d/field/grid_generator.gd").new()
	generator.set_seed(1101)
	var sections: Array = generator.generate_field("normal", "gurhacia").sections
	# Deliberately emulate an old retained field with the former reversed IDs.
	for cell in sections[2].cells:
		if cell.stage_id == "s01b_sa1":
			cell.portals = {"north": "portal_1769178737883_7bppcx8w1", "south": "portal_1769178748150_zpfcscb89"}
	SessionManager.enter_field("gurhacia", "normal")
	SessionManager.set_field_sections(sections)
	SessionManager.set_current_section(2)
	SceneManager._transition_data = {"current_cell_pos": sections[2].start_pos, "spawn_edge": sections[2].entry_direction}
	field = preload("res://scenes/3d/field/valley_field.tscn").instantiate()
	add_child(field)
	await get_tree().create_timer(2).timeout
	print("[entry-debug] root=", field._map_root.global_transform, " player=", field.player.global_position, " entry=", field._spawn_edge)
	for direction in ["north", "south"]:
		var portal: Dictionary = field._portal_data[direction]
		var label := Label3D.new()
		label.text = direction.to_upper()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 80
		add_child(label)
		label.global_position = portal.gate_pos + Vector3.UP * 4
		print("[entry-debug] ", direction, " gate=", portal.gate_pos, " spawn=", portal.spawn_pos)
	var map: Control = field._room_minimap
	map.update_player(field.player.global_position, 0, field._map_root)
	print("[entry-debug] player map=", map._player_display_pos)
	for gate in map._gate_entries:
		print("[entry-debug] map ", gate.dir, "=", map._svg_to_display(gate.center))
	var markers := {}
	for gate in map._gate_entries:
		markers[gate.dir] = map._svg_to_display(gate.center)
	var passed: bool = field._spawn_edge == "south" and field._portal_data.south.id == "portal_1769178737883_7bppcx8w1" \
		and map._player_display_pos.distance_to(markers.south) < map._player_display_pos.distance_to(markers.north)
	print("[entry-debug] thematic south portal + minimap alignment: ", "PASS" if passed else "FAIL")
	var canvas := CanvasLayer.new()
	canvas.layer = 300
	add_child(canvas)
	var caption := Label.new()
	caption.position = Vector2(20, 200)
	caption.text = "VALLEY B ENTRY DEBUG\nSpawn: SOUTH / Valley E transition\nNORTH: planked slope into Valley B\nR: reset arrival  |  Esc: quit"
	caption.add_theme_font_size_override("font_size", 22)
	canvas.add_child(caption)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if passed else 1)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			field.player.global_position = field._portal_data.south.spawn_pos
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()

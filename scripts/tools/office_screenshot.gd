extends Node
## One-shot office render harness (#356). Sets up a minimal character, loads
## the city_office scene, lets it settle, saves a framebuffer PNG, and quits.
## Run under xvfb with the offline manifest (pack textures + principal GLB live
## in the pack). NOT shipped/registered anywhere — a dev screenshot tool.
##
##   xvfb-run -a godot --path . res://scenes/tools/office_screenshot.tscn

func _ready() -> void:
	await get_tree().process_frame
	# A character so the office's _spawn_player / HUD have valid state.
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "ShotHero")
	CharacterManager.set_active_slot(0)
	CharacterManager._sync_to_game_state()
	# Plain office (no intro/briefing): clear any spawn key.
	if CityState.has_method("clear"):
		CityState.clear()
	# Instance as a child of root (NOT change_scene — that frees this harness
	# node, killing the await below). The office's own Camera3D becomes current
	# and renders to the root viewport we capture.
	var office: Node = load("res://scenes/3d/city/city_office.tscn").instantiate()
	get_tree().root.add_child(office)
	# Let textures stream, lights/emission settle, player+camera spawn.
	await get_tree().create_timer(2.0).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://office_shot.png")
	print("[office-shot] saved user://office_shot.png (%dx%d)" % [img.get_width(), img.get_height()])
	# A dedicated camera keeps the inspection shot inside the room. Moving
	# the player sideways placed the follow camera inside an entrance column.
	var inspection_camera := Camera3D.new()
	office.add_child(inspection_camera)
	inspection_camera.position = Vector3(4.0, 4.1, 4.8)
	inspection_camera.look_at(Vector3(0, 3.3, -4.5))
	inspection_camera.make_current()
	await get_tree().create_timer(0.5).timeout
	var img2: Image = get_viewport().get_texture().get_image()
	img2.save_png("user://office_shot_angle.png")
	print("[office-shot] saved user://office_shot_angle.png")
	await get_tree().process_frame
	get_tree().quit()

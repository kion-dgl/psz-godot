extends Node
## Headless transition diagnostic (not shipped). Loads city_counter, teleports
## the player onto a named exit trigger, and lets the [diag ...] logging in
## city_area_base reveal where each scene spawns the player — to catch bounce
## loops. Run:
##   PSZ_DIAG=1 PSZ_DIAG_TARGET=counter-exit godot --path . res://scenes/tools/transition_diag.tscn

func _init() -> void:
	ProjectSettings.load_resource_pack(ProjectSettings.globalize_path("res://dist/assets.pck"), false)

func _ready() -> void:
	await get_tree().process_frame
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "Diag")
	CharacterManager.set_active_slot(0)
	CharacterManager._sync_to_game_state()
	if CityState.has_method("clear"):
		CityState.clear()
	var counter: Node = load("res://scenes/3d/city/city_counter.tscn").instantiate()
	add_child(counter)
	await get_tree().create_timer(2.0).timeout
	var key: String = OS.get_environment("PSZ_DIAG_TARGET")
	if key == "":
		key = "counter-exit"
	var trig: Node3D = counter.find_child("AreaTrigger_%s" % key, true, false)
	var player: Node3D = get_tree().get_first_node_in_group("player")
	if trig and player:
		print("[diag] teleport player -> trigger '%s' at %s" % [key, str(trig.global_position)])
		player.global_position = trig.global_position
	else:
		print("[diag] MISSING trig=%s player=%s" % [str(trig), str(player)])
	# After the transition, this node is freed; the [diag] logs continue. The
	# outer `timeout` kills the process.
	await get_tree().create_timer(8.0).timeout
	get_tree().quit()

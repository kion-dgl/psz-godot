extends Node3D
class_name CityAreaBase
## Base class for all 3D city area controllers (Market, Counter, Warp).
## Provides shared logic for spawning the player, camera, NPCs, and triggers.

const PLAYER_SCENE := preload("res://scenes/3d/player/player.tscn")
const ORBIT_CAMERA_SCENE := preload("res://scenes/3d/camera/orbit_camera.tscn")
const FieldHudScript := preload("res://scripts/3d/field/field_hud.gd")

var player: CharacterBody3D
var orbit_camera: Node3D
var _npcs: Array[CityNPC] = []
var _warp_pads: Array[WarpPad] = []


func _spawn_player(default_pos: Vector3, default_rot: float, spawn_variants: Dictionary) -> CharacterBody3D:
	player = PLAYER_SCENE.instantiate()
	add_child(player)

	# Determine spawn position
	var spawn_key: String = CityState.get_spawn_key()
	if spawn_key in spawn_variants:
		var variant: Dictionary = spawn_variants[spawn_key]
		player.global_position = variant.get("position", default_pos)
		player.player_rotation = variant.get("rotation", default_rot)
	elif CityState.get_player_position() != null and CityState.get_area() == _get_area_name():
		player.global_position = CityState.get_player_position()
		player.player_rotation = CityState.get_player_rotation()
	else:
		player.global_position = default_pos
		player.player_rotation = default_rot

	player.spawn_position = player.global_position
	CityState.set_spawn_key("")

	# Add field HUD (stats panel + meseta)
	var field_hud := FieldHudScript.new()
	add_child(field_hud)

	return player


func _setup_camera(target: Node3D) -> Node3D:
	orbit_camera = ORBIT_CAMERA_SCENE.instantiate()
	add_child(orbit_camera)
	orbit_camera.set_target(target)
	return orbit_camera


func _add_npc(npc_name: String, pos: Vector3, rot: float, model_path: String, display_name: String, target_scene: String) -> CityNPC:
	var npc := CityNPC.new()
	npc.name = npc_name
	npc.npc_model_path = model_path
	npc.npc_display_name = display_name
	npc.target_scene_path = target_scene
	npc.npc_rotation_y = rot
	npc.position = pos
	add_child(npc)
	_npcs.append(npc)
	return npc


func _add_warp_pad(pad_name: String, pos: Vector3, area_id: String, display_name: String) -> WarpPad:
	var pad := WarpPad.new()
	pad.name = pad_name
	pad.area_id = area_id
	pad.display_name = display_name
	pad.position = pos
	add_child(pad)
	_warp_pads.append(pad)
	return pad


func _add_area_trigger(pos: Vector3, trigger_size: Vector3, target_scene: String, spawn_key: String) -> Area3D:
	var area := Area3D.new()
	area.name = "AreaTrigger_%s" % spawn_key
	area.collision_layer = 4  # Triggers layer
	area.collision_mask = 2   # Player layer
	area.position = pos

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = trigger_size
	shape.shape = box
	area.add_child(shape)

	area.body_entered.connect(func(_body: Node3D) -> void:
		if _body.is_in_group("player") or _body.name == "Player":
			_save_and_transition(target_scene, spawn_key)
	)

	add_child(area)
	return area


func _add_floor_collision(center: Vector3, floor_size: Vector3 = Vector3(50, 0.2, 70)) -> void:
	var body := StaticBody3D.new()
	body.name = "FloorCollision"
	body.collision_layer = 1  # Environment
	body.collision_mask = 0
	body.position = Vector3(center.x, 0, center.z)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = floor_size
	shape.shape = box
	shape.position.y = -floor_size.y / 2.0

	body.add_child(shape)
	add_child(body)


func _heal_character() -> void:
	var character = CharacterManager.get_active_character()
	if character:
		character["hp"] = int(character.get("max_hp", 100))
		character["pp"] = int(character.get("max_pp", 50))
		CharacterManager._sync_to_game_state()


func _save_player_state() -> void:
	if player and is_instance_valid(player):
		CityState.save_player_state(player.global_position, player.player_rotation, _get_area_name())


func _save_and_transition(target_scene: String, spawn_key: String) -> void:
	CityState.set_spawn_key(spawn_key)
	SceneManager.goto_scene(target_scene)


func _connect_player_to_interactables() -> void:
	for npc in _npcs:
		npc.set_player(player)
	for pad in _warp_pads:
		pad.set_player(player)


func _handle_esc() -> void:
	_save_player_state()
	SceneManager.push_scene("res://scenes/3d/city/city_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_handle_esc()
		get_viewport().set_input_as_handled()


## Override in subclasses to return the area identifier string.
func _get_area_name() -> String:
	return ""

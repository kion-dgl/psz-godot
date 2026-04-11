extends Node3D
class_name CityAreaBase
## Base class for all 3D city area controllers (Market, Counter, Warp).
## Provides shared logic for spawning the player, camera, NPCs, and triggers.

const PLAYER_SCENE := preload("res://scenes/3d/player/player.tscn")
const ORBIT_CAMERA_SCENE := preload("res://scenes/3d/camera/orbit_camera.tscn")
const FieldHudScript := preload("res://scripts/3d/field/field_hud.gd")
const TEXTURE_FIX_SHADER := preload("res://scripts/3d/field/texture_fix_shader.gdshader")
const WATERFALL_SHADER := preload("res://scripts/3d/field/waterfall_shader.gdshader")

## Textures that are baked shadow/lightmap overlays — hide meshes using them.
const SHADOW_TEXTURES := ["s00_1_gr1.png", "s00_0_gr1.png"]

## Static cache for global texture fixes (shared across all city area instances).
static var _global_texture_fixes: Dictionary = {}

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

	# Play city music based on area name
	var area_name: String = _get_area_name()
	if area_name == "office":
		MusicManager.play_location_music("office")
	elif area_name == "warp":
		MusicManager.play_location_music("teleporter")
	else:
		MusicManager.play_location_music("city")

	# Add field HUD (stats panel + meseta)
	var field_hud := FieldHudScript.new()
	add_child(field_hud)

	return player


func _setup_camera(target: Node3D) -> Node3D:
	orbit_camera = ORBIT_CAMERA_SCENE.instantiate()
	add_child(orbit_camera)
	orbit_camera.set_target(target)
	return orbit_camera


func _add_npc(npc_name: String, pos: Vector3, rot: float, model_path: String, display_name: String, target_scene: String, npc_idle_anim: String = "") -> CityNPC:
	var npc := CityNPC.new()
	npc.name = npc_name
	npc.npc_model_path = model_path
	npc.npc_display_name = display_name
	npc.target_scene_path = target_scene
	npc.npc_rotation_y = rot
	npc.idle_anim = npc_idle_anim
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


var _interactive_triggers: Array[GameElement] = []


func _add_interactive_trigger(pos: Vector3, trigger_size: Vector3, target_scene: String, spawn_key: String, prompt_text: String) -> GameElement:
	var trigger := GameElement.new()
	trigger.name = "InteractiveTrigger_%s" % spawn_key
	trigger.interactable = true
	trigger.collision_size = trigger_size
	trigger.position = pos
	add_child(trigger)

	# Prompt label
	var label := Label3D.new()
	label.text = prompt_text
	label.font_size = 32
	label.pixel_size = 0.01
	label.position = Vector3(0, 2.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(1, 0.8, 0)
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0)
	label.visible = false
	trigger.add_child(label)
	trigger.set_meta("_prompt_label", label)

	# Transition on interact
	trigger.interacted.connect(func(_p: Node3D) -> void:
		_save_and_transition(target_scene, spawn_key)
	)

	_interactive_triggers.append(trigger)
	return trigger


func _process(_delta: float) -> void:
	if not player or not is_instance_valid(player):
		return
	for trigger in _interactive_triggers:
		if is_instance_valid(trigger):
			var label: Label3D = trigger.get_meta("_prompt_label")
			label.visible = player.get_nearest_interactable() == trigger


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
	# Pause/Start handled by PsoStartMenu autoload
	pass


## Override in subclasses to return the area identifier string.
func _get_area_name() -> String:
	return ""


func _fix_city_materials() -> void:
	## Apply texture fixes from global-texture-fixes.json to all city GLB meshes.
	_load_global_texture_fixes()
	_fix_materials_recursive(self)


func _override_vertex_colors(enabled: bool) -> void:
	## Override vertex_color_use_as_albedo on all StandardMaterial3D in the scene.
	_set_vertex_colors_recursive(self, enabled)


func _set_vertex_colors_recursive(node: Node, enabled: bool) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				mat.vertex_color_use_as_albedo = enabled
	for child in node.get_children():
		_set_vertex_colors_recursive(child, enabled)


func _add_interior_lights(positions: Array = []) -> void:
	## Add warm OmniLight3D sources at the given positions.
	## If no positions given, place a default grid of lights.
	if positions.is_empty():
		positions = [Vector3(0, 4, 0), Vector3(0, 4, -10), Vector3(0, 4, 10)]
	for i in range(positions.size()):
		var light := OmniLight3D.new()
		light.name = "InteriorLight_%d" % i
		light.light_color = Color(1.0, 0.95, 0.88)
		light.light_energy = 2.0
		light.omni_range = 15.0
		light.omni_attenuation = 1.0
		light.shadow_enabled = false
		light.position = positions[i]
		add_child(light)
	print("[CityLights] Added %d interior lights" % positions.size())


static func _load_global_texture_fixes() -> void:
	if not _global_texture_fixes.is_empty():
		return
	var gtf_path := "res://data/stage_configs/global-texture-fixes.json"
	var gtf_file := FileAccess.open(gtf_path, FileAccess.READ)
	if gtf_file:
		if gtf_file:
			var gtf_json := JSON.new()
			if gtf_json.parse(gtf_file.get_as_text()) == OK:
				_global_texture_fixes = gtf_json.data as Dictionary
				print("[CityArea] Loaded global texture fixes: %d entries" % _global_texture_fixes.size())
			gtf_file.close()


static func _find_global_fix_for_material(mat: StandardMaterial3D) -> Dictionary:
	if not mat.albedo_texture or _global_texture_fixes.is_empty():
		return {}
	var tex_path: String = mat.albedo_texture.resource_path
	var tex_basename: String = tex_path.get_file()
	for suffix in ["#1", "#0", ""]:
		var key: String = tex_basename + suffix
		if _global_texture_fixes.has(key):
			return _global_texture_fixes[key] as Dictionary
	return {}


static func _wrap_mode_int(mode: String) -> int:
	match mode:
		"mirror": return 1
		"clamp": return 2
	return 0  # repeat


func _fix_materials_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var std_mat := mat as StandardMaterial3D
				# Hide baked shadow/lightmap surface with a fully transparent material
				if std_mat.albedo_texture:
					var tex_file: String = std_mat.albedo_texture.resource_path.get_file()
					if tex_file in SHADOW_TEXTURES:
						var hide_mat := StandardMaterial3D.new()
						hide_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						hide_mat.albedo_color = Color(0, 0, 0, 0)
						hide_mat.no_depth_test = true
						mesh_inst.set_surface_override_material(i, hide_mat)
						continue
				var fix := _find_global_fix_for_material(std_mat)
				var has_scroll := fix.has("scrollX") or fix.has("scrollY")
				var is_waterfall := has_scroll or (std_mat.albedo_texture and "_fall" in std_mat.albedo_texture.resource_path)
				var needs_shader := not fix.is_empty() and (
					is_waterfall or
					str(fix.get("wrapS", "repeat")) == "mirror" or
					str(fix.get("wrapT", "repeat")) == "mirror")
				if is_waterfall:
					var shader_mat := ShaderMaterial.new()
					shader_mat.shader = WATERFALL_SHADER
					if std_mat.albedo_texture:
						shader_mat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
					shader_mat.set_shader_parameter("albedo_color", std_mat.albedo_color)
					shader_mat.set_shader_parameter("uv_scale", Vector3(fix.get("repeatX", 1.0), fix.get("repeatY", 1.0), 1.0))
					shader_mat.set_shader_parameter("uv_offset", Vector3(fix.get("offsetX", 0.0), fix.get("offsetY", 0.0), 0.0))
					var scroll_x: float = fix.get("scrollX", 0.0)
					var scroll_y: float = fix.get("scrollY", -0.35)
					shader_mat.set_shader_parameter("uv_scroll", Vector2(scroll_x, scroll_y))
					shader_mat.render_priority = 1
					mesh_inst.set_surface_override_material(i, shader_mat)
				elif needs_shader:
					var shader_mat := ShaderMaterial.new()
					shader_mat.shader = TEXTURE_FIX_SHADER
					if std_mat.albedo_texture:
						shader_mat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
					shader_mat.set_shader_parameter("albedo_color", std_mat.albedo_color)
					shader_mat.set_shader_parameter("uv_scale", Vector3(fix.get("repeatX", 1.0), fix.get("repeatY", 1.0), 1.0))
					shader_mat.set_shader_parameter("uv_offset", Vector3(fix.get("offsetX", 0.0), fix.get("offsetY", 0.0), 0.0))
					shader_mat.set_shader_parameter("wrap_s", _wrap_mode_int(str(fix.get("wrapS", "repeat"))))
					shader_mat.set_shader_parameter("wrap_t", _wrap_mode_int(str(fix.get("wrapT", "repeat"))))
					mesh_inst.set_surface_override_material(i, shader_mat)
				else:
					var new_mat := std_mat.duplicate() as StandardMaterial3D
					# PER_VERTEX so lights affect the geometry
					new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
					new_mat.vertex_color_use_as_albedo = true
					new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					new_mat.alpha_scissor_threshold = 0.1
					new_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
					new_mat.texture_repeat = true
					if not fix.is_empty():
						new_mat.uv1_scale = Vector3(fix.get("repeatX", 1.0), fix.get("repeatY", 1.0), 1.0)
						new_mat.uv1_offset = Vector3(fix.get("offsetX", 0.0), fix.get("offsetY", 0.0), 0.0)
						if str(fix.get("wrapS", "repeat")) == "clamp" or str(fix.get("wrapT", "repeat")) == "clamp":
							new_mat.texture_repeat = false
					mesh_inst.set_surface_override_material(i, new_mat)
	for child in node.get_children():
		_fix_materials_recursive(child)

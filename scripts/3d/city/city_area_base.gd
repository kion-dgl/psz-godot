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
var _pos_overlay: Label  # Toggled by DebugConfig.show_player_position

# Diegetic shop view (spec /states/shops#presentation). While a shop is open the
# camera holds a fixed pose in front of the shopkeeper and the player is ghosted.
var _shop_open := false
var _shop_overlay: Node
var _shop_prev_fov := 50.0
# Fixed shop-camera pose relative to the NPC. Tunable — matches the web mock
# (Style A). Distance/height/look are metres; H_OFFSET shifts the frustum so the
# NPC sits on the screen-right (negative = subject moves right); FOV narrows the
# shot vs. the 50° gameplay camera.
const SHOP_CAM_DIST := 4.3
const SHOP_CAM_HEIGHT := 2.05
const SHOP_LOOK_HEIGHT := 1.3
const SHOP_CAM_FOV := 42.0
const SHOP_CAM_H_OFFSET := -1.15
const SHOP_CAM_TWEEN := 0.35



func _spawn_player(default_pos: Vector3, default_rot: float, spawn_variants: Dictionary) -> CharacterBody3D:
	player = PLAYER_SCENE.instantiate()
	add_child(player)

	# Determine spawn position
	var spawn_key: String = CityState.get_spawn_key()
	# PSZ_CITY_SPAWN="x,y,z": station probe — boot the player at a chosen
	# spot (the in-game counterpart of the labs' PSZ_WALK_TELEPORT). With
	# PSZ_CITY_DUMP this reads a station from inside the running game.
	var probe_spawn := OS.get_environment("PSZ_CITY_SPAWN")
	var probe_xyz := probe_spawn.split(",")
	if not probe_spawn.is_empty() and probe_xyz.size() == 3:
		player.global_position = Vector3(
			probe_xyz[0].to_float(), probe_xyz[1].to_float(), probe_xyz[2].to_float())
		player.player_rotation = default_rot
	elif spawn_key in spawn_variants:
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
	# Player model GLB is unlit + normal-less like the rooms — lit materials
	# and smoothed normals so lights reach it (#646, the field's spawn
	# contract). Without this the city omnis light the floor but the actor
	# stays pure bake (#669: the certified rig has the character lit BY the
	# placed lights — the walk labs spawn through the same pair).
	SmoothNormals.ensure(player, 2)
	SmoothNormals.make_lit(player)
	if OS.has_environment("PSZ_DIAG"):
		print("[diag spawn] area=%s key=%s pos=%s" % [_get_area_name(), spawn_key, str(player.global_position)])
	CityState.set_spawn_key("")

	# Force-sync SessionManager location to "city" — without this, a player
	# who went field → title → Dairon would leave _location = "field" and
	# the field HUD would treat Dairon as combat (showing the palette).
	SessionManager.set_location("city")

	# Play city music based on area name
	var area_name: String = _get_area_name()
	if area_name == "office":
		MusicManager.play_location_music("office")
	elif area_name == "warp":
		MusicManager.play_location_music("teleporter")
	else:
		MusicManager.play_location_music("city")

	# Add per-scene field HUD (palette / log / FPS). The HP/PP/Lv stats panel
	# is NOT here — it lives on the persistent HudStats autoload (#444).
	var field_hud := FieldHudScript.new()
	add_child(field_hud)

	return player


func _setup_camera(target: Node3D) -> Node3D:
	orbit_camera = ORBIT_CAMERA_SCENE.instantiate()
	add_child(orbit_camera)
	orbit_camera.set_target(target)
	return orbit_camera


func _add_npc(npc_name: String, pos: Vector3, rot: float, model_path: String, display_name: String, target_scene: String, npc_idle_anim: String = "", hat_path: String = "", interact_anim: String = "", interact_size: Vector3 = Vector3(2, 2, 2)) -> CityNPC:
	var npc := CityNPC.new()
	npc.name = npc_name
	npc.npc_model_path = model_path
	npc.npc_display_name = display_name
	npc.target_scene_path = target_scene
	npc.npc_rotation_y = rot
	npc.idle_anim = npc_idle_anim
	npc.hat_model_path = hat_path
	npc.interact_anim = interact_anim
	# Interaction box (set before add_child so _setup_collision picks it up).
	# Counter NPCs stand off the walkable floor, so widen the box to reach the
	# player at the counter front (player interaction radius is only 2.0).
	npc.collision_size = interact_size
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


## PSZ_CITY_DUMP companion: what stage surfaces render underfoot? Raycasts
## the scene's live world-space triangles from above the player down and
## prints the top hits with each surface's shading mode — the read that
## settled #669 (which mesh IS the walkable floor, and is it per-pixel?).
func _dump_underfoot_hits(feet: Vector3) -> void:
	var from := feet + Vector3.UP * 8.0
	var to := feet + Vector3.DOWN * 2.0
	var hits: Array = []
	for node in MeshUtils.collect_mesh_instances(self, []):
		var mi := node as MeshInstance3D
		if mi.is_inside_tree() and ("FloorCollision" in str(mi.get_path())
				or "Player" in str(mi.get_path())):
			continue
		var mesh := mi.mesh as ArrayMesh
		if mesh == null:
			continue
		for i in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(i)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var xform := mi.global_transform
			for t in range(0, verts.size() - 2, 3):
				var hit: Variant = Geometry3D.ray_intersects_triangle(from, to,
					xform * verts[t], xform * verts[t + 1], xform * verts[t + 2])
				if hit != null:
					var mat: Material = mi.get_active_material(i)
					var mode := "n/a"
					if mat is StandardMaterial3D:
						mode = str((mat as StandardMaterial3D).shading_mode)
					hits.append([(hit as Vector3).y,
						"%s[%d]'%s' shaded=%s" % [mi.name, i, mat.resource_name, mode]])
	hits.sort_custom(func(a, b): return a[0] > b[0])
	for i in mini(3, hits.size()):
		print("[CityDump] underfoot hit %d: y=%.2f %s" % [i + 1, hits[i][0], hits[i][1]])
	if hits.is_empty():
		print("[CityDump] underfoot hit: NONE (nothing renders under the player)")


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


var _dump_checked := false
var _dump_frame := -1
var _dump_path := ""


func _process(_delta: float) -> void:
	# PSZ_CITY_DUMP=/tmp/x.png: the game's own eyes — after 90 frames,
	# print every light's live state and save the viewport (the lab boots
	# kept disagreeing with kion's window; this reports from inside).
	if not _dump_checked:
		_dump_checked = true
		_dump_path = OS.get_environment("PSZ_CITY_DUMP")
		if "%s" in _dump_path:
			_dump_path = _dump_path % get_scene_file_path().get_file().get_basename()
		if not _dump_path.is_empty():
			_dump_frame = 0
			# Probe runs must keep compositing: macOS throttles occluded
			# windows to a standstill (the labs' station lesson) and the
			# frame counter never reaches the dump frame.
			get_window().always_on_top = true
	if _dump_frame >= 0:
		_dump_frame += 1
		if _dump_frame == 240:
			if player and is_instance_valid(player):
				var pbox := MeshUtils.global_mesh_aabb(player)
				print("[CityDump] player pos=%s (settled)  mesh y %s..%s" % [
					player.global_position.round(),
					"%.2f" % pbox.position.y if pbox.size != Vector3.ZERO else "?",
					"%.2f" % pbox.end.y if pbox.size != Vector3.ZERO else "?"])
				_dump_underfoot_hits(player.global_position)
			var cam := get_viewport().get_camera_3d()
			if cam:
				print("[CityDump] cam pos=%s  xform=%s" % [
					cam.global_position.round(), cam.global_transform])
			for child in get_children():
				if child is OmniLight3D:
					var l := child as OmniLight3D
					print("[CityDump] %s e=%.2f shadows=%s pos=%s" % [
						l.name, l.light_energy, l.shadow_enabled, l.global_position.round()])
				if child is DirectionalLight3D:
					var d := child as DirectionalLight3D
					print("[CityDump] SUN %s e=%.2f shadows=%s" % [
						d.name, d.light_energy, d.shadow_enabled])
			var img := get_viewport().get_texture().get_image()
			img.save_png(_dump_path)
			print("[CityDump] frame → %s" % _dump_path)
			_dump_frame = -1
	if not player or not is_instance_valid(player):
		return
	for trigger in _interactive_triggers:
		if is_instance_valid(trigger):
			var label: Label3D = trigger.get_meta("_prompt_label")
			label.visible = player.nearest_interactable == trigger
	_update_position_overlay()


func _update_position_overlay() -> void:
	if not DebugConfig.show_player_position:
		if _pos_overlay and is_instance_valid(_pos_overlay):
			_pos_overlay.visible = false
		return
	if not _pos_overlay or not is_instance_valid(_pos_overlay):
		var canvas := CanvasLayer.new()
		canvas.layer = 90
		add_child(canvas)
		_pos_overlay = Label.new()
		_pos_overlay.position = Vector2(8, 4)
		_pos_overlay.add_theme_font_size_override("font_size", 18)
		_pos_overlay.add_theme_color_override("font_color", Color(1, 1, 0.6))
		_pos_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
		_pos_overlay.add_theme_constant_override("outline_size", 4)
		canvas.add_child(_pos_overlay)
	_pos_overlay.visible = true
	var p: Vector3 = player.global_position
	var rot: float = player.player_rotation if "player_rotation" in player else player.rotation.y
	var deg: float = rad_to_deg(rot)
	_pos_overlay.text = "pos: (%.2f, %.2f, %.2f)  rot: %.2f rad (%.0f°)" % [p.x, p.y, p.z, rot, deg]


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


## Build a trimesh floor collider from a hand-authored -floor.glb (the walkable
## surface selected in the floor-collider web tool), offset into the scene's
## frame. Used where a flat box won't do — e.g. a stage with a slope/stairs.
## MapCollisionBuilder makes a StaticBody3D + trimesh shape per mesh and hides
## the visual (collision-only). No top-face filtering: the source is already a
## hand-picked walkable surface.
func _add_trimesh_floor(glb_path: String, offset: Vector3) -> void:
	var packed: PackedScene = load(glb_path)
	if packed == null:
		push_error("[city] floor collider not found: %s" % glb_path)
		return
	var holder := packed.instantiate()
	holder.name = "FloorCollision"
	holder.position = offset
	add_child(holder)
	# Build the trimesh StaticBody3D as a CHILD of each MeshInstance3D so it
	# inherits the mesh's world transform (the holder offset) exactly once. Don't
	# use MapCollisionBuilder here: it sets body.global_transform before the body
	# is in the tree, which double-applies the offset under a non-identity root.
	for mi in MeshUtils.collect_mesh_instances(holder, []):
		if mi.mesh == null:
			continue
		var shape: Shape3D = mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = "collision_floor"
		body.collision_layer = 1  # Environment
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
		mi.visible = false


func _heal_character() -> void:
	var character = CharacterManager.get_active_character()
	if character:
		character["hp"] = int(character.get("max_hp", 100))
		character["pp"] = int(character.get("max_pp", 50))
		CharacterManager._sync_to_game_state()


func _save_player_state() -> void:
	if player and is_instance_valid(player):
		CityState.save_player_state(player.global_position, player.player_rotation, _get_area_name())


## Open a shop diegetically: tween the camera to a fixed pose in front of the
## NPC (framed screen-right), ghost + freeze the player, then push the shop UI as
## a near-undimmed overlay over the still-rendered 3D city. Called by CityNPC on
## interaction. Falls back to the plain full-screen push when refs are missing.
func open_shop_view(npc: Node3D, scene_path: String, data: Dictionary = {}) -> void:
	if _shop_open:
		return
	if not (is_instance_valid(orbit_camera) and is_instance_valid(player) and orbit_camera.has_method("begin_shop_focus")):
		_save_player_state()
		SceneManager.push_scene(scene_path, data)
		return
	_shop_open = true
	_save_player_state()

	# Variant locals so the dynamic members (Camera3D handle, PlayerState enum)
	# resolve at runtime — orbit_camera/player are typed Node3D/CharacterBody3D.
	var oc: Variant = orbit_camera
	var pl: Variant = player
	var cam: Camera3D = oc.camera
	_shop_prev_fov = cam.fov
	oc.begin_shop_focus()
	if pl.has_method("set_ghost"):
		pl.set_ghost(true)
	if pl.has_method("transition_to"):
		pl.transition_to(pl.PlayerState.CUTSCENE)

	var pose := _compute_shop_pose(npc)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(cam, "global_transform", pose, SHOP_CAM_TWEEN)
	tw.tween_property(cam, "fov", SHOP_CAM_FOV, SHOP_CAM_TWEEN)
	tw.tween_property(cam, "h_offset", SHOP_CAM_H_OFFSET, SHOP_CAM_TWEEN)
	await tw.finished

	# Low dim so the live scene stays visible behind the overlay.
	var overlay: Node = await SceneManager.push_scene(scene_path, data, 0.0)
	_shop_overlay = overlay
	if is_instance_valid(overlay):
		overlay.tree_exited.connect(_close_shop_view)
	else:
		_close_shop_view()


## Restore gameplay when the shop overlay closes (its cancel path pops the scene,
## which frees it → tree_exited → here). Tweens the camera back to the follow
## pose, un-ghosts and unfreezes the player.
func _close_shop_view() -> void:
	if not _shop_open:
		return
	_shop_open = false
	_shop_overlay = null
	if not (is_instance_valid(orbit_camera) and is_instance_valid(player) and orbit_camera.has_method("end_shop_focus")):
		return

	var oc: Variant = orbit_camera
	var pl: Variant = player
	var cam: Camera3D = oc.camera
	if pl.has_method("set_ghost"):
		pl.set_ghost(false)

	var back: Transform3D = oc.get_follow_transform()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(cam, "global_transform", back, 0.3)
	tw.tween_property(cam, "fov", _shop_prev_fov, 0.3)
	tw.tween_property(cam, "h_offset", 0.0, 0.3)
	await tw.finished

	oc.end_shop_focus()
	if pl.has_method("transition_to"):
		pl.transition_to(pl.PlayerState.IDLE)


## The fixed camera transform for a shop: on the NPC's own facing axis, in front
## of it, looking at chest height. The NPC does not turn — the camera moves.
func _compute_shop_pose(npc: Node3D) -> Transform3D:
	var npc_pos := npc.global_position
	var rot: float = npc.get("npc_rotation_y") if npc.get("npc_rotation_y") != null else 0.0
	var facing := Vector3(sin(rot), 0, cos(rot))
	var floor_y := npc_pos.y
	var cam_pos := npc_pos + facing * SHOP_CAM_DIST
	cam_pos.y = floor_y + SHOP_CAM_HEIGHT
	var look_pos := Vector3(npc_pos.x, floor_y + SHOP_LOOK_HEIGHT, npc_pos.z)
	return Transform3D(Basis(), cam_pos).looking_at(look_pos, Vector3.UP)


func _save_and_transition(target_scene: String, spawn_key: String) -> void:
	if OS.has_environment("PSZ_DIAG"):
		print("[diag transit] from=%s -> %s key=%s" % [_get_area_name(), target_scene.get_file(), spawn_key])
	CityState.set_spawn_key(spawn_key)
	SceneManager.goto_scene(target_scene)


func _connect_player_to_interactables() -> void:
	for npc in _npcs:
		npc.set_player(player)
	for pad in _warp_pads:
		pad.set_player(player)


func _unhandled_input(_event: InputEvent) -> void:
	# Pause/Start handled by PsoStartMenu autoload
	pass


## Override in subclasses to return the area identifier string.
func _get_area_name() -> String:
	return ""


func _fix_city_materials() -> void:
	## Apply texture fixes from global-texture-fixes.json to all city GLB meshes.
	_load_global_texture_fixes()
	_fix_materials_recursive(self)


## Apply ONLY the scroll half of global-texture-fixes.json — the animated
## surfaces (water, waves) — and leave every other material exactly as the GLB
## authored it.
##
## For an area whose textures are already baked (the Market), the full
## _fix_city_materials() pass is too big a hammer: it rewrites shading mode,
## alpha scissor, depth draw and shadow-surface hiding on every surface in the
## scene, which is precisely what those areas opted out of. Scrolling one
## material should not re-light the whole market.
##
## An entry qualifies by carrying scrollX or scrollY. Note the asymmetry with
## _fix_materials_recursive: this pass does NOT infer scroll from a `_fall`
## texture name. A waterfall that wants to move says so in the data.
func _apply_scroll_fixes() -> void:
	_load_global_texture_fixes()
	var applied := _apply_scroll_fixes_recursive(self)
	# Worth printing: the lookup keys on the extracted texture filename, which
	# Godot derives from the GLB name (dairon2.glb + image `s00_2_wave01` =>
	# dairon2_s00_2_wave01.png). A re-export under a different name silently
	# stops matching, and a still surface is easy to miss. 0 here says so.
	print("[CityArea] scroll fixes applied to %d surface(s)" % applied)


func _apply_scroll_fixes_recursive(node: Node) -> int:
	var applied := 0
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if not (mat is StandardMaterial3D):
				continue
			var std_mat := mat as StandardMaterial3D
			var fix := _find_global_fix_for_material(std_mat)
			if not (fix.has("scrollX") or fix.has("scrollY")):
				continue
			var shader_mat := ShaderMaterial.new()
			shader_mat.shader = WATERFALL_SHADER
			if std_mat.albedo_texture:
				shader_mat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
			shader_mat.set_shader_parameter("albedo_color", std_mat.albedo_color)
			shader_mat.set_shader_parameter("uv_scale",
				Vector3(fix.get("repeatX", 1.0), fix.get("repeatY", 1.0), 1.0))
			shader_mat.set_shader_parameter("uv_offset",
				Vector3(fix.get("offsetX", 0.0), fix.get("offsetY", 0.0), 0.0))
			# Both default to 0 here, unlike the waterfall branch in
			# _fix_materials_recursive where a missing scrollY means -0.35. An
			# entry that asks for horizontal scroll must not inherit a vertical
			# crawl it never asked for.
			shader_mat.set_shader_parameter("uv_scroll",
				Vector2(fix.get("scrollX", 0.0), fix.get("scrollY", 0.0)))
			shader_mat.render_priority = 1
			mesh_inst.set_surface_override_material(i, shader_mat)
			applied += 1
	for child in node.get_children():
		applied += _apply_scroll_fixes_recursive(child)
	return applied


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


static func parse_lights_spec(text: String) -> Dictionary:
	## Parse a city-lights sidecar (authored in web #/city-lab) into
	## OmniLight3D-ready rows: {"lights": [...], "ambient": {...}|{}}.
	## Each light row carries typed name/pos/color/energy/range/attenuation/
	## shadows; rows with a bad pos/color are skipped, not fatal. A malformed
	## file yields {} so callers treat it as "no sidecar".
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var doc: Dictionary = parsed
	# A missing lights key is malformed (legacy rig rides); an EMPTY array
	# present is a valid authored-dark sidecar.
	if not doc.has("lights") or typeof(doc["lights"]) != TYPE_ARRAY:
		return {}
	var lights_raw: Variant = doc["lights"]
	var out: Array = []
	for entry in lights_raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = entry
		var pos_raw: Variant = spec.get("pos", [])
		var col_raw: Variant = spec.get("color", [])
		if typeof(pos_raw) != TYPE_ARRAY or pos_raw.size() != 3:
			continue
		if typeof(col_raw) != TYPE_ARRAY or col_raw.size() != 3:
			continue
		var pos := Vector3(float(pos_raw[0]), float(pos_raw[1]), float(pos_raw[2]))
		var col := Color(float(col_raw[0]), float(col_raw[1]), float(col_raw[2]))
		out.append({
			"name": String(spec.get("name", "AuthoredLight")),
			"pos": pos,
			"color": col,
			"energy": float(spec.get("energy", 2.0)),
			"range": float(spec.get("range", 15.0)),
			"attenuation": float(spec.get("attenuation", 1.0)),
			"shadows": bool(spec.get("shadows", false)),
		})
	var ambient: Dictionary = {}
	var amb_raw: Variant = doc.get("ambient", {})
	if typeof(amb_raw) == TYPE_DICTIONARY:
		var amb_col: Variant = amb_raw.get("color", [])
		if typeof(amb_col) == TYPE_ARRAY and amb_col.size() == 3:
			var col := Color(float(amb_col[0]), float(amb_col[1]), float(amb_col[2]))
			ambient = {"color": col, "energy": float(amb_raw.get("energy", 1.0))}
	return {"lights": out, "ambient": ambient}


## The certified DS bake look (#656, locked 2026-09-27 in the walk lab,
## kion's eyes): the stage goes pure bake (MeshUtils.make_unlit — UNSHADED,
## COLOR_0 modulates albedo, no light can touch the city mesh), the stage
## never casts (actors are the only shadow casters), and the collision
## shell renders as the shadow_to_opacity catcher — the c18324ba rig:
## the player lit by every light, dynamic per-light shadows everywhere,
## the between-feet contact under a light. Call AFTER the authored lights
## and the floor collision exist. `stage_node_name` is the scene's stage
## root ("Counter" / "Market" in the tscns).

## The floor-lit receiver (the lab kion confirmed live: "two shadows as
## expected... this is good"): every stage surface whose triangles are
## mostly floor-tilted and near walk height flips per-pixel WITH the bake
## as albedo — the floor shows its own baked textures, the authored omnis
## pool on it, their shadow maps land on it. No catcher, no veil — the
## floor cannot read black because it IS the stage's own surface.
##
## `floor_surfaces` is the surface name list (the wetlands `lit_surfaces`
## convention — authored material names, not geometry guessing); "*" flips
## the WHOLE stage per-pixel (the wetlands wildcard — kion's 2026-09-27
## live call: a name list reads as shadows that appear and vanish between
## floor materials, so the guild hall takes the full mesh). The list path
## exists for per-surface control; the geom gate remains the default for
## flat box floors (the market A/B) — but beware it on sloped colliders:
## floor_top reads the collision AABB TOP (the counter's kaidan shell:
## +14.7 against the −10.7 floor) and rejects every surface — the #669
## failure: the sidecar's pools and shadows armed, nothing landing.
func _apply_ds_floor_lit(stage_node_name: String, floor_surfaces: Array = []) -> void:
	var stage := get_node_or_null(stage_node_name)
	if stage == null:
		push_warning("[CityArea] DS floor-lit: no stage node '%s'" % stage_node_name)
		return
	MeshUtils.make_unlit(stage, [])
	for node in MeshUtils.collect_mesh_instances(stage, []):
		(node as MeshInstance3D).cast_shadow = \
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wanted: Dictionary = {}
	for surface_name in floor_surfaces:
		wanted[surface_name] = true
	var wildcard := wanted.has("*")
	var by_name := not wanted.is_empty()
	var floor_root := get_node_or_null("FloorCollision")
	var walk_y := MeshUtils.floor_top(floor_root) if floor_root else 0.0
	var flipped := 0
	for node in MeshUtils.collect_mesh_instances(stage, []):
		var mi := node as MeshInstance3D
		var arr_mesh: ArrayMesh = null if by_name else (mi.mesh as ArrayMesh)
		for i in range(mi.get_surface_override_material_count()):
			var mat: Material = mi.get_active_material(i)
			if not (mat is StandardMaterial3D):
				continue
			if by_name:
				if not wildcard and not wanted.has((mat as StandardMaterial3D).resource_name):
					continue
			elif not _surface_is_floor(mi, arr_mesh, i, walk_y):
				continue
			var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			dup.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			dup.vertex_color_use_as_albedo = MeshUtils.vertex_bake_present(mi, i)
			mi.set_surface_override_material(i, dup)
			flipped += 1
	# 0 flipped = the rig silently degenerated to pure bake (no pools, no
	# shadows land) — the exact #669 failure, invisible without this count.
	print("[CityArea] DS floor-lit on %s: %d surface(s) by %s" % [
		stage_node_name, flipped, "wildcard" if wildcard else \
		("name list" if by_name else "geom gate")])


## The geom gate: a stage surface is FLOOR when ≥ half its triangles tilt
## within ~53° of horizontal and its centroid sits at walk height ± 1.5 —
## floor materials come and go, floor SHAPE doesn't.
func _surface_is_floor(mi: MeshInstance3D, mesh: ArrayMesh, surf: int, walk_y: float) -> bool:
	if mesh == null or surf >= mesh.get_surface_count():
		return false
	var arrays := mesh.surface_get_arrays(surf)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() < 3:
		return false
	var ups := 0
	var total := 0
	var sum_y := 0.0
	for t in range(0, verts.size() - 2, 3):
		var a: Vector3 = mi.global_transform * verts[t]
		var b: Vector3 = mi.global_transform * verts[t + 1]
		var c: Vector3 = mi.global_transform * verts[t + 2]
		var n := (b - a).cross(c - a)
		sum_y += (a.y + b.y + c.y) / 3.0
		total += 1
		if absf(n.y) > 0.6 * n.length():
			ups += 1
	return total > 0 and ups >= total / 2 and absf(sum_y / total - walk_y) < 1.5

## The catcher's private render layer: the market's sun lights ONLY the
## catcher (its uniform energy clears the sto veil and its shadow maps
## carry the player silhouette — the valley sun contract, indoors), so it
## rides a layer the stage and actors never see.
const CATCHER_LAYER := 4


func _apply_ds_bake_look(stage_node_name: String, sun := false,
		plane_size := Vector2.ZERO, plane_center := Vector3.ZERO) -> void:
	var stage := get_node_or_null(stage_node_name)
	if stage == null:
		push_warning("[CityArea] DS bake look: no stage node '%s'" % stage_node_name)
		return
	MeshUtils.make_unlit(stage, [])
	for node in MeshUtils.collect_mesh_instances(stage, []):
		(node as MeshInstance3D).cast_shadow = \
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var catcher: MeshInstance3D = null
	var floor_root := get_node_or_null("FloorCollision")
	if plane_size.x > 0.0:
		# kion's spec (#670): the catcher plane AT y:0 — a hull-derived face
		# (the market's box top floats at +0.1) reads as a gray overlay
		# sheet; the authored plane carries the valley-A material (the sto
		# shader plane it replaces was the veil dead end: its alpha IS the
		# colored plane, it cannot read as "shadow only").
		catcher = MeshUtils.make_shadow_catcher_plane(plane_size, plane_center)
		# The plane rides the catcher's private render layer so the scene's
		# POINT lights can be culled off it (the caller's choice): measured
		# on compat (#670), the transparent pass blends in FLOAT — a lit
		# value past ×1 BRIGHTENS the floor (the e6 white sheet), and any
		# point pool pushes the total past 1 inside its falloff. The catcher
		# wants ONE uniform light — a directional tuned to land just under
		# ×1 — plus the ambient share as its shadow floor.
		catcher.layers = CATCHER_LAYER
	elif floor_root:
		catcher = MeshUtils.make_shadow_catcher(floor_root, true, true)
	if catcher == null:
		push_warning("[CityArea] DS bake look: no catcher (no hull, no plane)")
		return
	if sun:
		catcher.layers = CATCHER_LAYER
		var sun_light := DirectionalLight3D.new()
		sun_light.name = "CatcherSun"
		# Saturation is EMPIRICAL: shadow_to_opacity's alpha reaches 0
		# (catcher invisible, bake verbatim) only past a total the internal
		# attenuation weights heavily — measured on the market stage:
		# E1.8 -> floor mean 57 (a ~0.5 veil), E6.0 -> 93 ~= the pure-bake
		# 96. Weaker suns leave a gray wash; omni-only rigs leave the
		# ambient-capped black veil.
		sun_light.light_energy = float(OS.get_environment("PSZ_SUN_E")) if not OS.get_environment("PSZ_SUN_E").is_empty() else 6.0
		sun_light.rotation_degrees = Vector3(-55, 25, 0)
		sun_light.shadow_enabled = true
		sun_light.shadow_blur = 1.0
		# Only the catcher sees it — the baked stage is unlit regardless,
		# and the actors keep the authored omni rig as their only lights.
		sun_light.light_cull_mask = CATCHER_LAYER
		add_child(sun_light)
	add_child(catcher)


func _add_authored_lights(stage_id: String) -> bool:
	## Data-driven city lights (#656, #636 direction): load the sidecar the
	## web #/city-lab tool authors and spawn it — light_energy/omni_range/
	## omni_attenuation are the exact values the tool previewed. The ambient
	## override (if any) lands on this scene's WorldEnvironment. Returns
	## false when no valid sidecar exists; callers keep their legacy rig.
	var path := "res://data/stage_configs/city-lights/%s.json" % stage_id
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var spec := parse_lights_spec(file.get_as_text())
	if spec.is_empty():
		push_warning("[CityLights] malformed sidecar %s — keeping legacy rig" % path)
		return false
	var rows: Array = spec["lights"]
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var light := OmniLight3D.new()
		light.name = String(row.get("name", "AuthoredLight_%d" % i))
		var col: Color = row["color"]
		light.light_color = col
		light.light_energy = float(row["energy"])
		light.omni_range = float(row["range"])
		light.omni_attenuation = float(row["attenuation"])
		light.shadow_enabled = bool(row["shadows"])
		var pos: Vector3 = row["pos"]
		light.position = pos
		add_child(light)
	var ambient: Dictionary = spec["ambient"]
	if not ambient.is_empty():
		# By TYPE, not name: the tscn authors "WorldEnvironment", but any
		# runtime-built scene (the walk labs) gets @WorldEnvironment@N
		# auto-names that defeat a by-name find_child.
		var env_node: Node = null
		for child in get_children():
			if child is WorldEnvironment:
				env_node = child
				break
		if env_node is WorldEnvironment and env_node.environment != null:
			env_node.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			var amb_col: Color = ambient["color"]
			env_node.environment.ambient_light_color = amb_col
			env_node.environment.ambient_light_energy = float(ambient["energy"])
	# The sidecar is the whole rig (#656): scene-authored placeholder suns
	# (city_counter's 0.3 DirectionalLight3D, tuned for the no-sidecar look)
	# read as a flat ambient wash on top of it — the lab previews rig-only,
	# so the game must too. Zero rather than free: inspectable, reversible.
	for child in get_children():
		if child is DirectionalLight3D:
			child.light_energy = 0.0
	print("[CityLights] %s: %d authored lights" % [stage_id, rows.size()])
	return true


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


## The city rooms are hand-built scenes, not field cells — CellObjectSpawner
## never runs here — so the safe-room ambience rule (#644) needs its own hook.
## The market IS s00e_sa1, whose butterflies psz-re authors under set `c`
## (FieldPopulation's cross-set fallback resolves them). Positions are
## room-local in the same frame as the stage mesh; ambience only, inert.
func _add_ambience(room_code: String) -> void:
	for obj in FieldPopulation.objects_for_cell(
			room_code, true, false, RandomNumberGenerator.new()):
		if str(obj.get("type", "")) != "ambience":
			continue
		var pos_arr: Array = obj.get("position", [0.0, 0.0, 0.0])
		var critter := AmbientCritter.new()
		critter.critter_model = str(obj.get("model", ""))
		add_child(critter)
		critter.position = Vector3(
			float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))


## OUR flair butterflies at hand-picked spots (#644 playtest) — invented
## positions chosen for presence, unlike _add_ambience's authored table.
func _add_flair_critters(spots: Array) -> void:
	for spot in spots:
		var critter := AmbientCritter.new()
		critter.critter_model = "o0c_butterfly"
		add_child(critter)
		critter.position = spot

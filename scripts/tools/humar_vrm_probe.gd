extends Node3D
## Actual Player scenes, same animations/appearance/equipment, original vs VRM.
const PLAYER := preload("res://scenes/3d/player/player.tscn")
var players: Array[CharacterBody3D] = []
var selector: OptionButton
var elapsed := 0.0
var failures := 0

func _ready() -> void:
	if ProjectSettings.get_setting("application/config/name") != "PSZ HUmar VRM PoC":
		push_error("Use scripts/tools/run_humar_vrm_poc.py to isolate the live save.")
		get_tree().quit(1)
		return
	_setup.call_deferred()

func _setup() -> void:
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	var class_id := OS.get_environment("PSZ_VRM_CLASS")
	if class_id.is_empty(): class_id = "humar"
	var appearance := {"variation_index": int(OS.get_environment("PSZ_VRM_VARIATION"))}
	CharacterManager.create_character(0, class_id, "VRM Proof", appearance)
	CharacterManager.set_active_slot(0)
	SessionManager.enter_field("gurhacia", "normal")
	for i in range(2):
		var player := PLAYER.instantiate() as CharacterBody3D
		if i == 0:
			player.set_script(preload("res://scripts/tools/vrm/legacy_player_fixture.gd"))
		add_child(player)
		player.position.x = -0.9 if i == 0 else 0.9
		player.set_physics_process(false)
		player.set_process(false)
		player.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		players.append(player)
	_check(players[1].get_node("PlayerModel/Model").has_meta("psz_avatar_format"), "converted VRM actually loaded; no GLB fallback")
	_check(players[1].skeleton.get_bone_count() == 16, "legacy skeleton plus four weighted endpoints")
	_check(players[1].weapon_node != null, "production weapon attachment exists")
	_check(players[1].mag_node != null, "production mag attachment exists")
	_check(preload("res://scripts/3d/player/player_avatar.gd").legacy_buffer(PackedByteArray([1, 2, 3])).is_empty(), "invalid VRM fails safely")
	_build_view()
	_compare_animations()
	if DisplayServer.get_name() == "headless":
		print("[humar-vrm-probe] DONE failures=%d" % failures)
		get_tree().quit(1 if failures else 0)
		return
	var initial := 0
	for i in range(selector.item_count):
		if selector.get_item_text(i).ends_with("pmsa_wait"):
			initial = i
	selector.select(initial)
	_play_clip(initial)
	print("[humar-vrm-probe] Interactive comparison ready; failures=%d" % failures)

func _check(ok: bool, description: String) -> void:
	if ok:
		return
	failures += 1
	printerr("[humar-vrm-probe] FAIL #", failures, ": ", description)

func _compare_animations() -> void:
	var original: Skeleton3D = players[0].skeleton
	var converted: Skeleton3D = players[1].skeleton
	var clips: PackedStringArray = players[0].animation_player.get_animation_list()
	var comparisons := 0
	for clip in clips:
		var animation: Animation = players[0].animation_player.get_animation(clip)
		for fraction in [0.0, 0.3, 0.6, 0.95]:
			for player in players:
				player.animation_player.play(clip)
				player.animation_player.seek(animation.length * fraction, true)
				player.skeleton.force_update_all_bone_transforms()
			for bone in range(original.get_bone_count()):
				var bone_name := original.get_bone_name(bone)
				var other := converted.find_bone(bone_name)
				_check(other >= 0, "VRM retains animated bone " + bone_name)
				if other >= 0:
					_check(original.get_bone_global_pose(bone).is_equal_approx(converted.get_bone_global_pose(other)), "%s pose parity: %s" % [clip, bone_name])
					comparisons += 1
	print("[humar-vrm-probe] Compared %d clips / %d bone poses through production animation libraries" % [clips.size(), comparisons])

func _build_view() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("19222f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.8
	environment.environment = env
	add_child(environment)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 1.4, -5)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.current = true
	if OS.get_environment("PSZ_VRM_PORTABLE") == "1":
		for player in players:
			player.hide()
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var bytes := FileAccess.get_file_as_bytes(PlayerConfig.get_paths_for_character(CharacterManager.get_active_character()).model_path)
		_check(document.append_from_buffer(bytes, "", state) == OK, "portable VRM imports directly")
		var portable := document.generate_scene(state)
		if portable:
			add_child(portable)
		camera.position = Vector3(0, 1.3, 3.3)
		camera.look_at(Vector3(0, 0.95, 0))
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("354354")
	floor_mesh.material_override = material
	add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var overlay := CanvasLayer.new()
	overlay.layer = 300
	add_child(overlay)
	var label := Label.new()
	label.position = Vector2(24, 20)
	label.text = "Playable character VRM comparison\nOriginal GLB and converted VRM · identical native animation\nChoose a clip below · Esc to close"
	if OS.get_environment("PSZ_VRM_PORTABLE") == "1":
		label.text = "Portable VRM 1.0 · T-pose\nEmbedded default texture · no native rig restoration"
	label.add_theme_font_size_override("font_size", 22)
	overlay.add_child(label)
	selector = OptionButton.new()
	selector.position = Vector2(24, 118)
	for clip in players[0].animation_player.get_animation_list():
		selector.add_item(clip)
	overlay.add_child(selector)
	selector.item_selected.connect(_play_clip)
	if OS.get_environment("PSZ_VRM_PORTABLE") == "1":
		selector.hide()
		return
	for i in range(2):
		var nameplate := Label3D.new()
		nameplate.text = "Original GLB" if i == 0 else "Converted VRM"
		nameplate.position = Vector3(players[i].position.x, 2.05, 0)
		nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nameplate.font_size = 48
		add_child(nameplate)

func _play_clip(index: int) -> void:
	var clip := selector.get_item_text(index)
	for player in players:
		player.animation_player.play(clip)
		player.animation_player.seek(0, true)

func _process(delta: float) -> void:
	for player in players:
		if player.animation_player:
			player.animation_player.advance(delta)
	elapsed += delta
	var screenshot := OS.get_environment("PSZ_VRM_SCREENSHOT")
	if not screenshot.is_empty() and elapsed > 3 and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(screenshot)
		get_tree().quit(1 if failures else 0)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()

extends Node3D
## Weapon orientation test scene.
## Loads the active character's model + equipped weapon.
## Sliders adjust weapon position/rotation in real-time.
## Press 1-3 to play attack animations. Space to toggle idle/attack hold.
## Prints values to console for copy-paste into WEAPON_HOLD.

var _model: Node3D
var _skeleton: Skeleton3D
var _weapon: Node3D
var _anim_player: AnimationPlayer
var _anim_prefix: String = "pmsa"

# Current adjustable values
var _pos := Vector3(0.31, 0, 0)
var _rot := Vector3(0, 90, 0)

# UI elements
var _labels: Dictionary = {}
var _info_label: Label

const BONE_NAME := "070_RArm02"


func _ready() -> void:
	_load_character()
	_build_ui()
	_update_info()


func _load_character() -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		print("[WeaponTest] No active character!")
		return

	# Load player model
	var paths: Dictionary = PlayerConfig.get_paths_for_character(character)
	var model_path: String = paths["model_path"]
	var texture_path: String = paths["texture_path"]

	if not ResourceLoader.exists(model_path):
		print("[WeaponTest] Model not found: %s" % model_path)
		return

	var packed := load(model_path) as PackedScene
	_model = packed.instantiate()
	add_child(_model)

	# Apply texture
	if ResourceLoader.exists(texture_path):
		var texture := load(texture_path) as Texture2D
		if texture:
			_apply_texture(_model, texture)

	# Find skeleton
	_skeleton = _find_typed(_model, "Skeleton3D") as Skeleton3D
	if not _skeleton:
		print("[WeaponTest] No skeleton found!")
		return

	# Load animations
	_load_animations(character)

	# Load weapon
	_load_weapon(character)

	# Play idle
	if _anim_player:
		var idle_name := _anim_prefix + "_wait"
		if _anim_player.has_animation(idle_name):
			_anim_player.play(idle_name)


func _load_animations(character: Dictionary) -> void:
	var class_id: String = str(character.get("class_id", "humar"))
	var class_data = ClassRegistry.get_class_data(class_id)
	var is_female: bool = class_data and class_data.gender == "Female"
	var gender_key := "w" if is_female else "m"

	var weapon_id: String = str(character.get("equipment", {}).get("weapon", ""))
	var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(weapon_id)) if not weapon_id.is_empty() else null

	# Determine animation GLB and prefix
	var anim_glb := "res://assets/player/animations/saver_m.glb"
	_anim_prefix = "pmsa"

	if weapon:
		var WEAPON_ANIM_DATA: Dictionary = {
			0: {"glb_m": "res://assets/player/animations/saver_m.glb", "prefix_m": "pmsa", "glb_w": "res://assets/player/animations/saver_w.glb", "prefix_w": "pwsa"},
			1: {"glb_m": "res://assets/player/animations/sword_m.glb", "prefix_m": "pmsw", "glb_w": "res://assets/player/animations/sword_w.glb", "prefix_w": "pwsw"},
			2: {"glb_m": "res://assets/player/animations/dagger_m.glb", "prefix_m": "pmda", "glb_w": "res://assets/player/animations/dagger_w.glb", "prefix_w": "pwda"},
			5: {"glb_m": "res://assets/player/animations/spear_m.glb", "prefix_m": "pmsp", "glb_w": "res://assets/player/animations/spear_w.glb", "prefix_w": "pwsp"},
			9: {"glb_m": "res://assets/player/animations/handgun_m.glb", "prefix_m": "pmhg", "glb_w": "res://assets/player/animations/handgun_w.glb", "prefix_w": "pwhg"},
			10: {"glb_m": "res://assets/player/animations/machinegun_m.glb", "prefix_m": "pmmg", "glb_w": "res://assets/player/animations/machinegun_w.glb", "prefix_w": "pwmgs"},
			11: {"glb_m": "res://assets/player/animations/shotgun_m.glb", "prefix_m": "pmri", "glb_w": "res://assets/player/animations/shotgun_w.glb", "prefix_w": "pwri"},
			12: {"glb_m": "res://assets/player/animations/shotgun_m.glb", "prefix_m": "pmri", "glb_w": "res://assets/player/animations/shotgun_w.glb", "prefix_w": "pwri"},
			14: {"glb_m": "res://assets/player/animations/rod_m.glb", "prefix_m": "pmro", "glb_w": "res://assets/player/animations/rod_w.glb", "prefix_w": "pwro"},
			15: {"glb_m": "res://assets/player/animations/wand_m.glb", "prefix_m": "pmwa", "glb_w": "res://assets/player/animations/wand_w.glb", "prefix_w": "pwwa"},
		}
		var data: Dictionary = WEAPON_ANIM_DATA.get(weapon.weapon_type, {})
		if not data.is_empty():
			anim_glb = str(data.get("glb_" + gender_key, anim_glb))
			_anim_prefix = str(data.get("prefix_" + gender_key, _anim_prefix))

	if not ResourceLoader.exists(anim_glb):
		return

	var anim_packed := load(anim_glb) as PackedScene
	var anim_scene := anim_packed.instantiate()
	var source_player: AnimationPlayer = _find_typed(anim_scene, "AnimationPlayer") as AnimationPlayer
	if not source_player:
		anim_scene.queue_free()
		return

	_anim_player = AnimationPlayer.new()
	_anim_player.name = "TestAnimPlayer"
	_skeleton.get_parent().add_child(_anim_player)

	var lib := AnimationLibrary.new()
	for anim_name in source_player.get_animation_list():
		var source_anim := source_player.get_animation(anim_name)
		var new_anim := source_anim.duplicate() as Animation
		# Remap tracks
		for i in range(new_anim.get_track_count()):
			var track_path := String(new_anim.track_get_path(i))
			if "Skeleton3D" in track_path:
				var skel_idx := track_path.find("Skeleton3D")
				var prop_part := track_path.substr(skel_idx + 10)
				new_anim.track_set_path(i, NodePath(_skeleton.name + prop_part))
		# Set looping for idle/walk/run
		for suffix in ["_wait", "_walk", "_run", "_stp_fb", "_stp_lr"]:
			if anim_name.ends_with(suffix):
				new_anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(anim_name, new_anim)

	_anim_player.add_animation_library("", lib)
	anim_scene.queue_free()

	var anim_list := _anim_player.get_animation_list()
	print("[WeaponTest] Loaded %d animations, prefix=%s" % [anim_list.size(), _anim_prefix])


func _load_weapon(character: Dictionary) -> void:
	var weapon_id: String = str(character.get("equipment", {}).get("weapon", ""))
	if weapon_id.is_empty():
		return
	var weapon_data = WeaponRegistry.get_weapon(Inventory.get_base_id(weapon_id))
	if weapon_data == null or weapon_data.glb_path.is_empty():
		return
	if not ResourceLoader.exists(weapon_data.glb_path):
		return

	var bone_idx := _skeleton.find_bone(BONE_NAME)
	if bone_idx == -1:
		return

	var bone_attachment := BoneAttachment3D.new()
	bone_attachment.name = "WeaponAttachment"
	bone_attachment.bone_name = _skeleton.get_bone_name(bone_idx)
	_skeleton.add_child(bone_attachment)

	var packed := load(weapon_data.glb_path) as PackedScene
	_weapon = packed.instantiate()
	bone_attachment.add_child(_weapon)

	var s: float = weapon_data.glb_scale
	_weapon.scale = Vector3(s, s, s)
	_weapon.position = _pos
	_weapon.rotation_degrees = _rot

	print("[WeaponTest] Weapon loaded: %s (type=%d)" % [weapon_data.name, weapon_data.weapon_type])


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_1:
			_play_anim("_atk1")
		KEY_2:
			_play_anim("_atk2")
		KEY_3:
			_play_anim("_atk3")
		KEY_4:
			_play_anim("_wait")
		KEY_5:
			_play_anim("_walk")
		KEY_6:
			_play_anim("_run")
		KEY_7:
			_play_anim("_dam_n")
		KEY_P:
			_print_values()
		KEY_ESCAPE:
			SceneManager.goto_scene("res://scenes/2d/title.tscn")


func _play_anim(suffix: String) -> void:
	if not _anim_player:
		return
	var name := _anim_prefix + suffix
	if _anim_player.has_animation(name):
		_anim_player.play(name)
		print("[WeaponTest] Playing: %s" % name)
	else:
		print("[WeaponTest] Animation not found: %s" % name)


func _print_values() -> void:
	var text := 'position = Vector3(%.3f, %.3f, %.3f)\nrotation_degrees = Vector3(%.1f, %.1f, %.1f)' % [
		_pos.x, _pos.y, _pos.z, _rot.x, _rot.y, _rot.z]
	print("[WeaponTest] Current values:\n%s" % text)


func _apply_weapon_transform() -> void:
	if _weapon:
		_weapon.position = _pos
		_weapon.rotation_degrees = _rot
	_update_info()


func _build_ui() -> void:
	var ui := $UI
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.content_margin_left = 10
	style.content_margin_top = 10
	style.content_margin_right = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.offset_right = 280
	panel.offset_bottom = 500
	panel.offset_left = 10
	panel.offset_top = 10

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Weapon Orientation Test"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "1-3: Attacks  4: Idle  5: Walk  6: Run\n7: Damage  P: Print values  Esc: Exit"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(hint)

	# Position sliders
	_add_slider_group(vbox, "Position", "pos", ["x", "y", "z"], -0.5, 0.5, 0.005)

	# Rotation sliders
	_add_slider_group(vbox, "Rotation", "rot", ["x", "y", "z"], -180, 180, 1.0)

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	vbox.add_child(_info_label)

	panel.add_child(vbox)
	ui.add_child(panel)


func _add_slider_group(parent: VBoxContainer, group_name: String, field: String, axes: Array, min_val: float, max_val: float, step: float) -> void:
	var header := Label.new()
	header.text = group_name
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	parent.add_child(header)

	for axis in axes:
		var hbox := HBoxContainer.new()
		var label := Label.new()
		label.custom_minimum_size.x = 60
		label.add_theme_font_size_override("font_size", 12)
		_labels[field + "_" + axis] = label
		hbox.add_child(label)

		var slider := HSlider.new()
		slider.min_value = min_val
		slider.max_value = max_val
		slider.step = step
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.x = 150

		# Set initial value
		if field == "pos":
			match axis:
				"x": slider.value = _pos.x
				"y": slider.value = _pos.y
				"z": slider.value = _pos.z
		elif field == "rot":
			match axis:
				"x": slider.value = _rot.x
				"y": slider.value = _rot.y
				"z": slider.value = _rot.z

		var f: String = field
		var a: String = str(axis)
		slider.value_changed.connect(func(val: float) -> void:
			if f == "pos":
				match a:
					"x": _pos.x = val
					"y": _pos.y = val
					"z": _pos.z = val
			elif f == "rot":
				match a:
					"x": _rot.x = val
					"y": _rot.y = val
					"z": _rot.z = val
			_apply_weapon_transform()
		)
		hbox.add_child(slider)
		parent.add_child(hbox)


func _update_info() -> void:
	if _info_label:
		_info_label.text = "pos=(%.3f, %.3f, %.3f)\nrot=(%.1f, %.1f, %.1f)" % [
			_pos.x, _pos.y, _pos.z, _rot.x, _rot.y, _rot.z]
	for key in _labels:
		var parts: PackedStringArray = key.split("_")
		var val: float = 0
		if parts[0] == "pos":
			match parts[1]:
				"x": val = _pos.x
				"y": val = _pos.y
				"z": val = _pos.z
		elif parts[0] == "rot":
			match parts[1]:
				"x": val = _rot.x
				"y": val = _rot.y
				"z": val = _rot.z
		_labels[key].text = "%s.%s: %.3f" % [parts[0], parts[1], val]


func _find_typed(root: Node, type_name: String) -> Node:
	if root.get_class() == type_name:
		return root
	for child in root.get_children():
		var found := _find_typed(child, type_name)
		if found:
			return found
	return null


func _apply_texture(node: Node, texture: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var new_mat := mat.duplicate() as StandardMaterial3D
				new_mat.albedo_texture = texture
				new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				mesh_inst.set_surface_override_material(i, new_mat)
	for child in node.get_children():
		_apply_texture(child, texture)

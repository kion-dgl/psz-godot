class_name OctoPresentation extends Node
## Authored behind-player framing at recovered cinematic boundaries. Original
## z_002_* camera curves are not imported; do not describe these views as 1:1.
var _camera: Camera3D
var _previous: Camera3D
var _player: Node3D
var _player_processing := false
var _focus := Vector3.ZERO
var _position := Vector3.ZERO
var _wind: MeshInstance3D
var _wind_mesh: ImmediateMesh
var _wind_time := 0.0

func _ready() -> void:
	_wind = MeshInstance3D.new()
	_wind_mesh = ImmediateMesh.new()
	_wind.mesh = _wind_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.75,0.9,1.0,0.65)
	material.no_depth_test = false
	_wind.material_override = material
	get_parent().add_child.call_deferred(_wind)

func _update_wind(delta: float) -> void:
	if not is_instance_valid(_wind) or not _wind.is_inside_tree(): return
	var boss := get_parent() as OctoDiabloBoss
	_wind.visible = not boss._dying and boss.body_state == "absorb" and boss.action_id == 13
	if not _wind.visible: return
	_wind_time += delta
	_wind_mesh.clear_surfaces()
	_wind_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	# Short spiral streaks converge toward the mouth, rather than radiate out.
	for strand in 28:
		var progress := fposmod(_wind_time*0.8+float(strand)/28.0,1.0)
		for segment in 5:
			for end in 2:
				var t := clampf(progress-float(segment+end)*0.012,0.0,1.0)
				var angle := strand*2.4+t*TAU
				var radius := lerpf(4.5,0.35,t)
				_wind_mesh.surface_add_vertex(Vector3(cos(angle)*radius,2.0+sin(angle)*radius,lerpf(14.0,3.0,t)))
	_wind_mesh.surface_end()


func begin(player: Node3D, point: Vector3) -> void:
	finish()
	if not is_instance_valid(player): return
	_player = player
	_player_processing = player.is_physics_processing()
	player.set_physics_process(false)
	_previous = get_viewport().get_camera_3d()
	_focus = point + Vector3.UP*2
	var away := player.global_position-point
	away.y = 0
	if away.length_squared() < 0.01: away = Vector3.BACK
	_position = player.global_position + away.normalized()*6 + Vector3.UP*5
	_camera = Camera3D.new()
	_camera.fov = 65
	add_child(_camera)
	_camera.global_position = _position
	_camera.look_at(_focus)
	_camera.make_current()

func focus(point: Vector3) -> void:
	_focus = point+Vector3.UP*2

func _process(delta: float) -> void:
	_update_wind(delta)
	if not is_instance_valid(_camera): return
	var desired := _camera.global_transform.looking_at(_focus,Vector3.UP)
	_camera.global_transform = _camera.global_transform.interpolate_with(desired,1.0-exp(-delta*3.0))

func finish() -> void:
	if is_instance_valid(_player): _player.set_physics_process(_player_processing)
	_player = null
	if is_instance_valid(_camera):
		if is_instance_valid(_previous): _previous.make_current()
		_camera.queue_free()
	_camera = null
	_previous = null

func clear_storm() -> void:
	var field := get_tree().current_scene
	if field and field.has_method("clear_octo_storm"):
		field.clear_octo_storm()
		var sky := field.find_child("Skybox",true,false)
		if sky: _clear_sky(sky)

func _exit_tree() -> void:
	finish()

func _clear_sky(sky: Node) -> void:
	# Keep the original cloudy texture; lift its black storm sky for the
	# observed overcast ending. This grading is authored, not a retail palette.
	for node in sky.find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		for surface in mesh.get_surface_override_material_count():
			var original := mesh.get_active_material(surface)
			var texture: Texture2D
			if original is ShaderMaterial: texture = original.get_shader_parameter("albedo_texture")
			elif original is StandardMaterial3D: texture = original.albedo_texture
			if not texture: continue
			var material := ShaderMaterial.new()
			material.shader = preload("res://scripts/3d/enemies/octo_cleared_sky.gdshader")
			material.set_shader_parameter("cloud_texture",texture)
			material.set_shader_parameter("clear_amount",0.0)
			var base := original.duplicate() as Material
			base.next_pass = material
			mesh.set_surface_override_material(surface,base)
			var tween := mesh.create_tween()
			tween.tween_method(func(value: float): material.set_shader_parameter("clear_amount",value),0.0,1.0,6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

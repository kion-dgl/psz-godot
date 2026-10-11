extends RefCounted
## Scape Doll presentation: death -> particles -> stand-up. Nodes belong to the
## player so leaving the scene also removes the overlay and particles.
const DOWN_SECONDS := 1.2
const PARTICLE_SECONDS := 0.9
var active := false
var elapsed := 0.0
var down_seconds := DOWN_SECONDS
var wash: CanvasLayer
var particles: CPUParticles3D
var _red: ColorRect

func begin(player: Node3D) -> void:
	active = true
	elapsed = 0.0
	down_seconds = DOWN_SECONDS
	# Let the actual fall clip finish, then hold the prone pose briefly.
	var animator: AnimationPlayer = player.animation_player
	if is_instance_valid(animator) and animator.is_playing():
		down_seconds = maxf(DOWN_SECONDS, animator.current_animation_length + 0.35)
	if not player.is_inside_tree():
		return
	wash = CanvasLayer.new()
	wash.layer = DefeatScreen.LAYER
	player.add_child(wash)
	_red = ColorRect.new()
	_red.color = Color(0.6, 0.0, 0.0, 0.0)
	_red.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_red.mouse_filter = Control.MOUSE_FILTER_STOP
	wash.add_child(_red)
	player.create_tween().tween_property(_red, "color:a", DefeatScreen.RED_ALPHA, DefeatScreen.FADE_TIME)

func tick(player: Node3D, delta: float) -> void:
	if not active:
		return
	var previous := elapsed
	elapsed += delta
	if previous < down_seconds and elapsed >= down_seconds:
		_spawn_particles(player)
	if elapsed < down_seconds + PARTICLE_SECONDS:
		return
	active = false
	player._is_defeated = false
	player._recovery_left = 2.0
	GameState.set_hp(GameState.max_hp)
	var character = CharacterManager.get_active_character()
	if character != null:
		character["hp"] = GameState.hp
	player.transition_to(player.PlayerState.DAMAGED)
	player.play_animation(player._anim_prefix + "_dam_d_wa", false)
	player._ailments.feedback(player, "Scape Doll")
	if is_instance_valid(wash):
		var tween := player.create_tween()
		tween.tween_property(_red, "color:a", 0.0, 0.6)
		tween.tween_callback(wash.queue_free)
	if is_instance_valid(particles):
		var tween := player.create_tween()
		tween.tween_interval(1.0)
		tween.tween_callback(particles.queue_free)

func _spawn_particles(player: Node3D) -> void:
	if not player.is_inside_tree():
		return
	particles = CPUParticles3D.new()
	particles.amount = 48
	particles.lifetime = 1.2
	particles.one_shot = true
	particles.explosiveness = 0.65
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.65
	particles.direction = Vector3.UP
	particles.spread = 20.0
	particles.initial_velocity_min = 0.8
	particles.initial_velocity_max = 1.8
	particles.gravity = Vector3(0, 0.5, 0)
	particles.scale_amount_min = 0.04
	particles.scale_amount_max = 0.09
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.9, 0.45)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.75, 0.2)
	var mesh := SphereMesh.new()
	mesh.material = material
	particles.mesh = mesh
	player.add_child(particles)
	particles.position.y = 0.4
	particles.emitting = true

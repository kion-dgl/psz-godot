class_name FalzOrbit extends Node3D
## Authored shadow and orbit visuals; original effect models are not in the pack.
var balls: Array[MeshInstance3D] = []
var phase := 0.0
var extension := 1.0
var retracted := false
var contact_left := 0.0
var radius := 5.0
var shadow: MeshInstance3D

static func orbit_point(index: int, angle: float, reach: float, amount: float) -> Vector3:
	var theta := angle + TAU * float(index) / 3.0
	return Vector3(cos(theta) * reach * amount, lerpf(-0.5, 1.2, amount), sin(theta) * reach * amount)

func _ready() -> void:
	top_level = true # Turning Falz must not teleport the orbit into the player.
	shadow = MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = 4.0
	disk.bottom_radius = 4.0
	disk.height = 0.025
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.045, 0.015, 0.07, 0.85)
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disk.material = ink
	shadow.mesh = disk
	shadow.position.y = 0.04
	add_child(shadow)
	for index in 3:
		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.8
		sphere.height = 1.6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.28, 0.08, 0.4)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.08, 0.55)
		sphere.material = mat
		ball.mesh = sphere
		ball.position = orbit_point(index, phase, radius, extension)
		add_child(ball)
		balls.append(ball)

func advance(delta: float, boss: DarkFalzBoss) -> void:
	var previous_origin := global_position
	global_position = boss.global_position
	phase += delta * (1.3 if boss.submerged else 0.8)
	radius = 5.5 + sin(phase * 0.45) * 2.0
	extension = move_toward(extension, 0.0 if retracted else 1.0, delta * 1.5)
	contact_left = maxf(0.0, contact_left - delta)
	for index in balls.size():
		var ball := balls[index]
		var previous := previous_origin + ball.position
		ball.position = orbit_point(index, phase, radius, extension)
		ball.visible = extension > 0.1
		if retracted or extension < 0.95 or contact_left > 0 or not is_instance_valid(boss.target):
			continue
		var target := boss.target.global_position
		var hit := ProjectileSweep.planar_fraction(previous, ball.global_position - previous, target, 1.15)
		if hit >= 0.0 and absf(target.y - boss.global_position.y) < 2.5:
			contact_left = 1.2
			boss._damage_target()

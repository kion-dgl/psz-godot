extends Node3D
const DELAY := 0.95
var target: Node3D
var caster: Node3D
var damage := 0
var level := 1
var elapsed := 0.0
var struck := false
var glints: Array[MeshInstance3D] = []
var pillar: MeshInstance3D

func _ready() -> void:
	add_to_group("technique_visuals")
	for i in range(7):
		var glint := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.07
		mesh.height = 0.14
		glint.mesh = mesh
		glint.scale = Vector3(0.5, 3, 0.5)
		glint.material_override = _material(Color.from_hsv(float(i) / 7.0, 0.5, 1.0))
		add_child(glint)
		glints.append(glint)
	pillar = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.16
	cylinder.bottom_radius = 0.42
	cylinder.height = 3.6
	pillar.mesh = cylinder
	pillar.material_override = _material(Color(1.0, 0.98, 0.75, 0.8))
	pillar.hide()
	add_child(pillar)

func _material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = tint
	return mat

func _process(delta: float) -> void:
	elapsed += delta
	if not struck:
		if not is_instance_valid(target) or not target.get("is_alive") or not is_instance_valid(caster):
			queue_free()
			return
		global_position = target.global_position
	for i in range(glints.size()):
		var angle := TAU * float(i) / glints.size() + elapsed * 3.0
		glints[i].position = Vector3(cos(angle) * 0.55, 0.7 + 0.5 * sin(angle * 1.7 + elapsed), sin(angle) * 0.55)
		glints[i].visible = elapsed < DELAY + 0.15
	if elapsed >= DELAY and not struck:
		struck = true
		SfxManager.play_at("res://assets/sfx/common/common_133.wav", global_position, -5.0)
		if target.hurtbox: target.hurtbox.take_hit(damage, Vector3.ZERO, 100, "light", level, true, "technique", caster)
		pillar.show()
	if struck:
		var growth := smoothstep(DELAY, DELAY + 0.14, elapsed)
		pillar.scale.y = maxf(0.001, growth)
		pillar.position.y = 1.8 * growth
		pillar.material_override.albedo_color.a = 0.8 * (1.0 - smoothstep(DELAY + 0.2, DELAY + 0.55, elapsed))
	if elapsed >= DELAY + 0.55: queue_free()

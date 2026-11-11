extends Node3D
## One sequential chain, bounded by the area at cast time.
const RADIUS := 12.0
const HOP_RANGE := 8.0
const HOP_DELAY := 0.12
var caster: Node3D
var preferred: Node3D
var damage := 0
var knockback := 0.0
var element := "lightning"
var element_level := 1
var hit: Array = []
var source: Vector3
var countdown := 0.0
var finished := false
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("technique_visuals")
	rng.seed = get_instance_id()
	# Position is assigned immediately after add_child by the caster.

func _physics_process(delta: float) -> void:
	countdown -= delta
	if countdown > 0.0: return
	if finished or not is_instance_valid(caster):
		queue_free()
		return
	if hit.is_empty(): source = global_position + Vector3.UP
	var next: Node3D = null
	var distance := RADIUS if hit.is_empty() else HOP_RANGE
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy in hit or not enemy.get("is_alive") or not enemy.hurtbox: continue
		if enemy.global_position.distance_to(global_position) > RADIUS: continue
		var end: Vector3 = enemy.global_position + Vector3.UP
		var d := source.distance_to(end)
		if d > (RADIUS if hit.is_empty() and enemy == preferred else distance): continue
		var ray := PhysicsRayQueryParameters3D.create(source, end, 1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		next = enemy
		distance = d
		if hit.is_empty() and enemy == preferred: break
	if next == null:
		finished = true
		countdown = 0.45
		return
	var end := next.global_position + Vector3.UP
	_draw_bolt(source, end)
	hit.append(next)
	next.hurtbox.take_hit(damage, (end - source).normalized() * knockback, 100, element, element_level, true, "technique", caster)
	source = end
	countdown = HOP_DELAY
	if hit.size() >= 10:
		finished = true
		countdown = 0.45

func _draw_bolt(start: Vector3, end: Vector3) -> void:
	if start.distance_squared_to(end) < 0.0001: return
	var bolt := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, start.distance_to(end))
	bolt.mesh = quad
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/3d/shaders/lightning_bolt.gdshader")
	material.set_shader_parameter("Main_Color", Color(1.0, 1.0, 0.85))
	material.set_shader_parameter("Effect_Color", Color(0.55, 0.7, 1.0))
	material.set_shader_parameter("Seed", rng.randf() * 100.0)
	material.set_shader_parameter("Fade", 1.0)
	material.set_shader_parameter("Follow_Mesh_Axis", true)
	material.set_shader_parameter("Top_Taper", 0.03)
	bolt.material_override = material
	add_child(bolt)
	bolt.global_position = (start + end) * 0.5
	bolt.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	var tween := create_tween()
	tween.tween_interval(0.10)
	tween.tween_property(material, "shader_parameter/Fade", 0.0, 0.30)
	tween.tween_callback(bolt.queue_free)

class_name EnemyLob extends Node3D
## A lobbed grenade in flight (attack kind `lob`) — Godot port of fsm.ts
## `Lob`/`stepDeliveries`. Released once at the damaging-window open toward the
## target's position AT RELEASE (leading it is the player's problem); after
## LOB_FLIGHT_TIME it lands for area damage — `hit_reach` is the blast radius,
## tested planar against the target at landing ("i-frames at landing", spec
## /mechanics/enemy-attacks "kind"). The parabolic arc is
## swept against world geometry; a blocked lob is consumed without a blast.
## The web schematic has no world collision. #629.

const LOB_FLIGHT_TIME := 0.9  # fsm.ts LOB_FLIGHT_TIME
const TARGET_RADIUS := 0.5    # enemy_base.gd PLAYER_HIT_RADIUS

var from := Vector3.ZERO       # release position
var to := Vector3.ZERO         # landing point (the target's position at release)
var flight_time := LOB_FLIGHT_TIME
var blast_radius := 1.6        # = attack hit_reach
var damage := 1
var knockdown := false
var target: Node3D             # distance-tested at landing

var _t := 0.0
var _spent := false


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.4, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.9, 0.4)
	mat.emission_energy_multiplier = 1.5
	sm.material = mat
	mi.mesh = sm
	add_child(mi)


func _physics_process(delta: float) -> void:
	if _spent or is_queued_for_deletion():
		return
	var duration := maxf(flight_time, 0.001)
	var end := minf(_t + maxf(delta, 0.0), duration)
	# Bounded arc segments avoid slow-frame chords cutting through the ground.
	while _t < end:
		var next := minf(_t + 0.025, end)
		var start := _arc_position(_t / duration)
		var finish := _arc_position(next / duration)
		var wall := ProjectileSweep.environment_fraction(get_world_3d().direct_space_state,
			start, finish - start, 0.22)
		if wall >= 0.0:
			global_position = start.lerp(finish, wall)
			_spent = true
			queue_free()
			return
		global_position = finish
		_t = next

	if _t < duration:
		return

	# Landed — AoE around the landing point; hit_reach is the blast radius.
	_spent = true
	EnemyLob.spawn_ring(get_parent(), to, blast_radius)
	if is_instance_valid(target):
		var to_target := target.global_position - to
		to_target.y = 0.0
		var cover := PhysicsRayQueryParameters3D.create(to + Vector3.UP * 0.3,
			target.global_position + Vector3.UP * 0.5, 1)
		var dodging: bool = target.has_method("is_dodge_iframed") and target.is_dodge_iframed()
		if to_target.length() <= blast_radius + TARGET_RADIUS and not dodging \
				and get_world_3d().direct_space_state.intersect_ray(cover).is_empty() \
				and target.has_method("take_damage"):
			target.take_damage(damage, Vector3.ZERO, knockdown)
	queue_free()


func _arc_position(fraction: float) -> Vector3:
	# Keep the grenade center above the floor at landing.
	var pos := from.lerp(to + Vector3.UP * 0.25, fraction)
	pos.y += sin(fraction * PI) * 2.5
	return pos


## Shared expanding ground ring marking an AoE (the lob's landing blast, the leap's
## landing, the kamikaze self-destruct, boss shockwaves) — one implementation,
## every caller.
static func spawn_ring(parent: Node, pos: Vector3, radius: float) -> void:
	if not parent:
		return
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.6
	tm.outer_radius = radius * 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.2, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.material = mat
	ring.mesh = tm
	parent.add_child(ring)
	ring.global_position = Vector3(pos.x, pos.y + 0.2, pos.z)
	var tw := ring.create_tween()
	tw.parallel().tween_property(ring, "scale", Vector3.ONE * 1.4, 0.4)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.tween_callback(ring.queue_free)

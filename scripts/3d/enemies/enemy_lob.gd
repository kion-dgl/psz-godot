class_name EnemyLob extends Node3D
## A lobbed grenade in flight (attack kind `lob`) — Godot port of fsm.ts
## `Lob`/`stepDeliveries`. Released once at the damaging-window open toward the
## target's position AT RELEASE (leading it is the player's problem); after
## LOB_FLIGHT_TIME it lands for area damage — `hit_reach` is the blast radius,
## tested planar against the target at landing ("i-frames at landing", spec
## /mechanics/enemy-attacks "kind"). The parabolic visual arc is presentation
## only; the sim model is the 2D landing point. #629.

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
	_t += delta
	var f := clampf(_t / flight_time, 0.0, 1.0)
	global_position = from.lerp(to, f)
	global_position.y += sin(f * PI) * 2.5  # presentation-only arc

	if _t < flight_time:
		return

	# Landed — AoE around the landing point; hit_reach is the blast radius.
	_spawn_blast(blast_radius)
	if target and is_instance_valid(target):
		var to_target := target.global_position - to
		to_target.y = 0.0
		if to_target.length() <= blast_radius + TARGET_RADIUS and target.has_method("take_damage"):
			target.take_damage(damage, Vector3.ZERO, knockdown)
	queue_free()


func _spawn_blast(radius: float) -> void:
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
	var parent := get_parent()
	if parent:
		parent.add_child(ring)
		ring.global_position = Vector3(to.x, to.y + 0.2, to.z)
		var tw := ring.create_tween()
		tw.parallel().tween_property(ring, "scale", Vector3.ONE * 1.4, 0.4)
		tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.4)
		tw.tween_callback(ring.queue_free)

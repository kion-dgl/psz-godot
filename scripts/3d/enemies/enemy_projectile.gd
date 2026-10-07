class_name EnemyProjectile extends Node3D
## A straight enemy projectile in flight (attack kind `projectile`) — Godot port
## of fsm.ts `Projectile`/`stepDeliveries`. Released once at the damaging-window
## open along the facing locked at attack start; travels at PROJECTILE_SPEED,
## hits the target on planar contact (target radius + PROJECTILE_RADIUS), and
## expires at max_range = max(hit_reach, 1). One resolution: a contact during
## the target's dodge i-frames consumes the projectile for no damage (the
## player's take_damage no-ops), matching "i-frames at impact" (spec
## /mechanics/enemy-attacks "kind"). Manually stepped (not physics-driven) so
## the motion matches the web sim exactly and stays testable headless. #629.

const PROJECTILE_SPEED := 10.0   # fsm.ts PROJECTILE_SPEED
const PROJECTILE_RADIUS := 0.25  # fsm.ts PROJECTILE_RADIUS
const TARGET_RADIUS := 0.5       # enemy_base.gd PLAYER_HIT_RADIUS

var dir := Vector3.FORWARD      # XZ-normalized travel direction (locked facing)
var speed := PROJECTILE_SPEED
var max_range := 10.0           # traveled beyond this → expire (no hit)
var damage := 1
var knockdown := false
var color := Color(1.0, 0.5, 0.1)  # warm default; techs/attacks may recolor
var target: Node3D              # the player — distance-tested each step
var on_hit: Callable = Callable()  # optional extra effect (e.g. the lily's poison DoT)

var technique_id := ""
var hit_budget: Dictionary = {}

var _traveled := 0.0
var _hit := false


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = PROJECTILE_RADIUS + 0.1
	sm.height = (PROJECTILE_RADIUS + 0.1) * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	sm.material = mat
	if not technique_id.is_empty():
		var shard := PrismMesh.new()
		shard.size = Vector3(0.45, 0.65, 1.0)
		shard.material = mat
		mi.mesh = shard
	else:
		mi.mesh = sm
	add_child(mi)


func _physics_process(delta: float) -> void:
	if _hit or is_queued_for_deletion():
		return
	var step := minf(maxf(speed * delta, 0.0), maxf(max_range - _traveled, 0.0))
	var motion := dir.normalized() * step
	if is_instance_valid(target):
		var fraction := ProjectileSweep.planar_fraction(global_position, motion,
			target.global_position, TARGET_RADIUS + PROJECTILE_RADIUS)
		if fraction >= 0.0:
			global_position += motion * fraction
			_hit = true
			_resolve_contact()
			queue_free()
			return
	global_position += motion
	_traveled += step
	if _traveled >= max_range:
		queue_free()


func _resolve_contact() -> void:
	var key := target.get_instance_id()
	if hit_budget.has(key):
		return
	hit_budget[key] = true
	if target.has_method("is_dodge_iframed") and target.is_dodge_iframed():
		return
	if not technique_id.is_empty() and target.has_method("take_technique_hit"):
		target.take_technique_hit(damage, technique_id)
	elif target.has_method("take_damage"):
		target.take_damage(damage, Vector3.ZERO, knockdown)
	if on_hit.is_valid() and is_instance_valid(target):
		on_hit.call(target)

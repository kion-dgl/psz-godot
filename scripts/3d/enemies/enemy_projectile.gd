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
	mi.mesh = sm
	add_child(mi)


func _physics_process(delta: float) -> void:
	var step := speed * delta
	global_position += dir * step
	_traveled += step

	if target and is_instance_valid(target) and not _hit:
		var to := target.global_position - global_position
		to.y = 0.0
		if to.length() <= TARGET_RADIUS + PROJECTILE_RADIUS:
			_hit = true
			if target.has_method("take_damage"):
				target.take_damage(damage, Vector3.ZERO, knockdown)
			if on_hit.is_valid():
				on_hit.call(target)
			queue_free()
			return

	if _traveled >= max_range:
		queue_free()

extends Node3D
class_name ShrapnelBurst
## One-shot break shrapnel: individual tumbling shard nodes thrown radially
## with an upward bias, falling under gravity, plus a short hot flash.
## Hand-rolled instead of CPUParticles3D so every fragment is a real
## MeshInstance3D with its own size, spin and arc — and because draw_mesh
## assignment from GDScript proved unreliable on this engine build.
##
## The original's container-break effect id is still undecoded (no
## per-container entry in the effect factory tables); sizes/tint come from
## the broken element.

const SELF := preload("res://scripts/3d/elements/shrapnel_burst.gd")

const SHARD_COUNT := 18
const LIFETIME := 0.9
const SPEED_MIN := 3.0
const SPEED_MAX := 6.5

var _age := 0.0
var _shards: Array = []      # {node, velocity, spin: Vector3}
var _flash: OmniLight3D


static func spawn(parent: Node3D, at: Vector3, base_size: float, tint: Color) -> void:
	var burst: Node3D = SELF.new()
	burst.position = at
	burst._build(base_size, tint)
	parent.call_deferred("add_child", burst)


func _build(base_size: float, tint: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in SHARD_COUNT:
		var shard := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var s := base_size * rng.randf_range(0.5, 1.4)
		mesh.size = Vector3(s * rng.randf_range(0.6, 1.2), s, s * rng.randf_range(0.4, 0.9))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint.darkened(rng.randf_range(0.0, 0.25))
		mat.roughness = 0.9
		mesh.material = mat
		shard.mesh = mesh
		shard.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		add_child(shard)
		var yaw := rng.randf() * TAU
		var pitch := deg_to_rad(rng.randf_range(15.0, 80.0))  # upward-biased radial
		var speed := rng.randf_range(SPEED_MIN, SPEED_MAX)
		_shards.append({
			"node": shard,
			"velocity": Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * speed,
			"spin": Vector3(rng.randf_range(-14.0, 14.0), rng.randf_range(-14.0, 14.0), rng.randf_range(-14.0, 14.0)),
		})
	_flash = OmniLight3D.new()
	_flash.omni_range = base_size * 6.0
	_flash.light_energy = 3.0
	_flash.light_color = Color(1.0, 0.62, 0.25)
	add_child(_flash)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	for shard in _shards:
		var node: Node3D = shard["node"]
		shard["velocity"] = Vector3(shard["velocity"].x, shard["velocity"].y - 14.0 * delta, shard["velocity"].z)
		node.position += shard["velocity"] * delta
		node.rotation += Vector3(shard["spin"]) * delta
	if _flash:
		_flash.light_energy = maxf(0.0, 3.0 * (1.0 - _age / 0.2))
		if _flash.light_energy <= 0.0:
			_flash.queue_free()
			_flash = null

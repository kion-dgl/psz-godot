extends EnemyLob
## Rising guided arc, then a committed descent; uses the viewer's missile part.
var rare := false
var bend := Vector3.ZERO
var mesh: Node3D

func _ready() -> void:
	var path := "res://assets/enemies/tank_missiles/b_152m.glb" if rare else "res://assets/enemies/tank_missiles/b_052m.glb"
	mesh = load(path).instantiate()
	add_child(mesh)
	SmoothNormals.ensure(mesh, 2)
	SmoothNormals.make_lit(mesh)

func _physics_process(delta: float) -> void:
	# Freeze guidance before descent so the final approach can be sidestepped.
	if _t < flight_time * 0.5 and is_instance_valid(target):
		var next := to.move_toward(target.global_position, 5.0 * minf(delta, flight_time * 0.5 - _t))
		var fraction := _t / flight_time
		from -= (next - to) * fraction / (1.0 - fraction)
		to = next
	var before := global_position
	super._physics_process(delta)
	var direction := global_position - before
	if not direction.is_zero_approx():
		var up := Vector3.RIGHT if absf(direction.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
		mesh.global_basis = Basis.looking_at(direction.normalized(), up)

func _arc_position(fraction: float) -> Vector3:
	return super._arc_position(fraction) + bend * sin(fraction * PI)

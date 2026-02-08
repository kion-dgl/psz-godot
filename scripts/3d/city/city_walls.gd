extends Node3D
class_name CityWalls
## Generates invisible collision walls from data arrays.
## Each entry: [x, y, z, length, rotation_y]
## Creates StaticBody3D children with BoxShape3D for containment.

const WALL_HEIGHT := 5.0
const WALL_THICKNESS := 0.5


func create_walls(wall_data: Array) -> void:
	for i in range(wall_data.size()):
		var data: Array = wall_data[i]
		var pos := Vector3(float(data[0]), float(data[1]), float(data[2]))
		var wall_length: float = float(data[3])
		var rot_y: float = float(data[4])

		var body := StaticBody3D.new()
		body.name = "Wall_%d" % i
		body.collision_layer = 1  # Environment layer
		body.collision_mask = 0
		body.position = pos
		body.rotation.y = rot_y

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WALL_THICKNESS, WALL_HEIGHT, wall_length)
		shape.shape = box
		shape.position.y = WALL_HEIGHT / 2.0

		body.add_child(shape)
		add_child(body)

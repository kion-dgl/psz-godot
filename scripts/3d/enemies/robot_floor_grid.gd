class_name RobotFloorGrid extends Node3D
## ov22:02198450 timing, nine independent slots. Grid centers: ov22:021A0EC0; cell lookup: 02198778.
var counters: Array[int] = [-1,-1,-1,-1,-1,-1,-1,-1,-1]
var tiles: Array[MeshInstance3D] = []
const CELL_SIZE := 10.0

func _ready() -> void:
	for index in 9:
		var tile := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE*(CELL_SIZE-0.15)
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		plane.material = material
		tile.mesh = plane
		tile.position = Vector3((index%3-1)*CELL_SIZE,0.08,(index/3-1)*CELL_SIZE)
		tile.visible = false
		add_child(tile)
		tiles.append(tile)

func pulse(indices: Array) -> void:
	for index in indices:
		if int(index) >= 0 and int(index) < 9 and counters[int(index)] < 0: counters[int(index)] = -2

func advance() -> void:
	for index in 9:
		if counters[index] == -1: continue
		counters[index] = 0 if counters[index] == -2 else counters[index]+1
		if counters[index] >= 150: counters[index] = -1
		if tiles.is_empty(): continue
		var tile := tiles[index]
		tile.visible = counters[index] >= 0
		var material := (tile.mesh as PlaneMesh).material as StandardMaterial3D
		material.albedo_color = Color(0.2,0.75,1.0,0.8) if damaging(index) else Color(1,0.65,0.05,0.6 if counters[index] >= 90 else 0.3+0.15*sin(counters[index]*0.3))

func damaging(index: int) -> bool:
	return counters[index] >= 105 and counters[index] < 150

func cell_at(point: Vector3) -> int:
	var local := to_local(point)
	var x := clampi(int((local.x+15.0)/CELL_SIZE),0,2)
	var z := clampi(int((local.z+15.0)/CELL_SIZE),0,2)
	return z*3+x

func stop() -> void:
	counters.fill(-1)
	for tile in tiles: tile.hide()

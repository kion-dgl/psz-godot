class_name ReyburnPath extends RefCounted
## ov20:02198898 + ARM9:02091FF0/02091C20. Q12 natural cubic, 16 samples.
## Coordinates are arena-local retail units, not the moving boss's home point.
var samples: Array[Vector3i] = []
var distances: Array[int] = []
var position := Vector3i.ZERO
var motion := Vector3i.ZERO
var distance := 0
var speed := 0
var wanted_speed := 0
var gain := 0
var active := false

static func mul(a: int, b: int) -> int:
	return (a*b + 2048) >> 12

static func divide(a: int, b: int) -> int:
	return int(floor(float((a << 12) + (b >> 1))/float(b)))

static func scaled(v: Vector3i, amount: int) -> Vector3i:
	return Vector3i(mul(v.x,amount),mul(v.y,amount),mul(v.z,amount))

static func magnitude(v: Vector3i) -> int:
	return int(floor(sqrt(float(v.x*v.x+v.y*v.y+v.z*v.z))+0.5))

static func raw(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x*4096),roundi(v.y*4096),roundi(v.z*4096))

static func vector(v: Vector3i) -> Vector3:
	return Vector3(v)/4096.0

func begin(points: Array[Vector3i], velocity: int, attraction: int, reset_speed := false) -> void:
	_build(points)
	position = points[0]
	distance = 0
	wanted_speed = velocity
	if reset_speed: speed = velocity
	gain = attraction
	active = samples.size() > 1

func tick() -> Vector3i:
	motion = scaled(motion,3789)
	if active:
		speed = move_toward(speed,wanted_speed,410)
		distance += speed
		if distance >= distances.back():
			active = false
		else:
			var index := 0
			while index+1 < distances.size()-1 and distances[index+1] < distance: index += 1
			var weight := divide(distance-distances[index],distances[index+1]-distances[index])
			var point := scaled(samples[index],4096-weight)+scaled(samples[index+1],weight)
			motion += scaled(point-position,gain)
			var length := magnitude(motion)
			if length > speed: motion = scaled(scaled(motion,divide(4096,length)),speed)
	position += motion
	return position

func _build(points: Array[Vector3i]) -> void:
	var total := magnitude(points[0])
	var p: Array[Vector3i] = [points[0]]
	var h: Array[int] = [0]
	var knots: Array[int] = [0]
	for i in range(1,points.size()):
		var length := magnitude(points[i]-points[i-1])
		total += length
		if length > 0:
			p.append(points[i]); h.append(length); knots.append(knots.back()+length)
	var spacing := divide(total,16*4096)
	var n := p.size()
	var upper: Array[int] = []; upper.resize(n); upper.fill(0)
	var lower := upper.duplicate()
	var diagonal := upper.duplicate(); diagonal.fill(8192)
	var factor := upper.duplicate()
	var rhs: Array[Vector3i] = []; rhs.resize(n); rhs.fill(Vector3i.ZERO)
	var y := rhs.duplicate()
	var second := rhs.duplicate()
	for i in range(1,n-1):
		upper[i] = divide(h[i+1],h[i]+h[i+1])
		lower[i] = 4096-upper[i]
		rhs[i] = scaled(scaled(p[i+1]-p[i],divide(4096,h[i+1]))-scaled(p[i]-p[i-1],divide(4096,h[i])),divide(24576,h[i]+h[i+1]))
	for i in range(2,n-1):
		factor[i] = divide(lower[i],diagonal[i-1])
		diagonal[i] = 8192-mul(factor[i],upper[i-1])
	if n > 2: y[1] = rhs[1]
	for i in range(2,n-1): y[i] = rhs[i]-scaled(y[i-1],factor[i])
	for i in range(n-2,0,-1): second[i] = scaled(y[i]-scaled(second[i+1],upper[i]),divide(4096,diagonal[i]))
	samples = [p[0]]; distances = [0]
	var along := 0
	for i in range(1,n):
		var inverse := divide(4096,h[i])
		while along < knots[i]:
			if samples.size() >= 16: return
			along = mini(along+spacing,knots[i])
			var a := knots[i]-along
			var b := along-knots[i-1]
			var ca := mul(mul(mul(a,a),a),inverse)-mul(a,h[i])
			var cb := mul(mul(mul(b,b),b),inverse)-mul(b,h[i])
			var curve := scaled(scaled(second[i-1],ca)+scaled(second[i],cb),683)
			var linear := scaled(scaled(p[i-1],a)+scaled(p[i],b),inverse)
			samples.append(curve+linear); distances.append(along)

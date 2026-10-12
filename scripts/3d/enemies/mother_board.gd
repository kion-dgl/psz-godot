class_name MotherBoard extends RefCounted
## Authored movement on s07z_na1's visible 4-unit squares. Local to Trinity's root.
## The northern row is reserved for her body-entry zone, never a landing square.
const STEP := 4.0
var owners: Dictionary = {}
var occupied: Dictionary = {}
var destinations: Dictionary = {}

static func center(cell: Vector2i) -> Vector3:
	return Vector3((cell.x - 2) * STEP, 0, 6.0 + cell.y * STEP)

static func valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < 5 and cell.y >= 0 and cell.y < 4

func claim(piece: int, cell: Vector2i) -> bool:
	if not valid(cell) or owners.has(cell) or occupied.has(piece):
		return false
	owners[cell] = piece
	occupied[piece] = cell
	return true

func reserve_hop(piece: int, target_local: Vector3) -> Vector2i:
	var current: Vector2i = occupied[piece]
	if destinations.has(piece):
		return destinations[piece]
	var best := current
	var score := INF
	for y in range(current.y - 1, current.y + 2):
		for x in range(current.x - 1, current.x + 2):
			var cell := Vector2i(x, y)
			if not valid(cell) or owners.has(cell):
				continue
			var distance := center(cell).distance_squared_to(target_local)
			if distance < score:
				best = cell
				score = distance
	if best != current:
		owners[best] = piece
		destinations[piece] = best
	return best

func land(piece: int) -> void:
	if not destinations.has(piece):
		return
	owners.erase(occupied[piece])
	occupied[piece] = destinations[piece]
	destinations.erase(piece)

func release(piece: int) -> void:
	if occupied.has(piece):
		owners.erase(occupied[piece])
	if destinations.has(piece):
		owners.erase(destinations[piece])
	occupied.erase(piece)
	destinations.erase(piece)

extends RefCounted
## Deterministic occupancy interleavings, including reservations and death in flight.
static func run(t: Node) -> void:
	var board := MotherBoard.new()
	for piece in 3:
		t.assert_true(board.claim(piece, Vector2i(piece + 1, 1)), "distinct starting squares")
	t.assert_true(not board.claim(3, Vector2i(1,1)), "occupied square rejects second piece")
	t.assert_true(not board.claim(3, Vector2i(5,0)), "off-board square rejected")
	var sources := board.occupied.duplicate()
	for piece in 3:
		var destination := board.reserve_hop(piece, Vector3(0,0,6))
		t.assert_true(destination != sources[piece], "free neighbor chosen toward player")
		t.assert_eq(board.owners[sources[piece]], piece, "takeoff square retained during hop")
		t.assert_eq(board.owners[destination], piece, "destination reserved before motion")
	t.assert_eq(board.owners.size(), 6, "three distinct takeoff and destination squares")
	board.release(1)
	t.assert_eq(board.owners.size(), 4, "death in flight releases both squares")
	for piece in [2,0]: board.land(piece)
	t.assert_eq(board.owners.size(), 2, "landing releases old squares")
	var safe := true
	for tick in 300:
		var piece: int = [0,2][tick % 2]
		var aim := Vector3(sin(float(tick)) * 8, 0, 6 + float(tick % 4) * 4)
		var cell := board.reserve_hop(piece, aim)
		safe = safe and MotherBoard.valid(cell) and board.owners[cell] == piece
		if tick % 3 != 0: board.land(piece)
		var cells: Array = board.occupied.values() + board.destinations.values()
		var unique: Dictionary = {}
		for claimed in cells: unique[claimed] = true
		safe = safe and unique.size() == cells.size()
	t.assert_true(safe, "300 alternating reservations never collide or leave the floor grid")
	board.release(0)
	board.release(2)
	t.assert_true(board.owners.is_empty(), "encounter cleanup leaves no reservations")
	t.assert_eq(MotherBoard.center(Vector2i(0,0)), Vector3(-8,0,6), "grid aligns with northwest playable tile")
	t.assert_eq(MotherBoard.center(Vector2i(4,3)), Vector3(8,0,18), "grid aligns with southeast tile")

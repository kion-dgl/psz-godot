extends RefCounted
static func run(t: Node) -> void:
	for phase in 3:
		var threshold: int = [3072,2048,1024][phase]
		t.assert_true(HumiliasRules.split_due(phase,1800,threshold,4096,0),"inclusive Q12 phase boundary")
		t.assert_true(not HumiliasRules.split_due(phase,1799,threshold,4096,0),"cooldown before split")
		t.assert_true(not HumiliasRules.split_due(phase,1800,threshold+1,4096,0),"HP above phase threshold")
	t.assert_true(not HumiliasRules.split_due(3,9999,0,4096,0),"three HP split requests maximum")
	var grid := RobotFloorGrid.new()
	grid.pulse([0,8])
	for tick in 151:
		grid.advance()
		t.assert_eq(grid.damaging(0),tick >= 105 and tick < 150,"original floor attack interval")
		t.assert_true(not grid.damaging(4),"unselected spatial tile stays safe")
	# World transform queries require an attached node.
	t.add_child(grid)
	t.assert_eq(grid.cell_at(Vector3(-10,0,-10)),0,"first original floor center")
	t.assert_eq(grid.cell_at(Vector3(10,0,10)),8,"last original floor center")
	t.assert_eq(grid.cell_at(Vector3(-5,0,0)),4,"inclusive boundary enters next cell")
	t.assert_eq(grid.cell_at(Vector3(99,0,-99)),2,"retail lookup clamps outside arena")
	grid.free()

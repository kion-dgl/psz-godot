extends RefCounted
## Shared live encounter, ordinary AI, no forced attack choices. Verify every
## member participates and the return pipe waits for the LAST kill.
static func run(player: Node3D, group_id: String) -> bool:
	var tree := player.get_tree()
	var ids: Array = ColiseumRoster.MIXED_GROUPS[group_id].enemies
	var enemies: Array[EnemyBase] = []
	for frame in range(1200):
		enemies.clear()
		for node in tree.get_nodes_in_group("enemies"):
			if node is EnemyBase and node.enemy_data.id in ids:
				enemies.append(node)
		if enemies.size() == ids.size(): break
		await tree.physics_frame
	if enemies.size() != ids.size():
		print("[mixed] wrong spawn count ", enemies.size(), " expected ", ids.size())
		return false
	player.set_physics_process(false)
	player.global_position = Vector3(0,0.5,6)
	var attacks := {}
	for enemy in enemies:
		enemy.reveal()
		enemy.target = player
	for frame in range(900):
		GameState.set_hp(82)
		await tree.physics_frame
		for enemy in enemies:
			if enemy.is_attacking:
				attacks[enemy.enemy_data.id] = str(enemy._attack_def.get("id", ""))
		if _has_pipe(tree.current_scene): return false
	var participates := attacks.size() == ids.size()
	print("[mixed] ", group_id, " ordinary attacks=", attacks, " all participated=", participates)
	# Keep the last member alive and dormant to exercise the room-clear counter.
	var last := enemies.back() as EnemyBase
	last.dormant = true
	last.set_physics_process(false)
	for i in range(enemies.size()-1): enemies[i]._die()
	for frame in range(180): await tree.physics_frame
	if _has_pipe(tree.current_scene):
		print("[mixed] FAIL early room clear while last member alive")
		return false
	last._die()
	for frame in range(300):
		await tree.physics_frame
		if _has_pipe(tree.current_scene):
			print("[mixed] ", group_id, " last-kill return PASS=true")
			return participates
	print("[mixed] FAIL no return pipe after final kill")
	return false

static func _has_pipe(node: Node) -> bool:
	if node.name == "Telepipe": return true
	for child in node.get_children():
		if _has_pipe(child): return true
	return false

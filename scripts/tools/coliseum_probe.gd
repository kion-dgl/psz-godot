extends Node
## Headless end-to-end probe for the Coliseum Master 1:1 flow (#629): run the
## exact warp chain coliseum_pick._start_battle uses, then verify the live field —
## stage s00a_nr2 loads, the chosen enemy spawns and damages the player through
## the real attack machinery, and killing it spawns the room-clear telepipe home.
## Prints [coliseum] checkpoints; the oracle is "[coliseum] DONE ok" + exit 0.
## Run: godot --headless --path . res://scripts/tools/coliseum_probe.tscn
##
## The watcher must live on the tree ROOT: goto_scene frees the current scene
## (this probe), so the observing node is re-parented above the scene swap.

const FIELD_SCENE := "res://scenes/3d/field/valley_field.tscn"
const ENEMY_ID := "hildegigas"  # exercises threat display → charge/leap machinery live
const TIMEOUT_SEC := 240.0


func _ready() -> void:
	DebugConfig.verbose_field = true  # [RoomClear]/[CellObjects] traces for the probe log
	# Minimal session (the seeded-test recipe): a character so the player spawns
	# with a model and stats, then the picker's warp chain verbatim.
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	CharacterManager.create_character(0, "humar", "ProbeHero")
	CharacterManager.set_active_slot(0)

	SessionManager.enter_quest("debug_coliseum", "normal")
	SessionManager.set_field_sections(ColiseumRoster.make_sections(ENEMY_ID))
	print("[coliseum] warping: sections=%d cell=%s objects=%d" % [
		SessionManager.get_field_sections().size(),
		str(SessionManager.get_field_sections()[0]["cells"][0].get("stage_id", "?")),
		(SessionManager.get_field_sections()[0]["cells"][0].get("objects", []) as Array).size()])
	var watcher := Watch.new()
	watcher.enemy_id = ENEMY_ID
	# Deferred: the root is mid-setup during this scene's _ready, so a direct
	# add_child is rejected; the deferred attach still lands before the swap.
	get_tree().root.add_child.call_deferred(watcher)
	SceneManager.goto_scene(FIELD_SCENE, ColiseumRoster.warp_data())


## Root-level observer: survives the scene transition and asserts the live loop.
class Watch extends Node:
	var enemy_id := "hildegigas"
	var elapsed := 0.0
	var hp0 := -1
	var damaged := false
	var killed := false

	func _process(delta: float) -> void:
		elapsed += delta
		if elapsed > TIMEOUT_SEC:
			_fail("timed out after %.0fs (damaged=%s killed=%s)" % [elapsed, str(damaged), str(killed)])
			return

		var player: Node3D = _first_in_group("player")
		var enemy: EnemyBase = _find_enemy()

		if player == null:
			return  # field still loading
		if hp0 < 0:
			hp0 = GameState.hp
			print("[coliseum] field up: player in place (hp=%d)" % hp0)

		if not damaged:
			if enemy == null:
				return  # field still loading
			# The spawner places the enemy dormant; a start-cell enemy normally
			# reveals on room entry — force it after a grace second so the probe
			# never waits on the reveal stagger.
			if enemy.dormant:
				if elapsed > 1.0:
					enemy.reveal()
				return
			if not enemy.is_alive:
				_fail("enemy died before damaging the player")
				return
			# Keep the probe hero alive through the swings (player-death is not
			# what this probe tests) — top up once the machinery has proven it hits.
			if GameState.hp < hp0:
				damaged = true
				print("[coliseum] enemy landed damage through the live attack model (hp %d -> %d)" % [hp0, GameState.hp])
				print("[coliseum] state=%s kind=%s anim='%s'" % [
					str(enemy.current_state), str(enemy._attack_kind), enemy._attack_anim])
			elif GameState.hp < 30:
				GameState.set_hp(hp0)
			return

		# Damage proven — kill the enemy, then wait for the room-clear telepipe.
		if not killed:
			if enemy != null and enemy.is_alive:
				enemy._die()
				print("[coliseum] probe killed the enemy — expecting room-clear telepipe")
			killed = true
			return
		if _find_telepipe_under(get_tree().current_scene) != null:
			print("[coliseum] room-clear telepipe spawned after the kill")
			print("[coliseum] DONE ok")
			get_tree().quit(0)

	func _fail(msg: String) -> void:
		print("[coliseum] FAIL: %s" % msg)
		get_tree().quit(1)

	func _first_in_group(group: String) -> Node3D:
		var nodes := get_tree().get_nodes_in_group(group)
		return nodes[0] as Node3D if nodes.size() > 0 else null

	func _find_enemy() -> EnemyBase:
		for n in get_tree().get_nodes_in_group("enemies"):
			var e := n as EnemyBase
			if e and e.enemy_data and str(e.enemy_data.id) == enemy_id:
				return e
		return null

	## Match by node name ("Telepipe" — what _spawn_telepipe names it): the
	## `is Telepipe` class check from this inner class does not match the
	## field's preloaded script instance (observed in the probe run).
	func _find_telepipe_under(root: Node) -> Node:
		if root == null:
			return null
		if String(root.name) == "Telepipe":
			return root
		for c in root.get_children():
			var found := _find_telepipe_under(c)
			if found:
				return found
		return null

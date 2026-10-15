extends RefCounted
## Bounded interaction observation, shared by the unit and live harness.
const DELAY := 2.0
const MAX_ATTEMPTS := 3
var attempts := 0
var remaining := 0.0
var finished := false

func tick(delta: float, observed: bool, same_scene: bool = true) -> String:
	if finished:
		return "done"
	if observed or not same_scene:
		finished = true
		return "done"
	remaining -= delta
	if remaining > 0.0:
		return "wait"
	if attempts >= MAX_ATTEMPTS:
		finished = true
		return "fail"
	attempts += 1
	remaining = DELAY
	return "press"

## Poll each frame: an overlay can open and close within the retry delay.
static func watch(host: Node, expected: String) -> void:
	var retry = load("res://scripts/tools/interaction_retry.gd").new()
	var tree := host.get_tree()
	var scene := tree.current_scene
	var delta := 0.0
	while is_instance_valid(host):
		var observed: bool = SceneManager._scene_stack.has(expected)
		var action: String = retry.tick(delta, observed,
			is_instance_valid(scene) and scene == tree.current_scene)
		match action:
			"done": return
			"fail":
				host._fail_and_quit(failure_detail(tree, expected))
				return
			"press":
				print("[sanity] interact attempt %d/%d expecting %s" % [retry.attempts, MAX_ATTEMPTS, expected])
				host._press_action("interact")
		await tree.process_frame
		delta = host.get_process_delta_time()

static func failure_detail(tree: SceneTree, expected: String) -> String:
	var player := tree.get_first_node_in_group("player")
	var nearest: Node = player.get("nearest_interactable") if player else null
	var position = player.global_position if player is Node3D else null
	return "interact at %s found no expected response — player=%s nearest_interactable=%s expected=%s" % [
		position, position, str(nearest.name) if is_instance_valid(nearest) else "null", expected]

class_name BossModelChannel extends RefCounted
## Independent model/action channel, sharing its owning boss's HP and cleanup.
signal attack_tick(channel: BossModelChannel)
var clock := BossActionClock.new()
var model: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var channel := 0
var action_id := -1
var ticks := 0
var busy := false
var _actions: Array = []
var _queue: Array = []
var _idle := 23
var _hold := 0
var _pose := ""

func setup(parent: Node3D, index: int, mesh: PackedScene, library: AnimationLibrary, actions: Array, idle: int = -1) -> void:
	channel = index
	_idle = idle if idle >= 0 else (23 if index < 5 else 44)
	_actions = actions
	model = mesh.instantiate()
	model.name = "BossChannel%d" % index
	parent.add_child(model)
	player = NodeUtils.first_of_type(model,"AnimationPlayer") as AnimationPlayer
	skeleton = NodeUtils.first_of_type(model,"Skeleton3D") as Skeleton3D
	if library:
		for name in player.get_animation_library_list(): player.remove_animation_library(name)
		player.add_animation_library("",library)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	clock.stage_changed.connect(_stage_changed)
	clock.finished.connect(_next)

func play(actions: Array) -> void:
	_queue = actions.duplicate(true)
	busy = not _queue.is_empty()
	_next()

func _next() -> void:
	var entry: Variant = _idle
	if not _queue.is_empty(): entry = _queue.pop_front()
	else: busy = false
	action_id = int(entry.id) if entry is Dictionary else int(entry)
	_hold = int(entry.get("ticks",0)) if entry is Dictionary else 0
	ticks = 0
	var limits := {0:-1} if _hold > 0 or not busy else {}
	clock.begin(_actions[action_id],limits)

func tick() -> void:
	ticks += 1
	clock.advance(1.0/30.0)
	if player and not _pose.is_empty(): player.seek(clock.frame_q12/4096.0/60.0,true)
	attack_tick.emit(self)
	if _hold > 0 and ticks >= _hold: _next()

func _stage_changed(descriptor: Dictionary) -> void:
	_pose = str(descriptor.member).get_basename()
	if not player.has_animation(_pose):
		push_error("Missing boss channel %d clip %s" % [channel,_pose])
		_pose = ""
		return
	player.play(_pose)
	player.seek(0,true)

func stop() -> void:
	clock.cancel()
	_queue.clear()
	busy = false

func anchor() -> Transform3D:
	return model.global_transform

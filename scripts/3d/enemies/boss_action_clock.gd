class_name BossActionClock extends RefCounted
## Descriptor stages own playback, including explicit finite/infinite loop budgets.
## Imported GLBs use 60 fps; the encounter simulation uses 30 action ticks/sec.
## Controller transitions/loop budgets remain the caller's responsibility.

signal event_fired(record: Dictionary)
signal stage_changed(descriptor: Dictionary)
signal cycle_finished(stage_index: int, cycle: int)
signal finished

var action: Dictionary = {}
var stage := 0
var frame_q12 := 0
var running := false
var cycles := 0
var _limits: Dictionary = {}
var _events := BossActionEvents.new()
var _fraction := 0.0
var _pending_finish := false

func begin(descriptor: Dictionary, loop_limits: Dictionary = {}) -> void:
	cancel()
	action = descriptor
	_limits = loop_limits
	stage = 0
	frame_q12 = 0
	cycles = 0
	_fraction = 0.0
	_pending_finish = false
	running = not action.get("stages", []).is_empty()
	_events.begin(action)
	if running:
		stage_changed.emit(action.stages[stage])
		_sample()

func cancel() -> void:
	running = false
	for record in _events.cancel():
		event_fired.emit(record)

func advance(delta: float) -> void:
	_fraction += delta * 30.0
	while _fraction >= 1.0 and running:
		_fraction -= 1.0
		_tick()

func _tick() -> void:
	if _pending_finish:
		var carry := _fraction
		cancel()
		finished.emit()
		# A controller may synchronously begin its next action from finished.
		# Keep unconsumed catch-up ticks instead of losing time at that boundary.
		_fraction = carry
		return
	var descriptor: Dictionary = action.stages[stage]
	var end := (int(descriptor.clip_frames) - 1) * 4096
	frame_q12 += int(descriptor.playback_rate_raw)
	_sample()
	if frame_q12 < end:
		return
	cycles += 1
	cycle_finished.emit(stage, cycles)
	var limit := int(_limits.get(stage, 1))
	if bool(descriptor.loop) and (limit < 0 or cycles < limit):
		frame_q12 = 0
		_sample()
		return
	if stage + 1 == action.stages.size():
		_pending_finish = true
	else:
		stage += 1
		cycles = 0
		frame_q12 = 0
		stage_changed.emit(action.stages[stage])
		_sample()

func _sample() -> void:
	for record in _events.sample(stage, frame_q12, bool(action.stages[stage].loop)):
		event_fired.emit(record)

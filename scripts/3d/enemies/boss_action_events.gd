class_name BossActionEvents extends RefCounted
## Original descriptor event dispatch, separated from AI and animation playback.
## Port of the stage/frame crossing rules in ARM9 FUN_0204123C.
## Feed actual animation stage and Q12 frame position, once per animation update.
## Each model channel needs its own instance. This does not advance animation,
## choose attacks, apply damage, or interpret unresolved payloads.

const ONE := 4096

var _events: Array = []
var _states := PackedInt32Array() # 0 pending, 1 active window, 2 completed
var _previous_stage := -1
var _previous_frame := 0


func begin(action: Dictionary) -> Array[Dictionary]:
	var released := cancel()
	_events = action.get("events", []).duplicate(true)
	_states.resize(_events.size())
	_states.fill(0)
	_previous_stage = -1
	_previous_frame = 0
	return released


func cancel() -> Array[Dictionary]:
	var released: Array[Dictionary] = []
	for index in _events.size():
		if _states[index] == 1:
			released.append(_emission("window_end", index, true))
	_events.clear()
	_states.clear()
	_previous_stage = -1
	return released


func sample(stage: int, frame_q12: int, looping: bool = false) -> Array[Dictionary]:
	var emitted: Array[Dictionary] = []
	for index in _events.size():
		var state := _states[index]
		if state == 2:
			continue
		var event: Dictionary = _events[index]
		var window := bool(event.get("window_flag", false))
		var boundary_stage := int(event["start_stage"] if state == 0 else event["end_stage"])
		var boundary_frame := int(event["frame"] if state == 0 else event["second_frame"]) * ONE
		var passed_before := _at_or_after(_previous_stage, _previous_frame, boundary_stage, boundary_frame)
		var wrapped_here := stage == _previous_stage and frame_q12 < _previous_frame and stage == boundary_stage
		if _at_or_after(stage, frame_q12, boundary_stage, boundary_frame) and (not passed_before or wrapped_here):
			if state == 0 and window:
				_states[index] = 1
				emitted.append(_emission("window_start", index))
			else:
				_states[index] = 2
				emitted.append(_emission("window_end" if state == 1 else "point", index))
		elif state == 1:
			# Original class-0 active callback follows its bone/entity every update.
			emitted.append(_emission("window_update", index))
		# A loop re-arms points and windows contained in this one stage. Cross-stage
		# windows stay completed. The previous-frame crossing guard prevents duplicates.
		if _states[index] == 2 and looping:
			if not window or (stage == int(event["start_stage"]) and stage == int(event["end_stage"])):
				_states[index] = 0
	_previous_stage = stage
	_previous_frame = frame_q12
	return emitted


func _emission(kind: String, index: int, interrupted: bool = false) -> Dictionary:
	return {"kind": kind, "index": index, "event": _events[index].duplicate(true), "interrupted": interrupted}


static func _at_or_after(stage: int, frame: int, boundary_stage: int, boundary_frame: int) -> bool:
	return stage > boundary_stage or (stage == boundary_stage and frame >= boundary_frame)

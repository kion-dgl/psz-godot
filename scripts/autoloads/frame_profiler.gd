extends Node
## FrameProfiler — lightweight per-frame timing that logs slow frame breakdowns.
## Toggle with DebugConfig.profile_frames (P key in debug menu).
##
## Usage from any script:
##   FrameProfiler.mark("label")
##
## Call mark() at section boundaries. At end of each frame, if total exceeds
## SLOW_FRAME_MS, prints a breakdown of time between marks.

const SLOW_FRAME_MS := 20.0  # Log frames slower than this (50fps threshold)
const COOLDOWN_FRAMES := 60  # At most one log per this many frames

var _marks: Array = []  # [{label: String, time: int}]
var _frame_start: int = 0
var _cooldown: int = 0


func mark(label: String) -> void:
	if DebugConfig.profile_frames:
		_marks.append({"label": label, "time": Time.get_ticks_usec()})


func _physics_process(_delta: float) -> void:
	if not DebugConfig.profile_frames:
		_marks.clear()
		_frame_start = 0
		return

	# Check if previous frame was slow
	if _frame_start > 0 and _marks.size() > 0 and _cooldown <= 0:
		var frame_end: int = Time.get_ticks_usec()
		var frame_ms: float = (frame_end - _frame_start) / 1000.0
		if frame_ms > SLOW_FRAME_MS:
			_log_slow_frame(frame_ms)
			_cooldown = COOLDOWN_FRAMES

	if _cooldown > 0:
		_cooldown -= 1

	# Reset for new frame
	_frame_start = Time.get_ticks_usec()
	_marks.clear()
	mark("frame_start")


func _log_slow_frame(frame_ms: float) -> void:
	var enemy_count: int = get_tree().get_nodes_in_group("enemies").size()
	var parts: PackedStringArray = PackedStringArray()
	parts.append("[Profiler] SLOW %.1fms | %d enemies | %d FPS" % [
		frame_ms, enemy_count, Engine.get_frames_per_second()])

	# Print time between consecutive marks
	for i in range(1, _marks.size()):
		var prev_time: int = _marks[i - 1]["time"]
		var cur_time: int = _marks[i]["time"]
		var delta_ms: float = (cur_time - prev_time) / 1000.0
		if delta_ms > 0.5:  # Only show sections taking >0.5ms
			parts.append("  %s → %s: %.2fms" % [_marks[i - 1].label, _marks[i].label, delta_ms])

	# Time after the last mark is intentionally not logged — it includes idle
	# time spent waiting for the next frame.

	print("\n".join(parts))

class_name NavRepeat extends RefCounted
## Hold-to-repeat helper for menu navigation. Matches PSO GC scroll timing:
## 0.2s hold before auto-repeat, then 30 Hz ticks.
##
## Usage:
##     var _nav: NavRepeat
##     func _ready() -> void:
##         _nav = NavRepeat.new(["ui_up", "ui_down"], _on_nav_repeat)
##     func _process(delta: float) -> void:
##         _nav.tick(delta)
##     func _on_nav_repeat(action: String) -> void:
##         var ev := InputEventAction.new()
##         ev.action = action
##         ev.pressed = true
##         _unhandled_input(ev)
##
## The initial press is still handled by your own _unhandled_input through the
## normal event flow — NavRepeat only fires the repeats. It does NOT feed
## synthetic events into Input.parse_input_event (that leaks "pressed" state
## globally when no release is sent); instead the callback dispatches directly
## to your own handler.

const HOLD := 0.2
const REPEAT := 1.0 / 30.0
## Right stick deflection above this threshold counts as "pressed" for ui_up/ui_down.
const RSTICK_DEADZONE := 0.3

var _actions: Array[String] = []
var _callback: Callable
var _held: Dictionary = {}
var _next: Dictionary = {}
var _axis_prev: Dictionary = {}  # action → was axis-active last tick


func _init(actions: Array, callback: Callable) -> void:
	for a in actions:
		var name: String = str(a)
		_actions.append(name)
		_held[name] = 0.0
		_next[name] = 0.0
		_axis_prev[name] = false
	_callback = callback


# Synthesize right-stick Y as ui_up / ui_down so menu scroll matches d-pad.
# No action is bound to the right stick globally — NavRepeat handles it so
# the stick stays free for in-game camera control.
func _axis_active(action: String) -> bool:
	if action == "ui_up":
		return Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y) < -RSTICK_DEADZONE
	if action == "ui_down":
		return Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y) > RSTICK_DEADZONE
	return false


func tick(delta: float) -> void:
	for action in _actions:
		var action_active: bool = Input.is_action_pressed(action)
		var axis_active: bool = _axis_active(action)
		var active: bool = action_active or axis_active

		# Initial synthetic press fires only when the stick transitions into
		# deflected — real action events (d-pad / keyboard) already reach the
		# menu's _unhandled_input via the normal input flow, so we don't want
		# NavRepeat to double-fire the first tap on those.
		var transitioned: bool = axis_active and not bool(_axis_prev[action])
		if transitioned:
			_callback.call(action)
		_axis_prev[action] = axis_active

		if active:
			var h: float = float(_held[action]) + delta
			_held[action] = h
			# Skip the repeat block on the frame we fired a transition press —
			# otherwise a large delta (frame hitch) past HOLD would trigger the
			# while-loop too and the cursor would double-step.
			if h >= HOLD and not transitioned:
				var n: float = float(_next[action]) - delta
				while n <= 0.0:
					_callback.call(action)
					n += REPEAT
				_next[action] = n
		else:
			_held[action] = 0.0
			_next[action] = 0.0


func reset() -> void:
	for action in _actions:
		_held[action] = 0.0
		_next[action] = 0.0
		_axis_prev[action] = false

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

var _actions: Array[String] = []
var _callback: Callable
var _held: Dictionary = {}
var _next: Dictionary = {}


func _init(actions: Array, callback: Callable) -> void:
	for a in actions:
		var name: String = str(a)
		_actions.append(name)
		_held[name] = 0.0
		_next[name] = 0.0
	_callback = callback


func tick(delta: float) -> void:
	for action in _actions:
		if Input.is_action_pressed(action):
			var h: float = float(_held[action]) + delta
			_held[action] = h
			if h >= HOLD:
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

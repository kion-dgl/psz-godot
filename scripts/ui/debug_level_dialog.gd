class_name DebugLevelDialog extends ConfirmDialog
## Shared level editor for System → Debug and the Coliseum controls.
var value := 1
var allow_auto := false
var _value_label: Label
var _repeat: NavRepeat

func configure(title: String, initial: int, auto: bool = false) -> void:
	allow_auto = auto
	value = clampi(initial, 0 if auto else 1, 100)
	ask(title + "\n↑↓ ±1   ←→ ±10   Enter Apply   Esc Cancel")
	_refresh_value()

func _build_body(vbox: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	for amount in [-10, -1, 0, 1, 10]:
		if amount == 0:
			_value_label = Label.new()
			_value_label.custom_minimum_size.x = 110
			_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_value_label.add_theme_font_size_override("font_size", 26)
			row.add_child(_value_label)
		else:
			var button := Button.new()
			button.text = "%+d" % amount
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(func(): _change(amount))
			row.add_child(button)

func _ready() -> void:
	super._ready()
	_yes_button.text = "Apply"
	_no_button.text = "Cancel"
	_repeat = NavRepeat.new(["ui_up","ui_down","ui_left","ui_right"], _navigate)
	_refresh_value()

func _input(event: InputEvent) -> void:
	for action in ["ui_up","ui_down","ui_left","ui_right"]:
		if event.is_action_pressed(action):
			_navigate(action)
			get_viewport().set_input_as_handled()
			return
	super._input(event)

func _process(delta: float) -> void:
	if _repeat: _repeat.tick(delta)

func _navigate(action: String) -> void:
	_change({"ui_up":1,"ui_down":-1,"ui_left":-10,"ui_right":10}[action])

func _change(amount: int) -> void:
	value = clampi(value + amount, 0 if allow_auto else 1, 100)
	_refresh_value()

func _refresh_value() -> void:
	if _value_label: _value_label.text = "Auto" if value == 0 and allow_auto else "Lv.%d" % value

static func edit(parent: Node, title: String, initial: int, auto: bool, applied: Callable) -> DebugLevelDialog:
	var dialog := DebugLevelDialog.new()
	dialog.configure(title, initial, auto)
	dialog.confirmed.connect(func(): applied.call(dialog.value))
	parent.add_child(dialog)
	return dialog

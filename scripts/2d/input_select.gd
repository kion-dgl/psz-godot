extends Control
## InputSelect — multi-step input onboarding shown when no
## input_config.json exists (and re-entered from settings'
## "Reconfigure Controls" entry).
##
## Flow:
##   1. DETECT — wait for first input event
##      • InputEventKey       → device = keyboard, save defaults, done
##      • Any joypad event    → device = controller, continue
##   2. MAP_FACE × 4 — press the south, east, west, north face buttons
##      in turn; capture each button index. Duplicates re-prompt.
##   3. PICK_ACCEPT — choose which face button is accept: left / bottom
##      / right (west / south / east).
##   4. PICK_CANCEL — choose cancel from the remaining two faces.
##   5. Save + go back to title (or pop overlay if launched from in-game).
##
## We deliberately don't ask "Xbox / Switch / PlayStation" — the player's
## actual presses give us the button indices directly, and accept-position
## handles the JP-vs-Western flip. No per-key keyboard remapping yet
## (international layout complaints will trigger that work; for now
## keyboard uses the defaults already in project.godot).

const KENNEY_BASE := "res://assets/kenney_input-prompts/"

enum Step {
	DETECT,
	MAP_SOUTH,
	MAP_EAST,
	MAP_WEST,
	MAP_NORTH,
	PICK_ACCEPT,
	PICK_CANCEL,
	DONE,
}

const MAP_ORDER := ["south", "east", "west", "north"]

const POSITION_PROMPT := {
	"south": "Press the BOTTOM face button",
	"east":  "Press the RIGHT face button",
	"west":  "Press the LEFT face button",
	"north": "Press the TOP face button",
}
const POSITION_HINT := {
	"south": "Xbox A  •  Switch B  •  PS Cross",
	"east":  "Xbox B  •  Switch A  •  PS Circle",
	"west":  "Xbox X  •  Switch Y  •  PS Square",
	"north": "Xbox Y  •  Switch X  •  PS Triangle",
}

## Three accept-button options in physical-layout order (left → bottom →
## right). Labels stay generic (no Cross/Circle/A/B) since we no longer ask
## the player what controller they have.
const ACCEPT_OPTIONS := [
	{
		"id": "west",
		"label": "Left",
		"sublabel": "uncommon",
	},
	{
		"id": "south",
		"label": "Bottom",
		"sublabel": "Xbox / PS default",
	},
	{
		"id": "east",
		"label": "Right",
		"sublabel": "Nintendo / PSZ JP",
	},
]

const CARD_WIDTH := 200
const CARD_HEIGHT := 200
const ICON_SIZE := 110

var _step: int = Step.DETECT
var _selected: int = 0
var _controller_type: String = ""
var _face: Dictionary = {}     # "south"|"east"|"west"|"north" → button_index
var _accept_position: String = "south"
var _cancel_position: String = "east"
# Built fresh per PICK_CANCEL show by filtering ACCEPT_OPTIONS down to the
# faces the player didn't pick as accept.
var _cancel_options_view: Array = []

var _title: Label
var _prompt: Label
var _hint: Label
var _options_row: HBoxContainer
var _cards: Array = []

# Modal panel chrome — input_select renders as a fixed-size centered panel
# that slides in from the top. When pushed as an overlay (via the in-game
# "Reconfigure Controls" path) the push_scene dim provides the screen tint
# behind it; on the boot first-run path we draw our own fullscreen bg so
# the panel doesn't sit on a black void.
const MODAL_W := 880.0
const MODAL_H := 540.0
const MODAL_SLIDE_DISTANCE := 700.0   # px above center to start from
const MODAL_SLIDE_IN_SEC := 0.35
const MODAL_SLIDE_OUT_SEC := 0.22
var _panel: PanelContainer
var _is_overlay: bool = false


func _ready() -> void:
	_is_overlay = SceneManager.can_pop()

	if not _is_overlay:
		# Boot first-run path: nothing behind us, so fill the screen with
		# the legacy dark-navy bg. The overlay path skips this because
		# SceneManager.push_scene already drew a 50% dim layer underneath.
		var bg := ColorRect.new()
		bg.color = Color(0.0353, 0.0588, 0.1020, 1)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -MODAL_W * 0.5
	_panel.offset_right = MODAL_W * 0.5
	_set_panel_y_offset(0.0)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	margin.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color(0.94, 0.93, 0.97))
	vbox.add_child(_title)

	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.add_theme_color_override("font_color", Color(0.85, 0.86, 0.92))
	vbox.add_child(_prompt)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.65, 0.66, 0.74))
	vbox.add_child(_hint)

	_options_row = HBoxContainer.new()
	_options_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_options_row.add_theme_constant_override("separation", 16)
	vbox.add_child(_options_row)

	_show_detect()

	# Slide in from the top — start above-screen, ease to centered.
	_set_panel_y_offset(-MODAL_SLIDE_DISTANCE)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_panel_y_offset, -MODAL_SLIDE_DISTANCE, 0.0, MODAL_SLIDE_IN_SEC)


func _set_panel_y_offset(y: float) -> void:
	# Helper for the slide tween: shift the centered panel up/down by `y`
	# pixels (0 = centered). Used by both the open-in and close-out tweens.
	if _panel == null:
		return
	_panel.offset_top = -MODAL_H * 0.5 + y
	_panel.offset_bottom = MODAL_H * 0.5 + y


# ── Step renderers ────────────────────────────────────────────────────

func _show_detect() -> void:
	_step = Step.DETECT
	_title.text = "Controls Setup"
	_prompt.text = "Press any key or controller button to begin"
	_hint.text = "Keyboard or controller will be auto-detected"
	_clear_cards()


func _show_face_map(position: String) -> void:
	_step = {
		"south": Step.MAP_SOUTH,
		"east": Step.MAP_EAST,
		"west": Step.MAP_WEST,
		"north": Step.MAP_NORTH,
	}[position]
	_title.text = "Map Face Buttons (%d/4)" % (MAP_ORDER.find(position) + 1)
	_prompt.text = POSITION_PROMPT[position]
	_hint.text = POSITION_HINT[position]
	_clear_cards()


func _show_accept_pick() -> void:
	_step = Step.PICK_ACCEPT
	_title.text = "Accept Button"
	_prompt.text = "Which button accepts menus?"
	_hint.text = "Left/Right to choose, press any face button to confirm"
	# Default highlight on "Bottom" (south), the most common pick.
	_selected = 1
	_build_cards(ACCEPT_OPTIONS)


func _show_cancel_pick() -> void:
	_step = Step.PICK_CANCEL
	_title.text = "Cancel Button"
	_prompt.text = "Which button cancels / closes menus?"
	_hint.text = "Left/Right to choose, press any face button to confirm"
	# Filter to the faces the player didn't pick as accept. Two cards left.
	_cancel_options_view.clear()
	for opt in ACCEPT_OPTIONS:
		if str(opt["id"]) != _accept_position:
			_cancel_options_view.append(opt)
	# Default to the option that the legacy "south if accept != south else
	# east" rule would have picked, so the common case lands on the typical
	# Xbox / JP cancel position with zero extra presses.
	var default_cancel: String = "south" if _accept_position != "south" else "east"
	_selected = 0
	for i in _cancel_options_view.size():
		if str(_cancel_options_view[i]["id"]) == default_cancel:
			_selected = i
			break
	_build_cards(_cancel_options_view)


# ── Card UI for PICK_TYPE / PICK_ACCEPT ───────────────────────────────

func _clear_cards() -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	for child in _options_row.get_children():
		_options_row.remove_child(child)
		child.queue_free()


func _build_cards(options: Array) -> void:
	_clear_cards()
	for i in options.size():
		var card := _build_card(options[i])
		_options_row.add_child(card)
		_cards.append(card)
	_refresh_card_styles()


func _build_card(option: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 8)
	panel.add_child(inner)

	if option.has("icon"):
		var icon := TextureRect.new()
		var tex := load(KENNEY_BASE + str(option["icon"])) as Texture2D
		if tex:
			icon.texture = tex
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		inner.add_child(icon)

	var caption := Label.new()
	caption.text = str(option["label"])
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", Color(0.94, 0.93, 0.97))
	inner.add_child(caption)

	if option.has("sublabel"):
		var sub := Label.new()
		sub.text = str(option["sublabel"])
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size", 13)
		sub.add_theme_color_override("font_color", Color(0.75, 0.76, 0.84))
		inner.add_child(sub)

	return panel


func _refresh_card_styles() -> void:
	for i in _cards.size():
		var panel: PanelContainer = _cards[i]
		var style := StyleBoxFlat.new()
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		if i == _selected:
			style.bg_color = Color(0.2, 0.3, 0.45, 0.9)
			style.border_width_left = 3
			style.border_width_right = 3
			style.border_width_top = 3
			style.border_width_bottom = 3
			style.border_color = Color(1.0, 0.9, 0.5)
		else:
			style.bg_color = Color(0.1, 0.1, 0.12, 0.7)
			style.border_width_left = 1
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1
			style.border_color = Color(0.3, 0.3, 0.35)
		panel.add_theme_stylebox_override("panel", style)


# ── Input handling ────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# _input runs BEFORE _unhandled_input — handle here so we can capture
	# raw joypad button events for the face-mapping steps without them
	# being filtered by the existing action bindings (which we're about
	# to overwrite anyway).
	match _step:
		Step.DETECT:
			_on_detect_event(event)
		Step.MAP_SOUTH, Step.MAP_EAST, Step.MAP_WEST, Step.MAP_NORTH:
			_on_face_map_event(event)
		Step.PICK_ACCEPT:
			_on_pick_card_event(event, ACCEPT_OPTIONS, Callable(self, "_on_accept_confirmed"))
		Step.PICK_CANCEL:
			_on_pick_card_event(event, _cancel_options_view, Callable(self, "_on_cancel_confirmed"))
		Step.DONE:
			pass


func _on_detect_event(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Keyboard path. Skip the whole controller flow.
		InputConfig.set_keyboard()
		_finish()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.pressed:
		_face.clear()
		_show_face_map(MAP_ORDER[0])
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		_face.clear()
		_show_face_map(MAP_ORDER[0])
		get_viewport().set_input_as_handled()
		return


func _on_pick_card_event(event: InputEvent, options: Array, on_confirm: Callable) -> void:
	if event.is_action_pressed("ui_left"):
		_selected = (_selected - 1 + options.size()) % options.size()
		_refresh_card_styles()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_right"):
		_selected = (_selected + 1) % options.size()
		_refresh_card_styles()
		get_viewport().set_input_as_handled()
		return
	# Any joypad button press confirms. We don't care which physical face
	# the user pressed at this stage — they navigated to a selection with
	# the d-pad, and any face press moves us forward.
	if event is InputEventJoypadButton and event.pressed:
		on_confirm.call(options[_selected])
		get_viewport().set_input_as_handled()
		return
	# Keyboard fallback for navigating + confirming via keyboard.
	if event.is_action_pressed("ui_accept"):
		on_confirm.call(options[_selected])
		get_viewport().set_input_as_handled()
		return


func _on_face_map_event(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton and event.pressed):
		return
	var btn_idx: int = (event as InputEventJoypadButton).button_index
	var position: String = _current_map_position()
	# Reject duplicates — that button is already assigned to a different
	# position. Stay on the same prompt; the player can press a different
	# button.
	for existing in _face.keys():
		if existing != position and int(_face[existing]) == btn_idx:
			_hint.text = "That button is already mapped to %s. Press a different face button." % existing.to_upper()
			get_viewport().set_input_as_handled()
			return
	_face[position] = btn_idx
	var next_idx: int = MAP_ORDER.find(position) + 1
	if next_idx < MAP_ORDER.size():
		_show_face_map(MAP_ORDER[next_idx])
	else:
		# All 4 positions mapped — always ask which face is accept, no
		# auto-shortcut from controller type (we don't know the type now).
		_show_accept_pick()
	get_viewport().set_input_as_handled()


func _on_accept_confirmed(option: Dictionary) -> void:
	_accept_position = str(option["id"])
	# Derive a controller_type for the legacy scheme name so icon-glyph /
	# settings-label callers still work. Mapping is approximate — west-accept
	# falls under "playstation" since the Square-accept layout is closest.
	_controller_type = {
		"south": "xbox",
		"east": "switch",
		"west": "playstation",
	}.get(_accept_position, "xbox")
	_show_cancel_pick()


func _on_cancel_confirmed(option: Dictionary) -> void:
	_cancel_position = str(option["id"])
	_save_and_finish()


func _current_map_position() -> String:
	return {
		Step.MAP_SOUTH: "south",
		Step.MAP_EAST: "east",
		Step.MAP_WEST: "west",
		Step.MAP_NORTH: "north",
	}[_step]


func _save_and_finish() -> void:
	InputConfig.set_controller_config(_controller_type, _face, _accept_position, _cancel_position)
	_finish()


func _finish() -> void:
	_step = Step.DONE
	SfxManager.play("res://assets/sfx/ui/title_start.wav")

	# Slide the modal back up before routing so the close motion matches the
	# open motion. After the slide, two callers diverge:
	#   • Bootstrap first-run onboarding → no overlay stack → go to title
	#   • In-game start menu "Reconfigure Controls" → pushed as overlay →
	#     pop ourselves so the gameplay scene under us comes back
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.tween_method(_set_panel_y_offset, 0.0, -MODAL_SLIDE_DISTANCE, MODAL_SLIDE_OUT_SEC)
	await tween.finished

	if SceneManager.can_pop():
		SceneManager.pop_scene()
	else:
		SceneManager.goto_scene("res://scenes/2d/title.tscn")

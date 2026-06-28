class_name DefeatScreen extends CanvasLayer
## The "You were defeated" screen (spec /states/player-death).
##
## Raised by the field controller when the player's HP reaches 0. A translucent
## red layer covers the play area BELOW the HUD (this CanvasLayer sits under
## FieldHud's layer 200, so the HP/PP panel stays visible on top), and a
## PSZ-style prompt asks whether to return to the city.
##
##   Yes → run the defeat transaction (SessionManager.defeat_return_to_city:
##         50% carried-meseta penalty, full-HP revive, session end) and travel
##         to the city counter at the telepipe-arrival spot — no telepipe used.
##   No  → stays on the prompt (the only exit is Yes).
##
## Built programmatically (no .tscn) and self-frees via the scene transition.

const LAYER := 190  # Below FieldHud (200) so the red sits under the HUD.
const RED_ALPHA := 0.42
const FADE_TIME := 0.4
const CITY_COUNTER := "res://scenes/3d/city/city_counter.tscn"

var _red: ColorRect
var _yes_button: Button
var _no_button: Button
var _focused_idx: int = 0  # 0 = Yes, 1 = No
var _confirming: bool = false
var _modal_pushed: bool = false


func _init() -> void:
	name = "DefeatScreen"
	layer = LAYER
	# Keep responding even if something pauses the tree mid-defeat.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	add_to_group("defeat_screen")

	# Translucent red wash over the whole play area; fades in.
	_red = ColorRect.new()
	_red.color = Color(0.6, 0.0, 0.0, 0.0)
	_red.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_red.mouse_filter = Control.MOUSE_FILTER_STOP  # absorb clicks behind it
	add_child(_red)
	var tween := create_tween()
	tween.tween_property(_red, "color:a", RED_ALPHA, FADE_TIME)

	_build_prompt()

	# Block gameplay input while the prompt is up (movement, attacks, menus).
	GameState.push_modal()
	_modal_pushed = true

	SfxManager.play("res://assets/sfx/ui/dialog_open.wav")
	print("[sanity] checkpoint: defeat-screen-shown")


func _build_prompt() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	# Back-most scanline overlay — the same tiling texture the shop white cards
	# use (PszStyle.scanline_texture), so the box reads as a PSZ panel.
	var scan := TextureRect.new()
	scan.texture = PszStyle.scanline_texture()
	scan.stretch_mode = TextureRect.STRETCH_TILE
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(scan)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	# Keep the scanlines behind the content.
	panel.move_child(scan, 0)

	var title := Label.new()
	title.text = "You were defeated"
	title.add_theme_font_size_override("font_size", PszStyle.FONT_TITLE + 4)
	title.add_theme_color_override("font_color", PszStyle.TEXT_DANGER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var question := Label.new()
	question.text = "Would you like to return to the city?"
	question.add_theme_font_size_override("font_size", PszStyle.FONT_ITEM)
	question.add_theme_color_override("font_color", PszStyle.TEXT)
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question.custom_minimum_size = Vector2(380, 0)
	vbox.add_child(question)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	_yes_button = _make_button("Yes")
	_no_button = _make_button("No")
	hbox.add_child(_yes_button)
	hbox.add_child(_no_button)
	_yes_button.pressed.connect(confirm_return)
	_no_button.pressed.connect(_decline)

	_focused_idx = 0
	_refresh_focus()


func _input(event: InputEvent) -> void:
	if _confirming:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_focused_idx = 1 - _focused_idx
		SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		_refresh_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if _focused_idx == 0:
			confirm_return()
		else:
			_decline()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		# Cancel maps to "No" — it MUST NOT be an escape hatch out of the screen.
		_decline()
		get_viewport().set_input_as_handled()


## "Yes" — apply the defeat consequences and travel to the city. Public so the
## autopilot defeat probe can drive it deterministically without input timing.
func confirm_return() -> void:
	if _confirming:
		return
	_confirming = true
	SfxManager.play("res://assets/sfx/ui/menu_select.wav")
	var result: Dictionary = SessionManager.defeat_return_to_city()
	print("[sanity] checkpoint: defeat-return-to-city meseta %d -> %d (lost %d)" % [
		int(result.get("meseta_before", 0)),
		int(result.get("meseta_after", 0)),
		int(result.get("meseta_lost", 0)),
	])
	# Pop the modal before the scene tears down so GameState.modal_stack doesn't
	# leak a count into the city.
	if _modal_pushed:
		GameState.pop_modal()
		_modal_pushed = false
	# Arrive where a telepipe would (the counter's telepipe-arrival spot). No
	# telepipe is consumed or spawned — return_to_city already cleared any pipe.
	CityState.set_spawn_key("telepipe-arrival")
	SceneManager.goto_scene(CITY_COUNTER)


## "No" — stays on the prompt. Per spec the only way off this screen is Yes.
func _decline() -> void:
	SfxManager.play("res://assets/sfx/ui/menu_back.wav")


func _notification(what: int) -> void:
	# Safety net: if this screen is ever freed without the Yes path (it normally
	# isn't), release the modal so input doesn't stay blocked.
	if what == NOTIFICATION_PREDELETE and _modal_pushed:
		GameState.pop_modal()
		_modal_pushed = false


# ── Styling (mirrors ConfirmDialog so the prompt matches the rest of the UI) ──

func _refresh_focus() -> void:
	PszStyle.apply_pill_button_style(_yes_button, _focused_idx == 0)
	PszStyle.apply_pill_button_style(_no_button, _focused_idx == 1)


func _make_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(96, 36)
	btn.focus_mode = Control.FOCUS_NONE  # focus visuals are managed manually
	btn.add_theme_font_size_override("font_size", PszStyle.FONT_ITEM)
	btn.add_theme_color_override("font_color", PszStyle.TEXT)
	btn.add_theme_color_override("font_hover_color", PszStyle.TEXT)
	btn.add_theme_color_override("font_pressed_color", PszStyle.TEXT)
	btn.add_theme_color_override("font_focus_color", PszStyle.TEXT)
	return btn


## PSZ white scan-lined card: near-opaque white bg (scanlines layered on top),
## a blue border with a heavier TOP edge, asymmetric corners (rounded top,
## squared bottom), and a soft drop shadow so it floats over the red wash.
const PANEL_BG := Color(1.0, 1.0, 1.0, 0.95)
const PANEL_BORDER := Color(0.30, 0.52, 0.82)  # PSZ blue

static func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.border_color = PANEL_BORDER
	# Thicker top edge (PSZ panel signature); thin on the other three sides.
	s.border_width_top = 5
	s.border_width_left = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	# Different radius on the two ends: rounded top, near-square bottom.
	s.corner_radius_top_left = 12
	s.corner_radius_top_right = 12
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	# Soft drop shadow.
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 5)
	s.content_margin_left = 28.0
	s.content_margin_right = 28.0
	s.content_margin_top = 22.0
	s.content_margin_bottom = 22.0
	return s

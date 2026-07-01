extends Control
## End credits roll — scrolling text over black background.
## Triggered after Dark Falz defeat. Pressing ui_accept, start, or touching
## the screen skips to the title screen. After the scroll finishes (or skip),
## fades to black and transitions to the title scene.

const SCROLL_SPEED := 40.0  # pixels per second

var _scrolling := true
var _fade_tween: Tween
var _scroll_container: Control
var _fade_overlay: ColorRect

# Credits content — each entry is [text, color, font_size]
var _credits_data: Array = []


func _ready() -> void:
	MusicManager.play_location_music("title")
	_build_credits_data()
	_build_ui()


func _build_credits_data() -> void:
	var h := ThemeColors.HEADER        # teal section headers
	var t := ThemeColors.HEADER_TEXT   # white regular text
	var d := ThemeColors.TEXT_SECONDARY # muted disclaimer

	_credits_data = [
		["PHANTASY STAR ZERO", t, 20],
		["Rebuilt in Godot", t, 16],
		["", t, 16],
		["", t, 16],

		["— Development —", h, 20],
		["", t, 16],
		["kion-dgl", t, 16],
		["Code, Design, Direction", t, 16],
		["", t, 16],
		["Rozalin", t, 16],
		["Playtesting, SFX Labeling", t, 16],
		["UI Mockups, Character Portraits", t, 16],
		["", t, 16],
		["", t, 16],

		["— Original Game —", h, 20],
		["", t, 16],
		["Phantasy Star Zero", t, 16],
		["SEGA / Sonic Team", t, 16],
		["", t, 16],
		["", t, 16],

		["— Music —", h, 20],
		["", t, 16],
		["Phantasy Star Zero Original Soundtrack", t, 16],
		["SEGA / Sonic Team", t, 16],
		["", t, 16],
		["", t, 16],

		["— Assets —", h, 20],
		["", t, 16],
		["Input Prompts, Nature Kit, Playing Cards Pack", t, 16],
		["Kenney (kenney.nl) — CC0", t, 16],
		["", t, 16],
		["Anime Combat Cowboy", t, 16],
		["Booth.pm — Saloon Blackjack Dealer", t, 16],
		["", t, 16],
		["Dairon City Stage Models", t, 16],
		["Calum \"Limitiv\" — limitiv.co.uk", t, 16],
		["", t, 16],
		["", t, 16],

		["— Engine —", h, 20],
		["", t, 16],
		["Godot 4.5", t, 16],
		["godotengine.org", t, 16],
		["", t, 16],
		["", t, 16],

		["— Special Thanks —", h, 20],
		["", t, 16],
		["The PSO community on Discord", t, 16],
		["for playtesting and feedback", t, 16],
		["", t, 16],
		["", t, 16],
		["", t, 16],

		["This is an unofficial fan project.", d, 13],
		["Phantasy Star, Phantasy Star Online,", d, 13],
		["and Phantasy Star Zero are trademarks of SEGA.", d, 13],
		["No affiliation with or endorsement", d, 13],
		["by SEGA is implied.", d, 13],
	]


func _build_ui() -> void:
	# Black background
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Scrolling container — holds all credit lines in a VBoxContainer
	_scroll_container = Control.new()
	_scroll_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_scroll_container)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.offset_left = -400
	vbox.offset_right = 400
	_scroll_container.add_child(vbox)

	# Add each credit line
	for entry in _credits_data:
		var text: String = entry[0]
		var color: Color = entry[1]
		var font_size: int = entry[2]

		var label := Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		var settings := LabelSettings.new()
		settings.font_color = color
		settings.font_size = font_size
		settings.shadow_color = Color(0, 0, 0, 0.6)
		settings.shadow_offset = Vector2(1, 1)
		settings.shadow_size = 2
		label.label_settings = settings

		# Empty lines still need height
		if text.is_empty():
			label.text = " "
			label.modulate.a = 0.0

		vbox.add_child(label)

	# Position the vbox so it starts just below the visible screen
	# We'll move it upward in _process
	vbox.position.y = get_viewport().get_visible_rect().size.y

	# Fade overlay — starts transparent, used for fade-out at end
	_fade_overlay = ColorRect.new()
	_fade_overlay.color = Color(0, 0, 0, 0)
	_fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_overlay)


func _process(delta: float) -> void:
	if not _scrolling:
		return

	var vbox := _scroll_container.get_child(0) as VBoxContainer
	vbox.position.y -= SCROLL_SPEED * delta

	# Check if all content has scrolled past the top
	var total_height := vbox.size.y
	if vbox.position.y < -total_height:
		_scrolling = false
		_fade_to_title()


func _unhandled_input(event: InputEvent) -> void:
	if not _scrolling:
		return

	var skip := false

	if event.is_action_pressed("ui_accept"):
		skip = true
	elif event.is_action_pressed("start"):
		skip = true
	elif event is InputEventScreenTouch and event.pressed:
		skip = true

	if skip:
		_scrolling = false
		get_viewport().set_input_as_handled()
		_fade_to_title()


func _fade_to_title() -> void:
	if _fade_tween:
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_overlay, "color:a", 1.0, 0.8)
	_fade_tween.tween_callback(func() -> void:
		SceneManager.goto_scene("res://scenes/2d/title.tscn")
	)

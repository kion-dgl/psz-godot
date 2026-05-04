extends Control
## Title screen — 3D backdrop (scenes/3d/ui/title_backdrop.tscn, via SubViewport)
## with "Press Start" prompt. Always routes to character-select on Start; the
## first-run controller prompt runs earlier, between bootstrap (logo check)
## and this scene (see bootstrap.gd::_goto_title).

@onready var prompt_label: Label = $VBox/PromptLabel
@onready var version_label: Label = $VBox/VersionLabel

var _blink_timer: float = 0.0
var _prompt_visible: bool = true
var _debug_guide: PanelContainer


func _ready() -> void:
	# Wipe any leftover quest/session state. If the player completed a
	# quest in field, returned to title without reporting at the guild,
	# and then re-entered the city, the guild counter would still show
	# the report option (and accepting it would credit the rewards
	# without re-running the mission). Reported by Rozalin.
	SessionManager.reset_all_state()

	MusicManager.play_location_music("title")
	prompt_label.text = "Press Start"
	# Local-build marker: CI sets the "ci" custom_feature flag in
	# export_presets.cfg before exporting. Local Godot exports leave it
	# empty, so OS.has_feature("ci") only returns true on official CI
	# builds. Anything Kion sideloads from his dev box gets a "-local"
	# suffix on the title screen so it's obvious which build is running.
	# The trailing number (when > 0) comes from BuildInfo.LOCAL_BUILD,
	# which scripts/tools/local_build_apk.sh increments on every export.
	# Lets the user confirm "did the new APK actually install?" by checking
	# whether the counter went up since they last looked.
	var app_version: String = ProjectSettings.get_setting("application/config/version", "0.0.0")
	var build_suffix := ""
	if not OS.has_feature("ci"):
		build_suffix = "-local"
		if BuildInfo.LOCAL_BUILD > 0:
			build_suffix += str(BuildInfo.LOCAL_BUILD)
	version_label.text = "PSZ Godot v%s%s" % [app_version, build_suffix]

	# Add text shadows for readability over the background image
	var prompt_settings := LabelSettings.new()
	prompt_settings.font_color = ThemeColors.HEADER_TEXT
	prompt_settings.shadow_color = Color(0, 0, 0, 0.8)
	prompt_settings.shadow_offset = Vector2(2, 2)
	prompt_settings.shadow_size = 3
	prompt_label.label_settings = prompt_settings

	var version_settings := LabelSettings.new()
	version_settings.font_color = ThemeColors.HINT_TEXT
	version_settings.shadow_color = Color(0, 0, 0, 0.8)
	version_settings.shadow_offset = Vector2(2, 2)
	version_settings.shadow_size = 3
	version_label.label_settings = version_settings

	_setup_debug_guide()


func _process(delta: float) -> void:
	_blink_timer += delta
	if _blink_timer >= 0.6:
		_blink_timer = 0.0
		_prompt_visible = not _prompt_visible
		if prompt_label.label_settings:
			prompt_label.label_settings.font_color = ThemeColors.TEXT_HIGHLIGHT if _prompt_visible else ThemeColors.HEADER_TEXT


func _open_input_debug() -> void:
	if get_tree().root.has_node("InputDebug"):
		return
	var debug_scene := preload("res://scripts/2d/input_debug.gd")
	var debug := debug_scene.new()
	debug.name = "InputDebug"
	get_tree().root.add_child(debug)


func _setup_debug_guide() -> void:
	_debug_guide = PanelContainer.new()
	_debug_guide.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.75)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	_debug_guide.add_theme_stylebox_override("panel", style)
	_debug_guide.anchor_left = 0.0
	_debug_guide.anchor_top = 0.0
	_debug_guide.offset_left = 12
	_debug_guide.offset_top = 12

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.4))
	label.text = "Field Debug (F1 to toggle)\n" \
		+ "F3   Toggle debug panel\n" \
		+ "F5   Triggers\n" \
		+ "F6   Gate markers\n" \
		+ "F7   Floor collision\n" \
		+ "F8   Spawn points\n" \
		+ "F9   All collision (labels)"
	_debug_guide.add_child(label)
	add_child(_debug_guide)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_debug_guide.visible = not _debug_guide.visible
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F2:
			_open_input_debug()
			get_viewport().set_input_as_handled()
			return

	# Select/Back button opens input debug
	if event is InputEventJoypadButton and event.pressed and event.button_index == 4:
		_open_input_debug()
		get_viewport().set_input_as_handled()
		return

	# Start game (but not if input debug is open)
	if get_tree().root.has_node("InputDebug"):
		return
	if event.is_action_pressed("ui_accept") \
			or event.is_action_pressed("start") \
			or (event is InputEventScreenTouch and event.pressed):
		SfxManager.play("res://assets/sfx/ui/title_start.wav")
		get_viewport().set_input_as_handled()
		SceneManager.goto_scene("res://scenes/2d/character_select.tscn")

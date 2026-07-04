extends CanvasLayer
## HudStats — persistent HP/PP/Lv stats panel (issue #444; spec /states/field-lifecycle).
##
## Promoted out of the per-scene FieldHud (pattern: PsoStartMenu) so an area
## transition (SceneManager.goto_scene → change_scene_to_file) can never free or
## rebuild it: the panel is an autoload CanvasLayer that stays in the tree,
## keeps rendering its last values while the world fades/reloads underneath,
## and reads live values straight from the GameState / CharacterManager
## autoloads. The per-scene FieldHud keeps the minimap, action palette, quick
## weapon menu and log — those are scene-specific and MAY rebuild per scene;
## only the stats panel is promoted.
##
## COMPILE CONTRACT: this script is an AUTOLOAD, so it MUST compile in
## repo-only CI (no downloaded asset pack — the pack mounts at runtime, after
## bootstrap). The panel backdrop (res://assets/hud/hp-pp.png) is pack-only:
## it is load()ed lazily behind ResourceLoader.exists and retried on every
## update until the pack mounts. NEVER preload() a pack path here — a parse
## failure on an autoload takes down the whole test run.

const LAYER := 200  # Above the PSO start menu (150); below the fade canvas (250)
const MARGIN := 12.0

var _stats_panel: StatsPanel
## True while the current scene is a gameplay scene (city / field). Held —
## deliberately NOT recomputed — while SceneManager is mid-transition, so the
## panel stays rendered (with its last values) across the fade + scene reload.
var _in_gameplay: bool = false


func _ready() -> void:
	layer = LAYER
	name = "HudStats"
	process_mode = Node.PROCESS_MODE_ALWAYS

	_stats_panel = StatsPanel.new()
	_stats_panel.visible = false  # Hidden until the first gameplay scene
	add_child(_stats_panel)
	_refresh_character_info()

	GameState.hp_changed.connect(_on_stats_changed)
	GameState.max_hp_changed.connect(_on_stats_changed)
	GameState.mp_changed.connect(_on_stats_changed)
	GameState.max_mp_changed.connect(_on_stats_changed)
	GameState.game_state_reset.connect(_on_game_state_reset)
	CharacterManager.level_up.connect(_on_level_up)
	CharacterManager.active_character_changed.connect(_on_active_character_changed)
	# SceneManager registers before this autoload (project.godot order), so it
	# is ready here.
	SceneManager.scene_changed.connect(_on_scene_changed)
	print("[HudStats] Ready — layer %d" % layer)


func _process(_delta: float) -> void:
	_update_visibility()


## Visibility contract (spec /states/field-lifecycle):
## - Rendered in gameplay scenes (res://scenes/3d/…) — city and field.
## - Stays rendered while SceneManager is transitioning (the whole point of
##   #444: the panel holds its last values under the world fade; it MUST NOT
##   blank for any frame of an area transition).
## - Stays rendered under the PSO start menu (layer 200 > 150) so the player
##   sees HP/PP while toggling options — the old FieldHud keep_stats rule.
## - Hidden under full-screen SceneManager overlays (shops, storage, guild,
##   reconfigure-controls) so the modal isn't drawn under the gameplay HUD.
## - Hidden on non-gameplay scenes (title, character select/create, 2D screens).
func _update_visibility() -> void:
	var scene: Node = get_tree().current_scene
	if scene != null and not SceneManager._transitioning:
		_in_gameplay = scene.scene_file_path.begins_with("res://scenes/3d/")
	var has_scene_overlay: bool = not SceneManager._overlay_stack.is_empty()
	_stats_panel.visible = _in_gameplay and not has_scene_overlay


## Re-read the active character's static info (level). Called on character
## switch and on every scene change so a fresh login shows the right level
## before the first level_up signal.
func _refresh_character_info() -> void:
	var ch = CharacterManager.get_active_character()
	if ch:
		_stats_panel.char_level = int(ch.get("level", 1))
	if _stats_panel.is_inside_tree():
		_stats_panel.update_display()


## Level display refresh for callers outside the CharacterManager.level_up
## signal path (e.g. cell_object_spawner's EXP award belt-and-suspenders).
func set_char_level(new_level: int) -> void:
	_stats_panel.char_level = new_level
	_stats_panel.update_display()


func _on_stats_changed(_value: int) -> void:
	_stats_panel.update_display()


func _on_game_state_reset() -> void:
	_stats_panel.update_display()


func _on_level_up(new_level: int) -> void:
	set_char_level(new_level)


func _on_active_character_changed(_slot: int) -> void:
	_refresh_character_info()


func _on_scene_changed(scene_path: String) -> void:
	# The panel node itself survived the transition (it is not part of the
	# freed scene); refresh values so the held display snaps to current state.
	_refresh_character_info()
	# Autopilot probe (#444, two-layer rule): report the panel's instance id on
	# every transition so the sanity run can assert it is NEVER freed/rebuilt.
	if OS.has_environment("PSZ_AUTOPILOT"):
		Autopilot.observe_hud_stats(_stats_panel.get_instance_id(), _stats_panel.is_inside_tree(), scene_path)


# ── Stats Panel (top-left) ───────────────────────────────────────────────────
# Moved verbatim from field_hud.gd's _StatsPanel (#444), except the backdrop
# texture: preload() became a lazy load() so this autoload compiles repo-only.

class StatsPanel extends Control:
	const BG_PATH := "res://assets/hud/hp-pp.png"
	const PANEL_W := 256.0
	const PANEL_H := 120.0
	const BAR_LEFT := 76.0
	const BAR_WIDTH := 160.0
	const BAR_HEIGHT := 7.0
	const HP_BAR_TOP := 62.0
	const PP_BAR_TOP := 98.0
	const LEVEL_FONT_SIZE := 16
	const VAL_FONT_SIZE := 14

	const HP_COLOR := Color(0.27, 0.85, 0.27)
	const PP_COLOR := Color(0.22, 0.56, 0.93)
	const LEVEL_COLOR := Color(1, 1, 1, 1)
	const VALUE_COLOR := Color(0, 0, 0, 1)
	const PANEL_SCALE := 0.8

	var char_level: int = 1

	var _bg: TextureRect
	var _level_label: Label
	var _hp_cur_label: Label
	var _hp_max_label: Label
	var _pp_cur_label: Label
	var _pp_max_label: Label
	var _hp_bar: ColorRect
	var _pp_bar: ColorRect

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		position = Vector2(MARGIN, MARGIN)
		size = Vector2(PANEL_W, PANEL_H)
		custom_minimum_size = size
		pivot_offset = Vector2.ZERO
		scale = Vector2(PANEL_SCALE, PANEL_SCALE)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

		_bg = TextureRect.new()
		_bg.position = Vector2.ZERO
		_bg.size = Vector2(PANEL_W, PANEL_H)
		_bg.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_bg)
		_ensure_bg_texture()

		_hp_bar = ColorRect.new()
		_hp_bar.color = HP_COLOR
		_hp_bar.position = Vector2(BAR_LEFT, HP_BAR_TOP)
		_hp_bar.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
		_hp_bar.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_hp_bar)

		_pp_bar = ColorRect.new()
		_pp_bar.color = PP_COLOR
		_pp_bar.position = Vector2(BAR_LEFT, PP_BAR_TOP)
		_pp_bar.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
		_pp_bar.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_pp_bar)

		_level_label = _make_label(Vector2(109, 13), Vector2(46, 22), LEVEL_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT, LEVEL_COLOR)
		_hp_cur_label = _make_label(Vector2(109, 40), Vector2(46, 18), VAL_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT, VALUE_COLOR)
		_hp_max_label = _make_label(Vector2(190, 40), Vector2(46, 18), VAL_FONT_SIZE, HORIZONTAL_ALIGNMENT_LEFT, VALUE_COLOR)
		_pp_cur_label = _make_label(Vector2(109, 76), Vector2(46, 18), VAL_FONT_SIZE, HORIZONTAL_ALIGNMENT_RIGHT, VALUE_COLOR)
		_pp_max_label = _make_label(Vector2(190, 76), Vector2(46, 18), VAL_FONT_SIZE, HORIZONTAL_ALIGNMENT_LEFT, VALUE_COLOR)

		update_display()

	## The hp-pp.png backdrop lives in the downloadable asset pack, which mounts
	## AFTER this autoload's _ready on a fresh install (and never in repo-only
	## CI). Retry on every update until it resolves — the bars and labels render
	## fine without the backdrop in the meantime. Mirrors PsoStartMenu's
	## lazy-icon contract: nulls are never cached, so a later pack mount
	## recovers without a restart.
	func _ensure_bg_texture() -> void:
		if _bg.texture != null:
			return
		if ResourceLoader.exists(BG_PATH):
			_bg.texture = load(BG_PATH)

	func _make_label(pos: Vector2, sz: Vector2, font_size: int, align: int, color: Color) -> Label:
		var lbl := Label.new()
		lbl.position = pos
		lbl.size = sz
		lbl.custom_minimum_size = sz
		lbl.horizontal_alignment = align
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", font_size)
		lbl.add_theme_color_override("font_color", color)
		lbl.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(lbl)
		return lbl

	func update_display() -> void:
		if not is_inside_tree():
			return
		_ensure_bg_texture()
		var hp: int = GameState.hp
		var max_hp: int = GameState.max_hp
		var pp: int = GameState.mp
		var max_pp: int = GameState.max_mp

		_level_label.text = str(char_level)
		_hp_cur_label.text = str(hp)
		_hp_max_label.text = str(max_hp)
		_pp_cur_label.text = str(pp)
		_pp_max_label.text = str(max_pp)

		var hp_ratio: float = clampf(float(hp) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 0.0
		var pp_ratio: float = clampf(float(pp) / float(max_pp), 0.0, 1.0) if max_pp > 0 else 0.0
		_hp_bar.size.x = BAR_WIDTH * hp_ratio
		_hp_bar.visible = hp_ratio > 0.0
		_pp_bar.size.x = BAR_WIDTH * pp_ratio
		_pp_bar.visible = pp_ratio > 0.0

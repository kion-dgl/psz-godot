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
## bootstrap). The panel is drawn by StartMenuMainSkin.NamePlate (Flauros
## restyle, playtest 2026-09-22 — it replaced the old pack-only hp-pp.png
## backdrop), which only touches repo-committed resources (VT323 from
## bootstrap/). NEVER preload() a pack path here — a parse failure on an
## autoload takes down the whole test run.

const LAYER := 200  # Above the PSO start menu (150); below the fade canvas (250)
const MARGIN := 16.0

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
		_stats_panel.set_char_name(str(ch.get("name", "???")))
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
# Restyled for the Flauros menu redesign (playtest 2026-09-22): the drawing
# lives in StartMenuMainSkin.NamePlate so the persistent HUD and the start
# menu's MAIN page are literally the same component. This shell keeps
# HudStats' public surface (char_level / update_display) and the stable
# instance id the autopilot observes across scene changes.

class StatsPanel extends Control:
	var char_level: int = 1  # kept for set_char_level callers; the plate draws no level
	var _plate: StartMenuMainSkin.NamePlate
	var _char_name: String = "???"

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		position = Vector2(16.0, 16.0)
		size = StartMenuMainSkin._v(StartMenuMainSkin.NAME_SIZE)
		_plate = StartMenuMainSkin.NamePlate.new()
		_plate.position = Vector2.ZERO
		add_child(_plate)
		_plate.setup_plate(_char_name)
		update_display()

	func set_char_name(new_name: String) -> void:
		_char_name = new_name
		if _plate != null:
			_plate.set_name_text(new_name)

	func update_display() -> void:
		if not is_inside_tree() or _plate == null:
			return
		var hp: int = GameState.hp
		var max_hp: int = GameState.max_hp
		var pp: int = GameState.mp
		var max_pp: int = GameState.max_mp
		var hp_ratio: float = clampf(float(hp) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 0.0
		var pp_ratio: float = clampf(float(pp) / float(max_pp), 0.0, 1.0) if max_pp > 0 else 0.0
		_plate.set_fractions(hp_ratio, pp_ratio)

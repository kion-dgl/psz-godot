extends CanvasLayer
## CrtFilter — optional full-screen CRT post-process. Spec: /states/crt-filter.
##
## The game's first video setting, so it also establishes the pattern: video
## options persist to a `user://video_settings.cfg` ConfigFile (mirroring
## MusicManager's audio_settings.cfg), NOT to the per-character save — the tube
## look belongs to the machine you're playing on, not to the character.
##
## Sits at layer 260, above the SceneManager fade (250), because the filter
## treats the *composited frame*: 3D world, HUD canvases, start menu and the
## fade all go through the same tube. Anything parked above it would float
## outside the glass and give the illusion away.
##
## COMPILE CONTRACT: this is an autoload, so it MUST compile in repo-only CI
## with no asset pack mounted. Everything it touches (the .gdshader) lives in
## `res://scripts/`, which ships in the binary — never move it under assets/.

const LAYER := 260
const SETTINGS_PATH := "user://video_settings.cfg"
const SHADER_PATH := "res://scripts/shaders/crt.gdshader"

enum Mode { OFF, SCANLINES, FULL }

## Persisted ids — index-aligned with Mode. Stored as strings rather than the
## enum's ints so a future reordering of Mode can't silently reinterpret a
## saved config as a different filter.
const MODE_IDS := ["off", "scanlines", "full"]
const MODE_LABELS := ["Off", "Scanlines", "Full"]

## Uniform values per mode. A new look is an entry here, not a new shader.
## Scanlines is the conservative preset: no geometric warp, so it is safe on
## touch devices where a warped frame would pull MobileControls' buttons away
## from the coordinates that actually register the tap.
const PRESETS := {
	Mode.SCANLINES: {
		"scanline_strength": 0.30,
		"mask_strength": 0.0,
		"curvature": 0.0,
		"aberration": 0.0,
		"glow": 0.0,
		"vignette": 0.15,
		"brightness": 1.18,
	},
	Mode.FULL: {
		"scanline_strength": 0.34,
		"mask_strength": 0.22,
		"curvature": 0.06,
		"aberration": 1.0,
		"glow": 0.50,
		"vignette": 0.40,
		"brightness": 1.32,
	},
}

var _mode: int = Mode.OFF
var _rect: ColorRect = null


func _ready() -> void:
	layer = LAYER
	name = "CrtFilter"
	process_mode = Node.PROCESS_MODE_ALWAYS

	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		# Fail dark, not black: with no shader the overlay would paint a flat
		# rect over the entire game. Skip building it and pin the filter Off.
		push_warning("[CrtFilter] %s missing — CRT filter disabled" % SHADER_PATH)
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader

	_rect = ColorRect.new()
	_rect.name = "CrtOverlay"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = mat
	_rect.visible = false
	add_child(_rect)

	# Autopilot renders to a movie file and greps its own frames; a tube filter
	# over that is noise, and the back-buffer copy skews the frame timings the
	# matrix measures. Headless runs (test_runner) have nothing to filter.
	if OS.has_environment("PSZ_AUTOPILOT") or DisplayServer.get_name() == "headless":
		return

	_set_mode_no_save(_load_mode())


## Current filter as a Mode enum value.
func get_mode() -> int:
	return _mode


## Human-readable name of the current mode, for the Options row.
func get_mode_label() -> String:
	return MODE_LABELS[_mode]


func set_mode(mode: int) -> void:
	_set_mode_no_save(mode)
	_save_mode()


## Apply without touching disk — the boot path (the mode came *from* disk) and
## tests, which must not clobber the dev's real video_settings.cfg.
func _set_mode_no_save(mode: int) -> void:
	_mode = clampi(mode, 0, Mode.size() - 1)
	_apply()


## Step through the modes, wrapping. `step` is +1 (Accept / Right) or -1 (Left).
func cycle(step: int = 1) -> void:
	set_mode(wrapi(_mode + step, 0, Mode.size()))


func _apply() -> void:
	if _rect == null:
		return
	if _mode == Mode.OFF:
		# Hide rather than zero the uniforms: an invisible canvas item costs
		# nothing, while a transparent one still forces the back-buffer copy.
		_rect.visible = false
		return
	var mat := _rect.material as ShaderMaterial
	for key in PRESETS[_mode]:
		mat.set_shader_parameter(key, PRESETS[_mode][key])
	_rect.visible = true


func _load_mode() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return Mode.OFF
	var id: String = str(cfg.get_value("video", "crt_mode", MODE_IDS[Mode.OFF]))
	var idx: int = MODE_IDS.find(id)
	return idx if idx >= 0 else Mode.OFF


func _save_mode() -> void:
	var cfg := ConfigFile.new()
	# Load-then-set so a future video setting written by someone else isn't
	# clobbered by this save.
	cfg.load(SETTINGS_PATH)
	cfg.set_value("video", "crt_mode", MODE_IDS[_mode])
	cfg.save(SETTINGS_PATH)

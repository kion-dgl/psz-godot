extends CanvasLayer
## Main HUD displaying player HP, PP, and interaction prompts.

const HP_BAR_MAX_WIDTH: float = 160.0
const HP_BAR_LEFT: float = 76.0
const HP_BAR_RIGHT: float = HP_BAR_LEFT + HP_BAR_MAX_WIDTH
const HP_BAR_TOP: float = 62.0
const HP_BAR_BOTTOM: float = 69.0
const PP_BAR_TOP: float = 98.0
const PP_BAR_BOTTOM: float = 105.0

@onready var char_info_label: Label = $TopLeft/VBox/CharInfoLabel
@onready var level_label: Label = $TopLeft/VBox/StatPanel/LevelLabel
@onready var hp_current_label: Label = $TopLeft/VBox/StatPanel/HPCurrent
@onready var hp_max_label: Label = $TopLeft/VBox/StatPanel/HPMax
@onready var pp_current_label: Label = $TopLeft/VBox/StatPanel/PPCurrent
@onready var pp_max_label: Label = $TopLeft/VBox/StatPanel/PPMax
@onready var hp_bar: ColorRect = $TopLeft/VBox/StatPanel/HPBar
@onready var pp_bar: ColorRect = $TopLeft/VBox/StatPanel/PPBar
@onready var interaction_prompt: PanelContainer = $BottomCenter/InteractionPrompt
@onready var prompt_label: Label = $BottomCenter/InteractionPrompt/PromptLabel


func _ready() -> void:
	GameState.hp_changed.connect(_on_hp_changed)
	GameState.max_hp_changed.connect(_on_max_hp_changed)
	GameState.mp_changed.connect(_on_mp_changed)
	GameState.max_mp_changed.connect(_on_max_mp_changed)
	CharacterManager.level_up.connect(_on_level_up)

	_update_char_info()
	_update_level_display()
	_update_hp_display()
	_update_mp_display()
	hide_interaction_prompt()


func _update_hp_display() -> void:
	if hp_current_label:
		hp_current_label.text = str(GameState.hp)
	if hp_max_label:
		hp_max_label.text = str(GameState.max_hp)
	_set_bar_fill(hp_bar, GameState.hp, GameState.max_hp, HP_BAR_TOP, HP_BAR_BOTTOM)


func _update_mp_display() -> void:
	if pp_current_label:
		pp_current_label.text = str(GameState.mp)
	if pp_max_label:
		pp_max_label.text = str(GameState.max_mp)
	_set_bar_fill(pp_bar, GameState.mp, GameState.max_mp, PP_BAR_TOP, PP_BAR_BOTTOM)


func _set_bar_fill(bar: ColorRect, value: int, maximum: int, top: float, bottom: float) -> void:
	if not bar:
		return
	var ratio: float = 0.0
	if maximum > 0:
		ratio = clampf(float(value) / float(maximum), 0.0, 1.0)
	bar.offset_left = HP_BAR_LEFT
	bar.offset_right = HP_BAR_LEFT + HP_BAR_MAX_WIDTH * ratio
	bar.offset_top = top
	bar.offset_bottom = bottom
	bar.visible = ratio > 0.0


func show_interaction_prompt(text: String) -> void:
	if interaction_prompt and prompt_label:
		prompt_label.text = text
		interaction_prompt.visible = true


func hide_interaction_prompt() -> void:
	if interaction_prompt:
		interaction_prompt.visible = false


func _on_hp_changed(_new_hp: int) -> void:
	_update_hp_display()


func _on_max_hp_changed(_new_max_hp: int) -> void:
	_update_hp_display()


func _on_mp_changed(_new_mp: int) -> void:
	_update_mp_display()


func _on_max_mp_changed(_new_max_mp: int) -> void:
	_update_mp_display()


func _on_level_up(_new_level: int) -> void:
	_update_char_info()
	_update_level_display()


func _update_level_display() -> void:
	if not level_label:
		return
	var character = CharacterManager.get_active_character()
	var level: int = int(character.get("level", 1)) if character else 1
	level_label.text = str(level)


func _update_char_info() -> void:
	if not char_info_label:
		return
	var character = CharacterManager.get_active_character()
	if character == null:
		char_info_label.text = ""
		return
	var char_name: String = character.get("name", "???")
	var class_id: String = character.get("class_id", "")
	var class_display := class_id
	var class_data = ClassRegistry.get_class_data(class_id)
	if class_data:
		class_display = class_data.name
	char_info_label.text = "%s  %s" % [char_name, class_display]

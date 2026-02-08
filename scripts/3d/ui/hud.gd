extends CanvasLayer
## Main HUD displaying player HP, PP, meseta, and interaction prompts.

@onready var hp_bar = $TopLeft/Panel/VBox/HPBar
@onready var pp_bar = $TopLeft/Panel/VBox/PPBar
@onready var meseta_label: Label = $TopRight/MesetaPanel/HBox/MesetaLabel
@onready var meseta_icon: Label = $TopRight/MesetaPanel/HBox/MesetaIcon
@onready var interaction_prompt: PanelContainer = $BottomCenter/InteractionPrompt
@onready var prompt_label: Label = $BottomCenter/InteractionPrompt/PromptLabel


func _ready() -> void:
	# Connect to GameState signals
	GameState.hp_changed.connect(_on_hp_changed)
	GameState.max_hp_changed.connect(_on_max_hp_changed)
	GameState.mp_changed.connect(_on_mp_changed)
	GameState.max_mp_changed.connect(_on_max_mp_changed)
	GameState.meseta_changed.connect(_on_meseta_changed)

	# Style the meseta icon
	var icon_settings := LabelSettings.new()
	icon_settings.font_color = ThemeColors.MESETA_GOLD
	icon_settings.font_size = 14
	meseta_icon.label_settings = icon_settings

	var meseta_settings := LabelSettings.new()
	meseta_settings.font_color = ThemeColors.MESETA_GOLD
	meseta_label.label_settings = meseta_settings

	# Initialize display
	_update_hp_display()
	_update_mp_display()
	_update_meseta_display()
	hide_interaction_prompt()


func _update_hp_display() -> void:
	if hp_bar:
		hp_bar.set_values(GameState.hp, GameState.max_hp)


func _update_mp_display() -> void:
	if pp_bar:
		pp_bar.set_values(GameState.mp, GameState.max_mp)


func _update_meseta_display() -> void:
	if meseta_label:
		meseta_label.text = str(GameState.meseta)


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


func _on_meseta_changed(_new_amount: int) -> void:
	_update_meseta_display()

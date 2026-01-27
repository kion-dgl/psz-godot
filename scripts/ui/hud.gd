extends CanvasLayer
## Main HUD displaying player HP, MP, meseta, and equipped weapon.

@onready var hp_bar: ProgressBar = $MarginContainer/VBoxContainer/HPBar
@onready var hp_label: Label = $MarginContainer/VBoxContainer/HPBar/HPLabel
@onready var mp_bar: ProgressBar = $MarginContainer/VBoxContainer/MPBar
@onready var mp_label: Label = $MarginContainer/VBoxContainer/MPBar/MPLabel
@onready var meseta_label: Label = $MarginContainer/VBoxContainer/MesetaContainer/MesetaLabel


func _ready() -> void:
	# Connect to GameState signals
	GameState.hp_changed.connect(_on_hp_changed)
	GameState.max_hp_changed.connect(_on_max_hp_changed)
	GameState.mp_changed.connect(_on_mp_changed)
	GameState.max_mp_changed.connect(_on_max_mp_changed)
	GameState.meseta_changed.connect(_on_meseta_changed)

	# Initialize display
	_update_hp_display()
	_update_mp_display()
	_update_meseta_display()


func _update_hp_display() -> void:
	if hp_bar:
		hp_bar.max_value = GameState.max_hp
		hp_bar.value = GameState.hp
	if hp_label:
		hp_label.text = "%d / %d" % [GameState.hp, GameState.max_hp]


func _update_mp_display() -> void:
	if mp_bar:
		mp_bar.max_value = GameState.max_mp
		mp_bar.value = GameState.mp
	if mp_label:
		mp_label.text = "%d / %d" % [GameState.mp, GameState.max_mp]


func _update_meseta_display() -> void:
	if meseta_label:
		meseta_label.text = str(GameState.meseta)


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

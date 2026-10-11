extends VBoxContainer
## Live EXP and accessible Photon Blast control, attached below the vital panel.
var _exp: Label
var _blast: Button

func _ready() -> void:
	position = Vector2(12, 112)
	custom_minimum_size = Vector2(205, 48)
	_exp = Label.new()
	_exp.add_theme_font_size_override("font_size", 12)
	add_child(_exp)
	_blast = Button.new()
	_blast.add_theme_font_size_override("font_size", 12)
	_blast.focus_mode = Control.FOCUS_NONE
	_blast.pressed.connect(_activate)
	add_child(_blast)

func _process(_delta: float) -> void:
	var progress := CharacterManager.get_exp_progress()
	_exp.text = "EXP %d / %d" % [progress.current, progress.needed] if int(progress.needed) > 0 else "EXP MAX"
	var blast := PhotonBlast.equipped_blast()
	_blast.text = "PB · Evolve your Mag" if blast.is_empty() else "%s · %d%%" % [blast, PhotonBlast.gauge / 100]
	if PhotonBlast.flozir_left > 0.0:
		_blast.text = "Flozir · Free PP %ds" % ceili(PhotonBlast.flozir_left)
	_blast.disabled = blast.is_empty() or PhotonBlast.gauge < PhotonBlast.MAX_GAUGE
	_blast.tooltip_text = "Activate Photon Blast. You can also assign it to an action palette slot."

func _activate() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		PhotonBlast.activate(player)

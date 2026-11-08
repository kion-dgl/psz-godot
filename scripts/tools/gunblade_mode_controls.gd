extends CanvasLayer
var _player: Node3D
var _label: Label
func setup(player: Node3D) -> void:
	_player = player
	layer = 210
	_label = Label.new()
	_label.position = Vector2(245, 440)
	add_child(_label)
	_update_label()
func _update_label() -> void:
	_label.text = "Gunblade: each combo hit slashes nearby targets or shoots distant targets."

extends CanvasLayer
var _player: Node3D
var _label: Label
func setup(player: Node3D) -> void:
	_player = player
	layer = 210
	_label = Label.new()
	_label.position = Vector2(245, 15)
	add_child(_label)
	_update_label()
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_G:
		var rules = preload("res://scripts/3d/player/humar_saber_prototype.gd")
		if rules.toggle_gun_mode(_player): _update_label()
		else: _label.text = "Finish your action/cooldown before changing mode (G)."
		get_viewport().set_input_as_handled()
func _update_label() -> void:
	_label.text = "Gunblade: " + ("GUN" if _player.get_meta("prototype_gun_mode", false) else "BLADE") + " — G switches mode; normal/strong buttons attack."

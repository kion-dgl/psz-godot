extends RefCounted
static func show(parent: Node, at: Vector3, text: String, color: Color, small: bool = false) -> Label3D:
	var label := Label3D.new()
	label.name = "CombatPopup"
	label.text = text
	label.font_size = 30 if small else 48
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	label.outline_size = 4 if small else 6
	label.outline_modulate = Color.BLACK
	parent.add_child(label)
	label.global_position = at
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.0, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)
	return label

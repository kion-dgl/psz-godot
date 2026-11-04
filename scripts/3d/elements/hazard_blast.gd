extends RefCounted
## Visual blast grows from the trap model; gameplay queries remain at the source.
const EXPAND_TIME := 0.2
const HOLD_TIME := 0.25
const FADE_TIME := 0.7
const DURATION := EXPAND_TIME + HOLD_TIME + FADE_TIME

static func show_flash(source: Node3D, radius: float, color := Color(1.0, 0.45, 0.08), visual_source: Node3D = null) -> Node3D:
	if not source.is_inside_tree() or source.get_parent() == null:
		return null
	var burst := Node3D.new()
	burst.name = "HazardBlast"
	source.get_parent().add_child(burst)
	var origin := visual_source.global_position if is_instance_valid(visual_source) else source.global_position
	burst.global_transform = Transform3D(Basis.IDENTITY, origin)
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	flash.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, 0.22)
	flash.material_override = material
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.add_child(flash)
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.0, radius - 0.08)
	mesh.outer_radius = radius
	mesh.rings = 48
	mesh.ring_segments = 6
	ring.mesh = mesh
	# Keep the footprint at the gameplay ground height even for a floating trap.
	ring.position.y = source.global_position.y - origin.y + 0.04
	var rim := material.duplicate() as StandardMaterial3D
	rim.albedo_color.a = 0.8
	ring.material_override = rim
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.add_child(ring)
	flash.scale = Vector3.ONE * 0.08
	ring.scale = Vector3.ONE * 0.08
	var tween := burst.create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE, EXPAND_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "scale", Vector3.ONE, EXPAND_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, FADE_TIME).set_delay(EXPAND_TIME + HOLD_TIME)
	tween.tween_property(rim, "albedo_color:a", 0.0, FADE_TIME).set_delay(EXPAND_TIME + HOLD_TIME)
	tween.chain().tween_callback(burst.queue_free)
	return burst

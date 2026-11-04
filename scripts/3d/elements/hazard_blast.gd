extends RefCounted
## World-space blast volume and ground footprint; survives the source being freed.
static func show_flash(source: Node3D, radius: float, color := Color(1.0, 0.45, 0.08)) -> Node3D:
	if not source.is_inside_tree() or source.get_parent() == null:
		return null
	var burst := Node3D.new()
	burst.name = "HazardBlast"
	source.get_parent().add_child(burst)
	burst.global_transform = Transform3D(Basis.IDENTITY, source.global_position)
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	flash.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, 0.18)
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
	ring.position.y = 0.04
	var rim := material.duplicate() as StandardMaterial3D
	rim.albedo_color.a = 0.8
	ring.material_override = rim
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.add_child(ring)
	var tween := burst.create_tween().set_parallel(true)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.4)
	tween.tween_property(rim, "albedo_color:a", 0.0, 0.4)
	tween.chain().tween_callback(burst.queue_free)
	return burst

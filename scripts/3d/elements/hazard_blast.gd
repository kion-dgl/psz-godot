extends RefCounted
## Shared short-lived explosion flash for environmental traps.
static func show_flash(parent: Node3D, radius: float) -> void:
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	flash.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.45, 0.08, 0.35)
	flash.material_override = material
	parent.add_child(flash)
	var tween := parent.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.tween_callback(flash.queue_free)

extends RefCounted
class_name EffectBillboard
## Shared setup for the flat, camera-facing effect quads in assets/effects/.
##
## Every model in the effect archives is a flat unlit quad authored to face the
## viewer — no normals, no lighting, z-extent zero. Godot imports them as
## ordinary meshes, so each one needs the same four things done to it before it
## reads as an effect rather than a piece of scenery lying on its side:
## billboard the material, keep it unlit, stop it z-fighting with whatever it is
## pinned to, and fix the draw order for layered quads.
##
## Kept in one place because the reticle and the quest marker already need it
## and the remaining 140 models in #577 will need exactly the same treatment.

## Load an effect model and prepare every surface for billboard rendering.
## Returns null when the model is missing, so callers can fall back rather than
## spawning an invisible node.
##
## `center` shifts the model so its bounding box sits ON the node origin. The
## archives do not author these centred — ef_com_rockon hangs entirely below its
## origin (y -0.53..-0.27) and ef_com_quest floats a full unit above it (0.38..
## 1.62) — so without this a caller asking for "1.9 units up" gets something
## else, and the reticle silently sits lower than the sprite it replaced.
static func load_model(effect_id: String, render_priority := 0, center := true) -> Node3D:
	var path := "res://assets/effects/%s/%s.glb" % [effect_id, effect_id]
	var packed := load(path) as PackedScene
	if not packed:
		push_warning("EffectBillboard: missing effect model " + path)
		return null
	var node := packed.instantiate() as Node3D
	_prepare(node, render_priority)
	if center:
		node.position -= _mesh_center(node)
	return node


## Centre of every MeshInstance3D's AABB under `node`, in node-local space.
## Measured rather than hardcoded so a re-export cannot quietly move an effect.
static func _mesh_center(node: Node3D) -> Vector3:
	var merged := AABB()
	var first := true
	var stack: Array = [[node as Node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var current: Node = entry[0]
		var xform: Transform3D = entry[1]
		if current is Node3D and current != node:
			xform = xform * (current as Node3D).transform
		if current is MeshInstance3D and (current as MeshInstance3D).mesh:
			var box: AABB = xform * (current as MeshInstance3D).mesh.get_aabb()
			merged = box if first else merged.merge(box)
			first = false
		for child in current.get_children():
			stack.push_back([child, xform])
	return Vector3.ZERO if first else merged.get_center()


static func _prepare(node: Node, render_priority: int) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		# Effects are never shadow casters or receivers — they are light, not
		# geometry, and a flat quad casting a shadow looks like a bug.
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in range(mesh_inst.mesh.get_surface_count()):
			var src := mesh_inst.mesh.surface_get_material(i)
			if not (src is BaseMaterial3D):
				continue
			# Duplicate: the imported material is shared by every instance of
			# the model, so billboarding it in place would billboard them all.
			var mat := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			# Y-billboard keeps the quad upright; full billboard would let it
			# roll with the camera.
			mat.billboard_keep_scale = true
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.no_depth_test = true
			# Flat quads with no back: culling one side just makes them vanish
			# from behind, and it is what doubleSided already says on most of
			# these materials.
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.render_priority = render_priority
			mesh_inst.set_surface_override_material(i, mat)
	for child in node.get_children():
		_prepare(child, render_priority)

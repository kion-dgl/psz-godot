extends SceneTree
## Dev tool: build the real TeleporterDressing from data/city_teleporter.json
## against the actual special_c3 GLBs and dump the shader uniforms per surface.
## Not a CI test — the test_runner must stay pack-free (assets aren't in git).
## Run: godot --headless --path . --script res://scripts/tools/dump_dressing_uniforms.gd

const DressScript := preload("res://scripts/3d/elements/teleporter_dressing.gd")


func _init() -> void:
	var el = DressScript.new()
	var layout: Dictionary = el._load_layout()
	el.build(layout)
	print("anchor=", el.position)
	for pivot in el.get_children():
		print("PIECE ", pivot.name, "  pos=", pivot.position, " scale=", pivot.scale)
		_dump(pivot)
	el.free()
	quit()


func _dump(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in range(mi.get_surface_override_material_count()):
			var m := mi.get_surface_override_material(i)
			if m is ShaderMaterial:
				var sm := m as ShaderMaterial
				var tex: Texture2D = sm.get_shader_parameter("albedo_tex")
				var tex_name := String(tex.resource_path).get_file() if tex else "<none>"
				print("   %-22s scale=%s offset=%s scroll=%s wrap=(%s,%s)" % [
					tex_name,
					sm.get_shader_parameter("uv_scale"),
					sm.get_shader_parameter("uv_offset"),
					sm.get_shader_parameter("scroll_speed"),
					sm.get_shader_parameter("wrap_u"),
					sm.get_shader_parameter("wrap_v"),
				])
	for c in node.get_children():
		_dump(c)

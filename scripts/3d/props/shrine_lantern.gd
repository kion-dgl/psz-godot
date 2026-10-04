@tool
extends Node3D
## A reusable, solid interpretation of s07_1_blight's crossed sprite cards.
## Origin is the foot on the floor; the light is inside the open bronze cage.
@export_range(0.0, 4.0, 0.01) var light_energy := 1.4:
	set(value):
		light_energy = value
		if is_instance_valid(_light):
			_light.light_energy = value
@export var light_color := Color("2cae9e"):
	set(value):
		light_color = value
		if is_instance_valid(_light):
			_light.light_color = value
@export_range(0.0, 30.0, 0.1) var pole_depth := 0.0
var _light: OmniLight3D


func _ready() -> void:
	if get_node_or_null("LanternGeometry") != null:
		return
	var body := Node3D.new()
	body.name = "LanternGeometry"
	add_child(body)
	var bronze := StandardMaterial3D.new()
	bronze.resource_name = "AgedBronze"
	bronze.albedo_color = Color(0.22, 0.17, 0.115)
	bronze.metallic = 0.45
	bronze.roughness = 0.83
	bronze.emission_enabled = true
	bronze.emission = Color(0.025, 0.023, 0.019)
	if pole_depth > 0.0:
		_profile(body, "SupportPole", [Vector2(.095, -pole_depth), Vector2(.095, .06)], bronze)
	# Turned foot, slender stem, collar, bowl, and the tiered pointed roof.
	_profile(body, "FootAndStem", [Vector2(.19,0), Vector2(.19,.06), Vector2(.11,.12),
		Vector2(.065,.18), Vector2(.045,1.02), Vector2(.13,1.06), Vector2(.13,1.12),
		Vector2(.075,1.17)], bronze)
	_profile(body, "LowerBowl", [Vector2(.075,1.17), Vector2(.2,1.24),
		Vector2(.22,1.3), Vector2(.17,1.34)], bronze)
	_profile(body, "TieredRoof", [Vector2(.36,1.94), Vector2(.39,1.98),
		Vector2(.39,2.035), Vector2(.29,2.07), Vector2(.31,2.12),
		Vector2(.22,2.16), Vector2(.24,2.21), Vector2(.13,2.27),
		Vector2(.15,2.30), Vector2(.045,2.36), Vector2(0,2.42)], bronze)
	for i in range(4):
		var angle := TAU * float(i) / 4.0 + PI / 4.0
		var radial := Vector3(cos(angle), 0, sin(angle))
		var a := radial * .16 + Vector3.UP * 1.31
		var b := radial * .3 + Vector3.UP * 1.7
		var c := radial * .3 + Vector3.UP * 1.96
		_bar(body, a, b, bronze)
		_bar(body, b, c, bronze)
	var crystal := MeshInstance3D.new()
	crystal.name = "InnerGlow"
	var sphere := SphereMesh.new()
	sphere.radius = .115
	sphere.height = .46
	sphere.radial_segments = 8
	sphere.rings = 4
	var glow := StandardMaterial3D.new()
	glow.resource_name = "LanternInnerTeal"
	glow.albedo_color = Color("194b42")
	glow.emission_enabled = true
	glow.emission = light_color
	glow.emission_energy_multiplier = 2.4
	glow.roughness = .65
	sphere.material = glow
	crystal.mesh = sphere
	crystal.position.y = 1.63
	crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(crystal)
	_light = OmniLight3D.new()
	_light.name = "InteriorLight"
	_light.set_meta("authored_light", true)
	_light.position.y = 1.63
	_light.light_color = light_color
	_light.light_energy = light_energy
	_light.omni_range = 7.0
	_light.omni_attenuation = 2.0
	_light.light_cull_mask &= ~MeshUtils.SHADOW_CATCHER_LAYER
	add_child(_light)


func _profile(parent: Node3D, part_name: String, profile: Array[Vector2], material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(profile.size()-1):
		for i in range(8):
			var a := TAU * float(i)/8.0
			var b := TAU * float(i+1)/8.0
			var low := profile[row]
			var high := profile[row+1]
			var p := Vector3(cos(a)*low.x, low.y, sin(a)*low.x)
			var q := Vector3(cos(b)*low.x, low.y, sin(b)*low.x)
			var r := Vector3(cos(a)*high.x, high.y, sin(a)*high.x)
			var s := Vector3(cos(b)*high.x, high.y, sin(b)*high.x)
			for v in [p,q,r,q,s,r]:
				st.add_vertex(v)
	st.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = st.commit()
	instance.material_override = material
	parent.add_child(instance)


func _bar(parent: Node3D, a: Vector3, b: Vector3, material: Material) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = .022
	cylinder.bottom_radius = .03
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 6
	cylinder.material = material
	var instance := MeshInstance3D.new()
	instance.name = "CageRib"
	instance.mesh = cylinder
	instance.position = (a+b)*.5
	instance.quaternion = Quaternion(Vector3.UP, (b-a).normalized())
	parent.add_child(instance)

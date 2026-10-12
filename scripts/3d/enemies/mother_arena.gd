class_name MotherArena extends Node3D
## Reconstructed intact floor cover; original cover asset is not identified.
var cover: MeshInstance3D
var broken := false
var entering := false
var entry_elapsed := 0.0
var debris_time := 0.0
var _debris: Array[MeshInstance3D] = []
var body: Node3D

func _ready() -> void:
	cover = MeshInstance3D.new()
	var tile := PlaneMesh.new()
	tile.size = Vector2(12, 4)
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/stages/shrine_z/s07z_na1/lndmd/s07_0_zjime.png")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.uv1_scale = Vector3(1.5, 0.5, 1)
	material.uv1_offset = Vector3(0.5, 0, 0)
	tile.material = material
	cover.mesh = tile
	cover.position = Vector3(0, 0.025, 2)
	add_child(cover)
	if body:
		body.position.z = -6.0

func begin_entry() -> void:
	entering = true
	entry_elapsed = 0.0

func advance(delta: float) -> void:
	if entering and not broken and is_instance_valid(body):
		entry_elapsed += delta
		body.position.z = lerpf(-6.0, 0.0, clampf(entry_elapsed / (125.0 / 30.0), 0.0, 1.0))
	if broken:
		debris_time += delta
		for index in _debris.size():
			var chunk := _debris[index]
			chunk.position.y = -debris_time * debris_time * 4.0
			chunk.rotation.z = debris_time * float(index - 1) * 0.6
			chunk.visible = debris_time < 1.5

func break_cover() -> void:
	if broken:
		return
	broken = true
	cover.hide()
	if body:
		body.position.z = 0
	for index in 3:
		var chunk := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(3.8, 0.25, 3.8)
		mesh.material = cover.mesh.surface_get_material(0)
		chunk.mesh = mesh
		chunk.position = Vector3(float(index - 1) * 4, 0, 2)
		add_child(chunk)
		_debris.append(chunk)

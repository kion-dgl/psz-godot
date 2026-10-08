extends RefCounted
## Timed ice immobilization; normal hit reaction resumes on expiry or break.
var remaining := 0.0
var _visual: MeshInstance3D

func apply(player: Node3D, duration: float) -> void:
	if remaining > 0.0:
		return
	remaining = duration
	player._drop_charge()
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	if player.animation_player:
		player.animation_player.pause()
	if not is_instance_valid(_visual):
		_visual = MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(1.0, 1.8, 1.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.75, 1.0, 0.4)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material = mat
		_visual.mesh = mesh
		player.add_child(_visual)
		_visual.position.y = 0.9
	_visual.show()

func clear(player: Node3D) -> void:
	if remaining <= 0.0:
		return
	remaining = 0.0
	if is_instance_valid(_visual):
		_visual.hide()
	if player.animation_player:
		player.animation_player.play()

func tick(player: Node3D, delta: float) -> bool:
	if remaining <= 0.0:
		return false
	if remaining <= delta:
		clear(player)
	else:
		remaining -= delta
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	return true

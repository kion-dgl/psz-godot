extends Node3D
## Owned by the player: scene teardown cancels the delayed release automatically.
var blast := ""
var _elapsed := 0.0
var _released := false
var _ring: MeshInstance3D
const COLORS := {"Granir": Color(1, 0.5, 0.1), "Pacifal": Color(0.3, 0.7, 1), "Midgul": Color(0.6, 0.3, 1), "Flozir": Color(0.3, 1, 0.6)}

func _ready() -> void:
	var player = get_parent()
	player._drop_charge()
	player.transition_to(player.PlayerState.CUTSCENE)
	_ring = MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.9
	mesh.outer_radius = 1.05
	_ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = COLORS[blast]
	_ring.material_override = material
	_ring.position.y = 0.1
	add_child(_ring)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	_ring.scale = Vector3.ONE * (1.0 + _elapsed * 5.0)
	if not _released and _elapsed >= 0.8:
		_released = true
		_release()
	if _elapsed >= 1.5:
		cancel()

func cancel() -> void:
	var player = get_parent()
	if is_instance_valid(player) and player.current_state == player.PlayerState.CUTSCENE:
		player.transition_to(player.PlayerState.IDLE)
	queue_free()

func _release() -> void:
	if blast == "Flozir":
		PhotonBlast.flozir_left = 20.0
		return
	var player = get_parent()
	var stats := CombatManager._get_player_stats(CharacterManager.get_active_character())
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is EnemyBase or not enemy.is_alive or player.global_position.distance_to(enemy.global_position) > 12.0:
			continue
		if blast == "Midgul":
			var old := enemy.get_node_or_null("PhotonDebuff")
			if old:
				old.refresh()
			else:
				var debuff = preload("res://scripts/3d/combat/photon_debuff.gd").new()
				debuff.name = "PhotonDebuff"
				enemy.add_child(debuff)
		else:
			var power: int = int(stats.attack) + int(stats.weapon_attack) if blast == "Granir" else int(stats.technique) + 100
			enemy.hurtbox.take_attack({"damage": power * 5, "accuracy": 10000, "charge_pb": false, "kind": "blast"}, Vector3.ZERO)

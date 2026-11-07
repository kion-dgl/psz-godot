extends RefCounted
## Opt-in #790 rules; shared player/enemy resources remain unchanged.
const LIBRARY := "res://assets/player/animations/pso_humar_saber.glb"
const CAUTION_RANGE := 6.0
const CONTACT := [0.40, 0.40, 0.45]
const CHAIN: Array[float] = [0.55, 0.95]

static func enabled(player) -> bool:
	if OS.get_environment("PSZ_HUMAR_SABER") != "1": return false
	var character = CharacterManager.get_active_character()
	return SessionManager.get_location() == "field" and character != null and character.get("class_id", "") == "humar" \
		and SessionManager.get_session().get("quest_id", "") == "debug_coliseum" \
		and not player._is_barehanded() and player._get_equipped_weapon_type() == WeaponData.WeaponType.SABER

static func caution(player) -> bool:
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase and enemy.current_hp > 0 and player.global_position.distance_to(enemy.global_position) <= CAUTION_RANGE:
			return true
	return false

static func facing_guard(facing: float, offset: Vector3) -> bool:
	var planar := Vector3(offset.x, 0, offset.z)
	return planar.length_squared() > 0.0001 and Vector3(sin(facing), 0, cos(facing)).dot(planar.normalized()) >= 0.5

static func try_guard(player, source: Node3D) -> bool:
	if not enabled(player) or not is_instance_valid(source) or not player.can_take_hit(): return false
	if GameState.is_gameplay_blocked() or player._freeze.remaining > 0.0 or player._ailments.blocks_attack(): return false
	if player.current_state not in [player.PlayerState.IDLE, player.PlayerState.WALKING]: return false
	if not facing_guard(player.player_rotation, source.global_position - player.global_position): return false
	if not player.animation_player or not player.animation_player.has_animation("pso_sa_block"): return false
	player.transition_to(player.PlayerState.DAMAGED)
	player.play_animation("pso_sa_block", false)
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	return true

static func guarding(player) -> bool:
	return enabled(player) and player.current_state == player.PlayerState.DAMAGED \
		and player.animation_player != null and player.animation_player.current_animation == "pso_sa_block"

static func select_walk(player, cautious: bool) -> void:
	var clip := "pso_sa_walk_ready" if cautious else "pso_sa_walk"
	if player._walk_anim == clip: return
	player._walk_anim = clip
	if player.current_state == player.PlayerState.WALKING: player.play_animation(clip, true)

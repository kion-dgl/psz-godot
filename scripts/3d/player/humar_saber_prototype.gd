extends RefCounted
## Opt-in #790 rules; shared player/enemy resources remain unchanged.
const LIBRARY := "res://assets/player/animations/pso_humar_saber.glb"
const FEMALE_LIBRARY := "res://assets/player/animations/pso_female_saber.glb"
const MALE_PROFILE := {"library": LIBRARY, "native_library": "res://assets/player/animations/saver_m.glb", "prefix": "pso_sa", "native_prefix": "pmsa", "walk": "pmsa_walk", "source_count": 15, "class_id": "humar"}
const FEMALE_PROFILE := {"library": FEMALE_LIBRARY, "native_library": "res://assets/player/animations/saver_w.glb", "prefix": "pso_f_sa", "native_prefix": "pwsa", "walk": "pwsa_walk", "source_count": 16, "class_id": "humarl"}

const MALE_SWORD_PROFILE := {"library": "res://assets/player/animations/pso_male_sword.glb", "native_library": "res://assets/player/animations/sword_m.glb", "prefix": "pso_sw", "native_prefix": "pmsw", "walk": "pmsa_walk", "run": "pso_sw_run", "source_count": 13, "class_id": "humar", "contact": [0.3191, 0.3261, 0.44], "recovery": [0.18, 0.20, 0.28]}
const FEMALE_SWORD_PROFILE := {"library": "res://assets/player/animations/pso_female_sword.glb", "native_library": "res://assets/player/animations/sword_w.glb", "prefix": "pso_f_sw", "native_prefix": "pwsw", "walk": "pwsa_walk", "run": "pso_f_sw_run", "source_count": 13, "class_id": "humarl", "contact": [0.3191, 0.3261, 0.44], "recovery": [0.18, 0.20, 0.28]}

static func profile(player) -> Dictionary:
	if player._get_equipped_weapon_type() == WeaponData.WeaponType.SWORD:
		return FEMALE_SWORD_PROFILE if player._is_female else MALE_SWORD_PROFILE
	return FEMALE_PROFILE if player._is_female else MALE_PROFILE

static func profile_for_library(path: String) -> Dictionary:
	if path == FEMALE_SWORD_PROFILE.library: return FEMALE_SWORD_PROFILE
	if path == MALE_SWORD_PROFILE.library: return MALE_SWORD_PROFILE
	if path == LIBRARY: return MALE_PROFILE
	if path == FEMALE_LIBRARY: return FEMALE_PROFILE
	return {}

static func ready_clip(player) -> String:
	return str(profile(player).prefix) + "_wait"

static func native_clip(player, role: String) -> String:
	return str(profile(player).native_prefix) + "_" + role

const CHARGE_SOUND := "res://assets/sfx/common/common_060.wav" # SE_PL_BIGCHARGE
const LOCK_SOUND := "res://assets/sfx/common/common_017.wav" # SE_PL_LOCKCURSOR
const RETREAT_CAUTION_TIME := 0.5
const READY_PREP := 0.25
const READY_BLEND := 0.08
const FINISHER_GUARD := 0.35
const BROKEN_RECOVERY := 0.25
const STOPPED_ATTACK_COOLDOWN := 0.3
const CONTACT := [0.40, 0.40, 0.45]
const RECOVERY := [0.14, 0.16, 0.22]
const CHAIN: Array[float] = [0.55, 0.95]

static func enabled(player) -> bool:
	if OS.get_environment("PSZ_HUMAR_SABER") != "1": return false
	var character = CharacterManager.get_active_character()
	return SessionManager.get_location() == "field" and character != null and character.get("class_id", "") in ["humar", "humarl"] \
		and SessionManager.get_session().get("quest_id", "") == "debug_coliseum" \
		and not player._is_barehanded() and (player._get_equipped_weapon_type() == WeaponData.WeaponType.SABER \
		 or player._get_equipped_weapon_type() == WeaponData.WeaponType.SWORD)

static func caution(player, movement_yaw: Variant = null) -> bool:
	for enemy in player._targeted_enemies:
		if is_instance_valid(enemy) and enemy is EnemyBase and enemy.current_hp > 0:
			if movement_yaw != null:
				var toward: Vector3 = enemy.global_position - player.global_position
				toward.y = 0
				var moving := Vector3(sin(float(movement_yaw)), 0, cos(float(movement_yaw)))
				if not toward.is_zero_approx() and moving.dot(toward.normalized()) < -0.25:
					continue # Retreat may turn the cursor away, but the hold timer persists.
			return true
	return false

static func update_caution(player, movement_yaw: float, delta: float) -> bool:
	if caution(player, movement_yaw):
		player._saber_caution_active = true
		player._saber_retreat_elapsed = 0.0
	elif player._saber_caution_active:
		player._saber_retreat_elapsed += delta
		if player._saber_retreat_elapsed >= RETREAT_CAUTION_TIME:
			player._saber_caution_active = false
			player._saber_retreat_elapsed = 0.0
			# The half-second caution hold replaces the ordinary run delay.
			player.walk_timer = player.WALK_TO_RUN_DELAY
	return player._saber_caution_active

static func idle_clip(player) -> String:
	return native_clip(player, "wait")

static func facing_guard(facing: float, offset: Vector3) -> bool:
	var planar := Vector3(offset.x, 0, offset.z)
	return planar.length_squared() > 0.0001 and Vector3(sin(facing), 0, cos(facing)).dot(planar.normalized()) >= 0.5

static func try_guard(player, source: Node3D) -> bool:
	if not enabled(player) or not is_instance_valid(source) or not player.can_take_hit(): return false
	if player._saber_attack_cooldown > 0.0: return false
	if GameState.is_gameplay_blocked() or player._freeze.remaining > 0.0 or player._ailments.blocks_attack(): return false
	var ready_recovery: bool = player.current_state == player.PlayerState.ATTACKING and player._saber_phase == "guard_recovery"
	if not ready_recovery and player.current_state not in [player.PlayerState.IDLE, player.PlayerState.WALKING]: return false
	if not facing_guard(player.player_rotation, source.global_position - player.global_position): return false
	if not player.animation_player or not player.animation_player.has_animation(str(profile(player).prefix) + "_block"): return false
	player.transition_to(player.PlayerState.DAMAGED)
	player.play_animation(str(profile(player).prefix) + "_block", false)
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	return true

static func guarding(player) -> bool:
	return enabled(player) and player.current_state == player.PlayerState.DAMAGED \
		and player.animation_player != null and player.animation_player.current_animation == str(profile(player).prefix) + "_block"

static func select_walk(player, cautious: bool) -> void:
	var clip: String = str(profile(player).prefix) + "_walk_ready" if cautious else str(profile(player).walk)
	if player._walk_anim == clip: return
	player._walk_anim = clip
	if player.current_state == player.PlayerState.WALKING: player.play_animation(clip, true)

# Supply exactly enough accuracy for 100% in the existing physical-hit formula.
# Geometry, defense, criticals and immunity continue through the normal path.
static func contact_accuracy(evasion: int) -> int:
	return ceili(float(100 + ((evasion * 0x333 + 0x800) >> 12)) * 2.5)

static func palette_cue(player) -> Dictionary:
	if not enabled(player) or GameState.is_gameplay_blocked(): return {}
	if player.current_state != player.PlayerState.ATTACKING or player.combo_state not in [1, 2]: return {}
	if player._combo_fumbled or player._attack_anim_length <= 0: return {}
	var progress: float = player._attack_frac()
	if progress > CHAIN[1]: return {}
	return {"progress": progress, "ready": progress >= CHAIN[0], "queued": player._queued_combo != player.ComboQueue.NONE}

static func contact_feedback(enemy, source, strong: bool) -> void:
	# The caller verifies actual HP loss; no spark or sound on a whiff/immune hit.
	SfxManager.play_at("res://assets/sfx/weapons/saber_hit.wav", enemy.global_position, 0.0 if strong else -7.0)
	if strong and enemy.is_alive and enemy.current_state == enemy.EnemyState.HURT:
		enemy.hurt_timer = maxf(enemy.hurt_timer, 0.45)
	var burst := CPUParticles3D.new()
	burst.name = "SaberContactSpark"
	burst.add_to_group("saber_contact_feedback")
	burst.one_shot = true
	burst.amount = 7 if strong else 4
	burst.lifetime = 0.18
	burst.explosiveness = 1.0
	burst.direction = Vector3.UP
	burst.spread = 100.0
	burst.initial_velocity_min = 0.5
	burst.initial_velocity_max = 1.3 if strong else 0.8
	burst.gravity = Vector3(0, -2, 0)
	burst.scale_amount_min = 0.5
	burst.scale_amount_max = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.025
	mesh.height = 0.05
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.8, 0.35) if strong else Color(0.8, 1.0, 1.0)
	mesh.material = material
	burst.mesh = mesh
	source.get_tree().current_scene.add_child(burst)
	var toward: Vector3 = (source.global_position - enemy.global_position).normalized()
	burst.global_position = enemy.global_position + Vector3.UP + toward * 0.35
	burst.emitting = true
	burst.finished.connect(burst.queue_free)

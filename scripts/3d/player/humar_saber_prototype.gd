extends RefCounted
## Opt-in #790 rules; shared player/enemy resources remain unchanged.
const LIBRARY := "res://assets/player/animations/pso_humar_saber.glb"
const FEMALE_LIBRARY := "res://assets/player/animations/pso_female_saber.glb"
const MALE_PROFILE := {"library": LIBRARY, "native_library": "res://assets/player/animations/saver_m.glb", "prefix": "pso_sa", "native_prefix": "pmsa", "walk": "pmsa_walk", "source_count": 15, "class_id": "humar"}
const FEMALE_PROFILE := {"library": FEMALE_LIBRARY, "native_library": "res://assets/player/animations/saver_w.glb", "prefix": "pso_f_sa", "native_prefix": "pwsa", "walk": "pwsa_walk", "source_count": 16, "class_id": "humarl"}

const MALE_SWORD_PROFILE := {"library": "res://assets/player/animations/pso_male_sword.glb", "native_library": "res://assets/player/animations/sword_m.glb", "prefix": "pso_sw", "native_prefix": "pmsw", "walk": "pmsa_walk", "run": "pso_sw_run", "source_count": 13, "class_id": "humar", "contact": [0.3191, 0.3261, 0.44], "recovery": [0.18, 0.20, 0.28]}
const FEMALE_SWORD_PROFILE := {"library": "res://assets/player/animations/pso_female_sword.glb", "native_library": "res://assets/player/animations/sword_w.glb", "prefix": "pso_f_sw", "native_prefix": "pwsw", "walk": "pwsa_walk", "run": "pso_f_sw_run", "source_count": 13, "class_id": "humarl", "contact": [0.3191, 0.3261, 0.44], "recovery": [0.18, 0.20, 0.28]}

const MALE_DAGGER_PROFILE := {"library": "res://assets/player/animations/pso_male_dagger.glb", "native_library": "res://assets/player/animations/dagger_m.glb", "prefix": "pso_da", "native_prefix": "pmda", "walk": "pmsa_walk", "run": "pso_da_run", "source_count": 13, "class_id": "humar", "hit_fracs": [[0.1556, 0.3333], [0.2895], [0.2075, 0.4151, 0.5849]], "recovery": [0.10, 0.12, 0.18]}
const FEMALE_DAGGER_PROFILE := {"library": "res://assets/player/animations/pso_female_dagger.glb", "native_library": "res://assets/player/animations/dagger_w.glb", "prefix": "pso_f_da", "native_prefix": "pwda", "walk": "pwsa_walk", "run": "pso_f_da_run", "source_count": 8, "class_id": "humarl", "hit_fracs": [[0.1556, 0.3333], [0.2895], [0.2075, 0.4151, 0.5849]], "recovery": [0.10, 0.12, 0.18]}

const MALE_CLAW_PROFILE := {"library": "res://assets/player/animations/pso_male_claw.glb", "native_library": "res://assets/player/animations/claw_m.glb", "prefix": "pso_cl", "native_prefix": "pmcl", "walk": "pmsa_walk", "run": "pso_cl_run", "source_count": 5, "class_id": "humar", "hit_fracs": [[0.2368], [0.2632], [0.2245, 0.6735]], "recovery": [0.10, 0.12, 0.18]}
const FEMALE_CLAW_PROFILE := {"library": "res://assets/player/animations/pso_female_claw.glb", "native_library": "res://assets/player/animations/claw_w.glb", "prefix": "pso_f_cl", "native_prefix": "pwcl", "walk": "pwsa_walk", "run": "pso_f_cl_run", "source_count": 5, "class_id": "humarl", "hit_fracs": [[0.2368], [0.2632], [0.2245, 0.6735]], "recovery": [0.10, 0.12, 0.18]}

const MALE_GUNBLADE_PROFILE := {"library": "res://assets/player/animations/pso_male_gunblade.glb", "native_library": "res://assets/player/animations/shotgun_m.glb", "prefix": "pso_gb", "source_prefix": "pso_sa", "native_prefix": "pmgb", "walk": "pmsa_walk", "run": "pso_gb_run", "source_count": 15, "class_id": "humar", "hit_fracs": [[0.25], [0.282051], [0.372093]], "recovery": [0.14, 0.16, 0.22]}
const FEMALE_GUNBLADE_PROFILE := {"library": "res://assets/player/animations/pso_female_gunblade.glb", "native_library": "res://assets/player/animations/shotgun_w.glb", "prefix": "pso_f_gb", "source_prefix": "pso_f_sa", "native_prefix": "pwgbs", "walk": "pwsa_walk", "run": "pso_f_gb_run", "source_count": 16, "class_id": "humarl", "hit_fracs": [[0.25], [0.282051], [0.372093]], "recovery": [0.14, 0.16, 0.22]}

const MALE_SLICER_PROFILE := {"library": "res://assets/player/animations/pso_male_slicer.glb", "native_library": "res://assets/player/animations/slicer_m.glb", "prefix": "pso_sl", "native_prefix": "pmsl", "walk": "pmsa_walk", "run": "pso_sl_run", "source_count": 12, "class_id": "humar", "hit_fracs": [[0.30303], [0.40], [0.45]], "recovery": [0.14, 0.16, 0.22]}
const FEMALE_SLICER_PROFILE := {"library": "res://assets/player/animations/pso_female_slicer.glb", "native_library": "res://assets/player/animations/slicer_w.glb", "prefix": "pso_f_sl", "source_prefix": "pso_sl", "native_prefix": "pwsls", "walk": "pwsa_walk", "run": "pso_f_sl_run", "source_count": 12, "class_id": "humarl", "hit_fracs": [[0.30303], [0.40], [0.45]], "recovery": [0.14, 0.16, 0.22]}

const MALE_SPEAR_PROFILE := {"library": "res://assets/player/animations/pso_male_spear.glb", "native_library": "res://assets/player/animations/spear_m.glb", "prefix": "pso_pa", "native_prefix": "pmsp", "walk": "pmsa_walk", "run": "pso_pa_run", "source_count": 14, "class_id": "humar", "hit_fracs": [[0.294118], [0.297297], [0.55]], "recovery": [0.14, 0.16, 0.22]}
const FEMALE_SPEAR_PROFILE := {"library": "res://assets/player/animations/pso_female_spear.glb", "native_library": "res://assets/player/animations/spear_w.glb", "prefix": "pso_f_pa", "source_prefix": "pso_pa", "native_prefix": "pwsp", "walk": "pwsa_walk", "run": "pso_f_pa_run", "source_count": 14, "class_id": "humarl", "hit_fracs": [[0.294118], [0.297297], [0.55]], "recovery": [0.14, 0.16, 0.22]}

const MALE_DOUBLE_PROFILE := {"library": "res://assets/player/animations/pso_male_double_saber.glb", "native_library": "res://assets/player/animations/dsaver_m.glb", "prefix": "pso_ds", "native_prefix": "pmds", "walk": "pmsa_walk", "run": "pso_ds_run", "source_count": 5, "class_id": "humar", "hit_fracs": [[0.3404, 0.3617], [0.3953], [0.3922, 0.4706, 0.5294]], "recovery": [0.14, 0.16, 0.22]}
const FEMALE_DOUBLE_PROFILE := {"library": "res://assets/player/animations/pso_female_double_saber.glb", "native_library": "res://assets/player/animations/dsaver_w.glb", "prefix": "pso_f_ds", "native_prefix": "pwdss", "walk": "pwsa_walk", "run": "pso_f_ds_run", "source_count": 5, "class_id": "humarl", "hit_fracs": [[0.3404, 0.3617], [0.3953], [0.3922, 0.4706, 0.5294]], "recovery": [0.14, 0.16, 0.22]}

static func profile(player) -> Dictionary:
	if player._get_equipped_weapon_type() == WeaponData.WeaponType.GUN_BLADE:
		var base: Dictionary = FEMALE_GUNBLADE_PROFILE if player._is_female else MALE_GUNBLADE_PROFILE
		if gun_mode(player):
			var shooting := base.duplicate(true)
			shooting["attack_prefix"] = str(base.native_prefix) + "_shot"
			shooting["hit_fracs"] = [[0.35], [0.35], [0.35]]
			return shooting
		return base
	if player._get_equipped_weapon_type() == WeaponData.WeaponType.SLICER: return FEMALE_SLICER_PROFILE if player._is_female else MALE_SLICER_PROFILE
	if player._get_equipped_weapon_type() == WeaponData.WeaponType.SPEAR: return FEMALE_SPEAR_PROFILE if player._is_female else MALE_SPEAR_PROFILE
	if player._get_equipped_weapon_type() == WeaponData.WeaponType.DOUBLE_SABER: return FEMALE_DOUBLE_PROFILE if player._is_female else MALE_DOUBLE_PROFILE
	if player._get_equipped_weapon_type() == WeaponData.WeaponType.CLAW: return FEMALE_CLAW_PROFILE if player._is_female else MALE_CLAW_PROFILE
	if player._get_equipped_weapon_type() == WeaponData.WeaponType.DAGGERS: return FEMALE_DAGGER_PROFILE if player._is_female else MALE_DAGGER_PROFILE
	if player._get_equipped_weapon_type() == WeaponData.WeaponType.SWORD:
		return FEMALE_SWORD_PROFILE if player._is_female else MALE_SWORD_PROFILE
	return FEMALE_PROFILE if player._is_female else MALE_PROFILE

static func profile_for_library(path: String) -> Dictionary:
	if path == FEMALE_GUNBLADE_PROFILE.library: return FEMALE_GUNBLADE_PROFILE
	if path == MALE_GUNBLADE_PROFILE.library: return MALE_GUNBLADE_PROFILE
	if path == FEMALE_SLICER_PROFILE.library: return FEMALE_SLICER_PROFILE
	if path == MALE_SLICER_PROFILE.library: return MALE_SLICER_PROFILE
	if path == FEMALE_SPEAR_PROFILE.library: return FEMALE_SPEAR_PROFILE
	if path == MALE_SPEAR_PROFILE.library: return MALE_SPEAR_PROFILE
	if path == FEMALE_DOUBLE_PROFILE.library: return FEMALE_DOUBLE_PROFILE
	if path == MALE_DOUBLE_PROFILE.library: return MALE_DOUBLE_PROFILE
	if path == FEMALE_CLAW_PROFILE.library: return FEMALE_CLAW_PROFILE
	if path == MALE_CLAW_PROFILE.library: return MALE_CLAW_PROFILE
	if path == FEMALE_DAGGER_PROFILE.library: return FEMALE_DAGGER_PROFILE
	if path == MALE_DAGGER_PROFILE.library: return MALE_DAGGER_PROFILE
	if path == FEMALE_SWORD_PROFILE.library: return FEMALE_SWORD_PROFILE
	if path == MALE_SWORD_PROFILE.library: return MALE_SWORD_PROFILE
	if path == LIBRARY: return MALE_PROFILE
	if path == FEMALE_LIBRARY: return FEMALE_PROFILE
	return {}

static func ready_clip(player) -> String:
	return str(profile(player).get("ready", str(profile(player).prefix) + "_wait"))

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
		 or player._get_equipped_weapon_type() == WeaponData.WeaponType.SWORD \
		 or player._get_equipped_weapon_type() == WeaponData.WeaponType.DAGGERS \
		 or player._get_equipped_weapon_type() == WeaponData.WeaponType.CLAW \
		 or player._get_equipped_weapon_type() == WeaponData.WeaponType.DOUBLE_SABER \
		 or player._get_equipped_weapon_type() == WeaponData.WeaponType.SPEAR \
		 or player._get_equipped_weapon_type() == WeaponData.WeaponType.SLICER \
		 or player._get_equipped_weapon_type() == WeaponData.WeaponType.GUN_BLADE)

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
	return str(profile(player).get("idle", native_clip(player, "wait")))

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
	block_feedback(player, source)
	return true

static func guarding(player) -> bool:
	return enabled(player) and player.current_state == player.PlayerState.DAMAGED \
		and player.animation_player != null and player.animation_player.current_animation == str(profile(player).prefix) + "_block"

static func select_walk(player, cautious: bool) -> void:
	var clip: String = str(profile(player).get("caution", str(profile(player).prefix) + "_walk_ready")) if cautious else str(profile(player).walk)
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
	if strong and enemy.is_alive and enemy.current_state == enemy.EnemyState.HURT:
		enemy.hurt_timer = maxf(enemy.hurt_timer, 0.45)
	if source._get_equipped_weapon_type() in [WeaponData.WeaponType.DAGGERS, WeaponData.WeaponType.CLAW, WeaponData.WeaponType.DOUBLE_SABER]:
		var now := Time.get_ticks_msec()
		if now - int(enemy.get_meta("dagger_feedback_ms", -1000)) < 80: return
		enemy.set_meta("dagger_feedback_ms", now)
	# The caller verifies actual HP loss; no spark or sound on a whiff/immune hit.
	SfxManager.play_at("res://assets/sfx/weapons/saber_hit.wav", enemy.global_position, 0.0 if strong else -7.0)
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

static func block_feedback(player, source: Node3D) -> void:
	# A distinct blue-white flash at the guard, only after a hit is blocked.
	var burst := CPUParticles3D.new()
	burst.name = "GuardSpark"
	burst.add_to_group("prototype_block_feedback")
	burst.one_shot = true
	burst.amount = 18
	burst.lifetime = 0.3
	burst.explosiveness = 1.0
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 0.06
	burst.direction = Vector3.UP
	burst.spread = 160.0
	burst.initial_velocity_min = 0.8
	burst.initial_velocity_max = 1.8
	burst.gravity = Vector3(0, -1.0, 0)
	burst.scale_amount_min = 0.6
	burst.scale_amount_max = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.055
	mesh.height = 0.11
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.55, 0.85, 1.0)
	mesh.material = material
	burst.mesh = mesh
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(0.5, 0.8, 1, 0))
	burst.color_ramp = fade
	player.get_tree().current_scene.add_child(burst)
	var toward: Vector3 = source.global_position - player.global_position
	toward.y = 0
	burst.global_position = player.global_position + Vector3.UP * 1.1 + toward.normalized() * 0.45
	burst.emitting = true
	burst.finished.connect(burst.queue_free)

	# Camera-facing flash stays readable even when the attacking enemy
	# overlaps the player's hands. This is at chest height, never on the floor.
	var flash := MeshInstance3D.new()
	flash.name = "GuardFlash"
	flash.add_to_group("prototype_block_flash")
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	var ring := Gradient.new()
	ring.offsets = PackedFloat32Array([0.0, 0.55, 0.70, 0.84, 1.0])
	ring.colors = PackedColorArray([Color(0.4,0.9,1,0.15), Color(0.4,0.9,1,0), Color(0.7,1,1,1), Color(0.2,0.8,1,0.85), Color(0.2,0.8,1,0)])
	var texture := GradientTexture2D.new()
	texture.width = 64
	texture.height = 64
	texture.gradient = ring
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_material.no_depth_test = true
	flash_material.albedo_texture = texture
	quad.material = flash_material
	flash.mesh = quad
	player.get_tree().current_scene.add_child(flash)
	flash.global_position = burst.global_position
	flash.scale = Vector3.ONE * 0.7
	var tween := flash.create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 1.25, 0.32)
	tween.tween_property(flash_material, "albedo_color:a", 0.0, 0.24).set_delay(0.08)
	tween.chain().tween_callback(flash.queue_free)

static func gun_mode(player) -> bool:
	return player._get_equipped_weapon_type() == WeaponData.WeaponType.GUN_BLADE and bool(player.get_meta("prototype_gun_mode", false))

static func select_gunblade_step(player) -> void:
	if not enabled(player) or player._get_equipped_weapon_type() != WeaponData.WeaponType.GUN_BLADE: return
	player._update_combat_targets()
	var shoot := false
	if not player._targeted_enemies.is_empty():
		var target = player._targeted_enemies[0]
		if is_instance_valid(target):
			var offset: Vector3 = target.global_position - player.global_position
			offset.y = 0
			shoot = offset.length() > 2.4
	player.set_meta("prototype_gun_mode", shoot)
	player._run_anim = str(profile(player).run)
	select_walk(player, player._saber_caution_active)

static func toggle_gun_mode(player) -> bool:
	if not enabled(player) or player._get_equipped_weapon_type() != WeaponData.WeaponType.GUN_BLADE: return false
	if player.current_state not in [player.PlayerState.IDLE, player.PlayerState.WALKING, player.PlayerState.RUNNING] or player._saber_attack_cooldown > 0 or player._recovery_left > 0: return false
	player.set_meta("prototype_gun_mode", not gun_mode(player))
	player._queued_combo = player.ComboQueue.NONE
	player._queued_combo_special = false
	player._queued_combo_yaw = null
	player._attack_damage_snapshot.clear()
	player._run_anim = str(profile(player).run)
	select_walk(player, player._saber_caution_active)
	player.transition_to(player.current_state)
	return true

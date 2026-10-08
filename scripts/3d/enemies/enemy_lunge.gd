extends RefCounted
## Single-clip lunge: body movement owns planar travel; the rig owns its pose.
var distance := 0.0
var progress := 0.0
var blocked := false

func begin(enemy: CharacterBody3D, target_distance: float) -> void:
	distance = minf(target_distance + 0.5, float(enemy._attack_def.get("max_range", 7.0)))
	progress = 0.0
	blocked = false

func step(enemy: CharacterBody3D, fraction: float) -> void:
	var next := clampf(fraction, 0.0, 1.0)
	var motion: Vector3 = enemy._attack_facing * distance * maxf(next - progress, 0.0)
	progress = next
	var start := enemy.global_position
	# Bound floor checks even if a slow frame crosses most of the attack window.
	var remaining := motion.length()
	while not blocked and remaining > 0.00001:
		var step_length := minf(remaining, 0.5)
		if enemy._can_move_to(enemy._attack_facing):
			blocked = enemy.move_and_collide(enemy._attack_facing * step_length) != null
		else:
			blocked = true
		remaining -= step_length
	if enemy._attack_hit_resolved or not is_instance_valid(enemy.target):
		return
	var reach: float = float(enemy._attack_def.get("hit_reach", 1.0)) + enemy.PLAYER_HIT_RADIUS
	if ProjectileSweep.planar_fraction(start, enemy.global_position - start, enemy.target.global_position, reach) >= 0.0:
		enemy._attack_hit_resolved = true
		enemy._deal_damage_for(enemy._attack_def)

## Clone the library before editing; imported resources can be shared by enemies.
static func prepare_clip(player: AnimationPlayer, full_name: String, bone: String) -> void:
	if full_name.is_empty() or bone.is_empty() or player.has_meta("lunge:" + full_name):
		return
	var slash := full_name.find("/")
	var library_name := full_name.substr(0, slash) if slash >= 0 else ""
	var clip_name := full_name.substr(slash + 1)
	var library := player.get_animation_library(library_name).duplicate(true) as AnimationLibrary
	var animation := library.get_animation(clip_name)
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D or not str(animation.track_get_path(track)).ends_with(":" + bone):
			continue
		var origin: Vector3 = animation.track_get_key_value(track, 0)
		for key in range(animation.track_get_key_count(track)):
			var value: Vector3 = animation.track_get_key_value(track, key)
			value.x = origin.x
			value.z = origin.z
			animation.track_set_key_value(track, key, value)
	player.remove_animation_library(library_name)
	player.add_animation_library(library_name, library)
	player.set_meta("lunge:" + full_name, true)

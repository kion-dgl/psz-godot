extends RefCounted
## Two alternating contact cues per locomotion cycle, in either playback direction.
var clip := ""
var previous := 0.0
var reverse := false
var emitted := 0

static func crossed(start: float, end: float, backwards: bool, contacts := 2) -> bool:
	if is_equal_approx(start, end): return false
	if backwards:
		if end > start: end -= 1.0
		return ceili(start * contacts) != ceili(end * contacts)
	if end < start: end += 1.0
	return floori(start * contacts) != floori(end * contacts)

func tick(p, moved: float) -> void:
	var ap: AnimationPlayer = p.animation_player
	if not p.is_on_floor() or moved < 0.000001 or not p.current_state in [p.PlayerState.WALKING, p.PlayerState.RUNNING] or ap == null or not ap.is_playing():
		clip = ""
		return
	var name: String = ap.current_animation
	var length := ap.current_animation_length
	if length <= 0.0: return
	var phase := fposmod(ap.current_animation_position / length, 1.0)
	var backwards := ap.get_playing_speed() < 0.0
	var strafing: bool = p.combat_aim != null and p.combat_aim.active
	if clip == name and reverse == backwards and crossed(previous, phase, backwards, 1 if strafing else 2):
		var sound: String = p._resolve_footstep_clip()
		if not sound.is_empty():
			SfxManager.play_at(sound, p.global_position, -16.0 if strafing else -8.0, strafing)
			emitted += 1
	clip = name
	previous = phase
	reverse = backwards

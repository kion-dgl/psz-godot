extends Node3D
class_name TrapBall
## An elemental trap. ONE class, two families — which is how the game does it.
##
## psz-re decoded the original: the four trap ITEMS a CAST drops (#575) and the
## four elemental traps AUTHORED into every field room (#579) are the same
## object class — factory index 19 / type 0x1C13 — and the only thing that tells
## them apart is one byte in the object's parameter block. The player's trap is
## built by a four-slot manager (one live trap per player) that synthesises the
## same 24-byte set record the level files carry, with that byte set to 1.
## See psz-re nodes/sys.player-traps.json and docs/godot-field-parity.md §8.1.
##
## So `field_placed` here is that byte, and everything else is shared.
##
##   player-placed   dropped at the player's feet, arms after ARM_DELAY, fires
##                   on the first valid target inside TRIGGER_RADIUS.
##   field-placed    authored into the room and INVISIBLE. Arms when a player
##                   walks inside TRIGGER_RADIUS, rises out of the ground, and
##                   fires on the players.
##
## Both then run the same fuse: a measured frame count between arming and the
## blast, during which the ball is up and visible and can be walked away from.
##
## NOT DECODED, and flagged so nobody reads this as measured: what arms a field
## trap. psz-re can read the state machine but the transition out of dormant is
## written by the base object class and was not followed, so "a player walks
## close" is the obvious reading of a thing that rises out of the ground on a
## fuse — it is not measured, and neither is its radius. TRIGGER_RADIUS is the
## one radius psz-re does publish (the Heal element's player scan) reused here.

## Ball model per trap element.
##
## MAPPING IS PROVISIONAL. There are four balls and four trap items, but nothing
## states which is which. Decoding the textures gives burst01 green (128,224,192),
## burst02 gold (224,192,64), burst03 magenta (224,128,192), burst04 pale cyan
## (192,224,224), so the colours are read as Heal / Heat / Light / Ice. The
## tempting index reading (01 -> Heat, matching item order) disagrees: it would
## make Heat green and Ice magenta.
##
## SECOND WITNESS, from psz-re §8.1: the object-side element ladder decoded out
## of the constructor's cmp chain runs `0 Heal, 1 Heat, 2 Light, 3 Ice` — the
## same order, arrived at from the instruction stream with no reference to any
## texture. Colour and code now agree, so this table is no longer resting on one
## reading. A savestate with a known trap on the ground would still settle it
## outright.
const TRAP_MODELS := {
	"heal_trap": "o0c_burst01",
	"heat_trap": "o0c_burst02",
	"light_trap": "o0c_burst03",
	"ice_trap": "o0c_burst04",
}

## Element index, as the game orders them. Used for the fuse table, which
## singles out element 0.
const TRAP_ELEMENT := {"heal_trap": 0, "heat_trap": 1, "light_trap": 2, "ice_trap": 3}

## What each trap does.
##
## `heal_percent` is MEASURED: psz-re reads the Heal element's command 0x22 as
## `max_hp / 2` in both of the game's handlers, so 50% is the game's number and
## not an estimate. The statuses are still from the consumable's `details` text.
##
## `light_trap` should inflict Confusion, which does not exist as a status —
## CombatManager.STATUS_EFFECTS has freeze/stun/poison/slow/paralysis/burn/sleep
## and nothing that turns an enemy on its allies. Stunned is the nearest
## existing behaviour and is used as a stand-in; a real Confusion status is its
## own piece of work.
const TRAP_EFFECTS := {
	"heat_trap": {"target": "enemies", "status": "burn"},
	"ice_trap": {"target": "enemies", "status": "freeze"},
	"light_trap": {"target": "enemies", "status": "stun"},
	"heal_trap": {"target": "allies", "heal_percent": 0.5},
}

## Damage a field-placed hostile trap deals to the player.
##
## NOT MEASURED. psz-re establishes that the elemental trap carries no
## per-instance parameters at all — the block is event-flag conditions and
## zeros — and does not name the attack descriptor the class builds, so there is
## no number to port. This is ours, sized to sting rather than kill.
const FIELD_TRAP_DAMAGE := 15

## Frames between arming and the blast, measured out of FUN_0209B8C4.
##
## The player's trap singles out element 0 (Heal) at 150 and gives every other
## element 75. The field's trap switches on the session record's difficulty byte
## instead, and gets FASTER as the difficulty rises — 45 / 30 / 15.
const PLAYER_FUSE_FRAMES := {0: 150, "else": 75}
const FIELD_FUSE_FRAMES := [45, 30, 15]
const FUSE_FPS := 60.0

## The one radius psz-re publishes: the Heal element scans the four players and
## acts inside 0x4000 = 4.0 units.
const TRIGGER_RADIUS := 4.0
const ARM_DELAY := 1.0
const LIFETIME := 60.0
const BOB_AMPLITUDE := 0.06
const BOB_SPEED := 3.0

## How far a field trap rises out of the ground once armed. The game lifts it to
## +0x2800 in 1.19.12 = 2.5 units.
const FIELD_RISE_HEIGHT := 2.5
const FIELD_RISE_SECONDS := 0.35

## How long one Trap Vision lasts.
##
## NOT MEASURED — psz-re found no Trap Vision timer anywhere in the trap class,
## so there is nothing to port and this is a game-feel number.
const TRAP_VISION_SECONDS := 60.0

## How high the ball floats above the trap's origin (the player's feet).
##
## Set to the top of the player's head, so it reads as suspended on a string
## rather than dropped. Measured from the visual mesh, NOT the collision capsule:
## assets/player/pc_000/pc_000_000.glb spans y=0.003..1.840, so the crown is
## y≈1.84. (The capsule in player.tscn is only 1.4 tall — shorter than the model
## — which is why sizing against it put the ball at chest height.) The ball mesh
## is itself ~0.5 across, so its centre sits a little under the crown.
const REST_HEIGHT := 1.6

## A field trap sits ON the floor while dormant, not at head height.
const FIELD_REST_HEIGHT := 0.35

signal triggered(trap_id: String)

var trap_id: String = ""

## The parameter-block byte, inverted into the name the code reads better as.
## false = the player's item, true = authored into the room.
var field_placed: bool = false

## Difficulty index (0 normal, 1 hard, 2 v_hard) — the session-record byte the
## field fuse switches on. Only read when `field_placed`.
var difficulty: int = 0

## Set by the autopilot harness: a trap that never arms. The nav backbone walks
## straight over authored trap positions and a blast mid-route is noise, not a
## finding.
var disarmed: bool = false

## Wall-clock msec until which every trap is visible to everyone. Static so it
## survives the trap that granted it and needs no autoload.
static var vision_until_msec: int = 0

var _armed := false
var _triggered := false
var _spent := false
var _age := 0.0
var _fuse_left := 0.0
var _rise := 0.0
var _model: Node3D
var _area: Area3D


## Grant Trap Vision to the party. Static so the consumable can call it without
## a trap in the scene.
static func grant_vision(seconds: float = TRAP_VISION_SECONDS) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	vision_until_msec = maxi(vision_until_msec, until)


static func vision_active() -> bool:
	return Time.get_ticks_msec() < vision_until_msec


## True when a dormant field trap should be drawn: the active character is a
## CAST, or Trap Vision is running. Both, per the item's own description —
## "Temporarily allows any non-Cast race to see traps."
static func traps_are_visible() -> bool:
	if vision_active():
		return true
	return Inventory.can_use_traps()


## Build a placed trap. Returns null for an unknown id rather than dropping an
## invisible node the player has paid an item for.
static func build(id: String) -> TrapBall:
	if not TRAP_MODELS.has(id):
		push_warning("TrapBall: unknown trap id '%s'" % id)
		return null
	var trap := TrapBall.new()
	trap.trap_id = id
	trap.name = "TrapBall_" + id
	return trap


## Build the authored, field-placed form of the same object.
static func build_field(id: String, difficulty_index: int = 0) -> TrapBall:
	var trap := build(id)
	if trap == null:
		return null
	trap.field_placed = true
	trap.difficulty = clampi(difficulty_index, 0, FIELD_FUSE_FRAMES.size() - 1)
	trap.name = "FieldTrap_" + id
	return trap


## Seconds from arming to the blast, from the measured frame counts.
func fuse_seconds() -> float:
	if field_placed:
		return float(FIELD_FUSE_FRAMES[clampi(difficulty, 0, FIELD_FUSE_FRAMES.size() - 1)]) / FUSE_FPS
	var element: int = int(TRAP_ELEMENT.get(trap_id, 1))
	var frames: int = int(PLAYER_FUSE_FRAMES.get(element, PLAYER_FUSE_FRAMES["else"]))
	return float(frames) / FUSE_FPS


func _ready() -> void:
	add_to_group("player_traps")
	if field_placed:
		add_to_group("field_traps")
	_load_ball()
	_build_area()
	_apply_visibility()


func _rest_height() -> float:
	return FIELD_REST_HEIGHT if field_placed else REST_HEIGHT


func _load_ball() -> void:
	var model_id: String = str(TRAP_MODELS.get(trap_id, ""))
	var path := "res://assets/effects/%s/%s.glb" % [model_id, model_id]
	var packed := load(path) as PackedScene
	if not packed:
		push_warning("TrapBall: missing model " + path)
		return
	_model = packed.instantiate() as Node3D
	_model.position.y = _rest_height()
	add_child(_model)


func _build_area() -> void:
	_area = Area3D.new()
	_area.name = "TrapTrigger"
	# Layer 3 (triggers), watching players and enemies — the heal trap and every
	# field trap need the player layer, the rest need enemies.
	_area.collision_layer = 4
	_area.collision_mask = 2 | 8
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = TRIGGER_RADIUS
	shape.shape = sphere
	shape.position.y = _rest_height()
	_area.add_child(shape)
	add_child(_area)


## A dormant field trap is not drawn unless the viewer can see traps. A player's
## own trap is always drawn — they placed it.
func _apply_visibility() -> void:
	if not _model:
		return
	_model.visible = (not field_placed) or _armed or traps_are_visible()


func _process(delta: float) -> void:
	_age += delta
	if _spent:
		return

	# Stage 1 — dormant. A player's trap is arming on a timer; a field trap is
	# waiting for somebody to walk in.
	if not _armed:
		_idle_motion()
		_apply_visibility()
		if _should_arm():
			_arm()
		elif _age >= LIFETIME and not field_placed:
			_expire()
		return

	# Stage 2 — armed but not yet triggered. Only a player's trap sits here:
	# a field trap is triggered by the same proximity that armed it.
	if not _triggered:
		_idle_motion()
		if _check_targets():
			_trigger()
		elif _age >= LIFETIME:
			_expire()
		return

	# Stage 3 — the fuse. The ball is up and visible and can be walked away
	# from; whoever is still inside when it reaches zero takes the blast.
	if field_placed and _rise < 1.0:
		_rise = minf(1.0, _rise + delta / FIELD_RISE_SECONDS)
	_armed_motion()
	_fuse_left -= delta
	if _fuse_left <= 0.0:
		_detonate()


## Player-placed: arms on a timer. Field-placed: arms when someone walks in.
func _should_arm() -> bool:
	if disarmed:
		return false
	if not field_placed:
		return _age >= ARM_DELAY
	return _has_player_in_range()


func _arm() -> void:
	_armed = true
	if _model:
		_model.visible = true
	# A field trap's arming IS its trigger — the proximity that woke it is the
	# proximity that sets it off. A player's trap waits for a target.
	if field_placed:
		_trigger()


func _trigger() -> void:
	_triggered = true
	_fuse_left = fuse_seconds()


func _idle_motion() -> void:
	if not _model:
		return
	_model.position.y = _rest_height() + sin(_age * BOB_SPEED) * BOB_AMPLITUDE
	_model.rotation.y = _age


func _armed_motion() -> void:
	if not _model:
		return
	var base: float = _rest_height()
	if field_placed:
		base += FIELD_RISE_HEIGHT * _rise
	_model.position.y = base + sin(_age * BOB_SPEED) * BOB_AMPLITUDE
	_model.rotation.y = _age


func _has_player_in_range() -> bool:
	if not _area:
		return false
	for body in _area.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false


## Poll rather than react to body_entered: a trap arms a second after landing,
## and anything already standing inside it should set it off the moment it arms
## — an entered signal fired before arming would be lost.
func _check_targets() -> bool:
	if not _area:
		return false
	for body in _area.get_overlapping_bodies():
		if _is_valid_target(body):
			return true
	return false


func _is_valid_target(body: Node) -> bool:
	if field_placed:
		return body.is_in_group("player")
	var target: String = str(TRAP_EFFECTS.get(trap_id, {}).get("target", "enemies"))
	if target == "allies":
		return body.is_in_group("player")
	return body.is_in_group("enemies") and _is_alive(body)


func _is_alive(body: Node) -> bool:
	# Boxes share the "enemies" group so they can be attacked; they are not
	# something a trap should be spent on.
	if body is Box:
		return false
	if body.has_method("get") and body.get("is_alive") != null:
		return bool(body.get("is_alive"))
	return true


func _detonate() -> void:
	_spent = true
	var effect: Dictionary = TRAP_EFFECTS.get(trap_id, {})
	var status: String = str(effect.get("status", ""))
	var heal_percent: float = float(effect.get("heal_percent", 0.0))
	var hits := 0

	for body in _area.get_overlapping_bodies():
		if not _is_valid_target(body):
			continue
		hits += 1
		if field_placed:
			_hit_player(body, status, heal_percent)
		elif not status.is_empty() and body.has_method("apply_status_effect"):
			body.apply_status_effect(status)
		elif heal_percent > 0.0 and body.is_in_group("player"):
			_heal(heal_percent)

	print("[TrapBall] %s%s triggered on %d target(s)" % [
		trap_id, " (field)" if field_placed else "", hits])
	triggered.emit(trap_id)
	_finish()


## A field trap fires at the party. The Heal element still heals — psz-re's
## corpus has 287 authored Heal traps, so ~10% of what a field places helps you.
func _hit_player(body: Node, status: String, heal_percent: float) -> void:
	if heal_percent > 0.0:
		_heal(heal_percent)
		return
	if body.has_method("take_damage"):
		body.take_damage(FIELD_TRAP_DAMAGE)
	if not status.is_empty() and body.has_method("apply_status_effect"):
		body.apply_status_effect(status)


func _heal(percent: float) -> void:
	var amount: int = int(float(GameState.max_hp) * percent)
	GameState.set_hp(mini(GameState.hp + amount, GameState.max_hp))


func _expire() -> void:
	_spent = true
	print("[TrapBall] %s expired unused" % trap_id)
	_finish()


func _finish() -> void:
	set_process(false)
	if _area:
		_area.set_deferred("monitoring", false)
	queue_free()

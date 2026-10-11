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
## Constructor element ladder and burst texture colors agree on this mapping.
## See psz-re docs/godot-field-parity.md §8.1.
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
const FUSE_FPS := 60.0 # Remake conversion; original timer timebase is unresolved.

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
var _blast_area: Area3D
var hurtbox: Hurtbox
var _reticle: Node3D
@export var trigger_radius: float = TRIGGER_RADIUS
@export var blast_radius: float = TRIGGER_RADIUS
var is_alive: bool:
	get: return can_be_targeted()
var target_radius: float = 0.75
var target_height: float:
	get: return 2.0 * (_rest_height() + FIELD_RISE_HEIGHT * _rise)

func can_be_targeted() -> bool:
	return field_placed and trap_id != "heal_trap" and not _spent and not disarmed and (_armed or traps_are_visible())

func take_damage(amount: int, _knockback := Vector3.ZERO, _accuracy: int = 100) -> void:
	if amount <= 0 or not can_be_targeted():
		return
	disarmed = true
	_spent = true
	_finish()

func show_reticle() -> void:
	if _reticle:
		_reticle.visible = can_be_targeted()

func hide_reticle() -> void:
	if _reticle:
		_reticle.hide()

func _build_hurtbox() -> void:
	if not field_placed:
		return
	add_to_group("targetable_traps")
	hurtbox = Hurtbox.new()
	hurtbox.owner_node = self
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = target_radius
	shape.shape = sphere
	hurtbox.add_child(shape)
	add_child(hurtbox)
	_reticle = TargetReticle.build(0.0)
	add_child(_reticle)


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
	_build_hurtbox()
	_apply_visibility()


func _rest_height() -> float:
	return FIELD_REST_HEIGHT if field_placed else REST_HEIGHT


## Mirrored-repeat UV wrapping, which StandardMaterial3D cannot express.
##
## The burst GLBs declare wrapS = wrapT = MIRRORED_REPEAT (glTF 33648) and run
## TEXCOORD_0 V from -0.5 to +0.5, i.e. half of every quad samples outside 0..1
## and is meant to mirror back. Godot's glTF importer has no mirrored mode — the
## material only carries a `texture_repeat` bool — and it imports these as
## texture_repeat = false (CLAMP). Clamping smears the texture's edge row across
## the entire outside-0..1 half, which is the "grey angular mass with a coloured
## streak" these models render as. Plain repeat is not right either: it wraps
## instead of mirroring and seams down the middle of each quad.
##
## This is the same fix the stage/gate geometry already needed — see the shared
## fold in mirror_repeat.gdshaderinc. The long-term fix is at the asset level
## (bake the mirror into the texture and author UVs in 0..1), which would let
## every mirror_repeat* shader retire.
const MIRROR_SHADER := preload("res://scripts/3d/shaders/mirror_repeat_effect.gdshader")


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
	_apply_mirror_wrap(_model)


## Swap each surface's imported StandardMaterial3D for the mirrored-wrap shader,
## carrying over its albedo texture. Walks the whole subtree because the burst
## meshes sit under a Skeleton3D.
##
## A field-placed trap gets this too: it spends most of its life invisible, but
## the moment it arms it rises into view, and it is the same mesh either way.
func _apply_mirror_wrap(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh:
			for i in mesh.get_surface_count():
				var src := mesh.surface_get_material(i) as StandardMaterial3D
				if src == null or src.albedo_texture == null:
					continue
				var mat := ShaderMaterial.new()
				mat.shader = MIRROR_SHADER
				mat.set_shader_parameter("albedo_texture", src.albedo_texture)
				mat.set_shader_parameter("albedo_tint", src.albedo_color)
				mat.set_shader_parameter("mirror_x", true)
				mat.set_shader_parameter("mirror_y", true)
				mat.set_shader_parameter("alpha_scissor", src.alpha_scissor_threshold)
				(node as MeshInstance3D).set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_mirror_wrap(child)


func _build_area() -> void:
	_area = Area3D.new()
	_area.name = "TrapTrigger"
	# Layer 3 (triggers), watching players and enemies — the heal trap and every
	# field trap need the player layer, the rest need enemies.
	_area.collision_layer = 4
	_area.collision_mask = 2 | 8
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = trigger_radius
	shape.shape = sphere
	shape.position.y = _rest_height()
	_area.add_child(shape)
	add_child(_area)
	_blast_area = _area.duplicate() as Area3D
	_blast_area.name = "TrapBlast"
	var blast_shape := (_blast_area.get_child(0) as CollisionShape3D)
	blast_shape.shape = sphere.duplicate()
	(blast_shape.shape as SphereShape3D).radius = blast_radius
	add_child(_blast_area)


## A dormant field trap is not drawn unless the viewer can see traps. A player's
## own trap is always drawn — they placed it.
func _apply_visibility() -> void:
	if hurtbox:
		hurtbox.set_deferred("monitorable", can_be_targeted())
		hurtbox.position.y = target_height * 0.5
	if _reticle:
		_reticle.position.y = target_height * 0.5
		if not can_be_targeted():
			_reticle.hide()
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
	_apply_visibility()
	_fuse_left -= delta
	if _fuse_left <= 0.0:
		_detonate()


## Player-placed: arms on a timer. Field-placed: arms when someone walks in.
func _should_arm() -> bool:
	if disarmed:
		return false
	if not field_placed:
		return _age >= ARM_DELAY
	return _check_targets()


func _arm() -> void:
	_armed = true
	if _model:
		_model.visible = true
	# A field trap's arming IS its trigger — the proximity that woke it is the
	# proximity that sets it off. A player's trap waits for a target.
	if field_placed:
		_trigger()


func _trigger() -> void:
	if _spent or disarmed or _triggered:
		return
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
		return body.is_in_group("player") and GameState.hp > 0 and body.get("_is_defeated") != true
	var target: String = str(TRAP_EFFECTS.get(trap_id, {}).get("target", "enemies"))
	if target == "allies":
		return body.is_in_group("player") and GameState.hp > 0 and body.get("_is_defeated") != true
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
	if _spent or disarmed:
		return
	_spent = true
	var effect: Dictionary = TRAP_EFFECTS.get(trap_id, {})
	var status: String = str(effect.get("status", ""))
	var heal_percent: float = float(effect.get("heal_percent", 0.0))
	var hits := 0

	for body in _blast_area.get_overlapping_bodies():
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
	if GameState.hp <= 0 or body.get("_is_defeated") == true:
		return
	if heal_percent > 0.0:
		_heal(heal_percent)
		return
	if body.has_method("can_take_hit") and not body.can_take_hit():
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

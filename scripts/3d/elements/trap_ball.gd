extends Node3D
class_name TrapBall
## A trap the player has placed on the ground (#575).
##
## These are NOT the environmental trap meshes already in the storybook
## (o0c_torabasami, o0c_needle, o0c_gun01/02, o0c_poisonm). Those are room
## furniture placed by the level. These are the four trap ITEMS a CAST carries
## and drops, and they live in the item/effect archive as `o0c_burst01..04` —
## one shared 0.5-unit ball mesh with four recoloured skins, which is why the
## word "trap" appears nowhere in their filenames.
##
## Lifecycle: dropped at the player's feet -> arms after ARM_DELAY -> triggers
## on the first valid target inside TRIGGER_RADIUS -> applies its effect to
## everything in radius -> despawns. The arm delay exists so a trap dropped
## mid-fight does not detonate on the enemy already standing on the player.

## Ball model per trap item.
##
## MAPPING IS PROVISIONAL. There are four balls and four trap items, but nothing
## states which is which. Decoding the textures gives burst01 green (128,224,192),
## burst02 gold (224,192,64), burst03 magenta (224,128,192), burst04 pale cyan
## (192,224,224), so the colours are read as Heal / Heat / Light / Ice. The
## tempting index reading (01 -> Heat, matching item order) disagrees: it would
## make Heat green and Ice magenta. Colour wins here because it is evidence
## rather than an assumption about list order — but a savestate with a known
## trap on the ground settles it, and then only this table changes.
const TRAP_MODELS := {
	"heal_trap": "o0c_burst01",
	"heat_trap": "o0c_burst02",
	"light_trap": "o0c_burst03",
	"ice_trap": "o0c_burst04",
}

## What each trap does, taken from the consumable's own `details` text.
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

const TRIGGER_RADIUS := 4.0
const ARM_DELAY := 1.0
const LIFETIME := 60.0
const BOB_AMPLITUDE := 0.06
const BOB_SPEED := 3.0

## How high the ball floats above the trap's origin (the player's feet).
##
## Set to the top of the player's head, so it reads as suspended on a string
## rather than dropped. Measured from the visual mesh, NOT the collision capsule:
## assets/player/pc_000/pc_000_000.glb spans y=0.003..1.840, so the crown is
## y≈1.84. (The capsule in player.tscn is only 1.4 tall — shorter than the model
## — which is why sizing against it put the ball at chest height.) The ball mesh
## is centred on its own origin and 0.51 across, so it straddles the crown.
##
## The trigger volume is centred on the ball, so raising this lifts it too. That
## is deliberate and harmless: at TRIGGER_RADIUS 4.0 the sphere still reaches
## 3.55 units horizontally at ground level, where the enemies are.
const REST_HEIGHT := 1.85

signal triggered(trap_id: String)

var trap_id: String = ""

var _armed := false
var _spent := false
var _age := 0.0
var _model: Node3D
var _area: Area3D


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


func _ready() -> void:
	add_to_group("player_traps")
	_load_ball()
	_build_area()


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
	_model.position.y = REST_HEIGHT
	add_child(_model)
	_apply_mirror_wrap(_model)


## Swap each surface's imported StandardMaterial3D for the mirrored-wrap shader,
## carrying over its albedo texture. Walks the whole subtree because the burst
## meshes sit under a Skeleton3D.
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
				mat.set_shader_parameter("mirror_x", true)
				mat.set_shader_parameter("mirror_y", true)
				mat.set_shader_parameter("alpha_scissor", src.alpha_scissor_threshold)
				(node as MeshInstance3D).set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_mirror_wrap(child)


func _build_area() -> void:
	_area = Area3D.new()
	_area.name = "TrapTrigger"
	# Layer 3 (triggers), watching players and enemies — the heal trap needs the
	# player layer, the rest need enemies.
	_area.collision_layer = 4
	_area.collision_mask = 2 | 8
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = TRIGGER_RADIUS
	shape.shape = sphere
	shape.position.y = REST_HEIGHT
	_area.add_child(shape)
	add_child(_area)


func _process(delta: float) -> void:
	_age += delta
	if not _armed and _age >= ARM_DELAY:
		_armed = true
	if _model:
		_model.position.y = REST_HEIGHT + sin(_age * BOB_SPEED) * BOB_AMPLITUDE
		_model.rotation.y = _age
	if _age >= LIFETIME and not _spent:
		_expire()
		return
	if _armed and not _spent:
		_check_targets()


## Poll rather than react to body_entered: a trap arms a second after landing,
## and anything already standing inside it should set it off the moment it arms
## — an entered signal fired before arming would be lost.
func _check_targets() -> void:
	if not _area:
		return
	for body in _area.get_overlapping_bodies():
		if _is_valid_target(body):
			_detonate()
			return


func _is_valid_target(body: Node) -> bool:
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
		if not status.is_empty() and body.has_method("apply_status_effect"):
			body.apply_status_effect(status)
		elif heal_percent > 0.0 and body.is_in_group("player"):
			var amount: int = int(float(GameState.max_hp) * heal_percent)
			GameState.set_hp(mini(GameState.hp + amount, GameState.max_hp))

	print("[TrapBall] %s triggered on %d target(s)" % [trap_id, hits])
	triggered.emit(trap_id)
	_finish()


func _expire() -> void:
	_spent = true
	print("[TrapBall] %s expired unused" % trap_id)
	_finish()


func _finish() -> void:
	set_process(false)
	if _area:
		_area.set_deferred("monitoring", false)
	queue_free()

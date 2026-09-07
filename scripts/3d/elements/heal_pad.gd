extends GameElement
class_name HealPad
## The goal room's heal pad (o0c_healhp, #644): exactly one authored record in
## every area's ga1 — the room that terminates every generated section since
## #643, which is what makes the pad worth porting.
##
## THE STATES ARE THE STORYBOOK'S (web objectCatalog 'heal-pad' — the mock is
## the contract): `unused` (charged, can heal) → `used` (spent). Both frames
## live on one sheet — o0c_0_healhp.png, charged left, spent right — and the
## state shifts the texture window by ±0.5 offsetX, easing over 450ms so the
## pad reads as draining rather than cutting. The pad is CONSUMED by its one
## heal; how much the original restores is unmeasured, and the object's own
## name — heal hp — is the reading: HP to full, not PP.
##
## The pad is trigger-only (needle-trap layers): nothing solid for the
## autopilot backbone or the player to wedge on. Nothing about it persists —
## a revisit rebuilds it charged (per-visit resource, spec
## /mechanics/safe-room-ambience).

const STATE_UNUSED := "unused"
const STATE_USED := "used"
## Texture-window offsets, straight off the storybook entry (threejs
## texture.offset semantics match Godot's uv1_offset: sampled = uv + offset).
const UNUSED_OFFSET := 0.5
const USED_OFFSET := -0.5
const DRAIN_SECONDS := 0.45

var _trigger: Area3D = null
var _mat: StandardMaterial3D = null
var _offset_target: float = UNUSED_OFFSET
var _offset_now: float = UNUSED_OFFSET


func _init() -> void:
	model_path = "special_z/o0c_healhp.glb"
	element_state = STATE_UNUSED


func _ready() -> void:
	# Wide and low: the pad is stepped ON, not walked into at chest height.
	# (interactable/auto_collect stay at the base defaults — the pad is not an
	# E-key element and never auto-collects.)
	collision_size = Vector3(2.4, 0.8, 2.4)
	super._ready()
	if model:
		# Per-instance material carrying the state's texture window (the base
		# class's walker reaches every surface — the pad is one flat quad).
		apply_to_all_materials(func(mat, mesh, surface):
			if _mat == null and mat is StandardMaterial3D:
				var dup := (mat as StandardMaterial3D).duplicate()
				dup.uv1_offset = Vector3(_offset_now, 0.0, 0.0)
				mesh.set_surface_override_material(surface, dup)
				_mat = dup)
	_trigger = Area3D.new()
	_trigger.name = "HealArea"
	_trigger.collision_layer = 4  # Triggers layer — same as every element area
	_trigger.collision_mask = 2   # Player layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	shape.shape = box
	shape.position.y = collision_size.y / 2.0
	_trigger.add_child(shape)
	_trigger.body_entered.connect(_on_body_entered)
	add_child(_trigger)


func _on_body_entered(body: Node3D) -> void:
	if element_state != STATE_UNUSED:
		return  # spent for this visit
	if not (body.is_in_group("player") or body.name == "Player"):
		return
	if GameState.hp >= GameState.max_hp:
		return  # charged until it actually heals — a full-HP step is not a spend
	set_state(STATE_USED)
	GameState.set_hp(GameState.max_hp)
	print("[HealPad] Restored HP to %d/%d at %s (pad spent)" % [
		GameState.hp, GameState.max_hp, global_position])


func _apply_state() -> void:
	_offset_target = UNUSED_OFFSET if element_state != STATE_USED else USED_OFFSET


func _update_animation(delta: float) -> void:
	if not _mat:
		return
	# Ease the texture window to the state's frame — the drain.
	var step: float = absf(UNUSED_OFFSET - USED_OFFSET) * delta / DRAIN_SECONDS
	_offset_now = move_toward(_offset_now, _offset_target, step)
	_mat.uv1_offset = Vector3(_offset_now, 0.0, 0.0)

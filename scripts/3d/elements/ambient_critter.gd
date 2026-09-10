extends Node3D
class_name AmbientCritter
## An authored ambient creature — a valley butterfly, a wetlands dragonfly, or
## paru's one-off bird (#644). INERT BY CONTRACT (spec
## /mechanics/safe-room-ambience): no collision, no interaction, no minimap
## marker, no room count, nothing for the autopilot to wedge on.
##
## Does not extend GameElement since it has no interaction — the StoryProp
## precedent. The models are 2-3 KB unlit single-frame billboards with no
## embedded animation: the original animates them in runtime code, so the
## motion is authored here. The data carries positions and facings only; the
## motion parameters are OURS and the spec says so.
##
## ORIENTATION: the original renders these as JIT billboards that always face
## the camera upright — and the GLB's bind pose is a plane tilted across all
## three axes, so any yaw-only facing shows it tipped (kion's playtest: "the
## wings go towards the ground"). The quad's material is therefore switched to
## BILLBOARD_ENABLED, which replaces the basis with a clean camera-facing one.
## The bird is a real rig (body + wing joints) and faces its travel instead.
##
## MOTION: near-stationary (same playtest: "they mostly stuck to one place") —
## a slight drift around the anchor and a gentle bob, nothing that reads as a
## path. The wing-beat squeezes the quad on X; the bird beats its wing joints.
##
## Per-instance phase offsets come from a hash of the anchor, not the field
## RNG: a seeded field populates identically without consuming a single draw.

## Model name under assets/objects/special_z/, e.g. "o0c_butterfly".
@export var critter_model: String = ""

## Motion parameters per model. `hover` lifts the anchor off the authored
## spot: the quads are ~30cm tall and centred on their origin, so an authored
## y of 0 puts half the billboard under the floor — butterflies are authored
## at 0 and fly at ~1m; dragonflies are AUTHORED at 1.5 already, so their
## hover is 0.
const MOTION := {
	"o0c_butterfly": {"radius": 0.35, "lap": 16.0, "bob": 0.12, "flap_hz": 6.0,
		"flap_depth": 0.45, "billboard": true, "hover": 1.0},
	"o0c_dragonfly": {"radius": 0.30, "lap": 12.0, "bob": 0.10, "flap_hz": 14.0,
		"flap_depth": 0.18, "billboard": true, "hover": 0.0},
	"o0c_bird": {"radius": 0.8, "lap": 18.0, "bob": 0.25, "flap_hz": 2.2,
		"flap_depth": 0.7, "billboard": false, "hover": 1.0},
}

const MODEL_DIR := "res://assets/objects/special_z/"

var _anchor: Vector3
var _t: float = 0.0
var _p1: float = 0.0
var _p2: float = 0.0
var _p3: float = 0.0
var _motion: Dictionary = {}
var _quad: Node3D = null
var _quad_base_y: float = 1.0
var _wings: Array[Node3D] = []
var _last_xz := Vector2.ZERO


func _ready() -> void:
	if critter_model.is_empty():
		return
	_motion = MOTION.get(critter_model, MOTION["o0c_butterfly"])
	# Lift the anchor by the kind's hover BEFORE capturing it, so the drift
	# and bob orbit the flying height rather than the authored floor spot.
	position.y += float(_motion["hover"])
	_anchor = position
	_last_xz = Vector2(_anchor.x, _anchor.z)

	var packed := load(MODEL_DIR + critter_model + ".glb") as PackedScene
	if not packed:
		push_warning("AmbientCritter: Failed to load model: " + critter_model)
		return
	var model := packed.instantiate()
	add_child(model)

	# A quad billboard squeezes on X to sell the wing beat; the bird carries
	# real wing joints (wings01/wings02) and beats those instead.
	if _motion["billboard"]:
		_quad = model
		# The dragonfly's skinned node ships a 1.097 base scale; squeeze
		# RELATIVE to it rather than stomping the axis.
		_quad_base_y = model.scale.y
		_face_camera_upright(model)
	else:
		for wing_name in ["wings01", "wings02"]:
			var wing := _find_node(model, wing_name)
			if wing:
				_wings.append(wing)


func _face_camera_upright(model: Node3D) -> void:
	for node in _descend(model):
		if node is MeshInstance3D:
			var mesh := node as MeshInstance3D
			for surface in range(mesh.get_surface_override_material_count()):
				var mat := mesh.get_active_material(surface)
				if mat is StandardMaterial3D:
					var dup := (mat as StandardMaterial3D).duplicate()
					dup.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					mesh.set_surface_override_material(surface, dup)


func _descend(node: Node) -> Array:
	var out := [node]
	for child in node.get_children():
		out.append_array(_descend(child))
	return out


func _process(delta: float) -> void:
	if _motion.is_empty():
		return
	_t += delta

	var radius: float = _motion["radius"]
	var lap: float = _motion["lap"]
	var bob: float = _motion["bob"]
	# Slight drift around the anchor, NOT a path: two slow incommensurate
	# sines hold the critter near its authored spot (the original's
	# butterflies mostly stuck to one place).
	var a := TAU * _t / lap + _p1
	var b := TAU * _t * 0.618 + _p2
	position = _anchor + Vector3(
		radius * sin(a), bob * sin(TAU * _t * 0.9 + _p3), radius * 0.7 * sin(b))

	var flap: float = 0.5 + 0.5 * sin(TAU * float(_motion["flap_hz"]) * _t + _p2)
	if _quad:
		# SIMPLE squash-Y beat — a deliberate placeholder (kion's call after
		# the Flap Lab forensics): all faces visible, texture untouched, the
		# whole billboard breathes vertically. The real wing mechanics (the
		# crossed-quad X, pose swaps, hinge folds) are parked for a fidelity
		# pass in the Flap Lab (#/storybook/flap-lab).
		_quad.scale.y = _quad_base_y * (1.0 - float(_motion["flap_depth"]) * flap)
	elif not _wings.is_empty():
		# The rig's axis is unmeasured; a ±35° beat around X reads as flight
		# whatever the orientation, and taste here is ours (see header).
		var beat := deg_to_rad(35.0) - deg_to_rad(70.0) * flap
		for wing in _wings:
			wing.rotation.x = beat
		_face_travel_yaw()


func _face_travel_yaw() -> void:
	var xz := Vector2(position.x, position.z)
	var v := xz - _last_xz
	_last_xz = xz
	if v.length_squared() > 0.000001:
		rotation.y = atan2(v.x, v.y)


func _find_node(root: Node, node_name: String) -> Node3D:
	if root.name == node_name:
		return root as Node3D
	for child in root.get_children():
		var found := _find_node(child, node_name)
		if found:
			return found
	return null

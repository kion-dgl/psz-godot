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
## motion is authored here — a slow wander in a small radius around the
## authored anchor, a gentle bob, a wing-beat, and a camera-facing yaw for the
## flat quads (edge-on, a quad is invisible). The data carries positions and
## facings only; the motion parameters are OURS and the spec says so.
##
## Per-instance phase offsets come from a hash of the anchor, not the field
## RNG: a seeded field populates identically without consuming a single draw.

## Model name under assets/objects/special_z/, e.g. "o0c_butterfly".
@export var critter_model: String = ""

## Motion parameters per model. `hover` lifts the anchor off the authored
## spot: the quads are ~30cm tall and centred on their origin, so an authored
## y of 0 puts half the billboard under the floor — butterflies are authored
## at 0 and fly at ~1m; dragonflies are AUTHORED at 1.5 already, so their
## hover is 0. The bird is rigged (body + two wing joints), so it beats its
## wing NODES instead of squeezing the quad and faces its travel direction
## rather than yawing to the camera.
const MOTION := {
	"o0c_butterfly": {"radius": 1.6, "lap": 9.0, "bob": 0.22, "flap_hz": 6.0,
		"flap_depth": 0.45, "billboard": true, "hover": 1.0},
	"o0c_dragonfly": {"radius": 2.2, "lap": 7.0, "bob": 0.18, "flap_hz": 14.0,
		"flap_depth": 0.18, "billboard": true, "hover": 0.0},
	"o0c_bird": {"radius": 3.0, "lap": 12.0, "bob": 0.30, "flap_hz": 2.2,
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
var _quad_base_x: float = 1.0
var _wings: Array[Node3D] = []
var _last_xz := Vector2.ZERO


func _ready() -> void:
	if critter_model.is_empty():
		return
	_motion = MOTION.get(critter_model, MOTION["o0c_butterfly"])
	# Lift the anchor by the kind's hover BEFORE capturing it, so the wander
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
		_quad_base_x = model.scale.x
	else:
		for wing_name in ["wings01", "wings02"]:
			var wing := _find_node(model, wing_name)
			if wing:
				_wings.append(wing)

	# Stable per-instance phases from the anchor, so a field's butterflies all
	# flutter out of step without touching the seeded RNG stream.
	var h := int(abs(fposmod(_anchor.x * 733.0 + _anchor.z * 911.0, 65521.0)))
	_p1 = TAU * float(h % 97) / 97.0
	_p2 = TAU * float(h % 89) / 89.0
	_p3 = TAU * float(h % 83) / 83.0


func _find_node(root: Node, node_name: String) -> Node3D:
	if root.name == node_name:
		return root as Node3D
	for child in root.get_children():
		var found := _find_node(child, node_name)
		if found:
			return found
	return null


func _process(delta: float) -> void:
	if _motion.is_empty():
		return
	_t += delta

	var radius: float = _motion["radius"]
	var lap: float = _motion["lap"]
	var bob: float = _motion["bob"]
	# Lissajous wander around the anchor: two incommensurate frequencies, so
	# the path never reads as a circle on rails.
	var a := TAU * _t / lap + _p1
	var b := TAU * _t * 0.618 + _p2
	position = _anchor + Vector3(
		radius * sin(a), bob * sin(TAU * _t * 0.9 + _p3), radius * 0.7 * sin(b))

	var flap: float = 0.5 + 0.5 * sin(TAU * float(_motion["flap_hz"]) * _t + _p2)
	if _quad:
		_quad.scale.x = _quad_base_x * (1.0 - float(_motion["flap_depth"]) * flap)
		_face_camera_yaw()
	elif not _wings.is_empty():
		# The rig's axis is unmeasured; a ±35° beat around X reads as flight
		# whatever the orientation, and taste here is ours (see header).
		var beat := deg_to_rad(35.0) - deg_to_rad(70.0) * flap
		for wing in _wings:
			wing.rotation.x = beat
		_face_travel_yaw()


## Yaw to face the camera around Y only — a full billboard would lay the quad
## flat under a looking-down camera, and the critter lives near the ground.
func _face_camera_yaw() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var to_cam := cam.global_position - global_position
	rotation.y = atan2(to_cam.x, to_cam.z)


func _face_travel_yaw() -> void:
	var xz := Vector2(position.x, position.z)
	var v := xz - _last_xz
	_last_xz = xz
	if v.length_squared() > 0.00001:
		rotation.y = atan2(v.x, v.y)

extends Node3D
class_name QuestMarker
## The point-of-interest star that floats over a quest objective (#577).
##
## `ef_com_quest` is a flat unlit alpha-blended quad carrying a six-point star
## burst (`ff_com_quest.png`, material `light_cent`). It is the only effect in
## the archives that is directly portable — everything else needs its trigger
## conditions traced first — so it is the one that lands here.
##
## Attached to quest item pickups, which are the objectives the player is
## actually sent to collect. Nothing else in the game marks a point of interest
## today; the drop itself is a spinning star with no indication that it is the
## thing the quest wants.

const MODEL := "ef_com_quest"

## Height above the object's origin. The star is ~1.24 units across, so it wants
## to clear the pickup rather than sit inside it.
const DEFAULT_HEIGHT := 1.9

## Gentle vertical bob, matching the Waypoint indicator's feel.
const BOB_AMPLITUDE := 0.12
const BOB_SPEED := 2.2

## Slow spin so the star reads as active rather than painted on. Billboarding
## keeps it facing the camera, so this rolls it in view rather than turning it
## away.
const SPIN_SPEED := 0.6

var _base_y: float = DEFAULT_HEIGHT
var _time: float = 0.0
var _model: Node3D


## Build a marker ready to add_child(). Returns null when the model is missing
## so a caller can simply skip the marker instead of adding an empty node.
static func build(height := DEFAULT_HEIGHT) -> QuestMarker:
	var model := EffectBillboard.load_model(MODEL)
	if not model:
		return null
	var marker := QuestMarker.new()
	marker.name = "QuestMarker"
	marker._model = model
	marker._base_y = height
	marker.position = Vector3(0, height, 0)
	marker.add_child(model)
	return marker


func _process(delta: float) -> void:
	_time += delta
	position.y = _base_y + sin(_time * BOB_SPEED) * BOB_AMPLITUDE
	if _model:
		_model.rotation.z = _time * SPIN_SPEED

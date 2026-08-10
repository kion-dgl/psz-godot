extends Node3D
class_name QuestMarker
## The six-point star burst that marks a quest objective (#577).
##
## `ef_com_quest` is a flat unlit alpha-blended quad carrying the burst
## (`ff_com_quest.png`, material `light_cent`). It is the only effect in the
## archives that is directly portable — everything else needs its trigger
## conditions traced first — so it is the one that lands here.
##
## This IS the pickup's body, not a badge floating above one. The procedural
## gold star QuestItemPickup used to build was only ever a stand-in for this
## texture, so carrying both showed the imitation spinning on the floor and the
## thing it imitated hanging in the air above it.
##
## Deliberately static: no spin, no bob. The archives author it as a still
## burst, and billboarding already keeps it facing the camera.

const MODEL := "ef_com_quest"

## Height of the quad's centre above the pickup's origin. The burst is ~1.24
## units tall and EffectBillboard centres it on the node origin, so without this
## half of it would be under the floor.
const DEFAULT_HEIGHT := 0.7


## Build a marker ready to add_child(). Returns null when the model is missing
## so a caller can fall back instead of adding an invisible node.
static func build(height := DEFAULT_HEIGHT) -> QuestMarker:
	var model := EffectBillboard.load_model(MODEL)
	if not model:
		return null
	var marker := QuestMarker.new()
	marker.name = "QuestMarker"
	marker.position = Vector3(0, height, 0)
	marker.add_child(model)
	return marker

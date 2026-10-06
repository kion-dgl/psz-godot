extends RefCounted
## Floor-1 actor/prop accents. The floor slot's empty lit_surfaces list
## keeps the room on its baked, unshaded materials, including glass and
## scrolling panels. These lights never reach the shadow catcher.
## Positions follow the source stair runs and side-panel geometry; lifted
## above the walk surface to illuminate a character rather than its feet.
const BLUE := Color(0.18, 0.48, 1.0)
const GREEN := Color(0.12, 1.0, 0.48)
const ROOMS := {
	"s081_ga1": {
		"blue": [Vector3(0, 3.5, -7), Vector3(0, 6.5, -18.5), Vector3(0, 2.5, 26)],
		"green": [Vector3(26, 3.5, 10)],
	},
	"s081_sa1": {
		"blue": [Vector3(0, 2.5, -5), Vector3(0, 4.5, 32)],
		"green": [Vector3(-15.5, 3.5, 10)],
	},
	"s081_lb1": {
		"blue": [Vector3(0, 4.5, -32), Vector3(26, 2.5, 0)],
		"green": [Vector3(10.5, 3.5, -10.5)],
	},
	"s081_ib1": {
		"blue": [Vector3(0, 4.5, -32), Vector3(0, 2.5, 26)],
		# This corridor has green wall fixtures instead of scrolling squares.
		"green": [Vector3(-8, 3, -12), Vector3(8, 3, 12)],
	},
}


static func spawn(root: Node3D, stage_id: String) -> void:
	if not ROOMS.has(stage_id) or root.has_node("TowerInteriorLights"):
		return
	var rig := Node3D.new()
	rig.name = "TowerInteriorLights"
	root.add_child(rig)
	var recipe: Dictionary = ROOMS[stage_id]
	for accent in ["blue", "green"]:
		for point in recipe[accent]:
			var light := OmniLight3D.new()
			light.name = "StairBlue" if accent == "blue" else "PanelGreen"
			light.position = point
			light.light_color = BLUE if accent == "blue" else GREEN
			light.light_energy = 2.2 if accent == "blue" else 1.8
			light.omni_range = 20.0 if accent == "blue" else 24.0
			light.omni_attenuation = 1.2
			light.shadow_enabled = false
			light.light_cull_mask &= ~MeshUtils.SHADOW_CATCHER_LAYER
			rig.add_child(light, true)

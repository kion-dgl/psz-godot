extends GameElement
class_name Waypoint
## Navigation indicator placed in load area triggers. Shows if destination has been visited.
## States: new, unvisited, visited

## Target map ID this waypoint leads to
@export var target_map: String = ""

## Texture offset X values for different states (based on o0c_point.imd texture)
const STATE_OFFSETS: Dictionary = {
	"new": 0.00,
	"unvisited": 0.12,
	"visited": 0.40,
}

## Bob animation settings
const BOB_AMPLITUDE: float = 0.05
const BOB_SPEED: float = 2.0

var _base_y: float = 0.0


func _init() -> void:
	model_path = "valley/o0c_point.glb"
	element_state = "unvisited"


func _ready() -> void:
	super._ready()
	_base_y = position.y


func _update_animation(_delta: float) -> void:
	if not model:
		return

	# Gentle bob
	position.y = _base_y + sin(_time * BOB_SPEED) * BOB_AMPLITUDE


func _apply_state() -> void:
	if not model:
		return

	var offset_x: float = STATE_OFFSETS.get(element_state, 0.12)
	# Each waypoint instance needs its own material copy so UV offsets
	# don't bleed across instances sharing the same GLB mesh resource.
	_apply_unique_materials(model, offset_x)


func _apply_unique_materials(node: Node, offset_x: float) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		for i in range(mesh_inst.get_surface_override_material_count()):
			var mat := mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				var own_mat: StandardMaterial3D
				var override := mesh_inst.get_surface_override_material(i)
				if override and override is StandardMaterial3D:
					own_mat = override as StandardMaterial3D
				else:
					own_mat = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					mesh_inst.set_surface_override_material(i, own_mat)
				own_mat.uv1_offset = Vector3(offset_x, own_mat.uv1_offset.y, own_mat.uv1_offset.z)
	for child in node.get_children():
		_apply_unique_materials(child, offset_x)


## Mark as new area
func mark_new() -> void:
	set_state("new")


## Mark as unvisited
func mark_unvisited() -> void:
	set_state("unvisited")


## Mark as visited
func mark_visited() -> void:
	set_state("visited")

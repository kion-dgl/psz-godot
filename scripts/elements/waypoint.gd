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
	apply_to_all_materials(func(mat: Material, _mesh: MeshInstance3D, _surface: int):
		if mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			std_mat.uv1_offset.x = offset_x
	)


## Mark as new area
func mark_new() -> void:
	set_state("new")


## Mark as unvisited
func mark_unvisited() -> void:
	set_state("unvisited")


## Mark as visited
func mark_visited() -> void:
	set_state("visited")

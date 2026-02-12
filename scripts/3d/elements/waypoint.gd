extends GameElement
class_name Waypoint
## Navigation indicator placed in load area triggers. Shows if destination has been visited.
## States: new, unvisited, visited

## Target map ID this waypoint leads to
@export var target_map: String = ""

## Pure colors per state — texture is stripped so only this color shows
const STATE_COLORS: Dictionary = {
	"new": Color(0.3, 1.0, 0.4),       # bright green — unvisited destination
	"unvisited": Color(1.0, 0.7, 0.15), # amber — visited prior
	"visited": Color(0.6, 0.25, 0.25),  # dark red — came from
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

	var tint: Color = STATE_COLORS.get(element_state, Color.WHITE)
	# Each waypoint instance gets its own material with texture stripped
	# so the pure state color is unmistakable.
	_apply_unique_materials(model, tint)


func _apply_unique_materials(node: Node, tint: Color) -> void:
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
				# Remove texture so albedo_color is the sole color source
				own_mat.albedo_texture = null
				own_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				own_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.85)
				own_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				own_mat.emission_enabled = true
				own_mat.emission = tint
				own_mat.emission_energy_multiplier = 0.5
	for child in node.get_children():
		_apply_unique_materials(child, tint)


## Mark as new area
func mark_new() -> void:
	set_state("new")


## Mark as unvisited
func mark_unvisited() -> void:
	set_state("unvisited")


## Mark as visited
func mark_visited() -> void:
	set_state("visited")

extends DropBase
class_name DropMaterial
## Material/recipe drop that uses a procedural colored cone as placeholder.

const CONE_HEIGHT := 0.4
const CONE_RADIUS := 0.15

## Rarity-based colors for the cone
const RARITY_COLORS := {
	1: Color(0.7, 0.7, 0.75),   # Silver — common metals/polymers
	2: Color(0.4, 0.8, 0.4),    # Green — basic recipe boards
	3: Color(0.3, 0.7, 1.0),    # Cyan — photon crystals
	4: Color(0.2, 0.9, 0.5),    # Emerald — mid-tier materials/boards
	5: Color(0.9, 0.5, 0.9),    # Purple
	6: Color(1.0, 0.6, 0.1),    # Orange — advanced recipe boards
	7: Color(1.0, 0.85, 0.2),   # Gold — rare materials
}


func _init() -> void:
	super._init()


func _ready() -> void:
	# Build cone mesh before super._ready() sets up collision
	_build_cone_model()
	super._ready()


func _build_cone_model() -> void:
	var rarity := 1
	var mat_res = MaterialRegistry.get_material(item_id)
	if mat_res:
		rarity = mat_res.rarity
	else:
		var recipe_res = RecipeRegistry.get_recipe(item_id)
		if recipe_res:
			rarity = recipe_res.rarity

	var mesh_instance := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = CONE_RADIUS
	cone.height = CONE_HEIGHT
	cone.radial_segments = 8
	mesh_instance.mesh = cone
	mesh_instance.position.y = CONE_HEIGHT / 2.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = RARITY_COLORS.get(rarity, RARITY_COLORS[1])
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.4
	mat.emission_energy_multiplier = 0.5
	mesh_instance.set_surface_override_material(0, mat)

	model = mesh_instance
	add_child(model)


func _get_display_name() -> String:
	if item_id.is_empty():
		return "Material"
	var mat_res = MaterialRegistry.get_material(item_id)
	if mat_res:
		return mat_res.name
	var recipe_res = RecipeRegistry.get_recipe(item_id)
	if recipe_res:
		return recipe_res.name
	return item_id


func _give_reward() -> void:
	if item_id.is_empty():
		push_warning("[DropMaterial] No item_id set")
		return

	if Inventory.add_item(item_id, amount):
		print("[DropMaterial] Collected ", amount, "x ", _get_display_name())
	else:
		print("[DropMaterial] Failed to add to inventory: ", item_id)

extends "res://scripts/3d/player/player.gd"
## Test-only GLB baseline. Production loading is VRM-only.
func _load_character_model() -> void:
	var character: Dictionary = CharacterManager.get_active_character()
	var appearance: Dictionary = character.get("appearance", {})
	var variation: String = PlayerConfig.get_variation(character.class_id, int(appearance.get("variation_index", 0)))
	var scene := load("res://assets/player/%s/%s_000.glb" % [variation, variation]) as PackedScene
	_install_character_model(scene.instantiate())
	_apply_player_texture_from_path(PlayerConfig.get_paths_for_character(character).texture_path)

extends Node
## PlayerConfig — maps character classes to player model variations and textures.
## Ported from psz-sketch/src/config/characterConfig.ts

# Class ID → model prefix (lowercase class_id → pc_XX)
const CLASS_PREFIX := {
	"humar": "pc_00",
	"humarl": "pc_01",
	"ramar": "pc_02",
	"ramarl": "pc_03",
	"fomar": "pc_04",
	"fomarl": "pc_05",
	"hunewm": "pc_06",
	"hunewearl": "pc_07",
	"fonewm": "pc_08",
	"fonewearl": "pc_09",
	"hucast": "pc_10",
	"hucaseal": "pc_11",
	"racast": "pc_12",
	"racaseal": "pc_13",
}

const BODY_COLORS: Array[String] = ["Red", "Blue", "Green", "Blue & Red", "Black & Red"]
const HAIR_COLORS: Array[String] = ["Blonde", "Brown", "Black"]
const SKIN_TONES: Array[String] = ["Light", "Medium", "Dark"]
const HEAD_VARIATIONS := 4  # 0-3


## Get the variation directory name for a class + variation index (e.g. "pc_032")
func get_variation(class_id: String, variation_index: int) -> String:
	var prefix: String = CLASS_PREFIX.get(class_id, "pc_00")
	return prefix + str(clampi(variation_index, 0, HEAD_VARIATIONS - 1))


## Get the model GLB path for a class + variation index
func get_model_path(class_id: String, variation_index: int) -> String:
	var variation := get_variation(class_id, variation_index)
	return "res://assets/player/%s/%s_000.glb" % [variation, variation]


## Get the texture path for a specific appearance combo
## Texture index formula: floor(skinTone / 3) * 100 + (skinTone % 3) * 10 + bodyColor
## where skinTone = hair * 3 + skin (0-8 range from hair 0-2, skin 0-2)
func get_texture_path(class_id: String, variation_index: int, hair_color: int, skin_tone: int, body_color: int) -> String:
	var variation := get_variation(class_id, variation_index)
	var skin_tone_combined: int = clampi(hair_color, 0, 2) * 3 + clampi(skin_tone, 0, 2)
	var texture_index: int = (skin_tone_combined / 3) * 100 + (skin_tone_combined % 3) * 10 + clampi(body_color, 0, 4)
	var texture_name := "%s_%s" % [variation, str(texture_index).pad_zeros(3)]
	return "res://assets/player/%s/textures/%s.png" % [variation, texture_name]


## Get both model and texture paths from a character dictionary
func get_paths_for_character(character: Dictionary) -> Dictionary:
	var class_id: String = character.get("class_id", "humar")
	var appearance: Dictionary = character.get("appearance", {})
	var vi: int = int(appearance.get("variation_index", 0))
	var hair: int = int(appearance.get("hair_color_index", 0))
	var skin: int = int(appearance.get("skin_tone_index", 0))
	var body: int = int(appearance.get("body_color_index", 0))
	return {
		"model_path": get_model_path(class_id, vi),
		"texture_path": get_texture_path(class_id, vi, hair, skin, body),
	}

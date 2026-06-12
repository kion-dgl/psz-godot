extends RefCounted
## Pure state machine for the character-create flow (#215-D): which step
## is active, which class is selected, and the appearance/name being
## built. No UI — character_create.gd renders from this and forwards
## input to it, so the transitions are testable headless. Preloaded by
## the screen (no class_name; matches the ShopNav composition pattern).

enum Step { CLASS_SELECT, APPEARANCE, NAME_ENTRY }

const APPEARANCE_ROWS := 4  # head variation, hair color, body color, skin tone

var step: int = Step.CLASS_SELECT
var class_list: Array = []  # sorted ClassData array, set once on load
var selected_class_index: int = 0
var selected_class_id: String = ""
var char_name: String = ""
var appearance_row: int = 0
var appearance := {
	"variation_index": 0,
	"body_color_index": 0,
	"hair_color_index": 0,
	"skin_tone_index": 0,
}


func selected_class():
	return class_list[selected_class_index] if not class_list.is_empty() else null


func is_cast_class() -> bool:
	var cls = selected_class()
	return cls != null and cls.race == "Cast"


## Clamped move along the class list (no wrap — first/last feel like
## edges). Returns true when the selection actually changed.
func move_class(direction: int) -> bool:
	var prev := selected_class_index
	selected_class_index = clampi(selected_class_index + direction, 0, maxi(class_list.size() - 1, 0))
	return selected_class_index != prev


## Confirm the hovered class: lock its id, reset appearance to defaults,
## advance to the APPEARANCE step.
func confirm_class() -> void:
	if class_list.is_empty():
		return
	selected_class_id = class_list[selected_class_index].id
	appearance = {"variation_index": 0, "body_color_index": 0, "hair_color_index": 0, "skin_tone_index": 0}
	appearance_row = 0
	step = Step.APPEARANCE


func move_appearance_row(direction: int) -> void:
	appearance_row = wrapi(appearance_row + direction, 0, APPEARANCE_ROWS)


## Cycle the value of the active appearance row, wrapping within that
## row's option count (bounds from PlayerConfig).
func cycle_appearance_value(direction: int) -> void:
	match appearance_row:
		0:
			appearance["variation_index"] = wrapi(
				int(appearance["variation_index"]) + direction, 0, PlayerConfig.HEAD_VARIATIONS)
		1:
			appearance["hair_color_index"] = wrapi(
				int(appearance["hair_color_index"]) + direction, 0, PlayerConfig.HAIR_COLORS.size())
		2:
			appearance["body_color_index"] = wrapi(
				int(appearance["body_color_index"]) + direction, 0, PlayerConfig.BODY_COLORS.size())
		3:
			appearance["skin_tone_index"] = wrapi(
				int(appearance["skin_tone_index"]) + direction, 0, PlayerConfig.SKIN_TONES.size())


## Set the entered name (trimmed). Returns false when empty after trim —
## the screen keeps the player on NAME_ENTRY in that case.
func set_char_name(text: String) -> bool:
	char_name = text.strip_edges()
	return not char_name.is_empty()

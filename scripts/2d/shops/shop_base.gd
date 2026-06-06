class_name ShopBase
extends Control
## Shared base for the city's list-menu shop/counter screens. Owns scaffolding
## that was copy-pasted byte-for-byte across the screens. Subclasses extend this
## instead of Control. (Incremental extraction — see docs/shop-dedup.md.)


## The active character's meseta (0 if no active character).
func _get_meseta() -> int:
	var character = CharacterManager.get_active_character()
	if character:
		return int(character.get("meseta", 0))
	return 0


## NavRepeat callback: re-emit a held nav action as a synthetic input event so
## the screen's own _unhandled_input handles it (hold-to-repeat navigation).
func _on_nav_repeat(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_unhandled_input(ev)

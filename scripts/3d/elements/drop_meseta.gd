extends DropBase
class_name DropMeseta
## Meseta (currency) drop that auto-collects when player walks over it.


func _init() -> void:
	super._init()
	model_path = "valley/o0c_meseta.glb"
	amount = 10  # Default meseta amount
	auto_collect = true
	interactable = false


func _setup_prompt() -> void:
	# No prompt label for meseta — auto-collected on contact
	pass


## The target-info HUD reads this (spec /mechanics/targeting) — meseta has
## no item_id, so without it the panel showed a nameless entry (Rozalin).
func _get_display_name() -> String:
	return "%d Meseta" % amount


func _give_reward() -> bool:
	GameState.add_meseta(amount)
	print("[DropMeseta] Collected ", amount, " meseta (total: ", GameState.get_meseta(), ")")
	return true

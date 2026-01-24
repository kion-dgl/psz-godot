extends DropBase
class_name DropMeseta
## Meseta (currency) drop that can be collected by the player.


func _init() -> void:
	super._init()
	model_path = "valley/o0c_meseta.glb"
	amount = 10  # Default meseta amount


func _give_reward() -> void:
	print("[DropMeseta] Collected ", amount, " meseta")
	# TODO: Add to player's meseta count
	# GameState.add_meseta(amount)

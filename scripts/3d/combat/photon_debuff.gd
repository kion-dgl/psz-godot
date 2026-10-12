extends Node
## Provisional single-player Midgul: 25% ATP/DFP reduction, twenty seconds.
var _left := 20.0
var _defense_delta := 0

func _ready() -> void:
	var enemy = get_parent()
	_defense_delta = int(enemy.current_defense * 0.25)
	enemy.current_defense -= _defense_delta
	enemy.attack_multiplier *= 0.75

func refresh() -> void:
	_left = 20.0

func _physics_process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		var enemy = get_parent()
		enemy.current_defense += _defense_delta
		enemy.attack_multiplier /= 0.75
		queue_free()

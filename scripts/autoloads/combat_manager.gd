extends Node
## CombatManager — handles attack resolution, damage calculation, status effects.
## Ported from psz-sketch/src/systems/combat/

## Constants matching psz-sketch
const BASE_HIT_CHANCE := 0.7
const MAX_HIT_CHANCE := 0.95
const MIN_HIT_CHANCE := 0.3
const CRITICAL_BASE_CHANCE := 0.05
const CRITICAL_MULTIPLIER := 1.5
const DAMAGE_VARIANCE := 0.1

## Element weakness matrix: attacker_element -> defender_weak_to
const ELEMENT_WEAKNESS := {
	"fire": "ice",
	"ice": "fire",
	"lightning": "dark",
	"dark": "lightning",
	"light": "dark",  # Light is bonus damage vs dark only
}

## Status effects from elements
const ELEMENT_STATUS := {
	"fire": ["burn"],
	"ice": ["freeze", "slow"],
	"lightning": ["stun", "paralysis"],
	"dark": ["poison"],
	"light": [],  # No status, extra damage only
}

## Status effect definitions
const STATUS_EFFECTS := {
	"freeze": {"duration": 2, "skip_chance": 1.0, "damage_taken_mult": 1.5, "breaks_on_hit": true},
	"stun": {"duration": 1, "skip_chance": 1.0},
	"poison": {"duration": 3, "dot_percent": 0.05},
	"slow": {"duration": 3, "evasion_mod": -0.3},
	"paralysis": {"duration": 3, "skip_chance": 0.5},
	"burn": {"duration": 3, "dot_percent": 0.03, "defense_mod": -0.1},
}

## Area ID mapping for drop table lookups
const AREA_DROP_NAMES := {
	"gurhacia": "gurhacia-valley",
	"rioh": "rioh-snowfield",
	"ozette": "ozette-wetland",
	"paru": "oblivion-city-paru",
	"makara": "makara-ruins",
	"arca": "arca-plant",
	"dark": "dark-shrine",
}

## Current combat state
var _enemies: Array = []
var _combat_active: bool = false
var _dropped_items: Array = []
var _area_id: String = ""
var _difficulty: String = "normal"

signal combat_started()
signal combat_ended()
signal enemy_defeated(enemy_index: int, enemy_data: Dictionary)
signal enemy_aggroed(enemy_index: int, enemy_data: Dictionary)
signal wave_cleared()


## Initialize combat state
func init_combat(area_id: String = "", difficulty: String = "normal") -> void:
	_enemies.clear()
	_dropped_items.clear()
	_combat_active = true
	_area_id = area_id
	_difficulty = difficulty
	combat_started.emit()


## Set enemies for the current wave
func set_enemies(enemies: Array) -> void:
	_enemies = enemies


## Get current enemies
func get_enemies() -> Array:
	return _enemies


## Get alive enemies
func get_alive_enemies() -> Array:
	var alive: Array = []
	for enemy in _enemies:
		if enemy.get("alive", false):
			alive.append(enemy)
	return alive


## Player attacks an enemy. Returns result dict.
func attack(target_index: int) -> Dictionary:
	if not _combat_active or target_index < 0 or target_index >= _enemies.size():
		return {"hit": false, "message": "Invalid target"}

	var enemy: Dictionary = _enemies[target_index]
	if not enemy.get("alive", false):
		return {"hit": false, "message": "Target already defeated"}

	var character = CharacterManager.get_active_character()
	if character == null:
		return {"hit": false, "message": "No active character"}

	var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	var level: int = int(character.get("level", 1))
	var stats: Dictionary = {}
	if class_data:
		stats = class_data.get_stats_at_level(level)

	var player_attack: int = stats.get("attack", 50)
	var player_accuracy: int = stats.get("accuracy", 100)
	var enemy_evasion: int = int(enemy.get("evasion", 50))

	# Add weapon ATK from equipped weapon
	var weapon_attack := 0
	var equipment: Dictionary = character.get("equipment", {})
	var weapon_id: String = str(equipment.get("weapon", ""))
	if not weapon_id.is_empty():
		var weapon = WeaponRegistry.get_weapon(weapon_id)
		if weapon:
			weapon_attack = weapon.attack_base

	# Calculate hit chance
	var net_accuracy := player_accuracy - enemy_evasion
	var hit_chance := clampf(BASE_HIT_CHANCE + net_accuracy * 0.005, MIN_HIT_CHANCE, MAX_HIT_CHANCE)

	# Apply evasion modifier from status effects
	for effect in enemy.get("status_effects", []):
		var effect_def: Dictionary = STATUS_EFFECTS.get(effect.get("type", ""), {})
		if effect_def.has("evasion_mod"):
			hit_chance += float(effect_def["evasion_mod"]) * -0.5

	if randf() > hit_chance:
		return {"hit": false, "damage": 0, "critical": false, "message": "Miss!"}

	# Calculate damage
	var grind_bonus := 0
	var base_damage := player_attack + weapon_attack + grind_bonus

	# Element multiplier (placeholder)
	var elemental_mult := 1.0

	# Apply defense: damage - (def * 0.25) - (damage * def / 600)
	var enemy_defense: int = int(enemy.get("defense", 0))
	# Check for defense modifier from status
	for effect in enemy.get("status_effects", []):
		var effect_def: Dictionary = STATUS_EFFECTS.get(effect.get("type", ""), {})
		if effect_def.has("defense_mod"):
			enemy_defense = int(float(enemy_defense) * (1.0 + float(effect_def["defense_mod"])))

	var damage_after_element := float(base_damage) * elemental_mult
	var after_defense := damage_after_element - (float(enemy_defense) * 0.25) - (damage_after_element * float(enemy_defense) / 600.0)
	after_defense = maxf(after_defense, 1.0)

	# Critical hit
	var crit_chance := CRITICAL_BASE_CHANCE
	var is_critical := randf() < crit_chance
	if is_critical:
		after_defense *= CRITICAL_MULTIPLIER

	# Check freeze damage taken multiplier
	for effect in enemy.get("status_effects", []):
		if effect.get("type", "") == "freeze":
			after_defense *= 1.5
			# Break freeze on hit
			effect["duration"] = 0

	# Variance ±10%
	var variance := 1.0 + randf_range(-DAMAGE_VARIANCE, DAMAGE_VARIANCE)
	var final_damage := int(after_defense * variance)
	final_damage = maxi(final_damage, 1)

	# Apply damage
	enemy["hp"] = maxi(int(enemy["hp"]) - final_damage, 0)

	var result: Dictionary = {
		"hit": true,
		"damage": final_damage,
		"critical": is_critical,
		"message": "",
	}

	if int(enemy["hp"]) <= 0:
		enemy["alive"] = false
		result["message"] = "%s defeated!" % str(enemy.get("name", "Enemy"))
		result["defeated"] = true
		result["exp"] = int(enemy.get("exp_reward", 0))
		result["meseta"] = int(enemy.get("meseta_reward", 0))
		enemy_defeated.emit(target_index, enemy)
		_check_wave_cleared()
	else:
		if is_critical:
			result["message"] = "Critical! %d damage to %s!" % [final_damage, str(enemy.get("name", "Enemy"))]
		else:
			result["message"] = "%d damage to %s!" % [final_damage, str(enemy.get("name", "Enemy"))]

	return result


## Special attack — lower accuracy, can apply status effects
func special_attack(target_index: int) -> Dictionary:
	if not _combat_active or target_index < 0 or target_index >= _enemies.size():
		return {"hit": false, "message": "Invalid target"}

	var result := attack(target_index)
	# Special attacks have -30% accuracy (already factored in the roll above effectively)
	# and 70% damage but can apply status
	if result.get("hit", false):
		result["damage"] = int(float(result.get("damage", 0)) * 0.7)
		# Re-apply the reduced damage
		var enemy: Dictionary = _enemies[target_index]
		enemy["hp"] = maxi(int(enemy.get("max_hp", 100)) - (int(enemy.get("max_hp", 100)) - int(enemy["hp"])) + int(float(result.get("damage", 0)) * 0.3), 0)

	return result


## Enemy attacks the player. Returns result dict.
func enemy_attack(enemy_index: int) -> Dictionary:
	if enemy_index < 0 or enemy_index >= _enemies.size():
		return {"hit": false, "damage": 0, "message": ""}

	var enemy: Dictionary = _enemies[enemy_index]
	if not enemy.get("alive", false):
		return {"hit": false, "damage": 0, "message": ""}

	# Check if enemy skips turn from status
	for effect in enemy.get("status_effects", []):
		var effect_def: Dictionary = STATUS_EFFECTS.get(effect.get("type", ""), {})
		var skip_chance: float = float(effect_def.get("skip_chance", 0.0))
		if skip_chance > 0.0 and randf() < skip_chance:
			return {"hit": false, "damage": 0, "message": "%s is %s!" % [str(enemy.get("name", "Enemy")), str(effect.get("type", "stunned"))]}

	var character = CharacterManager.get_active_character()
	if character == null:
		return {"hit": false, "damage": 0, "message": ""}

	var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	var level: int = int(character.get("level", 1))
	var stats: Dictionary = {}
	if class_data:
		stats = class_data.get_stats_at_level(level)

	var player_evasion: int = stats.get("evasion", 100)
	var player_defense: int = stats.get("defense", 50)

	# Add armor DEF from equipped frame
	var equipment: Dictionary = character.get("equipment", {})
	var frame_id: String = str(equipment.get("frame", ""))
	if not frame_id.is_empty():
		var armor = ArmorRegistry.get_armor(frame_id)
		if armor:
			player_defense += armor.defense_base
			player_evasion += armor.evasion_base

	var enemy_atk: int = int(enemy.get("attack", 15))

	# Hit check
	var hit_chance := clampf(BASE_HIT_CHANCE + (50 - player_evasion) * 0.003, MIN_HIT_CHANCE, MAX_HIT_CHANCE)
	if randf() > hit_chance:
		return {"hit": false, "damage": 0, "message": "%s attacks! Miss!" % str(enemy.get("name", "Enemy"))}

	# Damage calculation
	var raw_damage := float(enemy_atk)
	var after_defense := raw_damage - (float(player_defense) * 0.25) - (raw_damage * float(player_defense) / 600.0)
	after_defense = maxf(after_defense, 1.0)

	var variance := 1.0 + randf_range(-DAMAGE_VARIANCE, DAMAGE_VARIANCE)
	var final_damage := int(after_defense * variance)
	final_damage = maxi(final_damage, 1)

	# Apply to player
	character["hp"] = maxi(int(character["hp"]) - final_damage, 0)
	CharacterManager._sync_to_game_state()

	var result: Dictionary = {
		"hit": true,
		"damage": final_damage,
		"message": "%s attacks! %d damage!" % [str(enemy.get("name", "Enemy")), final_damage],
	}

	if int(character["hp"]) <= 0:
		result["player_defeated"] = true
		result["message"] += " You have been defeated!"

	return result


## Process status effect ticks for all enemies. Returns array of tick results.
func process_enemy_status_effects() -> Array:
	var results: Array = []
	for enemy in _enemies:
		if not enemy.get("alive", false):
			continue
		var new_effects: Array = []
		for effect in enemy.get("status_effects", []):
			var effect_type: String = effect.get("type", "")
			var effect_def: Dictionary = STATUS_EFFECTS.get(effect_type, {})

			# Apply DoT
			var dot: float = float(effect_def.get("dot_percent", 0.0))
			if dot > 0:
				var dot_damage := int(float(enemy.get("max_hp", 100)) * dot)
				enemy["hp"] = maxi(int(enemy["hp"]) - dot_damage, 0)
				results.append({
					"enemy": str(enemy.get("name", "Enemy")),
					"type": effect_type,
					"damage": dot_damage,
					"message": "%s takes %d %s damage!" % [str(enemy.get("name", "Enemy")), dot_damage, effect_type],
				})
				if int(enemy["hp"]) <= 0:
					enemy["alive"] = false

			# Reduce duration
			effect["duration"] = int(effect.get("duration", 0)) - 1
			if int(effect["duration"]) > 0:
				new_effects.append(effect)

		enemy["status_effects"] = new_effects

	return results


## Check if all enemies are defeated
func is_wave_cleared() -> bool:
	for enemy in _enemies:
		if enemy.get("alive", false):
			return false
	return not _enemies.is_empty()


## Get total exp/meseta from defeated enemies
func get_wave_rewards() -> Dictionary:
	var total_exp := 0
	var total_meseta := 0
	for enemy in _enemies:
		if not enemy.get("alive", false):
			total_exp += int(enemy.get("exp_reward", 0))
			total_meseta += int(enemy.get("meseta_reward", 0))
	return {"exp": total_exp, "meseta": total_meseta}


## Process aggro rolls for idle enemies. Returns array of newly aggroed enemy messages.
func process_aggro() -> Array:
	var messages: Array = []
	for i in range(_enemies.size()):
		var enemy: Dictionary = _enemies[i]
		if not enemy.get("alive", false):
			continue
		if enemy.get("aggroed", false):
			continue
		# Roll to notice the player
		var chance: float = float(enemy.get("aggro_chance", 0.15))
		if randf() < chance:
			enemy["aggroed"] = true
			messages.append("%s notices you!" % str(enemy.get("name", "Enemy")))
			enemy_aggroed.emit(i, enemy)
	return messages


## Force aggro on a specific enemy and nearby allies (called when player attacks)
func aggro_on_attack(target_index: int) -> void:
	if target_index < 0 or target_index >= _enemies.size():
		return
	# The attacked enemy always aggros
	_enemies[target_index]["aggroed"] = true
	# Nearby enemies (adjacent indices ±1) have a small chance to also aggro
	for offset in [-1, 1]:
		var idx: int = target_index + offset
		if idx >= 0 and idx < _enemies.size():
			var neighbor: Dictionary = _enemies[idx]
			if neighbor.get("alive", false) and not neighbor.get("aggroed", false):
				if randf() < 0.2:
					neighbor["aggroed"] = true


## Check if an enemy is aggroed (for UI display)
func is_enemy_aggroed(index: int) -> bool:
	if index < 0 or index >= _enemies.size():
		return false
	return _enemies[index].get("aggroed", false)


## Generate drops when an enemy is defeated
func generate_drops(enemy: Dictionary) -> Array:
	var drops: Array = []
	var enemy_name: String = str(enemy.get("name", ""))
	var is_boss: bool = enemy.get("is_boss", false)
	var is_rare: bool = enemy.get("is_rare", false)

	# 1. Consumable drops (10% chance, higher for bosses)
	var consumable_chance := 0.10
	if is_rare:
		consumable_chance = 0.20
	if is_boss:
		consumable_chance = 0.35
	if randf() < consumable_chance:
		var consumables := ["monomate", "monofluid"]
		drops.append(consumables[randi() % consumables.size()])

	# 2. Weapon drops from drop table
	var drop_area: String = AREA_DROP_NAMES.get(_area_id, _area_id)
	var weapon_drops: Array = DropRegistry.get_enemy_drops(_difficulty, drop_area, enemy_name)
	if not weapon_drops.is_empty():
		var weapon_chance := 0.03  # 3% for normal enemies
		if is_rare:
			weapon_chance = 0.12
		if is_boss:
			weapon_chance = 0.25
		if randf() < weapon_chance:
			var drop_name: String = weapon_drops[randi() % weapon_drops.size()]
			drops.append(drop_name.to_lower().replace(" ", "_").replace("'", ""))

	# 3. Technique disk drops
	var disk_chance := 0.05  # 5% for normal enemies
	if is_rare:
		disk_chance = 0.12
	if is_boss:
		disk_chance = 0.30
	if randf() < disk_chance:
		var disk: Dictionary = TechniqueManager.generate_random_disk(_difficulty, _area_id, is_boss, is_rare)
		if not disk.is_empty():
			drops.append("disk:" + str(disk.get("technique_id", "")) + ":" + str(disk.get("level", 1)))

	return drops


## Get all pending dropped items on the field
func get_dropped_items() -> Array:
	return _dropped_items


## Add drops to the field
func add_drops(items: Array) -> void:
	for item in items:
		_dropped_items.append(item)


## Pick up all dropped items. Returns array of {id, name, picked_up: bool}
func pickup_all() -> Array:
	var results: Array = []
	for item_id in _dropped_items:
		# Handle technique disk drops (format: "disk:technique_id:level")
		if str(item_id).begins_with("disk:"):
			var parts: PackedStringArray = str(item_id).split(":")
			if parts.size() >= 3:
				var technique_id: String = parts[1]
				var level: int = int(parts[2])
				var disk := TechniqueManager.create_disk(technique_id, level)
				var character = CharacterManager.get_active_character()
				if character:
					var disk_result := TechniqueManager.use_disk(character, disk)
					results.append({"id": item_id, "name": disk.get("name", "Disk"), "picked_up": true, "disk": true, "learned": disk_result["success"], "message": disk_result["message"]})
				else:
					results.append({"id": item_id, "name": disk.get("name", "Disk"), "picked_up": false, "disk": true})
			continue

		var info: Dictionary = Inventory._lookup_item(item_id)
		if Inventory.can_add_item(item_id):
			Inventory.add_item(item_id, 1)
			results.append({"id": item_id, "name": info.name, "picked_up": true})
		else:
			results.append({"id": item_id, "name": info.name, "picked_up": false})
	_dropped_items.clear()
	return results


## Clear combat state
func clear_combat() -> void:
	_enemies.clear()
	_dropped_items.clear()
	_combat_active = false
	combat_ended.emit()


func _check_wave_cleared() -> void:
	if is_wave_cleared():
		wave_cleared.emit()

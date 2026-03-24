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

## Material stat mapping
const MATERIAL_STAT_MAP := {
	"power_material":  "attack",
	"guard_material":  "defense",
	"hit_material":    "accuracy",
	"swift_material":  "evasion",
	"mind_material":   "technique",
	"hp_material":     "hp",
	"pp_material":     "pp",
	"reset_material":  "reset",
}

const MAX_MATERIALS := 100

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
	"sleep": {"duration": 2, "skip_chance": 1.0, "breaks_on_hit": true},
}

## Map photon element to status effect
const ELEMENT_TO_STATUS := {
	"fire": "burn",
	"ice": "freeze",
	"lightning": "stun",
	"dark": "devil",
	"light": "sleep",
}

## Map enemy element to attribute key
const ENEMY_ELEMENT_TO_ATTR := {
	"native": "native_pct",
	"beast": "beast_pct",
	"machine": "machine_pct",
	"dark": "dark_pct",
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

## Per-weapon-type combat parameters
## combo_steps: number of attacks in a combo chain
## hits_per_step: Array of hit counts per step (daggers hit multiple times)
## damage_mult: Array of damage multipliers per step (finishers hit harder)
## speed_mult: animation speed multiplier (1.0 = normal)
## hitbox_size: Vector3 size of the attack hitbox
## hitbox_offset: how far in front of player the hitbox is placed
## knockback: Array of knockback force per step
## combo_window: seconds to input next attack before combo resets
const WEAPON_TYPE_CONFIGS := {
	0: {  # SABER — reliable single hits, moderate speed
		"combo_steps": 3,
		"hits_per_step": [1, 1, 1],
		"damage_mult": [1.0, 1.0, 1.3],
		"speed_mult": 1.0,
		"hitbox_size": Vector3(1.5, 1.0, 2.0),
		"hitbox_offset": 1.5,
		"knockback": [3.0, 3.0, 6.0],
		"combo_window": 0.5,
	},
	1: {  # SWORD — slow heavy hits, big knockback
		"combo_steps": 3,
		"hits_per_step": [1, 1, 1],
		"damage_mult": [1.2, 1.2, 1.8],
		"speed_mult": 0.8,
		"hitbox_size": Vector3(2.0, 1.2, 2.5),
		"hitbox_offset": 1.8,
		"knockback": [5.0, 5.0, 10.0],
		"combo_window": 0.6,
	},
	2: {  # DAGGERS — fast multi-hit, lower per-hit damage
		"combo_steps": 3,
		"hits_per_step": [2, 2, 3],
		"damage_mult": [0.5, 0.5, 0.4],
		"speed_mult": 1.3,
		"hitbox_size": Vector3(1.2, 0.8, 1.5),
		"hitbox_offset": 1.2,
		"knockback": [1.0, 1.0, 2.0],
		"combo_window": 0.4,
	},
	3: {  # CLAW — very fast, close range
		"combo_steps": 3,
		"hits_per_step": [2, 2, 2],
		"damage_mult": [0.6, 0.6, 0.8],
		"speed_mult": 1.4,
		"hitbox_size": Vector3(1.0, 0.8, 1.2),
		"hitbox_offset": 1.0,
		"knockback": [1.5, 1.5, 3.0],
		"combo_window": 0.35,
	},
	4: {  # DOUBLE_SABER — wide sweeps, moderate speed
		"combo_steps": 3,
		"hits_per_step": [1, 2, 1],
		"damage_mult": [1.0, 0.6, 1.5],
		"speed_mult": 1.1,
		"hitbox_size": Vector3(2.0, 1.0, 2.0),
		"hitbox_offset": 1.5,
		"knockback": [3.0, 2.0, 8.0],
		"combo_window": 0.45,
	},
	5: {  # SPEAR — long reach, thrust attacks
		"combo_steps": 3,
		"hits_per_step": [1, 1, 1],
		"damage_mult": [1.0, 1.1, 1.4],
		"speed_mult": 0.9,
		"hitbox_size": Vector3(1.0, 0.8, 3.0),
		"hitbox_offset": 2.2,
		"knockback": [4.0, 4.0, 8.0],
		"combo_window": 0.5,
	},
	6: {  # SLICER — ranged melee, moderate speed
		"combo_steps": 3,
		"hits_per_step": [1, 1, 1],
		"damage_mult": [0.9, 0.9, 1.2],
		"speed_mult": 1.0,
		"hitbox_size": Vector3(1.5, 1.0, 2.5),
		"hitbox_offset": 2.0,
		"knockback": [2.0, 2.0, 4.0],
		"combo_window": 0.5,
	},
	9: {  # HANDGUN — single shots
		"combo_steps": 3,
		"hits_per_step": [1, 1, 1],
		"damage_mult": [0.8, 0.8, 1.0],
		"speed_mult": 1.2,
		"hitbox_size": Vector3(0.5, 0.5, 0.5),
		"hitbox_offset": 5.0,
		"knockback": [1.0, 1.0, 2.0],
		"combo_window": 0.4,
	},
	10: {  # MECH_GUN — rapid fire spray
		"combo_steps": 3,
		"hits_per_step": [3, 3, 4],
		"damage_mult": [0.3, 0.3, 0.25],
		"speed_mult": 1.5,
		"hitbox_size": Vector3(0.5, 0.5, 0.5),
		"hitbox_offset": 5.0,
		"knockback": [0.5, 0.5, 1.0],
		"combo_window": 0.3,
	},
	11: {  # RIFLE — slow precision shots
		"combo_steps": 3,
		"hits_per_step": [1, 1, 1],
		"damage_mult": [1.3, 1.3, 1.8],
		"speed_mult": 0.7,
		"hitbox_size": Vector3(0.5, 0.5, 0.5),
		"hitbox_offset": 8.0,
		"knockback": [5.0, 5.0, 8.0],
		"combo_window": 0.6,
	},
	12: {  # BAZOOKA/LAUNCHER — slow AoE explosions
		"combo_steps": 2,
		"hits_per_step": [1, 1],
		"damage_mult": [1.5, 2.0],
		"speed_mult": 0.6,
		"hitbox_size": Vector3(3.0, 2.0, 3.0),
		"hitbox_offset": 6.0,
		"knockback": [8.0, 12.0],
		"combo_window": 0.7,
	},
	14: {  # ROD — melee swing, tech amplifier
		"combo_steps": 3,
		"hits_per_step": [1, 1, 1],
		"damage_mult": [0.7, 0.7, 0.9],
		"speed_mult": 0.9,
		"hitbox_size": Vector3(1.5, 1.0, 2.0),
		"hitbox_offset": 1.5,
		"knockback": [2.0, 2.0, 4.0],
		"combo_window": 0.5,
	},
	15: {  # WAND — melee swing, support amplifier
		"combo_steps": 3,
		"hits_per_step": [1, 1, 1],
		"damage_mult": [0.6, 0.6, 0.8],
		"speed_mult": 0.9,
		"hitbox_size": Vector3(1.5, 1.0, 2.0),
		"hitbox_offset": 1.5,
		"knockback": [2.0, 2.0, 3.0],
		"combo_window": 0.5,
	},
}

## Innate weapon damage bonus
const INNATE_WEAPON_BONUS := 0.15

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


## Get player combat stats (base + equipment + materials + buffs + set bonuses)
func _get_player_stats(character: Dictionary) -> Dictionary:
	var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	var level: int = int(character.get("level", 1))
	var stats: Dictionary = {}
	if class_data:
		stats = class_data.get_stats_at_level(level)

	var player_attack: int = stats.get("attack", 50)
	var player_defense: int = stats.get("defense", 50)
	var player_accuracy: int = stats.get("accuracy", 100)
	var player_evasion: int = stats.get("evasion", 100)
	var player_technique: int = stats.get("technique", 0)

	# Add material bonuses
	var mat_bonuses: Dictionary = character.get("material_bonuses", {})
	player_attack += int(mat_bonuses.get("attack", 0))
	player_defense += int(mat_bonuses.get("defense", 0))
	player_accuracy += int(mat_bonuses.get("accuracy", 0))
	player_evasion += int(mat_bonuses.get("evasion", 0))
	player_technique += int(mat_bonuses.get("technique", 0))

	# Mag bonuses
	var mag_id: String = str(character.get("equipment", {}).get("mag", ""))
	if not mag_id.is_empty():
		var mag_state: Dictionary = MagManager.get_mag_state(character, mag_id)
		if not mag_state.is_empty():
			var mag_bonuses: Dictionary = MagManager.get_stat_bonuses(mag_state)
			player_attack += int(mag_bonuses.get("attack", 0))
			player_defense += int(mag_bonuses.get("defense", 0))
			player_accuracy += int(mag_bonuses.get("accuracy", 0))
			player_technique += int(mag_bonuses.get("technique", 0))

	# Equipment
	var equipment: Dictionary = character.get("equipment", {})
	var weapon_id: String = str(equipment.get("weapon", ""))
	var weapon_attack := 0
	var weapon_accuracy := 0
	var weapon_name := ""
	if not weapon_id.is_empty():
		var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(weapon_id))
		if weapon:
			var grind_level: int = int(character.get("weapon_grinds", {}).get(weapon_id, 0))
			weapon_attack = weapon.get_attack_at_grind(grind_level)
			weapon_accuracy = weapon.get_accuracy_at_grind(grind_level)
			weapon_name = weapon.name

	var frame_id: String = str(equipment.get("frame", ""))
	var armor_defense := 0
	var armor_evasion := 0
	var armor_name := ""
	if not frame_id.is_empty():
		var armor = ArmorRegistry.get_armor(frame_id)
		if armor:
			armor_defense = armor.defense_base
			armor_evasion = armor.evasion_base
			armor_name = armor.name

	# Set bonuses
	var set_bonus: Dictionary = {}
	if not armor_name.is_empty() and not weapon_name.is_empty():
		set_bonus = SetBonusRegistry.get_set_bonus_for_equipment(armor_name, weapon_name)
	player_attack += int(set_bonus.get("attack", 0))
	player_defense += int(set_bonus.get("defense", 0))
	player_accuracy += int(set_bonus.get("accuracy", 0))
	player_evasion += int(set_bonus.get("evasion", 0))
	player_technique += int(set_bonus.get("mental", 0))

	# Buff: shifta (ATK boost)
	var buffs: Dictionary = character.get("combat_buffs", {})
	if buffs.has("shifta"):
		var buff: Dictionary = buffs["shifta"]
		if int(buff.get("turns", 0)) > 0:
			player_attack = int(float(player_attack) * (1.0 + float(buff.get("amount", 0.1))))
	# Buff: deband (DEF boost)
	if buffs.has("deband"):
		var buff: Dictionary = buffs["deband"]
		if int(buff.get("turns", 0)) > 0:
			player_defense = int(float(player_defense) * (1.0 + float(buff.get("amount", 0.1))))

	return {
		"attack": player_attack,
		"defense": player_defense,
		"accuracy": player_accuracy,
		"evasion": player_evasion,
		"technique": player_technique,
		"weapon_attack": weapon_attack,
		"weapon_accuracy": weapon_accuracy,
		"armor_defense": armor_defense,
		"armor_evasion": armor_evasion,
		"set_bonus": set_bonus,
	}


## Calculate attack damage for the real-time combat system.
## Returns: {damage: int, hits: int, knockback: float, accuracy: int, is_innate: bool, weapon_type: int}
func calculate_attack_damage(combo_step: int = 1) -> Dictionary:
	var character = CharacterManager.get_active_character()
	if character == null:
		return {"damage": 10, "hits": 1, "knockback": 5.0, "accuracy": 100, "is_innate": false, "weapon_type": 0}

	var stats: Dictionary = _get_player_stats(character)
	var player_attack: int = int(stats.get("attack", 10))
	var weapon_attack: int = int(stats.get("weapon_attack", 0))
	var player_accuracy: int = int(stats.get("accuracy", 100))

	# Get weapon type
	var weapon_type: int = 0
	var weapon_id: String = str(character.get("equipment", {}).get("weapon", ""))
	if not weapon_id.is_empty():
		var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(weapon_id))
		if weapon:
			weapon_type = weapon.weapon_type

	# Get weapon config
	var config: Dictionary = get_weapon_type_config(weapon_type)
	var step_idx: int = clampi(combo_step - 1, 0, config.get("combo_steps", 3) - 1)
	var damage_mult_arr: Array = config.get("damage_mult", [1.0, 1.0, 1.3])
	var hits_arr: Array = config.get("hits_per_step", [1, 1, 1])
	var knockback_arr: Array = config.get("knockback", [5.0, 5.0, 5.0])

	var damage_mult: float = float(damage_mult_arr[step_idx]) if step_idx < damage_mult_arr.size() else 1.0
	var hits: int = int(hits_arr[step_idx]) if step_idx < hits_arr.size() else 1
	var knockback_val: float = float(knockback_arr[step_idx]) if step_idx < knockback_arr.size() else 5.0

	# Check innate weapon bonus
	var is_innate: bool = false
	var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	if class_data and class_data.innate_weapon_type == weapon_type:
		is_innate = true

	# Base damage per hit
	var base_damage: float = float(player_attack + weapon_attack) * damage_mult
	if is_innate:
		base_damage *= (1.0 + INNATE_WEAPON_BONUS)

	# Apply variance
	var variance: float = randf_range(1.0 - DAMAGE_VARIANCE, 1.0 + DAMAGE_VARIANCE)
	var final_damage: int = maxi(int(base_damage * variance), 1)

	return {
		"damage": final_damage,
		"hits": hits,
		"knockback": knockback_val,
		"accuracy": player_accuracy,
		"is_innate": is_innate,
		"weapon_type": weapon_type,
	}


## Apply damage to an enemy, accounting for defense and evasion.
## Returns: {hit: bool, damage: int, is_critical: bool}
func apply_damage_to_enemy(raw_damage: int, enemy_defense: int, enemy_evasion: int, player_accuracy: int) -> Dictionary:
	# Hit/miss check
	var acc_ratio: float = float(player_accuracy) / maxf(float(enemy_evasion), 1.0)
	var hit_chance: float = clampf(BASE_HIT_CHANCE * acc_ratio, MIN_HIT_CHANCE, MAX_HIT_CHANCE)
	if randf() > hit_chance:
		return {"hit": false, "damage": 0, "is_critical": false}

	# Defense reduction (PSO-style)
	var def_reduction: float = float(enemy_defense) * 0.25 + float(raw_damage) * float(enemy_defense) / 600.0
	var after_def: float = maxf(float(raw_damage) - def_reduction, 1.0)

	# Critical hit check
	var is_critical: bool = randf() < CRITICAL_BASE_CHANCE
	if is_critical:
		after_def *= CRITICAL_MULTIPLIER

	return {"hit": true, "damage": maxi(int(after_def), 1), "is_critical": is_critical}


## Use a material item on the active character. Returns result dict.
func use_material(material_id: String) -> Dictionary:
	var character = CharacterManager.get_active_character()
	if character == null:
		return {"success": false, "message": "No active character"}

	if not MATERIAL_STAT_MAP.has(material_id):
		return {"success": false, "message": "Not a material"}

	var stat: String = MATERIAL_STAT_MAP[material_id]

	# Reset material — clears all bonuses
	if stat == "reset":
		character["material_bonuses"] = {}
		character["materials_used"] = 0
		Inventory.remove_item(material_id, 1)
		return {"success": true, "message": "All material bonuses reset!"}

	# Check cap
	var used: int = int(character.get("materials_used", 0))
	if used >= MAX_MATERIALS:
		return {"success": false, "message": "Material cap reached (%d/%d)" % [used, MAX_MATERIALS]}

	# Apply bonus
	if not character.has("material_bonuses"):
		character["material_bonuses"] = {}
	var bonuses: Dictionary = character["material_bonuses"]
	bonuses[stat] = int(bonuses.get(stat, 0)) + 2
	character["materials_used"] = used + 1

	# For HP/PP materials, also increase max_hp/max_pp
	if stat == "hp":
		character["max_hp"] = int(character.get("max_hp", 100)) + 2
		character["hp"] = mini(int(character.get("hp", 100)) + 2, int(character["max_hp"]))
	elif stat == "pp":
		character["max_pp"] = int(character.get("max_pp", 50)) + 2
		character["pp"] = mini(int(character.get("pp", 50)) + 2, int(character["max_pp"]))

	Inventory.remove_item(material_id, 1)
	CharacterManager._sync_to_game_state()

	var mat_name: String = material_id.replace("_", " ").capitalize()
	return {"success": true, "message": "Used %s! %s +2 (%d/%d materials)" % [mat_name, stat.capitalize(), used + 1, MAX_MATERIALS]}


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

	var pstats: Dictionary = _get_player_stats(character)
	var player_attack: int = pstats["attack"]
	var player_accuracy: int = pstats["accuracy"]
	var weapon_attack: int = pstats["weapon_attack"]
	var enemy_evasion: int = int(enemy.get("evasion", 50))

	# Calculate hit chance
	var net_accuracy := player_accuracy - enemy_evasion
	var hit_chance := clampf(BASE_HIT_CHANCE + net_accuracy * 0.005, MIN_HIT_CHANCE, MAX_HIT_CHANCE)

	# Add weapon hit% attribute to accuracy
	var equip: Dictionary = character.get("equipment", {})
	var wpn_id: String = str(equip.get("weapon", ""))
	var wpn_stats: Dictionary = character.get("weapon_stats", {}).get(wpn_id, {})
	var hit_bonus: int = int(wpn_stats.get("hit_pct", 0))
	if hit_bonus > 0:
		net_accuracy += hit_bonus
		hit_chance = clampf(BASE_HIT_CHANCE + net_accuracy * 0.005, MIN_HIT_CHANCE, MAX_HIT_CHANCE)

	# Apply evasion modifier from status effects
	for effect in enemy.get("status_effects", []):
		var effect_def: Dictionary = STATUS_EFFECTS.get(effect.get("type", ""), {})
		if effect_def.has("evasion_mod"):
			hit_chance += float(effect_def["evasion_mod"]) * -0.5

	if randf() > hit_chance:
		return {"hit": false, "damage": 0, "critical": false, "message": "Miss!"}

	# Calculate damage
	var base_damage := player_attack + weapon_attack

	# Element multiplier from weapon attributes
	var elemental_mult := 1.0
	var equipment: Dictionary = character.get("equipment", {})
	var weapon_id: String = str(equipment.get("weapon", ""))
	var w_stats: Dictionary = character.get("weapon_stats", {}).get(weapon_id, {})
	var enemy_element: String = str(enemy.get("element", "native"))
	var attr_key: String = ENEMY_ELEMENT_TO_ATTR.get(enemy_element, "")
	if not attr_key.is_empty() and w_stats.has(attr_key):
		elemental_mult = 1.0 + float(w_stats[attr_key]) / 100.0

	# Apply defense: damage - (def * 0.25) - (damage * def / 600)
	var enemy_defense: int = _get_enemy_defense(enemy)

	var damage_after_element := float(base_damage) * elemental_mult
	var after_defense := damage_after_element - (float(enemy_defense) * 0.25) - (damage_after_element * float(enemy_defense) / 600.0)
	after_defense = maxf(after_defense, 1.0)

	# Critical hit
	var crit_chance := CRITICAL_BASE_CHANCE
	var is_critical := randf() < crit_chance
	if is_critical:
		after_defense *= CRITICAL_MULTIPLIER

	# Check freeze damage taken multiplier and break-on-hit statuses
	for effect in enemy.get("status_effects", []):
		if effect.get("type", "") == "freeze":
			after_defense *= 1.5
			# Break freeze on hit
			effect["duration"] = 0
		elif effect.get("type", "") == "sleep":
			# Break sleep on hit
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

	# Try element special attack
	if result.get("hit", false) and not result.get("defeated", false):
		var special_msg: String = _try_element_special(enemy, w_stats)
		if not special_msg.is_empty():
			result["message"] += special_msg
			result["element_triggered"] = true
			# Check if devil killed the enemy
			if int(enemy.get("hp", 0)) <= 0:
				enemy["alive"] = false
				result["defeated"] = true
				result["exp"] = int(enemy.get("exp_reward", 0))
				result["meseta"] = int(enemy.get("meseta_reward", 0))
				enemy_defeated.emit(target_index, enemy)
				_check_wave_cleared()

	return result


## Try to trigger an element special attack after a successful hit.
## Returns a status message if triggered, empty string otherwise.
func _try_element_special(enemy: Dictionary, w_stats: Dictionary) -> String:
	var element: String = str(w_stats.get("element", ""))
	if element.is_empty():
		return ""

	var element_level: int = int(w_stats.get("element_level", 0))
	if element_level <= 0:
		return ""

	# Trigger chance: 10% + 10% per element level
	var trigger_chance := 0.10 + 0.10 * float(element_level)
	if randf() > trigger_chance:
		return ""

	var status_type: String = ELEMENT_TO_STATUS.get(element, "")
	if status_type.is_empty():
		return ""

	var enemy_name: String = str(enemy.get("name", "Enemy"))

	# Devil is special — instant 3/4 HP reduction
	if status_type == "devil":
		var current_hp: int = int(enemy.get("hp", 0))
		var new_hp: int = maxi(current_hp / 4, 1)
		var devil_damage: int = current_hp - new_hp
		enemy["hp"] = new_hp
		if int(enemy["hp"]) <= 0:
			enemy["alive"] = false
		return " Devil! %s loses %d HP!" % [enemy_name, devil_damage]

	# Apply status effect
	if not enemy.has("status_effects"):
		enemy["status_effects"] = []

	# Don't stack same status
	for existing in enemy["status_effects"]:
		if existing.get("type", "") == status_type:
			return ""

	var effect_def: Dictionary = STATUS_EFFECTS.get(status_type, {})
	var duration: int = int(effect_def.get("duration", 2))
	enemy["status_effects"].append({"type": status_type, "duration": duration})

	var element_names := {"fire": "Burn", "ice": "Freeze", "lightning": "Stun", "light": "Sleep"}
	var effect_name: String = element_names.get(element, element.capitalize())
	return " %s inflicted on %s!" % [effect_name, enemy_name]


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


## Cast a technique in combat. Returns result dict.
func cast_technique(technique_id: String, target_index: int) -> Dictionary:
	if not _combat_active:
		return {"hit": false, "message": "Not in combat"}

	var character = CharacterManager.get_active_character()
	if character == null:
		return {"hit": false, "message": "No active character"}

	var tech: Dictionary = TechniqueManager.get_technique(technique_id)
	if tech.is_empty():
		return {"hit": false, "message": "Unknown technique"}

	var level: int = TechniqueManager.get_technique_level(character, technique_id)
	if level <= 0:
		return {"hit": false, "message": "Technique not learned"}

	# PP cost
	var pp_cost: int = maxi(1, int(tech["pp"]) - int(float(level) / 5.0))
	var current_pp: int = int(character.get("pp", 0))
	if current_pp < pp_cost:
		return {"hit": false, "message": "Not enough PP (%d/%d)" % [current_pp, pp_cost]}

	# Deduct PP
	character["pp"] = current_pp - pp_cost
	CharacterManager._sync_to_game_state()

	var pstats: Dictionary = _get_player_stats(character)
	var tech_stat: int = pstats["technique"]
	var tech_name: String = str(tech.get("name", technique_id))
	var power: float = float(tech.get("power", 0))
	var target_type: String = str(tech.get("target", "single"))
	var element: String = str(tech.get("element", "none"))

	# Support techniques
	match technique_id:
		"resta":
			var heal_amount := int(power * (1.0 + float(level) / 10.0))
			character["hp"] = mini(int(character.get("hp", 0)) + heal_amount, int(character.get("max_hp", 100)))
			CharacterManager._sync_to_game_state()
			return {"hit": true, "damage": 0, "message": "Cast %s! Restored %d HP. (-%d PP)" % [tech_name, heal_amount, pp_cost], "heal": heal_amount}
		"anti":
			# In single-player, just clear any future debuff mechanic
			return {"hit": true, "damage": 0, "message": "Cast %s! Status effects cleared. (-%d PP)" % [tech_name, pp_cost]}
		"reverser":
			var heal_amount := int(power * 0.5 + float(level) * 2.0)
			heal_amount = maxi(heal_amount, 10)
			character["hp"] = mini(int(character.get("hp", 0)) + heal_amount, int(character.get("max_hp", 100)))
			CharacterManager._sync_to_game_state()
			return {"hit": true, "damage": 0, "message": "Cast %s! Restored %d HP. (-%d PP)" % [tech_name, heal_amount, pp_cost], "heal": heal_amount}
		"shifta":
			var amount := 0.1 * float(level)
			var turns := 3 + level
			if not character.has("combat_buffs"):
				character["combat_buffs"] = {}
			character["combat_buffs"]["shifta"] = {"turns": turns, "amount": amount}
			return {"hit": true, "damage": 0, "message": "Cast %s Lv.%d! ATK +%d%% for %d turns. (-%d PP)" % [tech_name, level, int(amount * 100), turns, pp_cost]}
		"deband":
			var amount := 0.1 * float(level)
			var turns := 3 + level
			if not character.has("combat_buffs"):
				character["combat_buffs"] = {}
			character["combat_buffs"]["deband"] = {"turns": turns, "amount": amount}
			return {"hit": true, "damage": 0, "message": "Cast %s Lv.%d! DEF +%d%% for %d turns. (-%d PP)" % [tech_name, level, int(amount * 100), turns, pp_cost]}
		"jellen":
			# Debuff all enemies ATK by 10% for 3 turns
			for enemy in _enemies:
				if enemy.get("alive", false):
					if not enemy.has("status_effects"):
						enemy["status_effects"] = []
					enemy["status_effects"].append({"type": "jellen", "duration": 3, "atk_mod": -0.1})
			return {"hit": true, "damage": 0, "message": "Cast %s! All enemies ATK reduced. (-%d PP)" % [tech_name, pp_cost]}
		"zalure":
			# Debuff all enemies DEF by 10% for 3 turns
			for enemy in _enemies:
				if enemy.get("alive", false):
					if not enemy.has("status_effects"):
						enemy["status_effects"] = []
					enemy["status_effects"].append({"type": "zalure", "duration": 3, "def_mod": -0.1})
			return {"hit": true, "damage": 0, "message": "Cast %s! All enemies DEF reduced. (-%d PP)" % [tech_name, pp_cost]}
		"megid":
			# Instant death chance
			if target_index < 0 or target_index >= _enemies.size():
				return {"hit": false, "message": "Invalid target"}
			var enemy: Dictionary = _enemies[target_index]
			if not enemy.get("alive", false):
				return {"hit": false, "message": "Target already defeated"}
			var death_chance := 0.20 + float(level) * 0.01
			if randf() < death_chance:
				enemy["hp"] = 0
				enemy["alive"] = false
				enemy_defeated.emit(target_index, enemy)
				_check_wave_cleared()
				return {"hit": true, "damage": 0, "message": "Cast %s! %s was consumed by darkness! (-%d PP)" % [tech_name, str(enemy.get("name", "Enemy")), pp_cost], "defeated": true, "exp": int(enemy.get("exp_reward", 0)), "meseta": int(enemy.get("meseta_reward", 0))}
			else:
				return {"hit": true, "damage": 0, "message": "Cast %s on %s... but it missed! (-%d PP)" % [tech_name, str(enemy.get("name", "Enemy")), pp_cost]}

	# Attack techniques — deal damage
	var base := power * (1.0 + float(level) / 10.0)
	var scaled := base * (float(tech_stat) / 100.0)

	var results: Array = []
	var targets: Array = []

	if target_type == "area":
		for i in range(_enemies.size()):
			if _enemies[i].get("alive", false):
				targets.append(i)
	else:
		if target_index >= 0 and target_index < _enemies.size() and _enemies[target_index].get("alive", false):
			targets.append(target_index)

	if targets.is_empty():
		return {"hit": false, "message": "No valid targets"}

	var total_damage := 0
	var any_defeated := false
	var messages: Array = []
	for idx in targets:
		var enemy: Dictionary = _enemies[idx]
		var enemy_def: int = _get_enemy_defense(enemy)
		var after_def := scaled - (float(enemy_def) * 0.15) - (scaled * float(enemy_def) / 800.0)
		var variance := 1.0 + randf_range(-DAMAGE_VARIANCE, DAMAGE_VARIANCE)
		var dmg := maxi(1, int(after_def * variance))
		enemy["hp"] = maxi(int(enemy["hp"]) - dmg, 0)
		total_damage += dmg
		if int(enemy["hp"]) <= 0:
			enemy["alive"] = false
			any_defeated = true
			messages.append("%s takes %d damage — defeated!" % [str(enemy.get("name", "Enemy")), dmg])
			enemy_defeated.emit(idx, enemy)
		else:
			messages.append("%s takes %d damage!" % [str(enemy.get("name", "Enemy")), dmg])

	if any_defeated:
		_check_wave_cleared()

	var msg := "Cast %s Lv.%d! (-%d PP) " % [tech_name, level, pp_cost] + " ".join(PackedStringArray(messages))
	return {"hit": true, "damage": total_damage, "message": msg, "area": target_type == "area"}


## Use a photon art in combat. Returns result dict.
func use_photon_art(art_id: String, target_index: int) -> Dictionary:
	if not _combat_active:
		return {"hit": false, "message": "Not in combat"}

	var character = CharacterManager.get_active_character()
	if character == null:
		return {"hit": false, "message": "No active character"}

	var art = PhotonArtRegistry.get_art(art_id)
	if art == null:
		return {"hit": false, "message": "Unknown photon art"}

	# Check weapon type match
	var equipment: Dictionary = character.get("equipment", {})
	var weapon_id: String = str(equipment.get("weapon", ""))
	if weapon_id.is_empty():
		return {"hit": false, "message": "No weapon equipped"}
	var weapon = WeaponRegistry.get_weapon(Inventory.get_base_id(weapon_id))
	if weapon == null:
		return {"hit": false, "message": "Unknown weapon"}
	if weapon.get_weapon_type_name() != art.weapon_type:
		return {"hit": false, "message": "%s requires a %s" % [art.name, art.weapon_type]}

	# Check class type match
	var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	if class_data and art.class_type != "" and class_data.type != art.class_type:
		return {"hit": false, "message": "%s cannot use %s" % [class_data.name, art.name]}

	# PP cost
	var pp_cost: int = art.pp_cost
	var current_pp: int = int(character.get("pp", 0))
	if current_pp < pp_cost:
		return {"hit": false, "message": "Not enough PP (%d/%d)" % [current_pp, pp_cost]}

	if target_index < 0 or target_index >= _enemies.size():
		return {"hit": false, "message": "Invalid target"}
	var enemy: Dictionary = _enemies[target_index]
	if not enemy.get("alive", false):
		return {"hit": false, "message": "Target already defeated"}

	# Deduct PP
	character["pp"] = current_pp - pp_cost
	CharacterManager._sync_to_game_state()

	var pstats: Dictionary = _get_player_stats(character)
	var player_atk: int = pstats["attack"]
	var weapon_atk: int = pstats["weapon_attack"]
	var player_acc: int = pstats["accuracy"]
	var enemy_eva: int = int(enemy.get("evasion", 50))

	var hits: int = maxi(art.hits, 1)
	var per_hit_damage: float = float(player_atk + weapon_atk) * (float(art.attack_mod) / 100.0) / float(hits)
	var hit_chance: float = clampf(0.7 + (float(player_acc) * float(art.accuracy_mod) / 100.0 - float(enemy_eva)) * 0.005, 0.3, 0.95)

	var total_damage := 0
	var hits_landed := 0
	var hit_messages: Array = []

	for i in range(hits):
		if randf() < hit_chance:
			var enemy_def: int = _get_enemy_defense(enemy)
			var after_def: float = per_hit_damage - (float(enemy_def) * 0.25) - (per_hit_damage * float(enemy_def) / 600.0)
			after_def = maxf(after_def, 1.0)
			var variance := 1.0 + randf_range(-DAMAGE_VARIANCE, DAMAGE_VARIANCE)
			var dmg := maxi(1, int(after_def * variance))
			enemy["hp"] = maxi(int(enemy["hp"]) - dmg, 0)
			total_damage += dmg
			hits_landed += 1
			hit_messages.append("Hit %d: %d" % [i + 1, dmg])
			if int(enemy["hp"]) <= 0:
				enemy["alive"] = false
				break
		else:
			hit_messages.append("Hit %d: Miss" % [i + 1])

	var result: Dictionary = {
		"hit": hits_landed > 0,
		"damage": total_damage,
		"hits": hits_landed,
		"total_hits": hits,
		"message": "",
	}

	if int(enemy["hp"]) <= 0:
		enemy["alive"] = false
		result["defeated"] = true
		result["exp"] = int(enemy.get("exp_reward", 0))
		result["meseta"] = int(enemy.get("meseta_reward", 0))
		enemy_defeated.emit(target_index, enemy)
		_check_wave_cleared()
		result["message"] = "%s! %d/%d hits, %d total damage — %s defeated! (-%d PP)" % [art.name, hits_landed, hits, total_damage, str(enemy.get("name", "Enemy")), pp_cost]
	else:
		result["message"] = "%s! %d/%d hits, %d total damage to %s. (-%d PP)" % [art.name, hits_landed, hits, total_damage, str(enemy.get("name", "Enemy")), pp_cost]

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

	var pstats: Dictionary = _get_player_stats(character)
	var player_evasion: int = pstats["evasion"] + pstats["armor_evasion"]
	var player_defense: int = pstats["defense"] + pstats["armor_defense"]

	var enemy_atk: int = int(enemy.get("attack", 15))
	# Check jellen debuff
	for effect in enemy.get("status_effects", []):
		if effect.get("type", "") == "jellen":
			enemy_atk = int(float(enemy_atk) * (1.0 + float(effect.get("atk_mod", 0))))

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


## Get enemy defense accounting for status effects (zalure, burn)
func _get_enemy_defense(enemy: Dictionary) -> int:
	var enemy_defense: int = int(enemy.get("defense", 0))
	for effect in enemy.get("status_effects", []):
		var effect_type: String = str(effect.get("type", ""))
		if effect_type == "zalure":
			enemy_defense = int(float(enemy_defense) * (1.0 + float(effect.get("def_mod", 0))))
		else:
			var effect_def: Dictionary = STATUS_EFFECTS.get(effect_type, {})
			if effect_def.has("defense_mod"):
				enemy_defense = int(float(enemy_defense) * (1.0 + float(effect_def["defense_mod"])))
	return enemy_defense


## Process player buff ticks. Call at end of each turn.
func process_player_buffs() -> Array:
	var character = CharacterManager.get_active_character()
	if character == null:
		return []

	var messages: Array = []
	var buffs: Dictionary = character.get("combat_buffs", {})
	var expired: Array = []

	for buff_name in buffs:
		var buff: Dictionary = buffs[buff_name]
		buff["turns"] = int(buff.get("turns", 0)) - 1
		if int(buff["turns"]) <= 0:
			expired.append(buff_name)
			messages.append("%s wore off." % buff_name.capitalize())

	for name in expired:
		buffs.erase(name)

	return messages


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
			var weapon_id: String = drop_name.to_lower().replace(" ", "_").replace("'", "").replace("-", "_").replace("/", "_")
			# Check if high-rarity weapon should be unidentified
			var weapon = WeaponRegistry.get_weapon(weapon_id)
			if weapon and weapon.rarity >= 5:
				drops.append("unid:" + weapon_id)
			else:
				drops.append(weapon_id)

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

	# 4. Photon Drop drops
	var pd_chance := 0.05
	if is_rare:
		pd_chance = 0.15
	if is_boss:
		pd_chance = 0.30
	if randf() < pd_chance:
		drops.append("photon_drop")

	# 5. Grinder drops
	if is_boss:
		if randf() < 0.30:
			drops.append("monogrinder")
		if randf() < 0.15:
			drops.append("digrinder")
		if randf() < 0.05:
			drops.append("trigrinder")
	elif is_rare:
		if randf() < 0.15:
			drops.append("monogrinder")
		if randf() < 0.05:
			drops.append("digrinder")
	else:
		if randf() < 0.05:
			drops.append("monogrinder")

	# 6. Material drops (boss only)
	if is_boss and randf() < 0.10:
		var material_ids: Array = ["power_material", "guard_material", "hit_material", "swift_material", "mind_material", "hp_material", "pp_material"]
		drops.append(material_ids[randi() % material_ids.size()])

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

		# Handle unidentified weapon drops (format: "unid:weapon_id")
		if str(item_id).begins_with("unid:"):
			var weapon_id: String = str(item_id).substr(5)
			var character = CharacterManager.get_active_character()
			if character:
				if not character.has("unidentified_weapons"):
					character["unidentified_weapons"] = []
				character["unidentified_weapons"].append(weapon_id)
				results.append({"id": item_id, "name": "??? (unidentified weapon)", "picked_up": true, "unidentified": true})
			else:
				results.append({"id": item_id, "name": "??? (unidentified weapon)", "picked_up": false, "unidentified": true})
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
	# Clear combat buffs
	var character = CharacterManager.get_active_character()
	if character:
		character["combat_buffs"] = {}
	combat_ended.emit()


func _check_wave_cleared() -> void:
	if is_wave_cleared():
		wave_cleared.emit()


## Get weapon type config, falling back to saber defaults
func get_weapon_type_config(weapon_type: int) -> Dictionary:
	return WEAPON_TYPE_CONFIGS.get(weapon_type, WEAPON_TYPE_CONFIGS[0])

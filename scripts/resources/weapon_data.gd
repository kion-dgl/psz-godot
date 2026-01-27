class_name WeaponData extends Resource
## Resource definition for weapons, matching psz-sketch weapon schema

enum WeaponType {
	SABER,
	SWORD,
	DAGGERS,
	CLAW,
	DOUBLE_SABER,
	SPEAR,
	SLICER,
	GUN_BLADE,
	SHIELD,
	HANDGUN,
	MECH_GUN,
	RIFLE,
	BAZOOKA,
	LASER_CANNON,
	ROD,
	WAND,
}

## Unique identifier (derived from filename)
@export var id: String = ""

## Display name
@export var name: String = ""

## Japanese name
@export var japanese_name: String = ""

## Rarity (1-7 stars)
@export_range(1, 7) var rarity: int = 1

## Weapon category
@export var weapon_type: WeaponType = WeaponType.SABER

## Maximum grind level
@export var max_grind: int = 0

## Required level to equip
@export var level: int = 1

## Shop resale value in meseta
@export var resale_value: int = 0

## Base attack power (null for tech weapons)
@export var attack_base: int = 0

## Max attack power at max grind
@export var attack_max: int = 0

## Base accuracy
@export var accuracy_base: int = 0

## Max accuracy
@export var accuracy_max: int = 0

## Element type (empty if none)
@export var element: String = ""

## Element level
@export var element_level: int = 0

## Photon Arts available on this weapon
@export var photon_arts: Array[Dictionary] = []

## Classes that can use this weapon
@export var usable_by: PackedStringArray = []

## PSO World reference ID
@export var pso_world_id: int = 0

## 3D model ID for loading
@export var model_id: String = ""

## Variant ID for texture/color
@export var variant_id: String = ""

## Icon texture
@export var icon: Texture2D


## Get weapon type as string
func get_weapon_type_name() -> String:
	match weapon_type:
		WeaponType.SABER: return "Saber"
		WeaponType.SWORD: return "Sword"
		WeaponType.DAGGERS: return "Daggers"
		WeaponType.CLAW: return "Claw"
		WeaponType.DOUBLE_SABER: return "Double Saber"
		WeaponType.SPEAR: return "Spear"
		WeaponType.SLICER: return "Slicer"
		WeaponType.GUN_BLADE: return "Gun Blade"
		WeaponType.SHIELD: return "Shield"
		WeaponType.HANDGUN: return "Handgun"
		WeaponType.MECH_GUN: return "Mech Gun"
		WeaponType.RIFLE: return "Rifle"
		WeaponType.BAZOOKA: return "Bazooka"
		WeaponType.LASER_CANNON: return "Laser Cannon"
		WeaponType.ROD: return "Rod"
		WeaponType.WAND: return "Wand"
	return "Unknown"


## Get attack at specific grind level
func get_attack_at_grind(grind: int) -> int:
	if max_grind <= 0:
		return attack_base
	var t = clampf(float(grind) / float(max_grind), 0.0, 1.0)
	return int(lerpf(attack_base, attack_max, t))


## Get accuracy at specific grind level
func get_accuracy_at_grind(grind: int) -> int:
	if max_grind <= 0:
		return accuracy_base
	var t = clampf(float(grind) / float(max_grind), 0.0, 1.0)
	return int(lerpf(accuracy_base, accuracy_max, t))


## Check if a class can use this weapon
func can_be_used_by(class_name_str: String) -> bool:
	if usable_by.is_empty():
		return true  # No restrictions
	return class_name_str in usable_by


## Get rarity as star string
func get_rarity_string() -> String:
	var stars = ""
	for i in range(rarity):
		stars += "★"
	return stars


## Is this a ranged weapon?
func is_ranged() -> bool:
	return weapon_type in [
		WeaponType.HANDGUN,
		WeaponType.MECH_GUN,
		WeaponType.RIFLE,
		WeaponType.BAZOOKA,
		WeaponType.LASER_CANNON,
	]


## Is this a tech weapon?
func is_tech_weapon() -> bool:
	return weapon_type in [WeaponType.ROD, WeaponType.WAND]

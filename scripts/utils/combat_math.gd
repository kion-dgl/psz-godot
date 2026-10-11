extends RefCounted
## PSZ ARM9 02042A4C and 02042964. See /states/combat-progression.
## Modifiers outside this recovered core remain explicit remake tuning.

static func damage(attack: int, defense: int, critical: bool = false, resistance: int = 0) -> int:
	var value := maxi(int(float(attack - defense) / 5.0), 0)
	value = int(float(value) * float(100 - clampi(resistance, 0, 100)) / 100.0)
	if critical:
		value += int(float(value) / 2.0)
	return value

static func hit_percent(accuracy: int, evasion: int, multiplier_q12: int = 4096) -> int:
	var base := int(float(accuracy * 4) / 10.0) - ((evasion * 0x333 + 0x800) >> 12)
	return (base * multiplier_q12 + 0x800) >> 12

static func attribute_attack(base: int, weapon: int, attributes: Dictionary, family: int) -> int:
	var keys := ["native_pct", "beast_pct", "machine_pct", "dark_pct"]
	var percent := clampi(int(attributes.get(keys[clampi(family, 0, 3)], 0)), -100, 100)
	return base + int(float(weapon) * (1.0 + float(percent) / 100.0))

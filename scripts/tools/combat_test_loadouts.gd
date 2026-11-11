extends RefCounted
const PRESETS := [
	["ramar", "handgun"], ["ramarl", "rifle"], ["racast", "mechgun"],
	["humar", "saber"], ["humarl", "sword"], ["hunewearl", "dagger"],
	["fomar", "rod"], ["fomarl", "wand"],
]

static func configure() -> void:
	var id := OS.get_environment("PSZ_AIM_CLASS")
	if id.is_empty(): id = "ramarl" if OS.get_environment("PSZ_AIM_FEMALE") == "1" else "ramar"
	CharacterManager.create_character(0, id, "Combat Test")
	var character: Dictionary = CharacterManager._characters[0]
	character.equipment.weapon = OS.get_environment("PSZ_AIM_WEAPON")
	if id.begins_with("fo"):
		character.techniques = {"foie": 1, "barta": 1, "resta": 1}
		character.action_palette = [["foie", "barta", "resta"], ["attack", "strong_attack", "monofluid"]]

static func next() -> void:
	var current: Dictionary = CharacterManager.get_active_character()
	var index := 0
	for i in range(PRESETS.size()):
		if PRESETS[i] == [current.class_id, current.equipment.weapon]: index = (i + 1) % PRESETS.size(); break
	OS.set_environment("PSZ_AIM_CLASS", PRESETS[index][0])
	OS.set_environment("PSZ_AIM_WEAPON", PRESETS[index][1])

static func label() -> String:
	var character: Dictionary = CharacterManager.get_active_character()
	return "%s / %s" % [str(character.class_id).to_upper(), str(character.equipment.weapon).capitalize()]

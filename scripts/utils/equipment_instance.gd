extends RefCounted
## Bank entries carry mutable instance properties when changing characters.
const FIELDS := ["weapon_grinds", "weapon_stats", "weapon_elements", "armor_slots", "mag_states", "equipment_tokens"]

static func capture(ch: Dictionary, id: String) -> Dictionary:
	identity(ch, id)
	var properties := {}
	for field in FIELDS:
		if ch.get(field, {}).has(id): properties[field] = ch[field][id]
	return properties.duplicate(true)

static func restore(ch: Dictionary, id: String, properties: Dictionary) -> void:
	for field in FIELDS:
		if not ch.has(field): ch[field] = {}
		ch[field].erase(id)
		if properties.has(field): ch[field][id] = properties[field]

static func identity(ch: Dictionary, id: String) -> String:
	if not ch.has("equipment_tokens"): ch.equipment_tokens = {}
	if not ch.equipment_tokens.has(id):
		ch.equipment_tokens[id] = Crypto.new().generate_random_bytes(16).hex_encode()
	return str(ch.equipment_tokens[id])

static func acquired(id: String) -> void:
	var ch = CharacterManager.get_active_character()
	if ch == null: return
	restore(ch, id, {})
	identity(ch, id)

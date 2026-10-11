extends Node
## Single-player PB lifecycle. Original gauge data; provisional blast presentation.
const MAX_GAUGE := 10000
const ChargeData = preload("res://data/re_reference/photon_blast_charge.json")
var gauge: int = 0
var flozir_left: float = 0.0
var _mag_key := ""
var _presentation: Node

func _ready() -> void:
	CharacterManager.active_character_changed.connect(func(_slot: int): reset())
	SessionManager.session_started.connect(func(_data: Dictionary): reset())
	SessionManager.session_ended.connect(reset)

func _process(delta: float) -> void:
	flozir_left = maxf(0.0, flozir_left - delta)
	var ch = CharacterManager.get_active_character()
	var key := "" if ch == null else str(ch.get("equipment", {}).get("mag", ""))
	if key != _mag_key:
		reset()
		_mag_key = key

func reset() -> void:
	gauge = 0
	flozir_left = 0.0
	if is_instance_valid(_presentation):
		_presentation.cancel()
	_presentation = null

func equipped_blast() -> String:
	var ch = CharacterManager.get_active_character()
	if ch == null:
		return ""
	var id: String = str(ch.get("equipment", {}).get("mag", ""))
	if id.is_empty():
		return ""
	var state := MagManager.get_mag_state(ch, id)
	var form = MagManager.get_mag_form(str(state.get("form_id", "mag")))
	if form == null or MagManager.get_level(state) < 10:
		return ""
	var blast: String = form.photon_blast
	if blast == "inherited":
		blast = str(state.get("inherited_blast", ""))
	return blast if blast in ["Granir", "Pacifal", "Midgul", "Flozir"] else ""

func gain_damage(amount: int, max_hp: int, taken: bool) -> void:
	if amount <= 0 or max_hp <= 0 or equipped_blast().is_empty() or is_instance_valid(_presentation):
		return
	gauge = mini(MAX_GAUGE, gauge + charge_amount(amount, max_hp, taken))

## Original parameter buckets; first selector row is the single-player baseline.
func charge_amount(amount: int, max_hp: int, taken: bool) -> int:
	if amount <= 0 or max_hp <= 0:
		return 0
	var data: Dictionary = ChargeData.data
	var prefix := "ten" if taken else "six"
	var limits: Array = data[prefix + "_thresholds"]
	var awards: Array = data[prefix + "_awards"]
	var ratio := int(float(mini(amount, max_hp) * 1000) / float(max_hp))
	for i in limits.size():
		if ratio < int(limits[i]) or i == limits.size() - 1:
			return int(float(int(awards[i]) * int(data.charge_multiplier) * int(data.selector_multipliers[0])) / 1000.0)
	return 0

func is_presenting(player: Node) -> bool:
	return is_instance_valid(_presentation) and _presentation.get_parent() == player

func activate(player: Node3D) -> bool:
	var blast := equipped_blast()
	if gauge < MAX_GAUGE or blast.is_empty() or is_instance_valid(_presentation):
		return false
	if not player.can_photon_blast():
		return false
	gauge = 0
	var presentation = preload("res://scripts/3d/combat/photon_blast_cast.gd").new()
	_presentation = presentation
	presentation.blast = blast
	player.add_child(presentation)
	return true

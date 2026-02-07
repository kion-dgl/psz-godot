extends Node
## Global game state singleton
## Ported from psz-sketch gameStateStore.ts (Zustand store)

# Combat stats
var hp: int = 100
var max_hp: int = 100
var mp: int = 50
var max_mp: int = 50

# Currency
var meseta: int = 0

# Equipment slots
var equipment: Dictionary = {
	"weapon": "",
	"armor": "",
	"accessory1": "",
	"accessory2": "",
}

# Completed missions tracking
var completed_missions: Array = []  # Array of mission IDs

# Shared storage (across all characters)
var shared_storage: Array = []  # Array of {id, name, quantity}
var stored_meseta: int = 0

# UI state
var is_pause_menu_open: bool = false
var active_shop_npc: String = ""

# Signals (equivalent to Zustand subscriptions)
signal hp_changed(new_hp: int)
signal mp_changed(new_mp: int)
signal max_hp_changed(new_max_hp: int)
signal max_mp_changed(new_max_mp: int)
signal equipment_changed(slot: String, item: String)
signal pause_menu_toggled(is_open: bool)
signal shop_opened(npc_name: String)
signal shop_closed()
signal game_state_reset()
signal meseta_changed(new_amount: int)


func _ready() -> void:
	pass


# HP/MP setters with signals
func set_hp(value: int) -> void:
	hp = clampi(value, 0, max_hp)
	hp_changed.emit(hp)


func set_mp(value: int) -> void:
	mp = clampi(value, 0, max_mp)
	mp_changed.emit(mp)


func set_max_hp(value: int) -> void:
	max_hp = value
	hp = mini(hp, max_hp)
	max_hp_changed.emit(max_hp)


func set_max_mp(value: int) -> void:
	max_mp = value
	mp = mini(mp, max_mp)
	max_mp_changed.emit(max_mp)


# Equipment management
func equip_item(slot: String, item: String) -> void:
	if slot in equipment:
		equipment[slot] = item
		equipment_changed.emit(slot, item)


func unequip_item(slot: String) -> void:
	if slot in equipment:
		equipment[slot] = ""
		equipment_changed.emit(slot, "")


func get_equipped_item(slot: String) -> String:
	if slot in equipment:
		return equipment[slot]
	return ""


# UI state management
func toggle_pause_menu() -> void:
	is_pause_menu_open = not is_pause_menu_open
	pause_menu_toggled.emit(is_pause_menu_open)
	get_tree().paused = is_pause_menu_open


func open_shop(npc_name: String) -> void:
	active_shop_npc = npc_name
	shop_opened.emit(npc_name)


func close_shop() -> void:
	active_shop_npc = ""
	shop_closed.emit()


# Reset all state to defaults
func reset_game_state() -> void:
	hp = 100
	max_hp = 100
	mp = 50
	max_mp = 50
	meseta = 0
	equipment = {
		"weapon": "",
		"armor": "",
		"accessory1": "",
		"accessory2": "",
	}
	is_pause_menu_open = false
	active_shop_npc = ""
	game_state_reset.emit()


# Utility functions
func heal(amount: int) -> void:
	set_hp(hp + amount)


func restore_mp(amount: int) -> void:
	set_mp(mp + amount)


func complete_mission(mission_id: String) -> void:
	if mission_id not in completed_missions:
		completed_missions.append(mission_id)


func is_mission_completed(mission_id: String) -> bool:
	return mission_id in completed_missions


func is_alive() -> bool:
	return hp > 0


func get_hp_percentage() -> float:
	if max_hp <= 0:
		return 0.0
	return float(hp) / float(max_hp)


func get_mp_percentage() -> float:
	if max_mp <= 0:
		return 0.0
	return float(mp) / float(max_mp)


# Meseta (currency) management
func add_meseta(amount: int) -> void:
	if amount > 0:
		meseta += amount
		meseta_changed.emit(meseta)


func remove_meseta(amount: int) -> bool:
	if amount > 0 and meseta >= amount:
		meseta -= amount
		meseta_changed.emit(meseta)
		return true
	return false


func get_meseta() -> int:
	return meseta

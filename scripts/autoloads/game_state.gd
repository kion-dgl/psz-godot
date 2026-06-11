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
## Count of open non-pausing modal menus (dialog boxes, start menu, etc.) that
## should block gameplay input even though the scene tree keeps running. Field
## pause menu and SceneManager overlays are covered by separate checks in the
## player's input handler; this is for modals that don't pause or push.
var modal_stack: int = 0

# Signals (equivalent to Zustand subscriptions)
signal hp_changed(new_hp: int)
signal mp_changed(new_mp: int)
signal max_hp_changed(new_max_hp: int)
signal max_mp_changed(new_max_mp: int)
signal game_state_reset()
signal meseta_changed(new_amount: int)


func _ready() -> void:
	pass


func push_modal() -> void:
	modal_stack += 1


func pop_modal() -> void:
	modal_stack = maxi(0, modal_stack - 1)


func is_gameplay_blocked() -> bool:
	return modal_stack > 0 or is_pause_menu_open or SceneManager.can_pop()


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
# UI state management
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


# Meseta (currency) management
func add_meseta(amount: int) -> void:
	if amount > 0:
		meseta += amount
		meseta_changed.emit(meseta)


func get_meseta() -> int:
	return meseta

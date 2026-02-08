extends Control
## Field combat screen — the main combat loop with enemy list, actions, and combat log.

enum State { PLAYER_TURN, ENEMY_TURN, WAVE_CLEAR, SESSION_COMPLETE, GAME_OVER }

var _state: int = State.PLAYER_TURN
var _selected_action: int = 0
var _selected_target: int = 0
var _choosing_target: bool = false
var _choosing_item: bool = false
var _choosing_technique: bool = false
var _choosing_pa: bool = false
var _selected_item: int = 0
var _selected_technique: int = 0
var _selected_pa: int = 0
var _usable_items: Array = []  # Array of {id, name, quantity}
var _available_techniques: Array = []  # Array of {id, name, level, pp_cost}
var _available_pas: Array = []  # Array of PhotonArtData refs
var _pending_action: String = ""  # "technique" or "pa" — what target selection is for
var _enemies: Array = []

const ACTIONS := ["Attack", "Special Attack", "Technique", "Photon Art", "Item", "Run"]

@onready var header_label: Label = $VBox/HeaderLabel
@onready var enemy_panel: PanelContainer = $VBox/HBox/LeftVBox/EnemyPanel
@onready var player_panel: PanelContainer = $VBox/HBox/RightVBox/PlayerPanel
@onready var action_panel: PanelContainer = $VBox/HBox/LeftVBox/ActionPanel
@onready var log_panel: PanelContainer = $VBox/HBox/RightVBox/LogPanel
@onready var hint_label: Label = $VBox/HintLabel

var _log_messages: Array = []


func _ready() -> void:
	_start_wave()


func _start_wave() -> void:
	var session: Dictionary = SessionManager.get_session()
	if session.is_empty():
		SceneManager.goto_scene("res://scenes/3d/city/city_market.tscn")
		return

	var area_id: String = session.get("area_id", "gurhacia")
	var difficulty: String = session.get("difficulty", "normal")
	var stage: int = int(session.get("stage", 1))
	var wave: int = int(session.get("wave", 1))

	_enemies = EnemySpawner.generate_wave(area_id, difficulty, stage, wave)
	CombatManager.init_combat(area_id, difficulty)
	CombatManager.set_enemies(_enemies)

	_state = State.PLAYER_TURN
	_selected_action = 0
	_selected_target = 0
	_choosing_target = false
	_choosing_technique = false
	_choosing_pa = false

	_add_log("── Stage %d Wave %d ──" % [stage, wave])
	_add_log("%d enemies appeared!" % _enemies.size())

	_refresh_display()


func _unhandled_input(event: InputEvent) -> void:
	match _state:
		State.PLAYER_TURN:
			_handle_player_input(event)
		State.WAVE_CLEAR:
			if event.is_action_pressed("ui_accept"):
				_advance_or_complete()
				get_viewport().set_input_as_handled()
		State.SESSION_COMPLETE:
			if event.is_action_pressed("ui_accept"):
				_return_to_city()
				get_viewport().set_input_as_handled()
		State.GAME_OVER:
			if event.is_action_pressed("ui_accept"):
				_return_to_city()
				get_viewport().set_input_as_handled()


func _handle_player_input(event: InputEvent) -> void:
	if _choosing_item:
		_handle_item_input(event)
	elif _choosing_technique:
		_handle_technique_input(event)
	elif _choosing_pa:
		_handle_pa_input(event)
	elif _choosing_target:
		_handle_target_input(event)
	else:
		_handle_action_input(event)


func _handle_action_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_selected_action = wrapi(_selected_action - 1, 0, ACTIONS.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_action = wrapi(_selected_action + 1, 0, ACTIONS.size())
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_select_action()
		get_viewport().set_input_as_handled()


func _handle_target_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_move_target(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_target(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_execute_action()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_choosing_target = false
		_pending_action = ""
		_refresh_display()
		get_viewport().set_input_as_handled()


func _handle_item_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_selected_item = wrapi(_selected_item - 1, 0, maxi(_usable_items.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_item = wrapi(_selected_item + 1, 0, maxi(_usable_items.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_use_selected_item()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_choosing_item = false
		_refresh_display()
		get_viewport().set_input_as_handled()


func _handle_technique_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_selected_technique = wrapi(_selected_technique - 1, 0, maxi(_available_techniques.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_technique = wrapi(_selected_technique + 1, 0, maxi(_available_techniques.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_select_technique()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_choosing_technique = false
		_refresh_display()
		get_viewport().set_input_as_handled()


func _handle_pa_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_selected_pa = wrapi(_selected_pa - 1, 0, maxi(_available_pas.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_pa = wrapi(_selected_pa + 1, 0, maxi(_available_pas.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_select_pa()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_choosing_pa = false
		_refresh_display()
		get_viewport().set_input_as_handled()


func _select_action() -> void:
	match ACTIONS[_selected_action]:
		"Attack", "Special Attack":
			_pending_action = ACTIONS[_selected_action]
			_choosing_target = true
			_selected_target = _find_first_alive_enemy()
			_refresh_display()
		"Technique":
			_open_technique_menu()
		"Photon Art":
			_open_pa_menu()
		"Item":
			_open_item_menu()
		"Run":
			_add_log("Escaped from battle!")
			SessionManager.return_to_city()
			SceneManager.goto_scene("res://scenes/3d/city/city_market.tscn")


func _open_technique_menu() -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		return
	var techniques: Dictionary = character.get("techniques", {})
	if techniques.is_empty():
		_add_log("No techniques learned!")
		_refresh_display()
		return

	_available_techniques.clear()
	for tech_id in techniques:
		var level: int = int(techniques[tech_id])
		if level <= 0:
			continue
		var tech: Dictionary = TechniqueManager.get_technique(tech_id)
		if tech.is_empty():
			continue
		var pp_cost: int = maxi(1, int(tech["pp"]) - int(float(level) / 5.0))
		_available_techniques.append({
			"id": tech_id,
			"name": tech.get("name", tech_id),
			"level": level,
			"pp_cost": pp_cost,
			"target": tech.get("target", "single"),
		})

	if _available_techniques.is_empty():
		_add_log("No techniques available!")
		_refresh_display()
		return

	_choosing_technique = true
	_selected_technique = 0
	hint_label.text = "[↑/↓] Select Technique  [ENTER] Cast  [ESC] Back"
	_refresh_display()


func _select_technique() -> void:
	if _available_techniques.is_empty() or _selected_technique >= _available_techniques.size():
		return
	var tech_info: Dictionary = _available_techniques[_selected_technique]
	var target_type: String = str(tech_info.get("target", "single"))

	_choosing_technique = false
	_pending_action = "technique"

	# Area/party/self techniques don't need target selection
	if target_type in ["area", "party", "self"]:
		_selected_target = _find_first_alive_enemy()
		_execute_action()
	else:
		_choosing_target = true
		_selected_target = _find_first_alive_enemy()
		_refresh_display()


func _open_pa_menu() -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var equipment: Dictionary = character.get("equipment", {})
	var weapon_id: String = str(equipment.get("weapon", ""))
	if weapon_id.is_empty():
		_add_log("No weapon equipped!")
		_refresh_display()
		return

	var weapon = WeaponRegistry.get_weapon(weapon_id)
	if weapon == null:
		_add_log("Unknown weapon!")
		_refresh_display()
		return

	var weapon_type_name: String = weapon.get_weapon_type_name()
	var class_data = ClassRegistry.get_class_data(str(character.get("class_id", "")))
	var class_type: String = class_data.type if class_data else ""

	_available_pas.clear()
	var all_arts: Array = PhotonArtRegistry.get_arts_by_weapon_type(weapon_type_name)
	for art in all_arts:
		if art.class_type == "" or art.class_type == class_type:
			_available_pas.append(art)

	if _available_pas.is_empty():
		_add_log("No photon arts available for %s!" % weapon_type_name)
		_refresh_display()
		return

	_choosing_pa = true
	_selected_pa = 0
	hint_label.text = "[↑/↓] Select PA  [ENTER] Use  [ESC] Back"
	_refresh_display()


func _select_pa() -> void:
	if _available_pas.is_empty() or _selected_pa >= _available_pas.size():
		return

	_choosing_pa = false
	_pending_action = "pa"
	_choosing_target = true
	_selected_target = _find_first_alive_enemy()
	_refresh_display()


func _open_item_menu() -> void:
	# Build list of usable consumables from inventory
	_usable_items.clear()
	var all_items: Array = Inventory.get_all_items()
	for item in all_items:
		var item_id: String = item.get("id", "")
		var consumable = ConsumableRegistry.get_consumable(item_id)
		if consumable:
			_usable_items.append(item)
		elif item_id == "telepipe":
			_usable_items.append(item)
		elif CombatManager.MATERIAL_STAT_MAP.has(item_id):
			_usable_items.append(item)

	if _usable_items.is_empty():
		_add_log("No usable items!")
		_refresh_display()
		return

	_choosing_item = true
	_selected_item = 0
	hint_label.text = "[↑/↓] Select Item  [ENTER] Use  [ESC] Back"
	_refresh_display()


func _use_selected_item() -> void:
	if _usable_items.is_empty() or _selected_item >= _usable_items.size():
		return

	var item: Dictionary = _usable_items[_selected_item]
	var item_id: String = item.get("id", "")
	var item_name: String = item.get("name", item_id)

	# Handle telepipe
	if item_id == "telepipe":
		Inventory.remove_item("telepipe", 1)
		_add_log("Used Telepipe! Warping to city...")
		_choosing_item = false
		SessionManager.suspend_session()
		SceneManager.goto_scene("res://scenes/3d/city/city_market.tscn")
		return

	# Handle materials
	if CombatManager.MATERIAL_STAT_MAP.has(item_id):
		var result: Dictionary = CombatManager.use_material(item_id)
		_add_log(str(result.get("message", "")))
		_choosing_item = false
		_refresh_display()
		_state = State.ENEMY_TURN
		await get_tree().create_timer(0.3).timeout
		_process_enemy_turns()
		return

	var consumable = ConsumableRegistry.get_consumable(item_id)
	if consumable == null:
		return

	# Apply consumable effect by parsing the details string
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var details: String = consumable.details.to_lower()
	var applied := false

	# Parse "Restores X% of HP/TP"
	var regex = RegEx.new()
	regex.compile("restores\\s+(\\d+)%\\s+of\\s+(hp|tp)")
	var result = regex.search(details)
	if result:
		var percent: int = int(result.get_string(1))
		var stat_type: String = result.get_string(2)
		if stat_type == "hp":
			var max_hp: int = int(character.get("max_hp", 100))
			var heal_amount: int = int(float(max_hp) * float(percent) / 100.0)
			character["hp"] = mini(int(character["hp"]) + heal_amount, max_hp)
			_add_log("Used %s! Restored %d HP." % [item_name, heal_amount])
			applied = true
		elif stat_type == "tp":
			var max_pp: int = int(character.get("max_pp", 50))
			var restore_amount: int = int(float(max_pp) * float(percent) / 100.0)
			character["pp"] = mini(int(character["pp"]) + restore_amount, max_pp)
			_add_log("Used %s! Restored %d PP." % [item_name, restore_amount])
			applied = true

	# Check for "Restores all HP" / full restore
	if not applied and "restores all" in details:
		if "hp" in details:
			character["hp"] = int(character.get("max_hp", 100))
			_add_log("Used %s! Fully restored HP." % item_name)
			applied = true
		if "tp" in details:
			character["pp"] = int(character.get("max_pp", 50))
			_add_log("Used %s! Fully restored PP." % item_name)
			applied = true

	if not applied:
		_add_log("Used %s." % item_name)

	# Remove from inventory
	Inventory.remove_item(item_id, 1)
	CharacterManager._sync_to_game_state()

	_choosing_item = false
	_refresh_display()

	# Using an item takes a turn — enemies act next
	_state = State.ENEMY_TURN
	await get_tree().create_timer(0.3).timeout
	_process_enemy_turns()


func _move_target(direction: int) -> void:
	var alive: Array = CombatManager.get_alive_enemies()
	if alive.is_empty():
		return
	# Find current target in alive list
	var current_alive_idx := 0
	for i in range(alive.size()):
		if _enemies.find(alive[i]) == _selected_target:
			current_alive_idx = i
			break
	current_alive_idx = wrapi(current_alive_idx + direction, 0, alive.size())
	_selected_target = _enemies.find(alive[current_alive_idx])
	_refresh_display()


func _find_first_alive_enemy() -> int:
	for i in range(_enemies.size()):
		if _enemies[i].get("alive", false):
			return i
	return 0


func _execute_action() -> void:
	_choosing_target = false

	var result: Dictionary

	if _pending_action == "technique":
		# Cast selected technique
		var tech_info: Dictionary = _available_techniques[_selected_technique]
		result = CombatManager.cast_technique(str(tech_info["id"]), _selected_target)
		_add_log(str(result.get("message", "")))
		if result.get("defeated", false):
			var drops: Array = CombatManager.generate_drops(_enemies[_selected_target])
			CombatManager.add_drops(drops)
		_pending_action = ""
		_refresh_display()
		if CombatManager.is_wave_cleared():
			_on_wave_cleared()
			return
		_state = State.ENEMY_TURN
		await get_tree().create_timer(0.3).timeout
		_process_enemy_turns()
		return

	if _pending_action == "pa":
		# Use selected photon art
		var art = _available_pas[_selected_pa]
		result = CombatManager.use_photon_art(art.id, _selected_target)
		_add_log(str(result.get("message", "")))
		if result.get("defeated", false):
			var drops: Array = CombatManager.generate_drops(_enemies[_selected_target])
			CombatManager.add_drops(drops)
		_pending_action = ""
		_refresh_display()
		if CombatManager.is_wave_cleared():
			_on_wave_cleared()
			return
		_state = State.ENEMY_TURN
		await get_tree().create_timer(0.3).timeout
		_process_enemy_turns()
		return

	var action: String = _pending_action if not _pending_action.is_empty() else ACTIONS[_selected_action]
	_pending_action = ""

	if action == "Attack":
		result = CombatManager.attack(_selected_target)
	elif action == "Special Attack":
		result = CombatManager.special_attack(_selected_target)
	else:
		return

	# Attacking draws aggro from the target and nearby enemies
	CombatManager.aggro_on_attack(_selected_target)

	if result.get("hit", false):
		_add_log("You attack %s! %s" % [str(_enemies[_selected_target].get("name", "Enemy")), str(result.get("message", ""))])
		# Generate drops if enemy was defeated
		if result.get("defeated", false):
			var drops: Array = CombatManager.generate_drops(_enemies[_selected_target])
			CombatManager.add_drops(drops)
			for drop_id in drops:
				var info: Dictionary = Inventory._lookup_item(drop_id)
				_add_log("  Dropped: %s" % info.name)
	else:
		_add_log("You attack %s... Miss!" % str(_enemies[_selected_target].get("name", "Enemy")))

	_refresh_display()

	# Check for wave clear
	if CombatManager.is_wave_cleared():
		_on_wave_cleared()
		return

	# Enemy turn
	_state = State.ENEMY_TURN
	await get_tree().create_timer(0.3).timeout
	_process_enemy_turns()


func _process_enemy_turns() -> void:
	# Process player buff ticks
	var buff_msgs: Array = CombatManager.process_player_buffs()
	for msg in buff_msgs:
		_add_log(msg)

	# Process status effects first
	var ticks: Array = CombatManager.process_enemy_status_effects()
	for tick in ticks:
		_add_log(str(tick.get("message", "")))

	# Process aggro — idle enemies may notice the player
	var aggro_msgs: Array = CombatManager.process_aggro()
	for msg in aggro_msgs:
		_add_log(msg)

	# Only aggroed enemies attack
	for i in range(_enemies.size()):
		if not _enemies[i].get("alive", false):
			continue
		if not _enemies[i].get("aggroed", false):
			continue  # Still wandering, doesn't attack
		var result: Dictionary = CombatManager.enemy_attack(i)
		if not str(result.get("message", "")).is_empty():
			_add_log(str(result.get("message", "")))

		if result.get("player_defeated", false):
			_state = State.GAME_OVER
			_add_log("You have been defeated!")
			hint_label.text = "[ENTER] Return to City"
			_refresh_display()
			return

	# Check for wave clear after enemy DoT
	if CombatManager.is_wave_cleared():
		_on_wave_cleared()
		return

	_state = State.PLAYER_TURN
	_refresh_display()


func _on_wave_cleared() -> void:
	_state = State.WAVE_CLEAR
	var rewards: Dictionary = CombatManager.get_wave_rewards()
	var exp_gained: int = int(rewards.get("exp", 0))
	var meseta: int = int(rewards.get("meseta", 0))

	SessionManager.add_rewards(exp_gained, meseta)

	# Apply rewards
	var level_result: Dictionary = CharacterManager.add_experience(exp_gained)
	var character = CharacterManager.get_active_character()
	if character:
		character["meseta"] = int(character.get("meseta", 0)) + meseta
		GameState.meseta = int(character["meseta"])

	_add_log("── Wave Cleared! ──")
	_add_log("EXP: +%d  Meseta: +%d" % [exp_gained, meseta])
	if level_result.get("leveled_up", false):
		_add_log("LEVEL UP! Now Level %d!" % int(level_result.get("new_level", 1)))

	# Pick up all dropped items
	var dropped: Array = CombatManager.get_dropped_items()
	if not dropped.is_empty():
		_add_log("")
		_add_log("── Picking up loot ──")
		var pickup_results: Array = CombatManager.pickup_all()
		for pr in pickup_results:
			if pr.get("disk", false):
				# Technique disk — show learn result message
				_add_log("  %s" % str(pr.get("message", "Found a disk!")))
			elif pr.get("unidentified", false):
				if pr.get("picked_up", false):
					_add_log("  Found ??? (unidentified weapon)")
				else:
					_add_log("  Inventory full! Left: ??? weapon")
			elif pr.get("picked_up", false):
				_add_log("  Picked up: %s" % str(pr.get("name", "???")))
			else:
				_add_log("  Inventory full! Left: %s" % str(pr.get("name", "???")))

	hint_label.text = "[ENTER] Continue"
	_refresh_display()


func _advance_or_complete() -> void:
	if SessionManager.next_wave():
		_start_wave()
	elif SessionManager.next_stage():
		_start_wave()
	else:
		_state = State.SESSION_COMPLETE
		var session: Dictionary = SessionManager.get_session()
		_add_log("══════ SESSION COMPLETE ══════")
		_add_log("Total EXP: %d" % int(session.get("total_exp", 0)))
		_add_log("Total Meseta: %d" % int(session.get("total_meseta", 0)))

		# Mark mission as completed and grant rewards
		var mission_id: String = session.get("mission_id", "")
		if not mission_id.is_empty():
			GameState.complete_mission(mission_id)
			_grant_mission_rewards(mission_id, session.get("difficulty", "normal"))

		hint_label.text = "[ENTER] Return to City"
		_refresh_display()


func _grant_mission_rewards(mission_id: String, difficulty: String) -> void:
	var mission = MissionRegistry.get_mission(mission_id)
	if mission == null or mission.rewards.is_empty():
		return

	# Map session difficulty to reward key: "normal" → "normal", "hard" → "hard", "super-hard" → "superHard"
	var reward_key: String = difficulty
	if difficulty == "super-hard":
		reward_key = "superHard"

	var reward: Dictionary = mission.rewards.get(reward_key, {})
	if reward.is_empty():
		# Fallback to first available difficulty
		for key in mission.rewards:
			reward = mission.rewards[key]
			break

	if reward.is_empty():
		return

	_add_log("")
	_add_log("── Mission Rewards ──")

	# Grant reward meseta
	var reward_meseta: int = int(reward.get("meseta", 0))
	if reward_meseta > 0:
		var character = CharacterManager.get_active_character()
		if character:
			character["meseta"] = int(character.get("meseta", 0)) + reward_meseta
			GameState.meseta = int(character["meseta"])
		_add_log("Meseta: +%d" % reward_meseta)

	# Grant reward item
	var item_name: String = str(reward.get("item", ""))
	var quantity: int = int(reward.get("quantity", 1))
	if not item_name.is_empty():
		var item_id: String = item_name.to_lower().replace(" ", "_").replace("'", "").replace("-", "_").replace("/", "_")
		for _i in range(quantity):
			if Inventory.can_add_item(item_id):
				Inventory.add_item(item_id, 1)
				_add_log("Received: %s" % item_name)
			else:
				_add_log("Inventory full! Could not receive: %s" % item_name)


func _return_to_city() -> void:
	# On death: set HP to 50% as penalty
	if _state == State.GAME_OVER:
		var character = CharacterManager.get_active_character()
		if character:
			var max_hp: int = int(character.get("max_hp", 100))
			character["hp"] = int(max_hp * 0.5)
			character["pp"] = int(character.get("max_pp", 50))
			CharacterManager._sync_to_game_state()
	else:
		# Normal return (completed or ran): full heal
		_heal_to_full()

	SessionManager.return_to_city()
	SaveManager.auto_save()
	SceneManager.goto_scene("res://scenes/3d/city/city_market.tscn")


func _heal_to_full() -> void:
	var character = CharacterManager.get_active_character()
	if character:
		character["hp"] = int(character.get("max_hp", 100))
		character["pp"] = int(character.get("max_pp", 50))
		CharacterManager._sync_to_game_state()


func _add_log(message: String) -> void:
	_log_messages.append(message)
	# Keep last 50 messages
	if _log_messages.size() > 50:
		_log_messages = _log_messages.slice(-50)


func _refresh_display() -> void:
	var session: Dictionary = SessionManager.get_session()
	var area_name: String = str(session.get("area_id", "???")).capitalize()
	header_label.text = "─── %s ─── Stage %d/%d ─── Wave %d/%d ───" % [
		area_name,
		int(session.get("stage", 1)), 3,
		int(session.get("wave", 1)), 3,
	]

	if _state == State.PLAYER_TURN:
		if _choosing_target:
			hint_label.text = "[↑/↓] Select Target  [ENTER] Confirm  [ESC] Back"
		elif not _choosing_item and not _choosing_technique and not _choosing_pa:
			hint_label.text = "[↑/↓] Select Action  [ENTER] Confirm"

	_refresh_enemies()
	_refresh_player()
	_refresh_actions()
	_refresh_log()


func _refresh_enemies() -> void:
	for child in enemy_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	var header := Label.new()
	header.text = "── ENEMIES ──"
	header.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(header)

	for i in range(_enemies.size()):
		var enemy: Dictionary = _enemies[i]
		var label := Label.new()
		var name_str: String = str(enemy.get("name", "???"))
		var hp: int = int(enemy.get("hp", 0))
		var max_hp: int = int(enemy.get("max_hp", 1))
		var alive: bool = enemy.get("alive", false)
		var aggroed: bool = enemy.get("aggroed", false)

		if not alive:
			label.text = "  %-12s [DEFEATED]" % name_str
			label.modulate = Color(0.333, 0.333, 0.333)
		elif not aggroed:
			# Wandering — not yet hostile
			label.text = "%-14s (wandering)" % name_str
			if _choosing_target and i == _selected_target:
				label.text = "> " + label.text
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + label.text
				label.modulate = Color(0.5, 0.5, 0.5)
		else:
			var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
			var bar_len := 6
			var filled := int(ratio * bar_len)
			var bar := "█".repeat(filled) + "░".repeat(bar_len - filled)
			label.text = "%-14s HP %s %d" % [name_str, bar, hp]

			if _choosing_target and i == _selected_target:
				label.text = "> " + label.text
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + label.text
				if enemy.get("is_boss", false):
					label.modulate = Color(1, 0.267, 0.267)
				elif enemy.get("is_rare", false):
					label.modulate = Color(1, 0.8, 0)

		vbox.add_child(label)

	enemy_panel.add_child(vbox)


func _refresh_player() -> void:
	for child in player_panel.get_children():
		child.queue_free()

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var header := Label.new()
	header.text = "── PLAYER ──"
	header.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.text = "%s Lv.%d" % [str(character.get("class_id", "???")), int(character.get("level", 1))]
	vbox.add_child(name_label)

	# HP
	var hp: int = int(character.get("hp", 0))
	var max_hp: int = int(character.get("max_hp", 1))
	var hp_ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var hp_filled := int(hp_ratio * 10)
	var hp_label := Label.new()
	hp_label.text = "HP %s %d/%d" % ["█".repeat(hp_filled) + "░".repeat(10 - hp_filled), hp, max_hp]
	if hp_ratio < 0.25:
		hp_label.modulate = Color(1, 0.267, 0.267)
	vbox.add_child(hp_label)

	# PP
	var pp: int = int(character.get("pp", 0))
	var max_pp: int = int(character.get("max_pp", 1))
	var pp_ratio := clampf(float(pp) / float(max_pp), 0.0, 1.0)
	var pp_filled := int(pp_ratio * 10)
	var pp_label := Label.new()
	pp_label.text = "PP %s %d/%d" % ["█".repeat(pp_filled) + "░".repeat(10 - pp_filled), pp, max_pp]
	vbox.add_child(pp_label)

	var meseta_label := Label.new()
	meseta_label.text = "Meseta: %d" % int(character.get("meseta", 0))
	meseta_label.modulate = Color(1, 0.8, 0)
	vbox.add_child(meseta_label)

	# Active buffs
	var buffs: Dictionary = character.get("combat_buffs", {})
	if not buffs.is_empty():
		for buff_name in buffs:
			var buff: Dictionary = buffs[buff_name]
			var turns: int = int(buff.get("turns", 0))
			if turns > 0:
				var buff_label := Label.new()
				buff_label.text = "%s (%d turns)" % [buff_name.capitalize(), turns]
				buff_label.modulate = Color(0.5, 1, 0.5)
				vbox.add_child(buff_label)

	player_panel.add_child(vbox)


func _refresh_actions() -> void:
	for child in action_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	if _choosing_item:
		var header := Label.new()
		header.text = "── ITEMS ──"
		header.modulate = Color(0, 0.733, 0.8)
		vbox.add_child(header)

		for i in range(_usable_items.size()):
			var item: Dictionary = _usable_items[i]
			var label := Label.new()
			var qty: int = int(item.get("quantity", 1))
			var display: String = "%s x%d" % [item.get("name", item.get("id", "???")), qty]
			if i == _selected_item:
				label.text = "> " + display
				label.modulate = Color(1, 0.8, 0)
			else:
				label.text = "  " + display
			vbox.add_child(label)
	elif _choosing_technique:
		var header := Label.new()
		header.text = "── TECHNIQUES ──"
		header.modulate = Color(0, 0.733, 0.8)
		vbox.add_child(header)

		var character = CharacterManager.get_active_character()
		var current_pp: int = int(character.get("pp", 0)) if character else 0
		for i in range(_available_techniques.size()):
			var tech: Dictionary = _available_techniques[i]
			var label := Label.new()
			var display: String = "%s Lv.%d (%d PP)" % [tech["name"], tech["level"], tech["pp_cost"]]
			if i == _selected_technique:
				label.text = "> " + display
				label.modulate = Color(1, 0.8, 0) if current_pp >= int(tech["pp_cost"]) else Color(1, 0.267, 0.267)
			else:
				label.text = "  " + display
				if current_pp < int(tech["pp_cost"]):
					label.modulate = Color(0.5, 0.5, 0.5)
			vbox.add_child(label)
	elif _choosing_pa:
		var header := Label.new()
		header.text = "── PHOTON ARTS ──"
		header.modulate = Color(0, 0.733, 0.8)
		vbox.add_child(header)

		var character = CharacterManager.get_active_character()
		var current_pp: int = int(character.get("pp", 0)) if character else 0
		for i in range(_available_pas.size()):
			var art = _available_pas[i]
			var label := Label.new()
			var display: String = "%s (%d PP, %dx)" % [art.name, art.pp_cost, art.hits]
			if i == _selected_pa:
				label.text = "> " + display
				label.modulate = Color(1, 0.8, 0) if current_pp >= art.pp_cost else Color(1, 0.267, 0.267)
			else:
				label.text = "  " + display
				if current_pp < art.pp_cost:
					label.modulate = Color(0.5, 0.5, 0.5)
			vbox.add_child(label)
	else:
		var header := Label.new()
		header.text = "── ACTIONS ──"
		header.modulate = Color(0, 0.733, 0.8)
		vbox.add_child(header)

		if _state != State.PLAYER_TURN or _choosing_target:
			for action in ACTIONS:
				var label := Label.new()
				label.text = "  " + action
				label.modulate = Color(0.333, 0.333, 0.333)
				vbox.add_child(label)
		else:
			for i in range(ACTIONS.size()):
				var label := Label.new()
				if i == _selected_action:
					label.text = "> " + ACTIONS[i]
					label.modulate = Color(1, 0.8, 0)
				else:
					label.text = "  " + ACTIONS[i]
				vbox.add_child(label)

	action_panel.add_child(vbox)


func _refresh_log() -> void:
	for child in log_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := Label.new()
	header.text = "── COMBAT LOG ──"
	header.modulate = Color(0, 0.733, 0.8)
	vbox.add_child(header)

	# Show last N messages
	var start_idx := maxi(0, _log_messages.size() - 12)
	for i in range(start_idx, _log_messages.size()):
		var label := Label.new()
		label.text = _log_messages[i]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(label)

	scroll.add_child(vbox)
	log_panel.add_child(scroll)

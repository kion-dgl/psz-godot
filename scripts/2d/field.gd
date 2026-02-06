extends Control
## Field combat screen — the main combat loop with enemy list, actions, and combat log.

enum State { PLAYER_TURN, ENEMY_TURN, WAVE_CLEAR, SESSION_COMPLETE, GAME_OVER }

var _state: int = State.PLAYER_TURN
var _selected_action: int = 0
var _selected_target: int = 0
var _choosing_target: bool = false
var _enemies: Array = []

const ACTIONS := ["Attack", "Special Attack", "Item", "Run"]

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
	var session := SessionManager.get_session()
	if session.is_empty():
		SceneManager.goto_scene("res://scenes/2d/city.tscn")
		return

	var area_id: String = session.get("area_id", "gurhacia")
	var difficulty: String = session.get("difficulty", "normal")
	var stage: int = int(session.get("stage", 1))
	var wave: int = int(session.get("wave", 1))

	_enemies = EnemySpawner.generate_wave(area_id, difficulty, stage, wave)
	CombatManager.init_combat()
	CombatManager.set_enemies(_enemies)

	_state = State.PLAYER_TURN
	_selected_action = 0
	_selected_target = 0
	_choosing_target = false

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
	if _choosing_target:
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
			_refresh_display()
			get_viewport().set_input_as_handled()
	else:
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


func _select_action() -> void:
	match ACTIONS[_selected_action]:
		"Attack", "Special Attack":
			_choosing_target = true
			_selected_target = _find_first_alive_enemy()
			_refresh_display()
		"Item":
			_add_log("No items in inventory.")
			_refresh_display()
		"Run":
			_add_log("Escaped from battle!")
			SessionManager.return_to_city()
			SceneManager.goto_scene("res://scenes/2d/city.tscn")


func _move_target(direction: int) -> void:
	var alive := CombatManager.get_alive_enemies()
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
	var action: String = ACTIONS[_selected_action]

	var result: Dictionary
	if action == "Attack":
		result = CombatManager.attack(_selected_target)
	elif action == "Special Attack":
		result = CombatManager.special_attack(_selected_target)
	else:
		return

	if result.get("hit", false):
		_add_log("You attack %s! %s" % [str(_enemies[_selected_target].get("name", "Enemy")), str(result.get("message", ""))])
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
	# Process status effects first
	var ticks := CombatManager.process_enemy_status_effects()
	for tick in ticks:
		_add_log(str(tick.get("message", "")))

	# Each alive enemy attacks
	for i in range(_enemies.size()):
		if not _enemies[i].get("alive", false):
			continue
		var result := CombatManager.enemy_attack(i)
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
	var rewards := CombatManager.get_wave_rewards()
	var exp: int = int(rewards.get("exp", 0))
	var meseta: int = int(rewards.get("meseta", 0))

	SessionManager.add_rewards(exp, meseta)

	# Apply rewards
	var level_result := CharacterManager.add_experience(exp)
	var character := CharacterManager.get_active_character()
	if character:
		character["meseta"] = int(character.get("meseta", 0)) + meseta
		GameState.meseta = int(character["meseta"])

	_add_log("── Wave Cleared! ──")
	_add_log("EXP: +%d  Meseta: +%d" % [exp, meseta])
	if level_result.get("leveled_up", false):
		_add_log("LEVEL UP! Now Level %d!" % int(level_result.get("new_level", 1)))

	hint_label.text = "[ENTER] Continue"
	_refresh_display()


func _advance_or_complete() -> void:
	if SessionManager.next_wave():
		_start_wave()
	elif SessionManager.next_stage():
		_start_wave()
	else:
		_state = State.SESSION_COMPLETE
		var session := SessionManager.get_session()
		_add_log("══════ SESSION COMPLETE ══════")
		_add_log("Total EXP: %d" % int(session.get("total_exp", 0)))
		_add_log("Total Meseta: %d" % int(session.get("total_meseta", 0)))
		hint_label.text = "[ENTER] Return to City"
		_refresh_display()


func _return_to_city() -> void:
	SessionManager.return_to_city()
	SaveManager.auto_save()
	SceneManager.goto_scene("res://scenes/2d/city.tscn")


func _add_log(message: String) -> void:
	_log_messages.append(message)
	# Keep last 50 messages
	if _log_messages.size() > 50:
		_log_messages = _log_messages.slice(-50)


func _refresh_display() -> void:
	var session := SessionManager.get_session()
	var area_name: String = str(session.get("area_id", "???")).capitalize()
	header_label.text = "─── %s ─── Stage %d/%d ─── Wave %d/%d ───" % [
		area_name,
		int(session.get("stage", 1)), 3,
		int(session.get("wave", 1)), 3,
	]

	if _state == State.PLAYER_TURN:
		if _choosing_target:
			hint_label.text = "[↑/↓] Select Target  [ENTER] Confirm  [ESC] Back"
		else:
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

		if not alive:
			label.text = "  %-12s [DEFEATED]" % name_str
			label.modulate = Color(0.333, 0.333, 0.333)
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

	var character := CharacterManager.get_active_character()
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

	player_panel.add_child(vbox)


func _refresh_actions() -> void:
	for child in action_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

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

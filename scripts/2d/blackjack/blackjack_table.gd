extends Control
## Saloon Blackjack — 2D card overlay opened by the cowgirl dealer.
## Sandbox chips: bankroll resets to 5000 each open; no meseta impact.

const STARTING_CHIPS := 5000
const BET_OPTIONS := [100, 500, 1000]
const CARDS_DIR := "res://assets/ui/cards/"
const CARD_W := 110
const CARD_H := 158
const CARD_GAP := 14
const BTN_MIN := Vector2(160, 64)

const OUTCOME_TEXT := {
	BlackjackGame.Outcome.PLAYER_BLACKJACK: "Blackjack! Pays 3:2.",
	BlackjackGame.Outcome.PLAYER_WIN: "You win!",
	BlackjackGame.Outcome.DEALER_WIN: "Dealer wins.",
	BlackjackGame.Outcome.PLAYER_BUST: "Bust.",
	BlackjackGame.Outcome.PUSH: "Push — bet returned.",
}

var _game: BlackjackGame
var _dealer_row: HBoxContainer
var _player_row: HBoxContainer
var _dealer_total_label: Label
var _player_total_label: Label
var _chips_label: Label
var _bet_label: Label
var _status_label: Label
var _bet_buttons: HBoxContainer
var _action_buttons: HBoxContainer
var _hit_btn: Button
var _stand_btn: Button
var _double_btn: Button
var _next_btn: Button
var _exit_btn: Button


func _ready() -> void:
	# MobileControls auto-switches to dpad+face-buttons mode when SceneManager
	# pushes an overlay (it polls SceneManager.can_pop()), so the joystick
	# hides on its own. We DO NOT disable the layer — the dpad + south face
	# button are how mobile players drive the table (focus + ui_accept).
	_build_ui()
	_game = BlackjackGame.new(STARTING_CHIPS)
	_game.state_changed.connect(_on_state_changed)
	_game.card_dealt.connect(_on_card_dealt)
	_game.hand_updated.connect(_on_hand_updated)
	_game.round_resolved.connect(_on_round_resolved)
	# Drive the initial UI snapshot — _init() emitted state_changed before
	# we connected, so manually sync to BETTING once.
	_on_state_changed(_game.state)
	_refresh_chips()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	var key := (event as InputEventKey).keycode
	match _game.state:
		BlackjackGame.State.BETTING:
			match key:
				KEY_1:
					_on_bet_pressed(BET_OPTIONS[0]); get_viewport().set_input_as_handled()
				KEY_2:
					_on_bet_pressed(BET_OPTIONS[1]); get_viewport().set_input_as_handled()
				KEY_3:
					_on_bet_pressed(BET_OPTIONS[2]); get_viewport().set_input_as_handled()
		BlackjackGame.State.PLAYER_TURN:
			match key:
				KEY_H:
					_on_hit(); get_viewport().set_input_as_handled()
				KEY_S:
					_on_stand(); get_viewport().set_input_as_handled()
				KEY_D:
					_on_double(); get_viewport().set_input_as_handled()
		BlackjackGame.State.RESOLVED:
			if key == KEY_ENTER or key == KEY_SPACE or key == KEY_KP_ENTER:
				_on_next(); get_viewport().set_input_as_handled()


# --- UI build ---

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.18, 0.10, 0.96)  # Felt green
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Permanent Leave button — top-right, always reachable
	_exit_btn = Button.new()
	_exit_btn.text = "← Leave"
	_exit_btn.custom_minimum_size = Vector2(140, 56)
	_exit_btn.add_theme_font_size_override("font_size", 22)
	_exit_btn.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	_exit_btn.offset_left = -160
	_exit_btn.offset_top = 16
	_exit_btn.offset_right = -16
	_exit_btn.offset_bottom = 72
	_exit_btn.pressed.connect(func() -> void: SceneManager.pop_scene())
	add_child(_exit_btn)

	var root_v := VBoxContainer.new()
	root_v.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root_v.add_theme_constant_override("separation", 12)
	root_v.offset_left = 24
	root_v.offset_right = -24
	root_v.offset_top = 16
	root_v.offset_bottom = -16
	add_child(root_v)

	var title := Label.new()
	title.text = "BLACKJACK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	root_v.add_child(title)

	# Dealer label + cards
	_dealer_total_label = Label.new()
	_dealer_total_label.text = "Dealer"
	_dealer_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dealer_total_label.add_theme_font_size_override("font_size", 20)
	root_v.add_child(_dealer_total_label)
	_dealer_row = HBoxContainer.new()
	_dealer_row.add_theme_constant_override("separation", CARD_GAP)
	_dealer_row.custom_minimum_size = Vector2(0, CARD_H)
	_dealer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_v.add_child(_dealer_row)

	# Status text — large, centered, between dealer and player
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 26)
	_status_label.add_theme_color_override("font_color", Color(1, 0.88, 0.4))
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 4)
	_status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root_v.add_child(_status_label)

	# Player cards + label
	_player_row = HBoxContainer.new()
	_player_row.add_theme_constant_override("separation", CARD_GAP)
	_player_row.custom_minimum_size = Vector2(0, CARD_H)
	_player_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_v.add_child(_player_row)
	_player_total_label = Label.new()
	_player_total_label.text = "You"
	_player_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_total_label.add_theme_font_size_override("font_size", 20)
	root_v.add_child(_player_total_label)

	# Chips + bet HUD
	var hud := HBoxContainer.new()
	hud.add_theme_constant_override("separation", 32)
	hud.alignment = BoxContainer.ALIGNMENT_CENTER
	root_v.add_child(hud)
	_chips_label = Label.new()
	_chips_label.add_theme_font_size_override("font_size", 22)
	hud.add_child(_chips_label)
	_bet_label = Label.new()
	_bet_label.add_theme_font_size_override("font_size", 22)
	hud.add_child(_bet_label)

	# Bet buttons (visible during BETTING)
	_bet_buttons = HBoxContainer.new()
	_bet_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_bet_buttons.add_theme_constant_override("separation", 16)
	root_v.add_child(_bet_buttons)
	for i in range(BET_OPTIONS.size()):
		var amount: int = BET_OPTIONS[i]
		var b := Button.new()
		b.text = "[%d] Bet %d" % [i + 1, amount]
		b.custom_minimum_size = BTN_MIN
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_on_bet_pressed.bind(amount))
		_bet_buttons.add_child(b)

	# Action buttons (visible during PLAYER_TURN / RESOLVED)
	_action_buttons = HBoxContainer.new()
	_action_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_buttons.add_theme_constant_override("separation", 16)
	_action_buttons.visible = false
	root_v.add_child(_action_buttons)
	_hit_btn = _make_action("[H] Hit", _on_hit)
	_stand_btn = _make_action("[S] Stand", _on_stand)
	_double_btn = _make_action("[D] Double", _on_double)
	_next_btn = _make_action("[Enter] Deal Again", _on_next)


func _make_action(label: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = BTN_MIN
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(callback)
	_action_buttons.add_child(b)
	return b


# --- Game event handlers ---

func _on_state_changed(new_state: int) -> void:
	match new_state:
		BlackjackGame.State.BETTING:
			_bet_buttons.visible = true
			_action_buttons.visible = false
			_dealer_row.visible = false
			_player_row.visible = false
			_dealer_total_label.text = "Dealer"
			_player_total_label.text = "You"
			_set_status("Place your bet — click a chip or press [1] [2] [3].")
		BlackjackGame.State.DEALING:
			_bet_buttons.visible = false
			_action_buttons.visible = false
			_clear_card_rows()
			_dealer_row.visible = true
			_player_row.visible = true
			_set_status("Dealing...")
		BlackjackGame.State.PLAYER_TURN:
			_action_buttons.visible = true
			_hit_btn.visible = true
			_stand_btn.visible = true
			_double_btn.visible = _game.get_player_hand().size() == 2 and _game.chips >= _game.bet
			_next_btn.visible = false
			_set_status("[H]it = take a card.   [S]tand = end turn.   [D]ouble = ×2 bet + 1 card.")
		BlackjackGame.State.DEALER_TURN:
			_action_buttons.visible = false
			_set_status("Dealer reveals + draws to 17...")
		BlackjackGame.State.RESOLVED:
			_action_buttons.visible = true
			_hit_btn.visible = false
			_stand_btn.visible = false
			_double_btn.visible = false
			_next_btn.visible = true
	_refresh_chips()
	_grab_default_focus.call_deferred()


func _on_card_dealt(_to: int, _card: Dictionary) -> void:
	_redraw_hands()
	_refresh_chips()
	if _game.state == BlackjackGame.State.PLAYER_TURN:
		_double_btn.visible = _game.get_player_hand().size() == 2 and _game.chips >= _game.bet


func _on_hand_updated(who: int, total: int, soft: bool) -> void:
	var label := "%d" % total
	if soft and total <= 21:
		label = "soft %d" % total
	if who == 0:
		_player_total_label.text = "You — %s" % label
	else:
		var hidden_card := false
		for c in _game.get_dealer_hand():
			if c.get("hidden", false):
				hidden_card = true
				break
		_dealer_total_label.text = "Dealer — ?" if hidden_card else "Dealer — %s" % label


func _on_round_resolved(outcome: int, _payout: int) -> void:
	var msg: String = OUTCOME_TEXT.get(outcome, "...")
	_set_status("%s    Press [Enter] to deal again." % msg)
	_redraw_hands()


func _grab_default_focus() -> void:
	# Skip transient DEALING/DEALER_TURN states — they'd steal focus mid-action.
	match _game.state:
		BlackjackGame.State.BETTING:
			for b in _bet_buttons.get_children():
				if b is Button and (b as Button).is_visible_in_tree():
					(b as Button).grab_focus()
					return
		BlackjackGame.State.PLAYER_TURN:
			if _hit_btn.is_visible_in_tree():
				_hit_btn.grab_focus()
		BlackjackGame.State.RESOLVED:
			if _next_btn.is_visible_in_tree():
				_next_btn.grab_focus()


# --- Buttons ---

func _on_bet_pressed(amount: int) -> void:
	if amount > _game.chips:
		_set_status("Not enough chips for that bet.")
		return
	_game.place_bet(amount)


func _on_hit() -> void: _game.hit()
func _on_stand() -> void: _game.stand()
func _on_double() -> void:
	if not _game.double_down():
		_set_status("Cannot double here — only on opening 2-card hand with chips to cover.")
func _on_next() -> void:
	if _game.chips <= 0:
		_set_status("Out of chips. Leave to reset bankroll.")
		return
	_game.next_round()


# --- Rendering ---

func _redraw_hands() -> void:
	_clear_card_rows()
	for c in _game.get_dealer_hand():
		_dealer_row.add_child(_make_card_node(c))
	for c in _game.get_player_hand():
		_player_row.add_child(_make_card_node(c))


func _clear_card_rows() -> void:
	for n in _dealer_row.get_children():
		n.queue_free()
	for n in _player_row.get_children():
		n.queue_free()


func _make_card_node(card: Dictionary) -> Control:
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(CARD_W, CARD_H)
	rect.texture = _card_texture(card)
	return rect


func _card_texture(card: Dictionary) -> Texture2D:
	if card.get("hidden", false):
		return load(CARDS_DIR + "card_back.png")
	var path := "%scard_%s_%s.png" % [CARDS_DIR, card.suit, card.rank]
	return load(path)


func _refresh_chips() -> void:
	_chips_label.text = "Chips: %d" % _game.chips
	_bet_label.text = "Bet: %d" % _game.bet


func _set_status(text: String) -> void:
	_status_label.text = text

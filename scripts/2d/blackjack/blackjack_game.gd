class_name BlackjackGame extends RefCounted
## Pure blackjack rules engine — deck, hands, dealer AI, payout resolution.
## No scene/UI dependencies; UI listens to signals and reads state.

signal state_changed(new_state: int)
signal card_dealt(to: int, card: Dictionary)  # to: 0=player, 1=dealer; card: {suit, rank, hidden}
signal hand_updated(who: int, total: int, soft: bool)
signal round_resolved(outcome: int, payout: int)  # outcome: see Outcome enum

enum State { IDLE, BETTING, DEALING, PLAYER_TURN, DEALER_TURN, RESOLVED }
enum Outcome { PLAYER_BLACKJACK, PLAYER_WIN, DEALER_WIN, PLAYER_BUST, PUSH }

const SUITS := ["clubs", "diamonds", "hearts", "spades"]
const RANKS := ["02", "03", "04", "05", "06", "07", "08", "09", "10", "J", "Q", "K", "A"]
const DEALER_HITS_SOFT_17 := false  # Stand on soft 17 (player-friendly H17 vs S17 toggle)

var state: int = State.IDLE
var bet: int = 0
var chips: int
var doubled: bool = false

var _deck: Array = []  # Top of deck is the END of the array (pop_back is O(1))
var _player_hand: Array = []
var _dealer_hand: Array = []
var _rng := RandomNumberGenerator.new()


func _init(starting_chips: int = 5000, seed_value: int = 0) -> void:
	chips = starting_chips
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_set_state(State.BETTING)


## Place a bet and start dealing. Returns false if invalid.
func place_bet(amount: int) -> bool:
	if state != State.BETTING:
		return false
	if amount <= 0 or amount > chips:
		return false
	bet = amount
	chips -= bet
	doubled = false
	_start_round()
	return true


## Player chooses to take another card.
func hit() -> void:
	if state != State.PLAYER_TURN:
		return
	_deal_to(_player_hand, 0, false)
	var t: Array = hand_total(_player_hand)
	if t[0] > 21:
		_resolve()
	elif t[0] == 21:
		_dealer_play()


## Player chooses to stop drawing.
func stand() -> void:
	if state != State.PLAYER_TURN:
		return
	_dealer_play()


## Player doubles down — double bet, take exactly one card, then stand.
## Allowed only on the opening 2-card hand and when chips can cover it.
func double_down() -> bool:
	if state != State.PLAYER_TURN:
		return false
	if _player_hand.size() != 2 or chips < bet:
		return false
	chips -= bet
	bet *= 2
	doubled = true
	_deal_to(_player_hand, 0, false)
	if hand_total(_player_hand)[0] > 21:
		_resolve()
	else:
		_dealer_play()
	return true


## Read-only views for the UI.
func get_player_hand() -> Array: return _player_hand.duplicate(true)
func get_dealer_hand() -> Array: return _dealer_hand.duplicate(true)


## (total, soft?) — soft means an ace is still counted as 11.
static func hand_total(hand: Array) -> Array:
	var total := 0
	var aces := 0
	for c in hand:
		if c.get("hidden", false):
			continue
		var r: String = c.rank
		if r == "A":
			aces += 1
			total += 11
		elif r in ["J", "Q", "K"]:
			total += 10
		else:
			total += int(r)
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return [total, aces > 0]


## Reset for a new round (after RESOLVED).
func next_round() -> void:
	if state != State.RESOLVED:
		return
	bet = 0
	doubled = false
	_player_hand.clear()
	_dealer_hand.clear()
	_set_state(State.BETTING)


# --- internals ---

func _start_round() -> void:
	_set_state(State.DEALING)
	if _deck.size() < 15:
		_build_and_shuffle_deck()
	_player_hand.clear()
	_dealer_hand.clear()
	_deal_to(_player_hand, 0, false)
	_deal_to(_dealer_hand, 1, false)
	_deal_to(_player_hand, 0, false)
	_deal_to(_dealer_hand, 1, true)  # Hole card
	# Natural blackjack check
	var p_total: int = hand_total(_player_hand)[0]
	if p_total == 21:
		_dealer_play()  # reveal dealer + resolve
	else:
		_set_state(State.PLAYER_TURN)


func _dealer_play() -> void:
	_set_state(State.DEALER_TURN)
	if _dealer_hand.size() > 1 and _dealer_hand[1].get("hidden", false):
		_dealer_hand[1].hidden = false
		var t := hand_total(_dealer_hand)
		hand_updated.emit(1, t[0], t[1])
	# Dealer draws until totals reach the stand threshold
	while true:
		var t := hand_total(_dealer_hand)
		var total: int = t[0]
		var soft: bool = t[1]
		if total > 21:
			break
		if total >= 17:
			if soft and total == 17 and DEALER_HITS_SOFT_17:
				pass  # hit soft 17
			else:
				break
		_deal_to(_dealer_hand, 1, false)
	_resolve()


func _resolve() -> void:
	# Reveal any remaining hole card before resolving
	for c in _dealer_hand:
		c.hidden = false
	var p_total: int = hand_total(_player_hand)[0]
	var d_total: int = hand_total(_dealer_hand)[0]
	var p_blackjack: bool = _player_hand.size() == 2 and p_total == 21 and not doubled
	var d_blackjack: bool = _dealer_hand.size() == 2 and d_total == 21
	var outcome: int
	var payout: int = 0
	if p_total > 21:
		outcome = Outcome.PLAYER_BUST
	elif p_blackjack and not d_blackjack:
		outcome = Outcome.PLAYER_BLACKJACK
		payout = bet + int(round(bet * 1.5))  # 3:2 plus stake back
	elif d_blackjack and not p_blackjack:
		outcome = Outcome.DEALER_WIN
	elif p_blackjack and d_blackjack:
		outcome = Outcome.PUSH
		payout = bet
	elif d_total > 21 or p_total > d_total:
		outcome = Outcome.PLAYER_WIN
		payout = bet * 2
	elif p_total < d_total:
		outcome = Outcome.DEALER_WIN
	else:
		outcome = Outcome.PUSH
		payout = bet
	chips += payout
	_set_state(State.RESOLVED)
	round_resolved.emit(outcome, payout)


func _deal_to(hand: Array, to: int, hidden: bool) -> void:
	if _deck.is_empty():
		_build_and_shuffle_deck()
	var card: Dictionary = _deck.pop_back()
	card.hidden = hidden
	hand.append(card)
	card_dealt.emit(to, card)
	var t := hand_total(hand)
	hand_updated.emit(to, t[0], t[1])


func _build_and_shuffle_deck() -> void:
	_deck.clear()
	for s in SUITS:
		for r in RANKS:
			_deck.append({"suit": s, "rank": r, "hidden": false})
	for i in range(_deck.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = _deck[i]
		_deck[i] = _deck[j]
		_deck[j] = tmp


func _set_state(new_state: int) -> void:
	state = new_state
	state_changed.emit(state)

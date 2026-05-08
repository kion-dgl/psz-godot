class_name QuantityDialog extends ConfirmDialog
## Two-step quantity-aware shop confirm. The original single-step design
## (qty selector AND Yes/No on the same modal) was confusing per playtest
## feedback — pressing Yes always bought whatever qty was shown, but the
## visual implied two separate decisions.
##
## Now: pick qty first, then confirm. PSO-style.
##
## Step 1 (SelectingQty): qty selector visible, single [Confirm] button.
##     ui_up / ui_down            qty + / -
##     ui_accept                  advance to Confirming
##     ui_cancel                  close (emits `cancelled`)
##
## Step 2 (Confirming): qty selector hidden, prompt rebuilt as
##     "Buy 7× Monomate for 350 M?" with [Yes] [No].
##     ui_left / ui_right         toggle focus
##     ui_accept on Yes           emit `confirmed_qty(qty)` + close
##     ui_accept on No / ui_cancel  return to SelectingQty (qty preserved)
##
## Edge case: max_qty <= 1 skips SelectingQty entirely and behaves like
## a one-step ConfirmDialog (qty is always 1).
##
## External API is unchanged: callers still call `set_item`, `ask`, and
## connect to `confirmed_qty(qty)`. The optional `verb` parameter on
## `set_item` (default "Buy") drives the confirm-step prompt for storage
## (which passes "Store" or "Withdraw").

signal confirmed_qty(qty: int)

const _NAV_ACTIONS := ["ui_up", "ui_down"]

enum Step { SelectingQty, Confirming }

var _item_name: String = ""
var _unit_cost: int = 0
var _max_qty: int = 1
var _qty: int = 1
var _verb: String = "Buy"
var _qty_prompt: String = ""

var _qty_row: HBoxContainer
var _qty_label: Label
var _total_label: Label
var _nav: NavRepeat

var _step: int = Step.SelectingQty


## Configure the dialog. max_qty should already be clamped by the caller
## (min of max_stack, meseta/cost, inventory_room); the dialog enforces
## qty ∈ [1, max_qty]. `verb` drives the confirm-step prompt
## (e.g. "Buy 7× Monomate for 350 M?", "Store 7× Monomate?").
func set_item(item_name: String, unit_cost: int, max_qty: int, verb: String = "Buy") -> QuantityDialog:
	_item_name = item_name
	_unit_cost = unit_cost
	_max_qty = maxi(1, max_qty)
	_qty = 1
	_verb = verb
	_refresh_qty_text()
	return self


## Override base `ask` so we remember the qty-step prompt — the
## confirm-step prompt is built from the verb/item/qty/cost.
func ask(prompt: String) -> ConfirmDialog:
	_qty_prompt = prompt
	return super(prompt)


func _build_body(vbox: VBoxContainer) -> void:
	_qty_row = HBoxContainer.new()
	_qty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_qty_row.add_theme_constant_override("separation", 12)
	vbox.add_child(_qty_row)

	var hint := Label.new()
	hint.text = "▲ ▼"
	hint.add_theme_font_size_override("font_size", PszStyle.FONT_HINT)
	hint.add_theme_color_override("font_color", PszStyle.TEXT_MUTED)
	_qty_row.add_child(hint)

	_qty_label = Label.new()
	_qty_label.add_theme_font_size_override("font_size", PszStyle.FONT_TITLE + 4)
	_qty_label.add_theme_color_override("font_color", PszStyle.TEXT_WHITE)
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty_label.custom_minimum_size = Vector2(140, 0)
	_qty_row.add_child(_qty_label)

	var hint2 := Label.new()
	hint2.text = ""
	hint2.add_theme_font_size_override("font_size", PszStyle.FONT_HINT)
	_qty_row.add_child(hint2)

	_total_label = Label.new()
	_total_label.add_theme_font_size_override("font_size", PszStyle.FONT_ITEM)
	_total_label.add_theme_color_override("font_color", PszStyle.TEXT_MESETA)
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_total_label)


func _ready() -> void:
	super()
	_refresh_qty_text()
	_nav = NavRepeat.new(_NAV_ACTIONS, _on_nav_repeat)
	# Single-quantity items skip qty selection entirely — go straight to
	# confirm so the modal behaves like a plain ConfirmDialog with the
	# auto-built "Buy Monomate for 50 M?" prompt.
	if _max_qty <= 1:
		_enter_step(Step.Confirming)
	else:
		_enter_step(Step.SelectingQty)


func _process(delta: float) -> void:
	# Hold-to-repeat only meaningful while the qty selector is active.
	if _nav != null and _step == Step.SelectingQty:
		_nav.tick(delta)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if _step == Step.SelectingQty:
		if event.is_action_pressed("ui_up"):
			_change_qty(1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_down"):
			_change_qty(-1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept"):
			SfxManager.play("res://assets/sfx/ui/menu_select.wav")
			_enter_step(Step.Confirming)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_cancel"):
			SfxManager.play("res://assets/sfx/ui/menu_back.wav")
			_emit_cancelled()
			get_viewport().set_input_as_handled()
			return
	else:  # Step.Confirming
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			_focused_idx = 1 - _focused_idx
			SfxManager.play("res://assets/sfx/ui/menu_move.wav")
			_refresh_focus()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept"):
			SfxManager.play("res://assets/sfx/ui/menu_select.wav")
			if _focused_idx == 0:
				_emit_confirmed()
			else:
				_return_to_qty_step()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_cancel"):
			SfxManager.play("res://assets/sfx/ui/menu_back.wav")
			# max_qty=1 has no qty step to return to — close instead.
			if _max_qty <= 1:
				_emit_cancelled()
			else:
				_return_to_qty_step()
			get_viewport().set_input_as_handled()
			return


func _enter_step(step: int) -> void:
	_step = step
	if step == Step.SelectingQty:
		if _qty_row != null:
			_qty_row.visible = true
		if _total_label != null:
			_total_label.visible = _unit_cost > 0
		_no_button.visible = false
		_yes_button.text = "Confirm"
		_focused_idx = 0
		_refresh_focus()
		if _qty_prompt != "":
			_prompt_label.text = _qty_prompt
	else:
		if _qty_row != null:
			_qty_row.visible = false
		if _total_label != null:
			_total_label.visible = false
		_no_button.visible = true
		_yes_button.text = "Yes"
		_focused_idx = 0
		_refresh_focus()
		_prompt_label.text = _build_confirm_prompt()


func _return_to_qty_step() -> void:
	_enter_step(Step.SelectingQty)


func _build_confirm_prompt() -> String:
	# Build the final "Buy 7× Monomate for 350 M?" sentence from verb +
	# item + qty + unit_cost. Single qty drops the "× 1" for natural
	# reading.
	var qty_part: String = ""
	if _qty > 1:
		qty_part = "%d× " % _qty
	if _unit_cost > 0:
		var total: int = _unit_cost * _qty
		return "%s %s%s for %d M?" % [_verb, qty_part, _item_name, total]
	return "%s %s%s?" % [_verb, qty_part, _item_name]


func _on_nav_repeat(action: String) -> void:
	if _step != Step.SelectingQty:
		return
	match action:
		"ui_up": _change_qty(1)
		"ui_down": _change_qty(-1)


func _change_qty(delta: int) -> void:
	var prev := _qty
	# Wrap so holding up at max comes back to 1 — matches PSO's loop-y feel.
	_qty = wrapi(_qty - 1 + delta, 0, _max_qty) + 1
	if _qty != prev:
		SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		_refresh_qty_text()


func _refresh_qty_text() -> void:
	if _qty_label == null:
		return
	if _max_qty <= 1:
		_qty_label.text = "1"
	else:
		_qty_label.text = "%d / %d" % [_qty, _max_qty]
	if _total_label == null:
		return
	# Hide the total line entirely when there's no currency cost (e.g.
	# storage transfers — qty matters but there's no meseta to spend).
	if _unit_cost <= 0:
		_total_label.visible = false
	else:
		_total_label.visible = _step == Step.SelectingQty
		_total_label.text = "Total: %d M" % (_unit_cost * _qty)


func _emit_confirmed() -> void:
	confirmed_qty.emit(_qty)
	# Also emit base `confirmed` for callers that don't care about qty.
	confirmed.emit()
	queue_free()

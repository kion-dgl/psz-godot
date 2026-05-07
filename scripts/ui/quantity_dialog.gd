class_name QuantityDialog extends ConfirmDialog
## Quantity-aware shop confirm. Same Yes/No skeleton as ConfirmDialog plus
## a `< N >` quantity selector and a live total. Emits `confirmed_qty(qty)`
## as well as the inherited `confirmed` (with qty=1 if you don't care).
##
## Usage:
##     var modal := QuantityDialog.new()
##     modal.set_item("Monomate", 50, max_qty)  # max_qty already capped
##     modal.confirmed_qty.connect(_on_buy)
##     modal.cancelled.connect(_on_cancel)
##     add_child(modal)
##     modal.ask("Buy Monomate?")
##
## Input (in addition to the inherited Yes/No focus + accept/cancel):
##     ui_up                    qty + 1   (top of the modal feels like increment)
##     ui_down                  qty - 1
##     ui_left/ui_right         (inherited) — swap focus between Yes and No
##
## We intentionally use ui_up/ui_down for the qty so the inherited
## ui_left/ui_right behavior (Yes ↔ No) keeps working unchanged. Hold-to-
## repeat lives in NavRepeat which we instantiate ourselves.

signal confirmed_qty(qty: int)

const _NAV_ACTIONS := ["ui_up", "ui_down"]

var _item_name: String = ""
var _unit_cost: int = 0
var _max_qty: int = 1
var _qty: int = 1
var _qty_label: Label
var _total_label: Label
var _nav: NavRepeat


## Configure the dialog. max_qty should already be clamped by the caller
## (min of max_stack, meseta/cost, inventory_room); the dialog enforces
## qty ∈ [1, max_qty].
func set_item(item_name: String, unit_cost: int, max_qty: int) -> QuantityDialog:
	_item_name = item_name
	_unit_cost = unit_cost
	_max_qty = maxi(1, max_qty)
	_qty = 1
	_refresh_qty_text()
	return self


func _build_body(vbox: VBoxContainer) -> void:
	var qty_row := HBoxContainer.new()
	qty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	qty_row.add_theme_constant_override("separation", 12)
	vbox.add_child(qty_row)

	var hint := Label.new()
	hint.text = "▲ ▼"
	hint.add_theme_font_size_override("font_size", PszStyle.FONT_HINT)
	hint.add_theme_color_override("font_color", PszStyle.TEXT_MUTED)
	qty_row.add_child(hint)

	_qty_label = Label.new()
	_qty_label.add_theme_font_size_override("font_size", PszStyle.FONT_TITLE + 4)
	_qty_label.add_theme_color_override("font_color", PszStyle.TEXT_WHITE)
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty_label.custom_minimum_size = Vector2(140, 0)
	qty_row.add_child(_qty_label)

	var hint2 := Label.new()
	hint2.text = ""
	hint2.add_theme_font_size_override("font_size", PszStyle.FONT_HINT)
	qty_row.add_child(hint2)

	_total_label = Label.new()
	_total_label.add_theme_font_size_override("font_size", PszStyle.FONT_ITEM)
	_total_label.add_theme_color_override("font_color", PszStyle.TEXT_MESETA)
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_total_label)


func _ready() -> void:
	super()
	_refresh_qty_text()
	_nav = NavRepeat.new(_NAV_ACTIONS, _on_nav_repeat)


func _process(delta: float) -> void:
	if _nav != null:
		_nav.tick(delta)


func _input(event: InputEvent) -> void:
	# Intercept up/down for qty before delegating to the parent's left/right
	# focus + accept/cancel handling. Mark them handled so the underlying
	# scene doesn't see them either.
	if event.is_action_pressed("ui_up"):
		_change_qty(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_down"):
		_change_qty(-1)
		get_viewport().set_input_as_handled()
		return
	super(event)


func _on_nav_repeat(action: String) -> void:
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
		_total_label.visible = true
		_total_label.text = "Total: %d M" % (_unit_cost * _qty)


func _emit_confirmed() -> void:
	confirmed_qty.emit(_qty)
	# Also emit base `confirmed` for callers that don't care about qty.
	confirmed.emit()
	queue_free()

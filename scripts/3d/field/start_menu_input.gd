class_name StartMenuInput
extends RefCounted

## Start-menu input / navigation router, extracted from PsoStartMenu.
##
## Holds a back-reference to the PsoStartMenu autoload (`_c`) and delegates all
## menu-state access and action methods through it. Behavior is identical to the
## original inline implementation — this is a relocation refactor, not a logic
## change.
##
## PsoStartMenu (a Node) keeps thin `_unhandled_input`/`_process` callbacks that
## forward to `handle_input` here and tick the shared NavRepeat, since the engine
## won't call lifecycle methods on a RefCounted.
##
## Constants live on the PsoStartMenu autoload and are referenced statically as
## `PsoStartMenu.<CONST>` (warning-free); enum values as `PsoStartMenu.Mode.*`.

## Back-reference to the PsoStartMenu autoload that owns this router.
var _c


func _init(controller) -> void:
	_c = controller


# Hold-to-repeat is handled by the shared NavRepeat (owned by the controller);
# its callback routes here. The initial d-pad/keyboard press still arrives via
# the normal event flow — NavRepeat only adds the repeats and the right stick.
func _dispatch_ui_action(action: String) -> void:
	## Route a synthetic press directly to our own input handler. Going through
	## Input.parse_input_event would mark the action as globally pressed without
	## a matching release, so Input.is_action_pressed() would return true forever
	## and NavRepeat would keep dispatching after the player let go.
	# Modal owns input — don't fire menu-scroll synthetic events while a
	# confirm dialog is open, otherwise list cursor moves under the modal.
	if is_instance_valid(_c._active_modal):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	handle_input(ev)


# ── Input ───────────────────────────────────────────────────────────────────────
func handle_input(event: InputEvent) -> void:
	# Open menu from anywhere with ESC/pause (only when closed, no overlay, and in gameplay)
	if not _c._is_open:
		if event.is_action_pressed("pause") and SceneManager._overlay_stack.is_empty() and _c._is_gameplay_scene():
			_c.open()
			_c.get_viewport().set_input_as_handled()
		return

	# Modal owns input. ConfirmDialog uses _input (priority) and calls
	# set_input_as_handled, so events should be swallowed before they
	# reach _unhandled_input — but the synthetic events from NavRepeat
	# skip _input entirely, so we still need this gate.
	if is_instance_valid(_c._active_modal):
		return

	# ── Menu is open — consume ALL input except movement ──

	# Joypad Start button always closes the menu, regardless of mode.
	# Checked first because Start and pause share button index 6 — if the pause
	# branch ran first in a sub-mode it would fall through without closing.
	# Enter also maps to the "start" action so we guard on InputEventJoypadButton
	# to keep Enter usable as accept inside menus.
	if event is InputEventJoypadButton and event.is_action_pressed("start"):
		_c.close()
		_c.get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if _c._mode == PsoStartMenu.Mode.MAIN:
			_c.close()
			_c.get_viewport().set_input_as_handled()
			return
		# In sub-menus, Esc/pause acts as back (falls through to mode handler)

	# Let movement actions pass through (WASD + left stick)
	if event.is_action("move_forward") or event.is_action("move_backward") or \
	   event.is_action("move_left") or event.is_action("move_right"):
		return  # Don't consume — let player walk

	# LB/RB → page flip when in main view
	if _c._mode == PsoStartMenu.Mode.MAIN:
		if event.is_action_pressed("palette_swap"):  # LB
			_c._info_page = wrapi(_c._info_page - 1, 0, 4)
			_c._canvas.queue_redraw()
			_c.get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("quest_log"):  # RB
			_c._info_page = wrapi(_c._info_page + 1, 0, 4)
			_c._canvas.queue_redraw()
			_c.get_viewport().set_input_as_handled()
			return

	# Right-stick menu scroll is handled by the shared NavRepeat (polls the axis
	# and repeats like the d-pad). Swallow the stick's motion events here so they
	# don't drift the camera while the menu is open.
	if event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis == JOY_AXIS_RIGHT_Y:
		_c.get_viewport().set_input_as_handled()
		return

	# Route to mode-specific handler
	var handled := true
	match _c._mode:
		PsoStartMenu.Mode.MAIN:
			handled = _input_main(event)
		PsoStartMenu.Mode.ITEMS:
			handled = _input_list(event, _c._get_inventory().size())
		PsoStartMenu.Mode.ITEMS_MOVE:
			handled = _input_items_move(event)
		PsoStartMenu.Mode.EQUIP:
			handled = _input_list(event, _c._get_equip_slots().size())
		PsoStartMenu.Mode.EQUIP_PICK:
			handled = _input_equip_pick(event)
		PsoStartMenu.Mode.TECHS:
			handled = _input_list(event, _c._get_techniques().size())
		PsoStartMenu.Mode.PALETTE:
			handled = _input_palette(event)
		PsoStartMenu.Mode.PALETTE_PICK:
			handled = _input_palette_pick(event)
		PsoStartMenu.Mode.MAGS:
			handled = _input_list(event, _c._get_mags().size())
		PsoStartMenu.Mode.MAG_FEED:
			handled = _input_list(event, _c._get_feed_items().size())
		PsoStartMenu.Mode.QUEST:
			handled = _input_back(event)
		PsoStartMenu.Mode.SYSTEM:
			handled = _input_system(event)
		PsoStartMenu.Mode.OPTIONS:
			handled = _input_options(event)
		PsoStartMenu.Mode.DEBUG:
			handled = _input_debug(event)

	if handled:
		# Skip generic SFX if menu was just closed — close() plays its own sound
		if not _c._is_open:
			_c._canvas.queue_redraw()
			_c.get_viewport().set_input_as_handled()
			return
		# Play menu SFX
		if event.is_action_pressed("ui_accept"):
			SfxManager.play("res://assets/sfx/ui/menu_select.wav")
		elif event.is_action_pressed("ui_cancel"):
			SfxManager.play("res://assets/sfx/ui/menu_back.wav")
		elif event.is_action_pressed("ui_up", false) or event.is_action_pressed("ui_down", false) \
			or event.is_action_pressed("ui_left", false) or event.is_action_pressed("ui_right", false):
			SfxManager.play("res://assets/sfx/ui/menu_move.wav")
		_c._canvas.queue_redraw()

	# ALWAYS consume input when menu is open (blocks camera, interact, quick weapon, palette)
	_c.get_viewport().set_input_as_handled()


func _input_items_move(event: InputEvent) -> bool:
	var count: int = _c._get_inventory().size()
	if event.is_action_pressed("ui_up", false) and count > 0:
		_c._sub_idx = wrapi(_c._sub_idx - 1, 0, count)
		# Recompute move origin index in case the list changed under us.
		_c._move_from_idx = _c._find_idx_for_id(_c._move_from_id)
		return true
	elif event.is_action_pressed("ui_down", false) and count > 0:
		_c._sub_idx = wrapi(_c._sub_idx + 1, 0, count)
		_c._move_from_idx = _c._find_idx_for_id(_c._move_from_id)
		return true
	elif event.is_action_pressed("ui_accept"):
		_c._do_move()
		return true
	elif event.is_action_pressed("ui_cancel"):
		_c._action_message = ""
		_c._exit_move_mode()
		return true
	return false


func _input_main(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_up", false):
		_c._menu_idx = wrapi(_c._menu_idx - 1, 0, _c._get_menu_labels().size())
		return true
	elif event.is_action_pressed("ui_down", false):
		_c._menu_idx = wrapi(_c._menu_idx + 1, 0, _c._get_menu_labels().size())
		return true
	elif event.is_action_pressed("ui_left", false):
		_c._info_page = wrapi(_c._info_page - 1, 0, 4)
		return true
	elif event.is_action_pressed("ui_right", false):
		_c._info_page = wrapi(_c._info_page + 1, 0, 4)
		return true
	elif event.is_action_pressed("ui_accept"):
		_c._enter_sub(_c._menu_idx)
		return true
	elif event.is_action_pressed("ui_cancel"):
		_c.close()
		return true
	return false


func _input_list(event: InputEvent, count: int) -> bool:
	if event.is_action_pressed("ui_up", false) and count > 0:
		_c._sub_idx = wrapi(_c._sub_idx - 1, 0, count)
		_c._action_message = ""
		return true
	elif event.is_action_pressed("ui_down", false) and count > 0:
		_c._sub_idx = wrapi(_c._sub_idx + 1, 0, count)
		_c._action_message = ""
		return true
	elif event.is_action_pressed("ui_accept"):
		_c._sub_accept()
		return true
	elif event.is_action_pressed("ui_cancel"):
		_c._action_message = ""
		_c._go_back()
		return true
	return false


func _input_equip_pick(event: InputEvent) -> bool:
	var candidates: Array = _c._get_equip_candidates(_c._equip_slot_idx)
	if event.is_action_pressed("ui_up", false) and candidates.size() > 0:
		_c._equip_item_idx = wrapi(_c._equip_item_idx - 1, 0, candidates.size())
		return true
	elif event.is_action_pressed("ui_down", false) and candidates.size() > 0:
		_c._equip_item_idx = wrapi(_c._equip_item_idx + 1, 0, candidates.size())
		return true
	elif event.is_action_pressed("ui_accept"):
		_c._do_equip()
		return true
	elif event.is_action_pressed("ui_cancel"):
		_c._mode = PsoStartMenu.Mode.EQUIP
		return true
	return false


func _input_palette(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_up", false):
		_c._pal_slot_idx = wrapi(_c._pal_slot_idx - 1, 0, 3)
		return true
	elif event.is_action_pressed("ui_down", false):
		_c._pal_slot_idx = wrapi(_c._pal_slot_idx + 1, 0, 3)
		return true
	elif event.is_action_pressed("ui_left", false):
		_c._pal_page_idx = wrapi(_c._pal_page_idx - 1, 0, ActionPalette.pages.size())
		return true
	elif event.is_action_pressed("ui_right", false):
		_c._pal_page_idx = wrapi(_c._pal_page_idx + 1, 0, ActionPalette.pages.size())
		return true
	elif event.is_action_pressed("ui_accept"):
		_c._mode = PsoStartMenu.Mode.PALETTE_PICK
		_c._sub_idx = 0
		var current_id: String = str(ActionPalette.pages[_c._pal_page_idx][_c._pal_slot_idx])
		var actions: Array = _c._get_palette_actions()
		for i in range(actions.size()):
			if str(actions[i].get("id", "")) == current_id:
				_c._sub_idx = i
				break
		return true
	elif event.is_action_pressed("ui_cancel"):
		_c._mode = PsoStartMenu.Mode.MAIN
		return true
	return false


func _pal_flat_to_row_col(flat_idx: int) -> Vector2i:
	var fi := 0
	for ri in range(PsoStartMenu._PAL_PICKER_ROWS.size()):
		var row_ids: Array = PsoStartMenu._PAL_PICKER_ROWS[ri].ids
		for ci in range(row_ids.size()):
			if fi == flat_idx:
				return Vector2i(ri, ci)
			fi += 1
	return Vector2i(0, 0)


func _pal_row_col_to_flat(row: int, col: int) -> int:
	var fi := 0
	for ri in range(row):
		fi += int(PsoStartMenu._PAL_PICKER_ROWS[ri].ids.size())
	fi += col
	return fi


func _input_palette_pick(event: InputEvent) -> bool:
	var actions: Array = _c._get_palette_actions()
	var rc := _pal_flat_to_row_col(_c._sub_idx)
	var in_left: bool = rc.x < PsoStartMenu._PAL_LEFT_COL_SIZE
	var col_start: int = 0 if in_left else PsoStartMenu._PAL_LEFT_COL_SIZE
	var col_size: int = PsoStartMenu._PAL_LEFT_COL_SIZE if in_left else PsoStartMenu._PAL_RIGHT_COL_SIZE

	if event.is_action_pressed("ui_up", false):
		var local_row: int = rc.x - col_start
		var new_local: int = wrapi(local_row - 1, 0, col_size)
		var new_row: int = col_start + new_local
		var new_col: int = clampi(rc.y, 0, int(PsoStartMenu._PAL_PICKER_ROWS[new_row].ids.size()) - 1)
		_c._sub_idx = _pal_row_col_to_flat(new_row, new_col)
		return true
	elif event.is_action_pressed("ui_down", false):
		var local_row: int = rc.x - col_start
		var new_local: int = wrapi(local_row + 1, 0, col_size)
		var new_row: int = col_start + new_local
		var new_col: int = clampi(rc.y, 0, int(PsoStartMenu._PAL_PICKER_ROWS[new_row].ids.size()) - 1)
		_c._sub_idx = _pal_row_col_to_flat(new_row, new_col)
		return true
	elif event.is_action_pressed("ui_right", false):
		var row_ids: Array = PsoStartMenu._PAL_PICKER_ROWS[rc.x].ids
		if rc.y < row_ids.size() - 1:
			_c._sub_idx = _pal_row_col_to_flat(rc.x, rc.y + 1)
		elif in_left:
			var target_row: int = clampi(rc.x - col_start, 0, PsoStartMenu._PAL_RIGHT_COL_SIZE - 1) + PsoStartMenu._PAL_LEFT_COL_SIZE
			var target_col: int = clampi(rc.y, 0, int(PsoStartMenu._PAL_PICKER_ROWS[target_row].ids.size()) - 1)
			_c._sub_idx = _pal_row_col_to_flat(target_row, target_col)
		return true
	elif event.is_action_pressed("ui_left", false):
		if rc.y > 0:
			_c._sub_idx = _pal_row_col_to_flat(rc.x, rc.y - 1)
		elif not in_left:
			var target_row: int = clampi(rc.x - PsoStartMenu._PAL_LEFT_COL_SIZE, 0, PsoStartMenu._PAL_LEFT_COL_SIZE - 1)
			var target_ids: Array = PsoStartMenu._PAL_PICKER_ROWS[target_row].ids
			_c._sub_idx = _pal_row_col_to_flat(target_row, target_ids.size() - 1)
		return true
	elif event.is_action_pressed("ui_accept"):
		if _c._sub_idx < actions.size():
			var action: Dictionary = actions[_c._sub_idx]
			var action_id: String = str(action.get("id", ""))
			if _c._is_palette_action_available(action_id):
				ActionPalette.set_action(_c._pal_page_idx, _c._pal_slot_idx, action_id)
				_c._mode = PsoStartMenu.Mode.PALETTE
		return true
	elif event.is_action_pressed("ui_cancel"):
		_c._mode = PsoStartMenu.Mode.PALETTE
		return true
	return false


func _input_system(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_up", false):
		_c._sub_idx = wrapi(_c._sub_idx - 1, 0, PsoStartMenu.SYSTEM_LABELS.size())
		return true
	elif event.is_action_pressed("ui_down", false):
		_c._sub_idx = wrapi(_c._sub_idx + 1, 0, PsoStartMenu.SYSTEM_LABELS.size())
		return true
	elif event.is_action_pressed("ui_accept"):
		match _c._sub_idx:
			0:
				SaveManager.save_game()
				SfxManager.play("res://assets/sfx/ui/game_saved.wav")
			1:
				SaveManager.save_game()
				SfxManager.play("res://assets/sfx/ui/game_saved.wav")
				_c.close()
				SceneManager.goto_scene("res://scenes/2d/title.tscn")
			2:
				_c._mode = PsoStartMenu.Mode.OPTIONS
				_c._options_idx = 0
			3:
				_c._mode = PsoStartMenu.Mode.DEBUG
				_c._debug_idx = 0
				_c._debug_msg = ""
		return true
	elif event.is_action_pressed("ui_cancel"):
		_c._mode = PsoStartMenu.Mode.MAIN
		return true
	return false


func _input_options(event: InputEvent) -> bool:
	var opts: Array = _c._get_options_list()
	if event.is_action_pressed("ui_up", false) and opts.size() > 0:
		_c._options_idx = wrapi(_c._options_idx - 1, 0, opts.size())
		return true
	elif event.is_action_pressed("ui_down", false) and opts.size() > 0:
		_c._options_idx = wrapi(_c._options_idx + 1, 0, opts.size())
		return true
	elif event.is_action_pressed("ui_left", false):
		if _c._options_idx == 0:
			_c._adjust_music_volume(-0.1)
			return true
		elif _c._options_idx == 1:
			_c._adjust_sfx_volume(-0.1)
			return true
		# (Controls: Reconfigure at idx 2 is action-only — Left/Right is a no-op.)
	elif event.is_action_pressed("ui_right", false):
		if _c._options_idx == 0:
			_c._adjust_music_volume(0.1)
			return true
		elif _c._options_idx == 1:
			_c._adjust_sfx_volume(0.1)
			return true
	elif event.is_action_pressed("ui_accept"):
		_c._toggle_option(_c._options_idx)
		return true
	elif event.is_action_pressed("ui_cancel"):
		_c._mode = PsoStartMenu.Mode.SYSTEM
		_c._sub_idx = 2
		return true
	return false


func _input_debug(event: InputEvent) -> bool:
	var items: Array = _c._get_debug_list()
	if event.is_action_pressed("ui_up", false) and items.size() > 0:
		_c._debug_idx = wrapi(_c._debug_idx - 1, 0, items.size())
		return true
	elif event.is_action_pressed("ui_down", false) and items.size() > 0:
		_c._debug_idx = wrapi(_c._debug_idx + 1, 0, items.size())
		return true
	elif event.is_action_pressed("ui_accept"):
		_c._toggle_debug(_c._debug_idx)
		return true
	elif event.is_action_pressed("ui_cancel"):
		_c._mode = PsoStartMenu.Mode.SYSTEM
		_c._sub_idx = 3
		return true
	return false


func _input_back(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		_c._mode = PsoStartMenu.Mode.MAIN
		return true
	return false

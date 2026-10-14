extends RefCounted
## Uses the start menu's existing modal ownership and input capture.
const Sets := preload("res://scripts/utils/equipment_sets.gd")

static func open(menu: Node, page: int = 0) -> void:
	var entries := Sets.list_sets()
	page = clampi(page, 0, maxi(0, (entries.size() - 1) / 3))
	var choices: Array = [{"label": "Save current equipment", "enabled": entries.size() < Sets.LIMIT}]
	var indices: Array = [-1]
	for index in range(page * 3, mini(page * 3 + 3, entries.size())):
		choices.append({"label": str(entries[index].name)})
		indices.append(index)
	if page > 0:
		choices.append({"label": "Previous page"})
		indices.append(-2)
	if page * 3 + 3 < entries.size():
		choices.append({"label": "Next page"})
		indices.append(-3)
	menu._open_choice("Equipment sets", choices, func(index):
		var selected: int = indices[index]
		if selected == -1: _name(menu, "", -1, false)
		elif selected == -2: open(menu, page - 1)
		elif selected == -3: open(menu, page + 1)
		else: _actions(menu, selected))

static func _actions(menu: Node, index: int) -> void:
	var entries := Sets.list_sets()
	if index >= entries.size(): return
	var label := str(entries[index].name)
	_choice(menu, label, ["Recall", "Replace with current equipment", "Rename", "Delete"], func(action):
		match action:
			0: _finish(menu, Sets.recall(index), true)
			1: _confirm(menu, index, label, false)
			2: _name(menu, label, index, true)
			3: _confirm(menu, index, label, true)
	)

static func _confirm(menu: Node, index: int, label: String, remove: bool) -> void:
	var verb := "Delete" if remove else "Replace"
	_choice(menu, "%s %s?" % [verb, label], ["Cancel", verb], func(answer):
		if answer == 1:
			_finish(menu, Sets.delete_set(index) if remove else Sets.save_set(label, index)))

static func _name(menu: Node, initial: String, index: int, rename: bool) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Name equipment set"
	dialog.ok_button_text = "Save"
	var edit := LineEdit.new()
	edit.name = "SetName"
	edit.placeholder_text = "Set name"
	edit.text = initial if not initial.is_empty() else "Set %d" % (Sets.list_sets().size() + 1)
	edit.max_length = 32
	edit.custom_minimum_size = Vector2(330, 40)
	dialog.add_child(edit)
	menu._active_modal = dialog
	menu.add_child(dialog)
	dialog.confirmed.connect(func():
		var result := Sets.rename_set(index, edit.text) if rename else Sets.save_set(edit.text, index)
		_finish(menu, result)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.tree_exited.connect(func():
		if menu._active_modal == dialog: menu._active_modal = null)
	edit.text_submitted.connect(func(_text): dialog.confirmed.emit())
	dialog.popup_centered(Vector2i(380, 130))
	edit.grab_focus()

static func _finish(menu: Node, outcome: Dictionary, refresh: bool = false) -> void:
	menu._action_message = outcome.message
	if outcome.success:
		if refresh:
			var player = menu.get_tree().get_first_node_in_group("player")
			if player:
				player.refresh_weapon()
				player.refresh_mag()
		SaveManager.save_game()
	menu._canvas.queue_redraw()
	if not outcome.success:
		_choice(menu, outcome.message, ["OK"], func(_index): pass)

static func _choice(menu: Node, prompt: String, labels: Array, action: Callable) -> void:
	menu._open_choice(prompt, labels.map(func(label): return {"label": label}), action)

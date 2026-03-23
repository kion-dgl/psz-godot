extends Control
## Mag List — shows all mags in inventory, marks equipped, opens feeder on select.

var _mags: Array = []  # Array of {id, name, level, form, equipped}
var _selected_index: int = 0

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var list_panel: PanelContainer = $Panel/VBox/HBox/ListPanel
@onready var detail_panel: PanelContainer = $Panel/VBox/HBox/DetailPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	PszStyle.style_menu(title_label, hint_label, [list_panel, detail_panel])
	title_label.text = "Mag"
	hint_label.text = "Up/Down: Select  Enter: Feed  Esc: Back"
	_refresh_mags()
	_refresh_display()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneManager.pop_scene()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected_index = wrapi(_selected_index - 1, 0, maxi(_mags.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_selected_index = wrapi(_selected_index + 1, 0, maxi(_mags.size(), 1))
		_refresh_display()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_open_feeder()
		get_viewport().set_input_as_handled()


func _refresh_mags() -> void:
	_mags.clear()
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var equipped_mag: String = str(character.get("equipment", {}).get("mag", ""))

	for item_id in Inventory._items:
		if not MagManager.is_mag(item_id):
			continue
		var mag_state: Dictionary = MagManager.get_mag_state(character, item_id)
		var form_id := "mag"
		var level := 0
		if not mag_state.is_empty():
			form_id = str(mag_state.get("form_id", "mag"))
			level = MagManager.get_level(mag_state)
		var form = MagManager.get_mag_form(form_id)
		var form_name: String = form.name if form else "Mag"
		_mags.append({
			"id": item_id,
			"name": form_name,
			"level": level,
			"form_id": form_id,
			"equipped": item_id == equipped_mag,
		})

	# Sort: equipped first, then by level descending
	_mags.sort_custom(func(a, b):
		if a.equipped != b.equipped:
			return a.equipped
		return int(a.level) > int(b.level)
	)


func _open_feeder() -> void:
	if _mags.is_empty() or _selected_index >= _mags.size():
		return
	var mag: Dictionary = _mags[_selected_index]
	SceneManager.push_scene("res://scenes/2d/mag_feeder.tscn", {"mag_id": mag.id})


func _notification(what: int) -> void:
	# Refresh when returning from feeder (mag may have leveled/evolved)
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_refresh_mags()
		_selected_index = clampi(_selected_index, 0, maxi(_mags.size() - 1, 0))
		_refresh_display()


func _refresh_display() -> void:
	_refresh_list()
	_refresh_detail()


func _refresh_list() -> void:
	for child in list_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	vbox.add_child(PszStyle.create_section_header("Mags (%d)" % _mags.size()))

	var selected_pill: Control = null

	if _mags.is_empty():
		vbox.add_child(PszStyle.create_pill("(No mags)", false, "", PszStyle.TEXT_MUTED))
	else:
		for i in range(_mags.size()):
			var mag: Dictionary = _mags[i]
			var equip_tag: String = " [E]" if mag.equipped else ""
			var display: String = "%s Lv.%d%s" % [mag.name, mag.level, equip_tag]
			var text_color := PszStyle.TEXT_HIGHLIGHT if mag.equipped else Color.TRANSPARENT
			var pill := PszStyle.create_pill(display, i == _selected_index, "", text_color)
			vbox.add_child(pill)
			if i == _selected_index:
				selected_pill = pill

	scroll.add_child(vbox)
	list_panel.add_child(scroll)

	if selected_pill != null:
		scroll.ensure_control_visible.call_deferred(selected_pill)


func _refresh_detail() -> void:
	for child in detail_panel.get_children():
		child.queue_free()

	if _mags.is_empty() or _selected_index >= _mags.size():
		return

	var mag: Dictionary = _mags[_selected_index]
	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var mag_state: Dictionary = MagManager.get_mag_state(character, mag.id)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	# Header
	vbox.add_child(PszStyle.detail_label("%s Lv.%d" % [mag.name, mag.level], PszStyle.TITLE_BG))
	if mag.equipped:
		vbox.add_child(PszStyle.detail_label("[Equipped]", PszStyle.TEXT_HIGHLIGHT))

	# Form info
	var form = MagManager.get_mag_form(mag.form_id)
	if form:
		vbox.add_child(PszStyle.detail_label("Stage %s" % str(form.stage)))
		if not str(form.photon_blast).is_empty() and str(form.photon_blast) != "None":
			vbox.add_child(PszStyle.detail_label("P. Blast: %s" % str(form.photon_blast), PszStyle.TEXT_SUCCESS))

	# Stats
	if not mag_state.is_empty():
		var stats: Dictionary = mag_state.get("stats", {})
		vbox.add_child(PszStyle.detail_label(""))
		for stat_key in ["power", "guard", "hit", "mind"]:
			var raw: int = int(stats.get(stat_key, 0))
			var stat_level: int = int(raw / MagManager.STATS_PER_LEVEL)
			var gauge: int = raw % MagManager.STATS_PER_LEVEL
			var gauge_str: String = "%d [%s%s]" % [stat_level, "|".repeat(gauge), ".".repeat(MagManager.STATS_PER_LEVEL - gauge)]
			vbox.add_child(PszStyle.detail_label("%s: %s" % [stat_key.substr(0, 3).to_upper(), gauge_str]))

		vbox.add_child(PszStyle.detail_label(""))
		vbox.add_child(PszStyle.detail_label("Sync: %d/%d" % [int(mag_state.get("sync", 0)), MagManager.MAX_SYNC]))
		vbox.add_child(PszStyle.detail_label("IQ: %d/%d" % [int(mag_state.get("iq", 0)), MagManager.MAX_IQ]))

		# Bonuses
		var bonuses: Dictionary = MagManager.get_stat_bonuses(mag_state)
		vbox.add_child(PszStyle.detail_label(""))
		vbox.add_child(PszStyle.detail_label("ATK +%d  DEF +%d" % [int(bonuses.get("attack", 0)), int(bonuses.get("defense", 0))], PszStyle.TEXT_SUCCESS))
		vbox.add_child(PszStyle.detail_label("ACC +%d  TEC +%d" % [int(bonuses.get("accuracy", 0)), int(bonuses.get("technique", 0))], PszStyle.TEXT_SUCCESS))

	detail_panel.add_child(vbox)

extends Control
## Mag Feeder — feed consumables to a mag, view stats and evolution.

const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")

var _mag_id: String = ""
var _feedable_items: Array = []  # Array of {id, name, effects}
var _selected_index: int = 0

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var feed_panel: PanelContainer = $Panel/VBox/HBox/FeedPanel
@onready var stats_panel: PanelContainer = $Panel/VBox/HBox/StatsPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	PszStyle.style_menu(title_label, hint_label, [feed_panel, stats_panel])
	var data: Dictionary = SceneManager.get_transition_data()
	_mag_id = str(data.get("mag_id", ""))
	if _mag_id.is_empty():
		title_label.text = "Mag Feeder"
		hint_label.text = "No mag selected!"
		return
	_refresh_feedable()
	_refresh_display()


func _unhandled_input(event: InputEvent) -> void:
	# sfx=false: these list screens predate the shop menu sfx convention.
	ShopNav.handle(self, event, {
		"sfx": false,
		"list_size": func() -> int: return _feedable_items.size(),
		"on_move": func(_old: int) -> void: _refresh_display(),
		"on_accept": _feed_selected,
	})


func _refresh_feedable() -> void:
	_feedable_items.clear()
	for item_id in Inventory._items:
		if MagManager.can_feed(item_id):
			var qty: int = int(Inventory._items[item_id])
			var info: Dictionary = Inventory._lookup_item(item_id)
			var effects: Dictionary = MagManager.FEED_EFFECTS.get(item_id, {})
			_feedable_items.append({"id": item_id, "name": info.name, "qty": qty, "effects": effects})


func _feed_selected() -> void:
	if _feedable_items.is_empty() or _selected_index >= _feedable_items.size():
		hint_label.text = "Nothing to feed!"
		return

	var character = CharacterManager.get_active_character()
	if character == null:
		return

	var mag_state: Dictionary = MagManager.get_mag_state(character, _mag_id)
	if mag_state.is_empty():
		hint_label.text = "Mag state not found!"
		return

	var item: Dictionary = _feedable_items[_selected_index]
	var item_id: String = item["id"]

	var result: Dictionary = MagManager.feed_mag(mag_state, item_id)
	if not result.get("success", false):
		hint_label.text = str(result.get("message", "Failed!"))
		return

	SfxManager.play("res://assets/sfx/ui/mag_feed.wav")

	# Consume the item
	Inventory.remove_item(item_id, 1)

	# Build result message
	var msg: String = "Fed %s!" % item["name"]
	if result.get("leveled_up", false):
		msg += " Level up! Lv.%d" % int(result.get("level_after", 0))
	if result.get("evolved", false):
		var new_form = MagManager.get_mag_form(str(result.get("form_after", "")))
		var new_name: String = new_form.name if new_form else str(result.get("form_after", ""))
		msg += " Evolved to %s!" % new_name
		# Refresh 3D mag model on player
		var player_node = get_tree().get_first_node_in_group("player")
		if player_node and player_node.has_method("refresh_mag"):
			player_node.refresh_mag()
	hint_label.text = msg

	_refresh_feedable()
	_selected_index = clampi(_selected_index, 0, maxi(_feedable_items.size() - 1, 0))
	_refresh_display()


func _refresh_display() -> void:
	var character = CharacterManager.get_active_character()
	var mag_state: Dictionary = {}
	if character:
		mag_state = MagManager.get_mag_state(character, _mag_id)

	var form_name := "Mag"
	var level := 0
	if not mag_state.is_empty():
		var form = MagManager.get_mag_form(mag_state.get("form_id", "mag"))
		form_name = form.name if form else "Mag"
		level = MagManager.get_level(mag_state)
	title_label.text = "%s Lv.%d" % [form_name, level]
	if hint_label.text.is_empty():
		hint_label.text = "Up/Down: Select  Enter: Feed  Esc: Back"

	_refresh_feed_list()
	_refresh_stats_panel(mag_state)


func _refresh_feed_list() -> void:
	for child in feed_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	vbox.add_child(PszStyle.create_section_header("Feed Items"))

	var selected_pill: Control = null

	if _feedable_items.is_empty():
		vbox.add_child(PszStyle.create_pill("(No feedable items)", false, "", PszStyle.TEXT_MUTED))
	else:
		for i in range(_feedable_items.size()):
			var item: Dictionary = _feedable_items[i]
			var effects: Dictionary = item.get("effects", {})
			var effect_parts: Array = []
			for stat_key in ["power", "guard", "hit", "mind"]:
				var val: int = int(effects.get(stat_key, 0))
				if val > 0:
					effect_parts.append("%s+%d" % [stat_key.substr(0, 3).to_upper(), val])
			var effect_str: String = " ".join(effect_parts)
			var display: String = "%s x%d" % [item["name"], int(item["qty"])]
			var pill := PszStyle.create_pill(display, i == _selected_index, effect_str)
			vbox.add_child(pill)
			if i == _selected_index:
				selected_pill = pill

	scroll.add_child(vbox)
	feed_panel.add_child(scroll)

	if selected_pill != null:
		scroll.ensure_control_visible.call_deferred(selected_pill)


func _refresh_stats_panel(mag_state: Dictionary) -> void:
	for child in stats_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	vbox.add_child(PszStyle.create_section_header("Mag Stats"))

	if mag_state.is_empty():
		vbox.add_child(PszStyle.create_pill("No mag data", false, "", PszStyle.TEXT_MUTED))
		scroll.add_child(vbox)
		stats_panel.add_child(scroll)
		return

	var stats: Dictionary = mag_state.get("stats", {})
	var level: int = MagManager.get_level(mag_state)

	# Overall level
	vbox.add_child(PszStyle.create_pill("Level", false, str(level)))

	# Individual stats with gauge (raw / 5 = stat level, raw % 5 = gauge progress)
	var stat_keys := ["power", "guard", "hit", "mind"]
	var stat_names := ["POW", "GRD", "HIT", "MND"]
	for i in range(stat_keys.size()):
		var raw: int = int(stats.get(stat_keys[i], 0))
		var stat_level: int = int(raw / MagManager.STATS_PER_LEVEL)
		var gauge: int = raw % MagManager.STATS_PER_LEVEL
		var gauge_str: String = "%d [%s%s]" % [stat_level, "|".repeat(gauge), ".".repeat(MagManager.STATS_PER_LEVEL - gauge)]
		vbox.add_child(PszStyle.create_pill(stat_names[i], false, gauge_str))

	# Sync and IQ
	vbox.add_child(PszStyle.create_pill("Sync", false, "%d/%d" % [int(mag_state.get("sync", 0)), MagManager.MAX_SYNC]))
	vbox.add_child(PszStyle.create_pill("IQ", false, "%d/%d" % [int(mag_state.get("iq", 0)), MagManager.MAX_IQ]))

	# Form info
	var form_id: String = str(mag_state.get("form_id", "mag"))
	var form = MagManager.get_mag_form(form_id)
	if form:
		vbox.add_child(PszStyle.create_section_header("Form"))
		vbox.add_child(PszStyle.create_pill("Name", false, form.name))
		vbox.add_child(PszStyle.create_pill("Stage", false, str(form.stage)))
		if not str(form.photon_blast).is_empty():
			vbox.add_child(PszStyle.create_pill("P. Blast", false, str(form.photon_blast), PszStyle.TEXT_SUCCESS))

	# Stat bonuses preview
	var bonuses: Dictionary = MagManager.get_stat_bonuses(mag_state)
	vbox.add_child(PszStyle.create_section_header("Bonuses"))
	vbox.add_child(PszStyle.create_pill("ATK", false, "+%d" % int(bonuses.get("attack", 0)), PszStyle.TEXT_SUCCESS))
	vbox.add_child(PszStyle.create_pill("DEF", false, "+%d" % int(bonuses.get("defense", 0)), PszStyle.TEXT_SUCCESS))
	vbox.add_child(PszStyle.create_pill("ACC", false, "+%d" % int(bonuses.get("accuracy", 0)), PszStyle.TEXT_SUCCESS))
	vbox.add_child(PszStyle.create_pill("TEC", false, "+%d" % int(bonuses.get("technique", 0)), PszStyle.TEXT_SUCCESS))

	scroll.add_child(vbox)
	stats_panel.add_child(scroll)

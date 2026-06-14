extends Control
## Photon Collector — trade Photon Drops for grinders, photon crystals, and materials.

const SHOP_PREVIEW_PATH := "res://assets/ui/shop-previews/photon-collector.png"
const ShopNav := preload("res://scripts/2d/shops/shop_nav.gd")

const EXCHANGE_ITEMS := [
	{"name": "Monogrinder", "id": "monogrinder", "cost": 1, "category": "Grinders"},
	{"name": "Digrinder", "id": "digrinder", "cost": 3, "category": "Grinders"},
	{"name": "Trigrinder", "id": "trigrinder", "cost": 5, "category": "Grinders"},
	{"name": "Im Photon", "id": "im_photon", "cost": 1, "category": "Photon Crystals"},
	{"name": "El Photon", "id": "el_photon", "cost": 3, "category": "Photon Crystals"},
	{"name": "Ban Photon", "id": "ban_photon", "cost": 2, "category": "Photon Crystals"},
	{"name": "Ray Photon", "id": "ray_photon", "cost": 2, "category": "Photon Crystals"},
	{"name": "Zon Photon", "id": "zon_photon", "cost": 2, "category": "Photon Crystals"},
	{"name": "Megi Photon", "id": "megi_photon", "cost": 2, "category": "Photon Crystals"},
	{"name": "Gra Photon", "id": "gra_photon", "cost": 2, "category": "Photon Crystals"},
	{"name": "Grinder Base C", "id": "grinder_base_c", "cost": 3, "category": "Materials"},
	{"name": "Grinder Base B", "id": "grinder_base_b", "cost": 5, "category": "Materials"},
	{"name": "Grinder Base A", "id": "grinder_base_a", "cost": 8, "category": "Materials"},
	{"name": "Mag", "id": "debug_mag", "cost": 0, "category": "Debug Mag"},
	{"name": "Mag POW +50", "id": "debug_mag_power", "cost": 0, "category": "Debug Mag"},
	{"name": "Mag GRD +50", "id": "debug_mag_guard", "cost": 0, "category": "Debug Mag"},
	{"name": "Mag HIT +50", "id": "debug_mag_hit", "cost": 0, "category": "Debug Mag"},
	{"name": "Mag MND +50", "id": "debug_mag_mind", "cost": 0, "category": "Debug Mag"},
]

var _selected_index: int = 0
var _mode_bar_parent: Control
var _tab_row: HBoxContainer
var _detail_panel: PanelContainer
var _active_modal: Control = null

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var mode_label: Label = $Panel/VBox/ModeLabel
@onready var content_panel: PanelContainer = $Panel/VBox/ContentPanel
@onready var hint_label: Label = $Panel/VBox/HintLabel


func _ready() -> void:
	_mode_bar_parent = mode_label.get_parent()
	PszStyle.style_menu(title_label, hint_label, [content_panel])
	title_label.text = "Photon Collector"
	_setup_portrait()
	hint_label.text = "Up/Down: Select  Enter: Exchange  Esc: Leave"
	_refresh_display()
	ShopPreviewSprite.attach(self, SHOP_PREVIEW_PATH)


func _setup_portrait() -> void:
	# Shared layout: list left (3/5), detail card top-right (2/5) stopping 10px
	# above the portrait — same scaffold as every other shop.
	_detail_panel = PszStyle.setup_shop_portrait($Panel, null, SHOP_PREVIEW_PATH)


func _unhandled_input(event: InputEvent) -> void:
	ShopNav.handle(self, event, {
		"modal": _active_modal,
		"list_size": func() -> int: return EXCHANGE_ITEMS.size(),
		"on_move": func(_old: int) -> void: _refresh_display(),
		"on_accept": _open_confirm_modal,
	})


func _open_confirm_modal() -> void:
	var item_v: Variant = ShopNav.selected_item(self, EXCHANGE_ITEMS)
	if item_v == null:
		return
	var item: Dictionary = item_v
	var cost: int = int(item["cost"])
	var item_name: String = item["name"]

	# Pre-flight checks so the modal isn't a dead-end. Mirrors the bail
	# paths in _exchange_selected so the user never sees a confirm for an
	# action that can't go through. Opens an info modal so the failure
	# is unmissable rather than a silent hint_label update.
	var pd_count: int = Inventory.get_item_count("photon_drop")
	if pd_count < cost:
		_open_info_modal("Not enough Photon Drops! Need %d" % cost)
		return
	var item_id: String = item["id"]
	if not item_id.begins_with("debug_mag") and not Inventory.can_add_item(item_id):
		_open_info_modal("Inventory full!")
		return

	var prompt: String
	if cost > 0:
		prompt = "Exchange %d Photon Drop%s for %s?" % [cost, "" if cost == 1 else "s", item_name]
	else:
		# debug_mag freebies — no PD spend
		prompt = "Take %s?" % item_name

	ShopNav.confirm(self, prompt, _exchange_selected)


## Open a single-button info modal for blocking error states (not enough
## photon drops, inventory full, etc.) so the failure is unmissable.
func _open_info_modal(msg: String) -> void:
	hint_label.text = msg
	ShopNav.info(self, msg)


func _exchange_selected() -> void:
	if _selected_index >= EXCHANGE_ITEMS.size():
		return

	var item: Dictionary = EXCHANGE_ITEMS[_selected_index]
	var cost: int = int(item["cost"])
	var item_id: String = item["id"]
	var item_name: String = item["name"]

	var pd_count: int = Inventory.get_item_count("photon_drop")
	if pd_count < cost:
		hint_label.text = "Not enough Photon Drops! Need %d" % cost
		return

	# Handle debug mag items
	if item_id.begins_with("debug_mag"):
		_handle_debug_mag(item_id, item_name, cost)
		return

	if not Inventory.can_add_item(item_id):
		hint_label.text = "Inventory full!"
		return

	Inventory.remove_item("photon_drop", cost)
	Inventory.add_item(item_id, 1)
	hint_label.text = "Exchanged %d Photon Drops for %s!" % [cost, item_name]
	_refresh_display()


func _handle_debug_mag(item_id: String, item_name: String, cost: int) -> void:
	var character = CharacterManager.get_active_character()
	if character == null:
		hint_label.text = "No active character!"
		return

	if item_id == "debug_mag":
		# Give a fresh base mag (special: needs mag_state)
		if not character.has("mag_states"):
			character["mag_states"] = {}
		var inst_id: String = MagManager.add_mag_to_character(character, "mag")
		if inst_id.is_empty():
			hint_label.text = "Inventory full!"
		else:
			if cost > 0:
				Inventory.remove_item("photon_drop", cost)
			hint_label.text = "Received a new Mag!"
		_refresh_display()
		return

	# Stat boost items — add to inventory as consumable items
	if not Inventory.can_add_item(item_id):
		hint_label.text = "Inventory full!"
		return
	if cost > 0:
		Inventory.remove_item("photon_drop", cost)
	Inventory.add_item(item_id, 1)
	hint_label.text = "Purchased %s! Feed it to your mag." % item_name
	_refresh_display()


func _refresh_display() -> void:
	mode_label.visible = false

	if not is_instance_valid(_tab_row):
		_tab_row = HBoxContainer.new()
		_tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_tab_row.add_theme_constant_override("separation", 8)
		_mode_bar_parent.add_child(_tab_row)
		_mode_bar_parent.move_child(_tab_row, mode_label.get_index() + 1)
	for child in _tab_row.get_children():
		child.queue_free()

	var pd_count: int = Inventory.get_item_count("photon_drop")
	var pd_label := Label.new()
	pd_label.text = "Photon Drops: %d" % pd_count
	pd_label.add_theme_color_override("font_color", PszStyle.TEXT_HIGHLIGHT)
	pd_label.add_theme_font_size_override("font_size", PszStyle.FONT_TAB)
	pd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tab_row.add_child(pd_label)

	for child in content_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)

	var selected_pill: Control = null
	var last_category: String = ""

	for i in range(EXCHANGE_ITEMS.size()):
		var item: Dictionary = EXCHANGE_ITEMS[i]
		var category: String = item["category"]
		var cost: int = int(item["cost"])

		if category != last_category:
			last_category = category
			vbox.add_child(PszStyle.create_section_header(category))

		var can_afford: bool = pd_count >= cost

		var held: int = Inventory.get_item_count(item["id"])
		var held_str: String = " (x%d)" % held if held > 0 else ""

		var item_icon: Texture2D = InventoryIcons.for_item(str(item["id"]))
		var icons: Array = [item_icon] if item_icon else []
		# Unified shop row (#368): grey (not red) when the player can't afford.
		# This is a list-only shop, so the held count stays in the row label.
		var pill := PszStyle.shop_row("%s%s" % [item["name"], held_str], "%d PD" % cost, {
			"icons": icons,
			"affordable": can_afford,
			"selected": i == _selected_index,
		})
		vbox.add_child(pill)
		if i == _selected_index:
			selected_pill = pill

	scroll.add_child(vbox)
	content_panel.add_child(scroll)

	if selected_pill != null:
		scroll.ensure_control_visible.call_deferred(selected_pill)

	_refresh_detail()


## Render the selected exchange item into the shared right-column detail card —
## category, photon-drop cost, held count, and the can't-afford reason.
func _refresh_detail() -> void:
	if not is_instance_valid(_detail_panel):
		return
	PszStyle.clear_detail_panel(_detail_panel)
	if _selected_index < 0 or _selected_index >= EXCHANGE_ITEMS.size():
		return

	var item: Dictionary = EXCHANGE_ITEMS[_selected_index]
	var cost: int = int(item["cost"])
	var pd_count: int = Inventory.get_item_count("photon_drop")
	var held: int = Inventory.get_item_count(item["id"])

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.add_child(PszStyle.detail_label(str(item["name"]), PszStyle.TITLE_BG))
	vbox.add_child(PszStyle.detail_label("Category: %s" % str(item["category"])))
	var cost_text: String = "Free" if cost == 0 else "%d Photon Drop%s" % [cost, "" if cost == 1 else "s"]
	vbox.add_child(PszStyle.detail_label("Cost: %s" % cost_text, PszStyle.TEXT_HIGHLIGHT))
	vbox.add_child(PszStyle.detail_label("You have: %d" % held))
	if cost > 0 and pd_count < cost:
		vbox.add_child(PszStyle.detail_label("Not enough Photon Drops", PszStyle.TEXT_WARNING))
	_detail_panel.add_child(vbox)


# ── Hold-to-repeat navigation (NavRepeat) ──────────────────────────────────────
var _nav: NavRepeat = null


func _process(delta: float) -> void:
	# Modal owns input + nav while open.
	if is_instance_valid(_active_modal):
		return
	if _nav == null:
		_nav = NavRepeat.new(["ui_up", "ui_down", "ui_left", "ui_right"], _on_nav_repeat)
	_nav.tick(delta)

# --- Shop scaffolding, inlined. These screens are standalone (extends Control)
# --- rather than sharing a ShopBase: a cross-script base class fails to
# --- resolve in the Android export at runtime (works in-editor and on every
# --- other platform). See the shop-dedup tracker.

## NavRepeat callback: re-emit a held nav action as a synthetic input event
## so this screen's own _unhandled_input handles it (hold-to-repeat nav).
func _on_nav_repeat(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_unhandled_input(ev)


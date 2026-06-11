# Shared shop-screen UI scaffolding — composition, NOT a base class.
#
# A cross-script `ShopBase` base class fails to resolve at runtime in the
# Android export when a shop screen is lazily loaded (every shop became
# unopenable on device; see commit dda43246 + docs/shop-dedup.md). So shared
# shop behavior lives in preloaded static helpers instead of inheritance.
# Deliberately NO `class_name` and consumers `preload()` it, so the dependency
# is embedded in each shop script rather than resolved via the global class
# registry.


## Restructure a shop screen's `$Panel` into the standard two-column layout:
## a styled panel whose content VBox sits on the left (stretch 3) and an empty
## right column (stretch 2) that the shop-preview overlay attaches into.
## Byte-identical across photon_shop / crafting_shop before this lift (#274 inc 5).
static func setup_portrait(owner: Control) -> void:
	var panel: PanelContainer = owner.get_node("Panel")
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	var fs := StyleBoxFlat.new()
	fs.bg_color = PszStyle.BG
	fs.content_margin_left = 12.0
	fs.content_margin_top = 8.0
	fs.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", fs)

	var vbox := panel.get_child(0) as VBoxContainer
	panel.remove_child(vbox)
	var outer := HBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_stretch_ratio = 3.0
	outer.add_child(vbox)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 2.0
	right.add_theme_constant_override("separation", 0)
	# Right column intentionally empty — shop preview is added separately
	# as an absolute overlay (see ShopPreviewSprite.attach below).
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	outer.add_child(right)
	panel.add_child(outer)

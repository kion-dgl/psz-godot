class_name ShopPreviewSprite extends RefCounted
## Helper that attaches a fixed-size shop-preview TextureRect to the
## bottom-right corner of a shop's Control root. Each shop (item, weapon,
## synth, photon, tekker, guild counter, storage) calls
## `ShopPreviewSprite.attach(self, PATH_TO_PREVIEW_PNG)` from _ready()
## to show its corresponding preview art (real call site picks the
## specific path under assets/images/).
##
## Render order: the sprite is added LAST so it draws on top of the shop's
## existing panels. mouse_filter is IGNORE so it doesn't intercept clicks.

const PREVIEW_SIZE := Vector2(180, 180)
const PREVIEW_MARGIN := Vector2(20, 20)


static func attach(parent: Control, texture_path: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.name = "ShopPreview"
	tr.texture = load(texture_path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	tr.custom_minimum_size = PREVIEW_SIZE
	tr.size = PREVIEW_SIZE
	tr.position = Vector2(-PREVIEW_SIZE.x - PREVIEW_MARGIN.x, -PREVIEW_SIZE.y - PREVIEW_MARGIN.y)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)
	return tr

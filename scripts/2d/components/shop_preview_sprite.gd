class_name ShopPreviewSprite extends RefCounted
## Absolutely-positioned shop preview overlay. Each shop calls
## `ShopPreviewSprite.attach(self, "res://assets/ui/shop-previews/<name>.png")`
## from _ready() — produces a TextureRect anchored to the bottom-right of
## the shop's Control with `right: 5px, bottom: 0px` and the texture's
## native aspect ratio (no stretch).
##
## The shop's own layout below is unaffected; the preview just floats
## above the bottom-right corner.

# Position offsets relative to the parent's bottom-right corner. Tuned
# by hand on the Retroid Pocket 3+ display:
#   RIGHT_INSET  — how far INSIDE the parent's right edge to draw (25 px)
#   BOTTOM_PUSH  — how far BELOW the parent's bottom edge to extend
#                  (100 px; the parent Control doesn't actually reach the
#                  physical screen bottom on this device, so we push past it)
const RIGHT_INSET := 25
const BOTTOM_PUSH := 100
# Rounded top corners only (bottom stays flush against the screen edge).
const CORNER_RADIUS := 18.0
# 256×256 sources scale × 1.8 → ~461×461 visible. Both axes scale
# together so aspect is preserved.
const SCALE_FACTOR := 1.8
# Gap kept between the bottom of a shop's detail card and the top of the
# portrait, so the card doesn't run flush into the artwork (#368).
const DETAIL_GAP := 10
# The detail column's bottom sits this far above the parent Control's bottom
# (the shop panel's content_margin_bottom — see setup_shop_portrait).
const COLUMN_BOTTOM_INSET := 8


## How much vertical space the detail card must leave free at the bottom of the
## right column so it ends DETAIL_GAP px above the portrait. The portrait is an
## absolute overlay whose top sits (sz.y - BOTTOM_PUSH) px above the parent's
## bottom; the column bottom sits COLUMN_BOTTOM_INSET px above it. Shops pass
## this as a fixed-height bottom spacer in the detail column.
static func detail_reserve_height(texture_path: String) -> float:
	var tex: Texture2D = load(texture_path) if texture_path != "" else null
	var natural := tex.get_size() if tex else Vector2(256, 256)
	var sz := natural * SCALE_FACTOR
	return maxf(0.0, sz.y - float(BOTTOM_PUSH) + float(DETAIL_GAP) - float(COLUMN_BOTTOM_INSET))


static func attach(parent: Control, texture_path: String) -> TextureRect:
	var tex: Texture2D = load(texture_path)
	var rect := TextureRect.new()
	rect.name = "ShopPreview"
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# All four anchors at the parent's bottom-right corner; offsets
	# compute the final rect relative to that anchor.
	rect.anchor_left = 1.0
	rect.anchor_top = 1.0
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	var natural := tex.get_size() if tex else Vector2(256, 256)
	var sz := natural * SCALE_FACTOR
	rect.offset_right = -float(RIGHT_INSET)
	rect.offset_bottom = float(BOTTOM_PUSH)
	rect.offset_left = -sz.x - float(RIGHT_INSET)
	rect.offset_top = -sz.y + float(BOTTOM_PUSH)

	# Rounded top corners (top-left + top-right). Bottom corners stay
	# sharp because the bottom is flush against the screen edge — no
	# point rounding what can't be seen.
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float radius = 18.0;
void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 px = UV * size;
	vec2 tl = vec2(radius, radius);
	vec2 tr = vec2(size.x - radius, radius);
	float d = 0.0;
	if (px.x < radius && px.y < radius) {
		d = distance(px, tl) - radius;
	} else if (px.x > size.x - radius && px.y < radius) {
		d = distance(px, tr) - radius;
	}
	vec4 col = texture(TEXTURE, UV);
	COLOR = vec4(col.rgb, col.a * (1.0 - clamp(d, 0.0, 1.0)));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("radius", CORNER_RADIUS)
	rect.material = mat

	parent.add_child(rect)
	return rect

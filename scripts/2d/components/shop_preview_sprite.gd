class_name ShopPreviewSprite extends RefCounted
## Disabled: the diegetic 3D shop view renders the real shopkeeper NPC behind
## the menu overlay, so the old 2D preview sprite is redundant and would
## double-draw over the live scene. `attach()` is kept as a no-op (rather than
## editing all seven shop call sites) — the original absolute-overlay
## implementation is in git history if the 2D portrait ever needs restoring.
static func attach(_parent: Control, _texture_path: String) -> TextureRect:
	return null

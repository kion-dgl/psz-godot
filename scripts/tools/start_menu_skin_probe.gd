extends Control
## Start-menu MAIN skin probe — stages a HUcast, opens PsoStartMenu and dumps
## screenshots so the Flauros redesign (skeleton/game_menu_redesign/) can be
## eyeballed without playing to a field first. Launch with:
##
##     godot --path . res://scripts/tools/start_menu_skin_probe.tscn
##
## Writes /tmp/menu_skin_p0.png (MAIN, page 1), /tmp/menu_skin_p2.png (page 3)
## and /tmp/menu_skin_sub.png (Items sub-mode, legacy look) then quits.

const SHOTS := [
	{"path": "/tmp/menu_skin_p0.png", "page": 0, "delay": 2.2},
	{"path": "/tmp/menu_skin_p2.png", "page": 2, "delay": 0.6},
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.18, 0.3)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Wipe slots first — the dev userdir may carry an older character, and
	# create_character refuses to clobber an occupied slot (same staging
	# pattern as the headless test runner).
	CharacterManager._characters = [null, null, null, null]
	CharacterManager._active_slot = -1
	var created = CharacterManager.create_character(0, "hucast", "Flauros")
	CharacterManager.set_active_slot(0)
	var ch: Dictionary = CharacterManager.get_active_character()
	print("[skin-probe] created=%s active=%s class=%s" % [created != null, ch != null, ch.get("class_id", "?")])
	ch["level"] = 60
	ch["experience"] = 567644
	ch["meseta"] = 56558
	ch["hp"] = 780

	PsoStartMenu.open()
	await _shoot(SHOTS[0])
	PsoStartMenu._info_page = 2
	await _shoot(SHOTS[1])
	# Sub-mode keeps the legacy renderer look — capture that boundary too.
	PsoStartMenu._enter_sub(0)
	await _shoot({"path": "/tmp/menu_skin_sub.png", "page": -1, "delay": 0.5})
	PsoStartMenu.close()
	get_tree().quit()


func _shoot(shot: Dictionary) -> void:
	await get_tree().create_timer(shot.delay).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(str(shot.path))
	# Round-3 samples: selected-row gradient direction (two x on one row),
	# bottom-left seam (single style), band body vs far-right fade, open area.
	for sample in [[40, 138], [140, 138], [80, 500], [900, 650], [1230, 700], [640, 360]]:
		print("[skin-probe] px(%d,%d)=%s" % [sample[0], sample[1], img.get_pixel(sample[0], sample[1]).to_html(false)])
	print("[skin-probe] wrote %s" % shot.path)

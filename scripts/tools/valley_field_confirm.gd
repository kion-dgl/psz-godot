extends Node3D
## Valley field confirm (#648): boots the REAL field controller — not the lab
## approximation — into a fresh free-roam expedition, one section per variant:
## A (grid), B (grid), E (transition), Z (boss arena). Everything the branch
## touches ships in that path: the slot apply, the shell carve-out, the
## panorama shadow-eye placement, the anchors, the blob-shadow skip, sand.
##
## The entry sequence is warp_teleporter._enter_fresh_field verbatim
## (enter_field → GridGenerator.generate_field → set_field_sections → the
## field scene's transition data); the field scene is instantiated as a child
## so N can cycle variants without quitting. Generated fields roll fresh
## rooms each run — the R key re-rolls the whole expedition.
##
## Env:  PSZ_FIELD_CONFIRM=a|b|e|z   boot variant (default a)
##       PSZ_FIELD_SUN_POS=x,y,z    pin the sun node's position — the compat
##                                   shadow eye (probe-scene PROBE_LIGHT_POS
##                                   pattern; harness-only, never ships)
##       PSZ_WALK_SHOT=/tmp/o.png    screenshot + quit smoke (FieldLab.ShotRun)
## Keys: N next variant (A→B→E→Z) · R re-roll the expedition · ESC quit

const FIELD_SCENE := preload("res://scenes/3d/field/valley_field.tscn")
const GridGenerator := preload("res://scripts/3d/field/grid_generator.gd")
const FieldSlotTableScript := preload("res://scripts/3d/field/field_slot_table.gd")
const FieldLabScript := preload("res://scripts/tools/field_lab.gd")

## N walks the letters in reading order; a generated expedition lays its
## sections out as [a-grid, e-transition, b-grid, z-boss] — the map picks
## each letter's section.
const VARIANT_ORDER := ["a", "b", "e", "z"]
const SECTION_FOR := {"a": 0, "b": 2, "e": 1, "z": 3}

var _sections: Array = []
var _variant := "a"
var _field: Node = null
var _shot := FieldLabScript.ShotRun.new()
var _label: Label


func _ready() -> void:
	var boot := OS.get_environment("PSZ_FIELD_CONFIRM")
	_variant = boot if SECTION_FOR.has(boot) else "a"
	_shot.path = OS.get_environment("PSZ_WALK_SHOT")
	_build_label()
	_roll_expedition()
	_enter_variant(_variant)


func _process(_delta: float) -> void:
	_shot.step(self, "FieldConfirm")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_N:
			_enter_variant(VARIANT_ORDER[(VARIANT_ORDER.find(_variant) + 1) % VARIANT_ORDER.size()])
		KEY_R:
			_roll_expedition()
			_enter_variant(_variant)


## A fresh expedition, the production free-field sequence.
func _roll_expedition() -> void:
	SessionManager.enter_field("gurhacia", "normal")
	_sections = GridGenerator.new().generate_field("normal", "gurhacia")["sections"]
	SessionManager.set_field_sections(_sections)


## Swap the field child to a variant's section start. The transition data is
## the fresh-entry shape (empty keys/state — every entry is a first visit).
func _enter_variant(variant: String) -> void:
	_variant = variant
	var idx: int = SECTION_FOR[variant]
	SessionManager.set_current_section(idx)
	var section: Dictionary = _sections[idx]
	var start_pos := str(section.get("start_pos", ""))
	var start_cell: Dictionary = {}
	for cell in section.get("cells", []):
		if str(cell.get("pos", "")) == start_pos:
			start_cell = cell
			break
	if is_instance_valid(_field):
		_field.queue_free()
	SceneManager._transition_data = {
		"current_cell_pos": start_pos,
		"spawn_edge": "",
		"keys_collected": {},
	}
	_field = FIELD_SCENE.instantiate()
	add_child(_field)

	var stage_id := str(start_cell.get("stage_id", "?"))
	var slot := FieldSlotTableScript.slot_for("gurhacia", stage_id)
	print("[FieldConfirm] variant %s (section %d %s): %s — hour %.0f  sun %.2f  ambient %.2f  pitch %.0f°  bake %.2f  shadows %s" % [
		variant.to_upper(), idx, str(section.get("type", "?")), stage_id,
		float(slot.get("hour", 10.0)), float(slot.get("sun_energy", 0.0)),
		float(slot.get("ambient_energy", 0.0)), float(slot.get("sun_pitch", 0.0)),
		float(slot.get("bake_mix", 0.0)),
		"sun+geometry" if slot.get("sun_shadows", false) else "off"])
	_label.text = "%s · %s — sun %.2f / ambient %.2f @ %.0f°  ·  N next  ·  R re-roll" % [
		variant.to_upper(), stage_id,
		float(slot.get("sun_energy", 0.0)), float(slot.get("ambient_energy", 0.0)),
		float(slot.get("sun_pitch", 0.0))]
	_settle_eye()


## Panorama placement + the row's rim pull land a frame AFTER field entry
## (the controller's post-await pass) — anything applied at add_child time
## gets overwritten. Settle two frames, log the eye the row produced, then
## apply the env pin last so it wins.
func _settle_eye() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var light := _field.get("_dir_light") as DirectionalLight3D
	if light == null:
		return
	var slot: Dictionary = _field.get("_slot")
	if slot.get("sun_shadows", false) or slot.get("moon_shadows", false):
		print("[FieldConfirm] eye (placement + row pull) at %s" % [light.global_position])
	var sun_pos := OS.get_environment("PSZ_FIELD_SUN_POS")
	if sun_pos.is_empty():
		return
	var parts := sun_pos.split(",")
	if parts.size() == 3:
		light.global_position = Vector3(
			float(parts[0]), float(parts[1]), float(parts[2]))
		print("[FieldConfirm] sun eye pinned at %s (post-placement)" % [light.global_position])


func _build_label() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 200  # above the field's own HUD + map overlay
	canvas.name = "ConfirmLabel"
	add_child(canvas)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_font_size_override("font_size", 18)
	canvas.add_child(_label)

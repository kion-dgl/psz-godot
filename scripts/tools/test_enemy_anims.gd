extends Node
## Headless storybook for enemies. Tests both enemy code paths:
##   1. EnemySpawn (data/enemies.json) — used by quest grid cells
##   2. EnemyBase + .tres (data/enemies/*.tres) — used by field exploration
## Plays every animation and reports unresolved tracks or missing players.
## Run: godot --headless res://scripts/tools/test_enemy_anims.tscn

var _broken: Array = []
var _ok_count: int = 0
var _total: int = 0


func _ready() -> void:
	print("\n══════ EnemySpawn (enemies.json) ══════")
	_test_enemy_spawn_path()
	print("\n══════ EnemyBase (.tres files) ══════")
	_test_enemy_base_path()
	_print_summary()
	get_tree().quit()


func _test_enemy_spawn_path() -> void:
	# Pull every model_id from enemies.json
	var fa := FileAccess.open("res://data/enemies.json", FileAccess.READ)
	if not fa:
		push_error("enemies.json not found")
		return
	var json := JSON.new()
	if json.parse(fa.get_as_text()) != OK:
		push_error("failed to parse enemies.json")
		return
	fa.close()

	var seen_models: Dictionary = {}
	for entry in json.data:
		var mid: String = str(entry.get("model_id", ""))
		if mid.is_empty() or seen_models.has(mid):
			continue
		seen_models[mid] = true

	var model_ids := seen_models.keys()
	model_ids.sort()
	print("Testing %d unique enemy models via EnemySpawn" % model_ids.size())

	for mid: String in model_ids:
		_test_model(mid)


func _test_enemy_base_path() -> void:
	# Walk data/enemies/*.tres
	var dir := DirAccess.open("res://data/enemies")
	if not dir:
		push_error("data/enemies not found")
		return
	dir.list_dir_begin()
	var tres_files: Array = []
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname.ends_with(".tres"):
			tres_files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	tres_files.sort()
	print("Testing %d enemy resources via EnemyBase" % tres_files.size())

	for f: String in tres_files:
		_test_tres("res://data/enemies/" + f)


func _test_model(model_id: String) -> void:
	_total += 1
	var glb_path := "res://assets/enemies/%s/%s.glb" % [model_id, model_id]
	if not ResourceLoader.exists(glb_path):
		_broken.append({"id": model_id, "issue": "GLB not found"})
		return

	# Use real EnemySpawn so we test the actual code path
	var spawn := EnemySpawn.new()
	spawn.enemy_id = model_id
	spawn.use_registry_hp = false
	add_child(spawn)

	# Find AnimationPlayer
	var ap: AnimationPlayer = _find_ap(spawn)
	if not ap:
		_broken.append({"id": model_id, "issue": "no AnimationPlayer"})
		spawn.queue_free()
		return

	if ap.get_animation_list().size() == 0:
		_broken.append({"id": model_id, "issue": "AnimationPlayer has 0 animations"})
		spawn.queue_free()
		return

	# Actually play every animation to trigger _update_caches and surface runtime warnings
	var anim_root := ap.get_node_or_null(ap.root_node)
	var bad_anims: Array = []
	for anim_name: String in ap.get_animation_list():
		var anim := ap.get_animation(anim_name)
		var bad_tracks: Array = []
		for i in range(anim.get_track_count()):
			var tp := anim.track_get_path(i)
			var target = anim_root.get_node_or_null(tp) if anim_root else null
			if not target:
				var s := str(tp)
				if s not in bad_tracks:
					bad_tracks.append(s)
		# Force AP to bind/cache this animation, which is what surfaces runtime warnings
		ap.play(anim_name)
		ap.advance(0.0)
		if bad_tracks.size() > 0:
			bad_anims.append({"anim": anim_name, "bad": bad_tracks})

	if bad_anims.size() > 0:
		_broken.append({"id": model_id, "issue": "broken tracks", "details": bad_anims})
	else:
		_ok_count += 1

	spawn.queue_free()


func _test_tres(tres_path: String) -> void:
	_total += 1
	var data := load(tres_path)
	if not data:
		_broken.append({"id": tres_path, "issue": "failed to load .tres"})
		return
	var label: String = "%s (%s)" % [data.id, data.model_id]

	var enemy := EnemyBase.new()
	enemy.enemy_data = data
	add_child(enemy)

	var ap: AnimationPlayer = enemy.animation_player
	if not ap:
		_broken.append({"id": label, "issue": "no AnimationPlayer"})
		enemy.queue_free()
		return
	if ap.get_animation_list().size() == 0:
		_broken.append({"id": label, "issue": "0 animations"})
		enemy.queue_free()
		return

	var anim_root := ap.get_node_or_null(ap.root_node)
	var bad_anims: Array = []
	for anim_name: String in ap.get_animation_list():
		var anim := ap.get_animation(anim_name)
		var bad_tracks: Array = []
		for i in range(anim.get_track_count()):
			var tp := anim.track_get_path(i)
			var target = anim_root.get_node_or_null(tp) if anim_root else null
			if not target:
				var s := str(tp)
				if s not in bad_tracks:
					bad_tracks.append(s)
		ap.play(anim_name)
		ap.advance(0.0)
		if bad_tracks.size() > 0:
			bad_anims.append({"anim": anim_name, "bad": bad_tracks})

	if bad_anims.size() > 0:
		_broken.append({"id": label, "issue": "broken tracks", "details": bad_anims})
	else:
		_ok_count += 1
	enemy.queue_free()


func _find_ap(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_ap(child)
		if found:
			return found
	return null


func _print_summary() -> void:
	print("\n" + "=".repeat(60))
	print("Summary: %d/%d enemies OK, %d broken" % [_ok_count, _total, _broken.size()])
	print("=".repeat(60))
	for entry: Dictionary in _broken:
		print("\n%s — %s" % [entry["id"], entry["issue"]])
		if entry.has("details"):
			for d: Dictionary in entry["details"]:
				print("  %s: %s" % [d["anim"], str(d["bad"])])

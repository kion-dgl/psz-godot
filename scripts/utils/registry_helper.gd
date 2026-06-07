class_name RegistryHelper
## Shared loader for the resource registries. Every registry instances each
## resource in its data dir, keyed by its `.id`, into a backing dict. This is
## the one place that loop lives — see #215-C1.

const _RU = preload("res://scripts/utils/resource_utils.gd")


## Clear `target`, load every resource under `dir_path`, key it by `.id`, and
## log a one-line summary. Returns the number of entries loaded.
## `label` is the log tag (e.g. "ArmorRegistry"); `noun` is the plural shown
## in the log line (e.g. "armors").
static func load_dir(dir_path: String, target: Dictionary, label: String, noun: String) -> int:
	target.clear()
	for path in _RU.list_resources(dir_path):
		var res = load(path)
		if res and not res.id.is_empty():
			target[res.id] = res
	print("[%s] Loaded %d %s" % [label, target.size(), noun])
	return target.size()

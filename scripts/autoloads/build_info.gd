## Build metadata — stamped at export time so the title screen can show a
## per-build identifier. The committed value is the sentinel 0; this means
## "not stamped" and the title screen renders just `-local` with no number
## (e.g. `godot --export-release` invoked manually without going through
## scripts/tools/local_build_apk.sh).
##
## scripts/tools/local_build_apk.sh seds this constant to a monotonically-
## incrementing counter (`~/.psz-local-build-counter`) before running the
## export, then restores the file via `git checkout --` so the working
## tree stays clean. Counter increments per export so the title shows
## `-local1`, `-local2`, etc — useful for confirming a fresh APK is on
## the device when you re-install many times in a row.
##
## CI builds set OS.has_feature("ci") via `custom_features` in
## export_presets.cfg, which short-circuits the local-build display in
## title.gd entirely — official releases never show a build number.

extends Node

const LOCAL_BUILD: int = 0

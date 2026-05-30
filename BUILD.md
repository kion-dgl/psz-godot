# Building from source

## Requirements

- [Godot 4.5.1+](https://godotengine.org/download/) (with export templates installed via `Editor → Manage Export Templates`)
- Node 22+ (for the web editor and the asset publish pipeline)
- Python 3.11+ (for CI-side scripts)
- `git-filter-repo`, `rclone`, `curl`, `jq` — only if you're running the asset publish / history tools

## Fresh clone

The game's binary assets (GLBs, textures, audio — ~500 MB) live on Cloudflare R2 and are not tracked in git. Populate them locally after cloning:

```bash
git clone git@github.com:kion-dgl/psz-godot.git
cd psz-godot
scripts/tools/fetch_assets_dev.sh
```

The fetch script reads `assets_manifest.json`, downloads every file listed in `assets_tree.json` from the public R2 URL, verifies md5, and drops everything into `/assets/` and `/web/public/assets/psobb_sfx/`. Subsequent runs only re-download what's changed.

The script runs unmodified on both macOS (BSD userland) and Linux (GNU) — it dispatches parallel downloads with `xargs -0` rather than `xargs -I`, so no GNU coreutils / `findutils` install is required on macOS. You do need `curl`, `jq`, and `md5sum` on `PATH` (on macOS, `md5sum` comes with `brew install coreutils`).

Once `/assets/` is populated, open the project in the Godot editor and hit **F5**.

## Exporting a release build locally

The release workflow runs in CI (`.github/workflows/release.yml`). For ad-hoc local exports:

```bash
# Linux (arm64 or x86_64)
godot --headless --path . --export-release "Linux arm64" build/linux-arm64/psz-godot.arm64

# Windows
godot --headless --path . --export-release "Windows x86_64" build/windows/psz-godot.exe

# Android
godot --headless --path . --export-release "Android" build/android/psz-godot.apk
```

Exports are minimal (~30 MB) — the binary only contains bootstrap code + scenes. At runtime, the bootstrap scene pulls the 667 MB asset pack from R2 (or Arweave if R2 is unreachable), verifies sha256, and mounts it via `ProjectSettings.load_resource_pack()`.

## Web editor / quest tools

```bash
cd web
npm install
npm run dev
```

The web app reads assets through the same R2 CDN. If `/assets/` is populated locally the dev server also works offline via the public symlinks.

## Asset pipeline (for maintainers)

- `scripts/publish/` — TypeScript project for uploading new asset pack versions to R2 (primary) and Arweave (permanent mirror). See `scripts/publish/README` in the file for invocation flags.
- `scripts/tools/build_assets_pack.gd` — Godot-headless PCK builder. Bundles `res://assets/` plus `res://.godot/imported/` into a single `.pck` for client mount.
- `scripts/tools/verify_assets_manifest.py` — CI integrity check; HEADs each URL and, when the manifest changes, downloads + sha256-verifies the pack.

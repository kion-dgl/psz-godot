# Launch experience — issue #739

Owner direction (2026-10-10): use the existing close-up Rappy framing on all
platforms; a black splash with centered white fan-remake and copyright notice;
keep “PSZ Godot” for now. The boot notice also includes the owner-requested
“Follow @wagieweeb on X for updates.” line without adding display time. The larger project is a PSO-style fan adaptation of
PSZ's story and gameplay. The normative startup contract is
`spec/src/pages/journey/splash.astro` and the cache behavior is documented in
`spec/src/pages/journey/download.astro`.

## Artwork

The shared opaque 1024×1024 master is `bootstrap/icons/rappy.png`. Project
(Linux/window/Web), Windows and macOS icon settings use this master. Android
uses the 192px derivative and a 432px adaptive layer with a 288px central
composition to compensate for launcher-mask cropping. There is no iOS export
preset yet; the square opaque master is available for a future iOS export.
OS masks are applied by the launcher, not baked into the master.

Image generation used the built-in image tool, editing the original
`android_icon_192.png` (the pixelated source remains in Git history). Final prompt:

> Use case: identity-preserve. Edit target: the supplied 192x192 Rappy app icon.
> Produce a polished high-resolution square mobile app icon, a faithful cleanup
> of THIS EXACT composition. PRESERVE THE FRAMING EXACTLY: extreme closeup yellow
> Rappy face tilted diagonally, left eye lower and right eye higher, both eyes
> and open happy beak in the same positions, tuft/ear tips intentionally cropped
> by top and left canvas edges, face filling nearly the entire square, small
> feathers cropped at bottom/right as in the reference. Do NOT zoom out, center
> the whole head, add padding, complete the cropped ears, or change the pose.
> Keep the warm ivory/cream opaque full-bleed background. Refine the pixelated
> edges into smooth clean dark contours, subtle warm yellow gradients and
> restrained soft shading, glossy deep blue-black eyes with the same highlights,
> small brown-orange smiling beak. Aim for premium iOS/Android illustrated
> game-app icon polish with strong small-size readability; retain the source's
> charm and identity. No 3D toy rendering, no elaborate feathers, no scenery,
> no text, no border, no badge, no pre-rounded corners, no transparent areas.
> Square 1024x1024.

Rebuild the typography-only native splash on macOS with
`swift scripts/tools/generate_boot_notice.swift`. Its wording also appears in
the Astro mock. Keep both in sync.

## Why there is no title-corner loader yet

The executable contains a fixed pack manifest; the title's logo, backdrop and
music require that pack. There is no independent remote update poll or
background save of new assets. Mounting a previously verified, unchanged pack
without rescanning removes the repeated patch-screen interruption. HTTP client
creation is deferred until an actual download. A changed required
pack still downloads before the title. A future background update flow must
first define compatibility and safe activation of old/new packs; don't show
a simulated busy indicator in the meantime.

A local receipt remembers the full hash, byte length and last-modified time
only after successful SHA-256 verification and mounting. Missing/malformed
receipts or changed metadata trigger full verification. Receipts optimize
app-private cache reuse; deliberate tampering preserving metadata is outside
this shortcut's integrity guarantee. Newly downloaded content is always hashed.
Hashing yields after a 4ms work budget instead of every MiB. Download errors
expose Retry, and HTTP requests have a 30-second timeout.

## Validation

- Unit registration: `scripts/tools/startup_cache_tests.gd` in `test_runner`.
- Runtime scene: `res://scripts/tools/startup_probe.tscn`.
- Isolated runtime matrix (also in CI):
  `GODOT=/path/to/godot python3 scripts/tools/autoplay/startup_check.py`.
  Covers first download, cache hit, old-cache migration, corrupt-cache recovery,
  rejection of a bad download without a receipt, and Retry recovery. The
  download fixture uses a throttled local HTTP server. It also runs spectator
  frame-advancement and anchor checks. Does not alter player data
  or the checkout's manifest.
- Owner/device review remains required for actual exported launcher icons,
  cold engine startup, slow network behavior and transitions to the title.
  Automated success does not change scorecard grades.

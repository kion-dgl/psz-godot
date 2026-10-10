# Coliseum spectator idle animation

Added to the launch-experience branch at Kion's request, 2026-10-10.
Contract: `spec/src/pages/mechanics/coliseum-spectators.astro`.

`assets/easter_eggs/kion_idle.png` and `rosaline_idle.png` are four equal-width
cells in one row, generated with the built-in image tool from their respective
existing `*_spectator.png` cutouts. They retain the existing simplified pixel
art, costumes and poses. Rosaline's original source-sheet credit remains
CrimsonPenguin (http://www.crimson-penguin.com), as recorded in the asset README.
The new sheets are shipped in the asset pack and mirrored to R2, following the
existing pack-only spectator layout; the raw PNGs are not committed to Git.

Runtime uses `AnimatedSprite3D`, holding the resting pose for 2.4 seconds,
breathing for 0.6, blinking for 0.12, then returning for 0.6. Kion starts on
frame 0 and Rosaline on frame 1. A shared atlas canvas aligns frame bottoms so
transparent margins cannot move the feet or alter the world-scale calculation.
The stage positions, inward-facing cards, alpha threshold, muted tint and
nearest filtering are unchanged. A one-frame fallback handles older packs.

Unit tests: `scripts/tools/spectator_frame_tests.gd`. Runtime advancement and
anchor checks run through `res://scripts/tools/startup_probe.tscn`, using a
small deterministic texture fixture so CI does not require the full game pack.
The actual generated sheets were also rendered in Godot for visual inspection.

## Generation prompts

Two separate image-edit calls used the following prompt, substituting the
respective character description:

- Kion: muted green spiky hair, simple charcoal and gray hoodie, green shorts
  and boots.
- Rosaline: blonde hair, burgundy bow and dress with gold/white trim.

> Use case: identity-preserve. Edit the supplied pixel-art character into a
> game-ready four-frame QUIET IDLE animation sheet. Match the exact existing
> character design, pixel grid, palette, costume, three-quarter facing and
> low-detail background-NPC style. Output one wide transparent PNG sprite sheet,
> exactly FOUR equal-width cells in ONE horizontal row, frames left to right,
> no dividers or labels. Every cell contains the same full body at IDENTICAL
> SCALE with feet on the SAME BASELINE and horizontal center aligned in its
> cell. Frame 1: original relaxed standing pose with eyes open. Frame 2: tiny
> breathing lift of chest by one native pixel, head and feet stay nearly fixed.
> Frame 3: same resting body with eyes CLOSED for a brief blink. Frame 4:
> original open eyes and relaxed chest again. Subtle idle only: no wave, no
> walking, no new props, no smile change, no head turn, no shifted feet, no
> squash/stretch. Hard crisp pixel-art clusters and dark outlines as in input;
> do not smooth, add fine detail, change proportions or repaint the costume.
> Keep the character fully inside each cell with small even padding. Four
> frames only; real alpha transparency throughout background, no ground/shadow,
> no text. 2048x1024 horizontal sheet.

The requested output size was art direction; the delivered sheets are
1774×887. Runtime divides the width into four 443px cells (the final two
columns are unused transparent padding), then normalizes visible bounds.

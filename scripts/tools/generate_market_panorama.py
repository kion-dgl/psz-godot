#!/usr/bin/env python3
"""Paint the canyon panorama for city_market as a hand-painted matte image.

Produces an equirectangular 2048x1024 PNG at
  assets/stages/city_e/market/canyon_panorama.png

Composition (top→bottom, equator at y=512):
  - Sky: cool teal gradient (matches existing kantei01 vertex-color palette)
  - Far mesa: pale cream silhouette, soft wavy horizon
  - Near mesa: warmer tan silhouette in front
  - Cliff face: warm sandstone with banded layers
  - Floor: dark earth so the lower hemisphere isn't void

Style is "PSO matte painting" — flat colors, gradients, soft blur. No PBR.
Re-run after tuning. The Godot scene already references the output PNG.
"""

import math
import os
import random
import sys
from pathlib import Path

try:
    from PIL import Image, ImageFilter
except ImportError:
    print("PIL/Pillow not installed. Try: pip install Pillow", file=sys.stderr)
    sys.exit(1)

WIDTH = 2048
HEIGHT = 1024

# Repo root = two levels up from this file (scripts/tools/)
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
OUT_PATH = REPO_ROOT / "assets/stages/city_e/market/canyon_panorama.png"

# Palette stops (RGB 0..1)
SKY_ZENITH    = (0.00, 0.02, 0.12)   # near-black navy (matches kantei01 top)
SKY_MID       = (0.17, 0.62, 0.73)   # cyan (matches kantei01 horizon)
SKY_LOW       = (0.55, 0.72, 0.78)   # pale cyan-gray (where sky meets mesa)
SKY_HORIZON   = (0.85, 0.75, 0.55)   # warm pale haze (sunset suggestion)

MESA_FAR      = (0.92, 0.78, 0.55)   # pale cream
MESA_NEAR     = (0.85, 0.55, 0.30)   # warm tan
CLIFF_LIGHT   = (0.85, 0.55, 0.30)   # cliff band light
CLIFF_DARK    = (0.62, 0.32, 0.18)   # cliff band dark
FLOOR_COLOR   = (0.10, 0.10, 0.12)   # dark earth-teal

# Y boundaries (px). Tune these to push composition.
SKY_TOP_Y     = 0
HORIZON_Y     = 480     # where SKY_HORIZON gradient terminates
MESA_FAR_Y0   = 380     # far mesa silhouette upper bound (peaks)
MESA_FAR_Y1   = 460     # far mesa base (where it meets near mesa)
MESA_NEAR_Y0  = 450     # near mesa silhouette upper bound
MESA_NEAR_Y1  = 540     # near mesa base (where cliff begins)
CLIFF_Y0      = 530     # cliff face top
CLIFF_Y1      = 700     # cliff face bottom
FLOOR_Y       = 700     # floor starts
BAND_PERIOD   = 14      # cliff band height in px


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_rgb(c1, c2, t):
    return (lerp(c1[0], c2[0], t),
            lerp(c1[1], c2[1], t),
            lerp(c1[2], c2[2], t))


def to_byte(c):
    return (
        max(0, min(255, int(round(c[0] * 255)))),
        max(0, min(255, int(round(c[1] * 255)))),
        max(0, min(255, int(round(c[2] * 255)))),
    )


def sky_color(y):
    """Vertical gradient from zenith (y=0) down to the mesa horizon (y=HORIZON_Y).
    Three stops: zenith → mid → low → warm horizon haze right at the bottom."""
    t = y / HORIZON_Y
    if t < 0.45:
        return lerp_rgb(SKY_ZENITH, SKY_MID, t / 0.45)
    elif t < 0.85:
        return lerp_rgb(SKY_MID, SKY_LOW, (t - 0.45) / 0.40)
    else:
        return lerp_rgb(SKY_LOW, SKY_HORIZON, (t - 0.85) / 0.15)


def silhouette_height(theta_norm, base_y, amp, seed_offset, harmonics):
    """Return Y where this silhouette layer's top edge sits, given a normalized
    theta (0..1 around the panorama). Multi-frequency sine + noise."""
    rng = random.Random(seed_offset)
    t = theta_norm * math.tau
    h = 0.0
    for freq, weight in harmonics:
        phase = rng.uniform(0, math.tau)
        h += math.sin(t * freq + phase) * weight
    # Low-frequency wobble for asymmetry — INTEGER frequencies only so the
    # silhouette wraps cleanly at the seam (theta=0 == theta=tau).
    rng2 = random.Random(seed_offset + 1)
    wobble = sum(math.sin(t * f + rng2.uniform(0, math.tau)) * (1.0 / f)
                 for f in (1, 2, 3, 4))
    h += wobble * 0.4
    return base_y - h * amp


def cliff_color(y, theta_norm, seed):
    """Banded sandstone — alternating light/dark bands with per-column hue jitter."""
    rng = random.Random(int(theta_norm * 4096) ^ seed)
    band_idx = (y // BAND_PERIOD) % 2
    base = CLIFF_LIGHT if band_idx == 0 else CLIFF_DARK
    # Hue jitter: shift toward red or yellow per column
    jitter_r = rng.uniform(-0.06, 0.06)
    jitter_g = rng.uniform(-0.04, 0.04)
    jitter_b = rng.uniform(-0.03, 0.03)
    # Vertical fade — slightly darker toward the bottom of the cliff
    fade_t = (y - CLIFF_Y0) / max(1, CLIFF_Y1 - CLIFF_Y0)
    fade_mul = 1.0 - 0.20 * fade_t
    return (
        (base[0] + jitter_r) * fade_mul,
        (base[1] + jitter_g) * fade_mul,
        (base[2] + jitter_b) * fade_mul,
    )


def render():
    img = Image.new("RGB", (WIDTH, HEIGHT))
    px = img.load()

    # Pre-compute mesa silhouette tops for every X column.
    # Far mesa: gentle, low-amplitude wobble.
    # Near mesa: sharper peaks, larger amplitude, sits in front of far mesa.
    far_top = []
    near_top = []
    for x in range(WIDTH):
        theta_norm = x / WIDTH
        far_top.append(silhouette_height(
            theta_norm, base_y=MESA_FAR_Y1,
            amp=MESA_FAR_Y1 - MESA_FAR_Y0,
            seed_offset=11,
            harmonics=[(2, 0.50), (5, 0.25), (11, 0.10)],
        ))
        near_top.append(silhouette_height(
            theta_norm, base_y=MESA_NEAR_Y1,
            amp=MESA_NEAR_Y1 - MESA_NEAR_Y0,
            seed_offset=23,
            harmonics=[(3, 0.55), (7, 0.30), (17, 0.15)],
        ))

    # Paint
    for x in range(WIDTH):
        theta_norm = x / WIDTH
        far_y = far_top[x]
        near_y = near_top[x]
        # Per-column jitter for cliff bands so it's not a barber pole
        cliff_seed = (x * 31) & 0xFFFF

        for y in range(HEIGHT):
            if y < far_y:
                # Sky
                px[x, y] = to_byte(sky_color(y))
            elif y < near_y:
                # Far mesa silhouette (with very slight gradient toward base)
                t = (y - far_y) / max(1, MESA_FAR_Y1 - far_y)
                col = lerp_rgb(MESA_FAR, MESA_NEAR, min(1.0, t * 0.6))
                px[x, y] = to_byte(col)
            elif y < CLIFF_Y0:
                # Near mesa
                t = (y - near_y) / max(1, MESA_NEAR_Y1 - near_y)
                col = lerp_rgb(MESA_NEAR, CLIFF_LIGHT, min(1.0, t))
                px[x, y] = to_byte(col)
            elif y < CLIFF_Y1:
                # Cliff face with banding
                px[x, y] = to_byte(cliff_color(y, theta_norm, cliff_seed))
            else:
                # Floor — slight fade from cliff base to dark
                t = (y - CLIFF_Y1) / max(1, HEIGHT - CLIFF_Y1)
                col = lerp_rgb(CLIFF_DARK, FLOOR_COLOR, min(1.0, t * 1.5))
                px[x, y] = to_byte(col)

    # Soft blur for painted feel — small radius preserves silhouettes
    img = img.filter(ImageFilter.GaussianBlur(radius=1.5))

    # Make sure the seam at x=0 / x=WIDTH-1 is consistent — equirectangular wraps.
    # Our silhouette functions use sin(theta) which is naturally periodic, so
    # the seam should already match. Verify by sampling first/last column tops:
    seam_diff = abs(far_top[0] - far_top[-1]) + abs(near_top[0] - near_top[-1])
    if seam_diff > 1.0:
        print(f"WARN: seam mismatch in silhouettes ({seam_diff:.2f} px)", file=sys.stderr)

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT_PATH, optimize=True)
    print(f"Wrote {OUT_PATH} ({OUT_PATH.stat().st_size} bytes, {WIDTH}x{HEIGHT})")


if __name__ == "__main__":
    random.seed(42)  # deterministic
    render()

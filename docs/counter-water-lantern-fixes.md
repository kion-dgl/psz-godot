# Counter water and lantern geometry

The counter pool now alpha-blends at its authored opacity rather than using the additive waterfall shader. Its upper panels meet the lower waterline without an overlapping strip. Waterfalls retain the existing shader and animation.

The hash-pinned source GLB lacks faces hidden by the original fixed camera. A generated JSON supplement adds 92 triangles for open-backed pillars, parapets, plinth, kiosk foundation, office bridge and the two office lantern roofs. Both lantern caps gain their missing rear halves, preserving the shared apex, UVs and materials. The runtime applies this only to the counter scene instance before material fixes; it is idempotent and does not rebuild collision or republish assets.

Kion approved the water and lantern appearance in local Mac playtesting on 2026-11-12. City grade remains unchanged; other principal-office review remains.

Regenerate with:

```sh
python3 scripts/tools/complete_counter_geometry.py assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m.glb data/stage_geometry/s00e_sa2_completion.json
```

With the existing city asset pack imported locally, run:

```sh
godot --headless --path . --script res://scripts/tools/counter_geometry_check.gd
godot --headless --path . --script res://scripts/tools/counter_water_material_check.gd
```

Checks cover 16 pillar sides, four foundation/bridge faces, four front/back lantern roof rays, twelve water seam rays, repeated application, authored pool opacity/scroll and unchanged waterfall shader.

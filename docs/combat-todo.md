# Combat System TODO

## Combat fidelity pass — October 2026

Gameplay reliability takes priority over exact DS behavior. This first slice
covers ranged contact, aiming, range, and dodge resolution; combo timings,
melee hit frames, damage balance, and boss part rigs still need hands-on review.

- [x] Sweep player projectiles through actual hurtbox shapes, ordered by impact;
      cover point-blank contact, unique-owner piercing caps, and range expiry.
- [x] Match weapon shot range and release aim to the weapon's targeting cone.
      Handgun now reaches its 9 m targeting range; rifle reaches 12 m.
- [x] Carry strong-attack elements on ranged shots without leaking them into normals.
- [x] Sweep enemy projectiles; dodging consumes direct damage and on-hit poison.
- [x] Keep the enemy-room web simulator consistent with swept contact/range rules.
- [x] Add physics regression coverage and actual weapon-release checks to the coliseum probe.
- [ ] Human coliseum feel pass: saber/sword/daggers → handgun/rifle/mechgun →
      mobile melee enemy → ranged/poison enemy → boss. Check rhythm, visual
      impact timing, attack recovery, and dodge readability before tuning numbers.

### Reference evidence and deliberate choices

Reviewed [psz-re at a84b8fd](https://psp2i.dev/kion/psz-re/src/commit/a84b8fdd9d0589ef2e4f1af25b66e8e6f080fb93).
Its [player animation events](https://psp2i.dev/kion/psz-re/src/commit/a84b8fdd9d0589ef2e4f1af25b66e8e6f080fb93/data/player_combo_windows.json)
provide weapon-specific hit frames and chain windows in animation frames at
rate 1.0. The source explicitly warns that a rate-2 cheat halved early measurements,
and that the slicer's windows extend beyond its clips and remain unexplained.
Keep our animation-relative timing until each equipped animation is compared;
do not use one sampled ranged weapon's frame counts as a universal combat rule.
The [enemy part findings](https://psp2i.dev/kion/psz-re/src/commit/a84b8fdd9d0589ef2e4f1af25b66e8e6f080fb93/nodes/sys.enemy-part-joints.json)
distinguish bone-attached parts from shared collision shapes. Our runtime keeps
one projectile damage budget per enemy across its hurtboxes; that is our
playability rule, not a proven DS boss multi-hit rule.
Swept collision and release-time aim are playability choices, not claimed DS algorithms.

### Repeatable checks

Use a disposable Godot user-data directory/project for probes and test_runner:
they create test characters and the full runner exercises save/load.
With local game assets imported:

```sh
godot --headless --path . res://scripts/tools/test_runner.tscn
godot --headless --path . res://scripts/tools/combat_fidelity_probe.tscn
godot --headless --path . res://scripts/tools/coliseum_probe.tscn
```

The asset-independent physics probe also runs in CI. The coliseum probe checks
handgun at 8 m, rifle at 10 m, off-axis mechgun bursts, and slicer contact against
the real arena enemy before testing enemy damage and the room-clear return warp.
Manual playtesting uses the existing Coliseum Master picker in the city.

### Coliseum pass: Booma Origin emergence

Booma Origin and Gigobooma Origin now author `fsm.spawn_clip: stt` and stay
stationary for the full entrance clip. The generic pre-strike telegraph was
replaying `stt` after pursuit; only stance risers now use that rise transition.
Other archetypes hold their own ready pose. Existing archetype definitions remain
in `/states/enemies`; the Bruiser entrance contract is now explicit there too.

Run the same disposable-project Coliseum probe with
`PSZ_COLISEUM_ENEMY=booma_origin` or `PSZ_COLISEUM_ENEMY=gigobooma_origin`.
Both real rigs passed a stationary 1.00-second entrance, pursuit, and two attacks
with exactly one emergence. Regression tests also cover slower playback,
missing entrance clips, repeated reveal, and archetype-specific telegraphs.

## Phase 1 — Previous pass

- [x] Add missing weapon types to shop (spear, claw, double saber, slicer)
- [x] Handgun hold orientation tuning
- [x] Rod hold orientation tuning
- [x] Hit reactions — animation-based stagger/knockdown/death (dam_n, dam_h, dam_d, dam_d_wa, dam_d_lp), no physics knockback
- [x] Real damage formula (stats + weapon + defense/evasion + crits)
- [x] Melee weapons: saber, sword, daggers, spear, rod, wand
- [x] Ranged weapons: handgun, rifle, mechgun (projectiles)
- [x] Per-weapon combo steps, hitbox shapes, max targets, multi-hit
- [x] Target reticles + floating damage numbers
- [x] EnemyBase AI (chase, attack, loaf, wander, hurt, death)
- [x] Class weapon equip restrictions + innate weapon bonus
- [x] Weapon test scene
- [x] Debug hitbox visualization
- [x] Wand weapons + animations
- [x] Rifle animations (PSO rifle bake)
- [x] Mechgun walk/run animations

## Phase 2 — Future

- [ ] Laser cannon — projectile travels straight, pierces enemies, damages each along the way
- [ ] Shot weapon — fires 3-5 bullets in a spread (port from PSO)
- [ ] Grenade launcher — fires in an arc, explodes on ground impact (PSU style)
- [ ] Hit feedback juice (screen shake, hitstop frames)
- [ ] Technique casting system (Forces)
- [ ] More enemy behaviors (ranged, charger, tank, boss patterns)
- [ ] Sound effects
- [ ] Photon blasts (mag trigger)
- [ ] Traps (Cast classes)


### Booma follow-up: preparation was misclassified as a strike

The first entrance fix did not verify the attack clip's visual meaning. Kion's
next playtest exposed `run` approach followed by damaging `atk` preparation.
Rendered samples of all nine source clips confirm `atk` crouches for the dash;
it is not a melee swing. Both variants now walk into range, prepare on `atk`,
dash on `run` with one contact resolution, then recover harmlessly on `atk_mi`.
Only roller archetypes receive engine-driven body rotation during a charge.

Evidence recovered from [notes intake #492](https://github.com/kion-dgl/psz-godot/issues/492)
and Git history: the earlier per-clip observations survive in
`data/enemy_attacks.json` (`clip_notes`). Booma had no authored notes/table;
“height swings” came from the vocabulary inventory in commit `170a7717`, not
confirmed visual semantics. Preserve observations and uncertainty in clip_notes.
The original outcome selection between `atk_hi` and `atk_mi` is still unknown;
using the short recovery for both hit and miss is an explicit gameplay choice.

The Coliseum probe now requires two complete `atk → run → atk_mi` cycles and
checks that preparation is stationary and causes no damage. Unit tests also put
the target inside contact range during preparation and test dash contact/dodge.

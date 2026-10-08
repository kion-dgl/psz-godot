# Combat System TODO

## Fidelity baseline and identity audit — October 8

The current owner grades and promotion criteria live in the spec at `/fidelity`;
combat remains **C**, bosses/traps/systems **D**. Automated passes do not raise
these playtest grades. `/states/combat-roster` renders the checked crosswalk in
`data/combat_roster.json` for #683, including tank/swordman and Mother conflicts,
the `chaos_mobius_paru` orphan, and Shinowa/Sinow catalog/encounter differences.
No runtime IDs or rigs were changed by this audit. Identity migrations and
source-name confirmation remain open; this is progress on #683, not closure.

Run `python3 scripts/tools/check_combat_roster.py` and
`python3 scripts/tools/test_combat_roster.py`. CI checks resource/attack/source
coverage, family tickets, boss encounters and explicit catalog exceptions.
Known gaps print on every pass; new discrepancies and stale exceptions fail.
Continue with #684/#685 real-rig/reference review, then #686/#687; use confirmed
rigs rather than current display names for identity-sensitive family work.

## Enemy family execution plan — October 7

Each family passes through: recover saved notes and reference assets → inspect
clips/effects → write explicit behavior and uncertainty → seeded tests → runtime
implementation → real-rig Coliseum probe → user feel checkpoint. Preserve the
mapping in `clip_notes`; do not infer damage or statuses from filenames alone.

1. **Helion / Blaze Helion (implemented; user feel check pending):** close claws and committed distant
   spin-lunge; align the animated body and collision, telegraph, dodge and recovery.
   Blaze initially shares the verified rig behavior; elemental differences remain open.
2. **Batt / Bullbatt:** distinguish bite/sonic delivery and investigate confusion.
3. **Finjer R/B/G:** shooting versus segmented spin and variant effects.
4. **Tank / swordman families:** verify roster/model identities, then distinct kits.
5. **Mother variants:** verify identities and weapon/technique/warp sequences.
6. **Mixed groups:** spacing, simultaneous telegraphs, target changes and fair
   recovery windows, after the individual family passes are stable.

Automated completion is not visual approval. Per the latest user request, implement
the whole remaining batch before the joint user playtest checkpoint.

## Remaining family batch — implemented, joint feel test pending

All 15 mapped enemies now have explicit kits: Batt/Bullbatt, all three Finjers,
Phobos/Dyna (tank rigs), Arkzein/R and Zaphobos/Dyna (swordman rigs), and the
four Mother entries. Existing roster identities are preserved; model filenames
alone are not evidence to rename or swap them. The schema now supports harmless
end clips and explicit locomotion tokens, so the shot/cast/throw sequences no
longer depend on a generic attack fallback.

Open **Coliseum Master → Mixed Groups** for:

- **Bats + Helion** — close pressure alongside sonic shots.
- **Finjer Trio** — spin preparation/travel/recovery and colored shots.
- **Tanks + Swordmen** — explosives, ranged shots, close sweeps and throws.
- **Mother Trio** — Blade, Shot and Force together.
- **Combined Pressure** — Batt, Finjer R, Phobos, Arkzein and Force Mother.

The original Enemies/Bosses tabs still provide individual tests. No change to
regular quest encounters or save data is required to use these presets.

Validation on Godot 4.5.1: 192 live ordinary-AI decision cases, 78 real-rig attack
execution cases (each attack with damage and sustained dodge), all 15 existing
weapon/room-clear probes, and all five simultaneous-group/final-kill probes pass.
Mixed tests require every member to attack and keep the exit closed with a dormant
last survivor. Results and input hashes: `docs/combat-family-results.json`.
Full suites: 6,829 Godot checks; 873 web checks (4 skipped). TypeScript, Astro,
code-graph and orphan checks pass. Headless probes verify mechanics, not visual feel.

Reproduce in a **disposable save project**, never against the player's save:
`PSZ_COLISEUM_ENEMY=finjer_r PSZ_COMBAT_SCENARIOS=1 PSZ_ENEMY_RUNTIME_CHECK=1 godot --headless --fixed-fps 60 --path <isolated-project> res://scripts/tools/coliseum_probe.tscn`.
For groups use `mixed_bats`, `mixed_finjers`, `mixed_machines`, `mixed_mothers`,
or `mixed_pressure` as the enemy argument. Passing requires `[coliseum] DONE ok`,
no `SCRIPT ERROR`, and no `PASS=false`.

Deliberate provisional choices to assess in the joint playtest:

- Bat bite and sonic share the sole imported attack clip. Sonic is a traveling
  ring; confusion remains unconfirmed and is not applied.
- Finjer projectile colors are presentation, not inferred elemental ailments.
- Tank `atk_mi` uses a close explosive lob; persistent mine triggers are unverified.
- Local swordman GLBs omit the viewer's `atk_th_sw`. Throw releases near the end
  of `atk_th_st`, then plays `atk_th_ed`; no unrelated fallback animation.
- Mother spells use neutral projectile/area delivery. Named techniques and warp
  rules remain unverified; Mothers currently approach using their floating pose.
- Windows, ranges, knockdown and damage multipliers are tuning values. Prioritize
  readable timing, body/hitbox alignment and fair simultaneous pressure during review.

## Combat fidelity pass — October 2026

### Coliseum playtest observations — October 7

- Helion is incorrectly covered by the `simple_melee` placeholder. User-observed
  behavior: lunge/spin attacks from a distance and claw attacks up close. Recover
  the clip mapping and implement distance-dependent selection before treating
  this enemy as validated. Blaze Helion also has the same placeholder definition;
  verify its variant behavior separately.
- Batt/Bullbatt currently have only a generic close-range `atk` entry. The user
  recalls a projectile attack. The [bat asset viewer](https://dashgl.github.io/psz-asset-viewer/enemies/bat/)
  lists six clips (`s_033_atk`, `ded`, `dmg`, `stt`, `wat`, `wlk`) and effects
  `ef_e_c_sdd` and `ef_e_c_sonic`. The sonic effect supports a sonic ranged attack
  interpretation; the viewer alone does not establish delivery shape, range,
  release timing, or whether the attack is a traveling projectile versus an area
  pulse. Recover those details before replacing the generic melee definition.

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

### Remaining enemy review: six runtime repairs

- Poison Lily uses shared cooldown/status/entry gates and attacks repeatedly.
- Snake, roller, revealed mimic, and airborne flyer select their authored idle
  poses; the generic `wat → stt` transition fallback is removed.
- Roller restores its model orientation on recovery, interruption, and death.
  Nonlethal hits preserve the full vulnerable recovery window.
- Snake holds `wt2w` to completion before recovery locomotion.
- Hypao Barta and Vespao Gibarta use shared ice delivery profiles: ground ice
  and a three-wave fan, with swept contact, one hit per cast, dodge protection,
  and freeze that expires or breaks on subsequent damage. The 20% freeze chance
  is explicit gameplay tuning, not a recovered DS constant.

`enemy_runtime_regression_tests.gd` covers these contracts. Enable real-rig
checks with `PSZ_ENEMY_RUNTIME_CHECK=1` and `PSZ_COLISEUM_ENEMY` set to
`poison_lily`, `garapython`, `rohjade`, `hypao`, or `vespao` when running
`coliseum_probe.tscn` in the disposable project. All five passed the runtime,
weapon contact, enemy damage, and room-clear checks. These are automated
behavior checks; visual feel and balance still need human playtesting.

### Asset viewer inventory audit — October 7

Compared every one of the **67 model pages** in the [enemy asset viewer](https://dashgl.github.io/psz-asset-viewer/enemies/) against local model IDs, shared animation rigs, and attack definitions. These map to 65 local enemy entries; 40 still use generic basic attack definitions (Reyburn’s dedicated kit is excluded from that count). Full clip/effect/part inventories and per-enemy comparisons are saved in [`data/re_reference/enemy_viewer_audit.json`](../data/re_reference/enemy_viewer_audit.json). This is an asset/definition audit, not a visual validation of every animation or proof of original attack mechanics.

Variant pages with zero animations are resolved through `animation_model_id`; their own effects remain separate. Generic `atk` can resolve via the runtime fallback, so a missing exact `atk` is not automatically a broken animation. It still does not supply the missing attack selection, delivery, or phase behavior. Reyburn is evaluated against its dedicated boss kit rather than its generic registry placeholder.

**Priority findings:**

- Helion/Blaze Helion: generic melee only despite `atk`, `atkb`, and jump-effect evidence. User-observed distant lunge/spin and close claws remain the behavior requirement; clip-to-action mapping needs confirmation.
- Batt/Bullbatt: generic melee only; effects differ (`sonic` versus `sonic2`). Bite plus sonic attack and sonic-induced confusion are user hypotheses, not established by the asset names.
- Finjer R/B/G: `atk_sh` and a segmented `atk_sp_st/lp/ed` set, with distinct `fbul/cbul/pbul` effects; all three still have one generic close melee definition. Elements/status meanings must be verified.
- Local `missile_tank` roster (currently Phobos/Phobos Dyna): `atk_bz`, `atk_mi`, `atk_sh`, mine and gun effects, but only generic melee. Verify roster/model identity as well as the kit.
- Local shade roster: `leg/lower` have `atk_a/atk_b`; swordman models have punch/swing/segmented attack clips and sword/spin effects. Generic fallback picks one clip without defining the full kit.
- Mother-family models: gun, sword, technique and warp sequences exist; all four local mother-caster definitions are generic melee. Verify the local Mother Trinity/boss model assignments before authoring behavior.
- Rumole: unused `atkb` and `grd01/02/03`/`nos` clips warrant a burrow/alternate-attack review; names alone do not establish their mechanics.
- Frog variants: the existing bubble projectile is authored, but poison/poison2 effects and Pobomma’s bomb/explosion assets warrant variant-specific delivery/status review. The generic projectile hook does not apply poison or bomb behavior.
- Pelcatraz/Pelcatobur: all three attack clips are represented, but provisional `atk2` is a melee arc. `bspin` and `b_snc` effects are useful evidence for revisiting the gust’s delivery.
- Non-Reyburn bosses remain generic in the spawn path despite large attack/part inventories. `boss_robot_cmb` and `boss_mother_piece` are separate viewer pages without direct roster entries; do not omit them when implementing their parent fights.

The enemy runtime has no direct references to these named `ef_*` viewer assets. Procedural projectile/lob/spawn/death effects already exist, so this is an asset-fidelity gap, not proof that all visual effects are absent. Shared death/spawn effects must not be counted as extra attacks.

**Complete model coverage:** `candidate clips` means attack/technique-named clips without explicit references in that enemy’s active authored definition (including segmented windup/charge references). Candidates can be transitions, unused variants, or fallback-selected clips. “Authored” does not mean visually validated.

| Viewer model | Local roster / animation source | Current coverage | Candidate clips | Effects |
|---|---|---|---|---|
| [armadillo](https://dashgl.github.io/psz-asset-viewer/enemies/armadillo/) | rohjade | Authored 1 attacks | — | ef_e_c_sdd, ef_e_c_smk, ef_e_c_spin |
| [armadillo_rare](https://dashgl.github.io/psz-asset-viewer/enemies/armadillo_rare/) | rohcrysta (rig armadillo) | Authored 1 attacks | — | ef_e_c_sdd, ef_e_c_smk, ef_e_c_spin |
| [bat](https://dashgl.github.io/psz-asset-viewer/enemies/bat/) | batt | Generic basic placeholder | — | ef_e_c_sdd, ef_e_c_sonic |
| [bat_blue](https://dashgl.github.io/psz-asset-viewer/enemies/bat_blue/) | bullbatt (rig bat) | Generic basic placeholder | — | ef_e_c_sdd, ef_e_c_sonic2 |
| [board](https://dashgl.github.io/psz-asset-viewer/enemies/board/) | finjer_r | Generic basic placeholder | atk_sh, atk_sp_ed, atk_sp_lp, atk_sp_st | ef_com_exp02, ef_com_explosion, ef_e_c_mdd, ef_e_l_arbd, ef_e_l_fbul, ef_e_l_stt |
| [board_blue](https://dashgl.github.io/psz-asset-viewer/enemies/board_blue/) | finjer_b | Generic basic placeholder | atk_sh, atk_sp_ed, atk_sp_lp, atk_sp_st | ef_com_exp02, ef_com_explosion, ef_e_c_mdd, ef_e_l_arbd, ef_e_l_cbul, ef_e_l_stt |
| [board_green](https://dashgl.github.io/psz-asset-viewer/enemies/board_green/) | finjer_g | Generic basic placeholder | atk_sh, atk_sp_ed, atk_sp_lp, atk_sp_st | ef_com_exp02, ef_com_explosion, ef_e_c_mdd, ef_e_l_arbd, ef_e_l_pbul, ef_e_l_stt |
| [booma](https://dashgl.github.io/psz-asset-viewer/enemies/booma/) | booma_origin | Authored 1 attacks | atk_hi | ef_e_c_rstt, ef_e_c_sdd |
| [boss_darkfalz](https://dashgl.github.io/psz-asset-viewer/enemies/boss_darkfalz/) | dark_falz | Generic basic placeholder | — | ef_dktnt, ef_e_d_bhole, ef_e_d_bit, ef_e_d_bsdw1, ef_e_d_bsdw2, ef_e_d_bsdw3, ef_e_d_bsdw4, ef_e_d_dark, ef_e_d_emit, ef_e_d_emit2, ef_e_d_emmz, ef_e_d_sdw, ef_e_d_sphit, ef_e_d_spr_st, ef_e_d_spread, ef_e_d_tame, ef_e_d_tsdw |
| [boss_dragon](https://dashgl.github.io/psz-asset-viewer/enemies/boss_dragon/) | reyburn | Dedicated Reyburn kit | — | ef_e_m_br, ef_e_m_br_s, ef_e_m_brhit, ef_e_m_cry, ef_e_m_fogc, ef_e_m_kaze, ef_e_m_lfire, ef_e_m_mbr, ef_e_m_spin, ef_e_m_taill, ef_en_m_dfog |
| [boss_mother](https://dashgl.github.io/psz-asset-viewer/enemies/boss_mother/) | humilias | Generic basic placeholder | — | ef_e_d_cmb, ef_e_d_fog, ef_e_d_head, ef_e_d_lsr, ef_e_d_lsrex, ef_e_d_piece, ef_e_d_pnt |
| [boss_mother_piece](https://dashgl.github.io/psz-asset-viewer/enemies/boss_mother_piece/) | No direct roster entry; part/alternate model | Review with parent boss | — | ef_e_d_arnd, ef_e_d_pzm, ef_e_d_reso, ef_e_d_stg, ef_e_d_swrd, ef_e_d_swrd_front |
| [boss_octopus](https://dashgl.github.io/psz-asset-viewer/enemies/boss_octopus/) | octo_diablo | Generic basic placeholder | — | ef_e_l_ebul, ef_e_w_canon, ef_e_w_ded, ef_e_w_gero, ef_e_w_hmn, ef_e_w_ihl, ef_e_w_psumi, ef_e_w_scrw, ef_e_w_shibuki, ef_e_w_shit, ef_e_w_spin, ef_e_w_stage, ef_e_w_stage1, ef_e_w_yuka |
| [boss_robot](https://dashgl.github.io/psz-asset-viewer/enemies/boss_robot/) | chaos_mobius | Generic basic placeholder | atk_dl_lp | ef_e_c_mdd, ef_e_l_bl_s, ef_e_l_drill1, ef_e_l_drill2, ef_e_l_dummy, ef_e_l_hit_s, ef_e_l_hov, ef_e_l_mz_s, ef_e_l_wave1, ef_e_l_wave2 |
| [boss_robot_cmb](https://dashgl.github.io/psz-asset-viewer/enemies/boss_robot_cmb/) | No direct roster entry; part/alternate model | Review with parent boss | — | ef_e_l_air, ef_e_l_bl_f, ef_e_l_bl_s, ef_e_l_bom, ef_e_l_dead, ef_e_l_dummy, ef_e_l_finish, ef_e_l_flash, ef_e_l_hit_f, ef_e_l_hit_s, ef_e_l_hov, ef_e_l_mz_f, ef_e_l_mz_s, ef_e_l_slash, ef_e_l_tsuki, ef_e_l_union, ef_e_l_warp, ef_e_l_warp1 |
| [circle](https://dashgl.github.io/psz-asset-viewer/enemies/circle/) | eulada | Generic basic placeholder | — | ef_e_d_stt |
| [circle_black](https://dashgl.github.io/psz-asset-viewer/enemies/circle_black/) | euladaveil (rig circle) | Generic basic placeholder | — | ef_e_d_stt |
| [deer](https://dashgl.github.io/psz-asset-viewer/enemies/deer/) | stagg | Generic basic placeholder | — | ef_e_c_sdd, ef_e_s_stt, ef_e_s_wbr |
| [frog](https://dashgl.github.io/psz-asset-viewer/enemies/frog/) | porel | Authored 1 attacks | — | ef_c_stt_w, ef_e_c_phit, ef_e_c_poisn, ef_e_c_sdd |
| [frog_bomb](https://dashgl.github.io/psz-asset-viewer/enemies/frog_bomb/) | pobomma (rig frog) | Authored 1 attacks | — | ef_com_explosion, ef_e_c_sdd, ef_e_r_stt, ef_e_w_bomb |
| [frog_rare](https://dashgl.github.io/psz-asset-viewer/enemies/frog_rare/) | pomarr (rig frog) | Authored 1 attacks | — | ef_c_stt_w, ef_e_c_phit2, ef_e_c_poison2, ef_e_c_sdd |
| [gorilla](https://dashgl.github.io/psz-asset-viewer/enemies/gorilla/) | hildegao | Authored 3 attacks | atk2_ed, atk2_lp, atk2_st | ef_e_c_sdd, ef_e_s_down, ef_e_s_stt, ef_e_s_wbr |
| [gorilla_female](https://dashgl.github.io/psz-asset-viewer/enemies/gorilla_female/) | hildeghana (rig gorilla) | Authored 3 attacks | atk2_ed, atk2_lp, atk2_st | ef_e_c_sdd, ef_e_s_down, ef_e_s_stt, ef_e_s_wbr |
| [gorilla_rare](https://dashgl.github.io/psz-asset-viewer/enemies/gorilla_rare/) | hildegigas (rig gorilla) | Authored 3 attacks | atk2_ed, atk2_lp, atk2_st | ef_e_c_sdd, ef_e_s_down, ef_e_s_stt, ef_e_s_wbr |
| [hyena](https://dashgl.github.io/psz-asset-viewer/enemies/hyena/) | grimble | Generic basic placeholder | — | ef_e_c_sdd, ef_e_m_stt |
| [hyena_rare](https://dashgl.github.io/psz-asset-viewer/enemies/hyena_rare/) | tormatible (rig hyena) | Generic basic placeholder | — | ef_e_c_sdd, ef_e_m_stt |
| [jigobooma](https://dashgl.github.io/psz-asset-viewer/enemies/jigobooma/) | gigobooma_origin | Authored 1 attacks | atk_hi | ef_e_c_rstt, ef_e_c_sdd |
| [leg](https://dashgl.github.io/psz-asset-viewer/enemies/leg/) | derreo | Generic basic placeholder | atk_a, atk_b | ef_e_d_stt |
| [leg_black](https://dashgl.github.io/psz-asset-viewer/enemies/leg_black/) | zerreo | Generic basic placeholder | atk_a, atk_b | ef_e_d_stt |
| [lion](https://dashgl.github.io/psz-asset-viewer/enemies/lion/) | helion | Generic basic placeholder | atkb | ef_e_c_sdd, ef_e_m_jmp, ef_e_m_stt |
| [lion_rare](https://dashgl.github.io/psz-asset-viewer/enemies/lion_rare/) | blaze_helion (rig lion) | Generic basic placeholder | atkb | ef_e_c_sdd, ef_e_m_jmp, ef_e_m_stt |
| [lizard](https://dashgl.github.io/psz-asset-viewer/enemies/lizard/) | ghowl | Generic basic placeholder | — | ef_e_c_sdd, ef_e_m_stt |
| [lower](https://dashgl.github.io/psz-asset-viewer/enemies/lower/) | eulid | Generic basic placeholder | atk_a, atk_b | ef_e_d_stt |
| [lower_black](https://dashgl.github.io/psz-asset-viewer/enemies/lower_black/) | eulidveil | Generic basic placeholder | atk_a, atk_b | ef_e_d_stt |
| [mole](https://dashgl.github.io/psz-asset-viewer/enemies/mole/) | rumole | Generic basic placeholder | atkb | ef_e_c_mud, ef_e_c_sdd, ef_e_c_stt_c |
| [mother](https://dashgl.github.io/psz-asset-viewer/enemies/mother/) | mother_trinity | Generic basic placeholder | atk_gu_a_ed, atk_gu_a_lp, atk_gu_a_st, atk_sa_a, atk_sb_a, tec_a, tec_t_ed, tec_t_lp, tec_t_st | ef_e_c_granz, ef_e_c_sdd, ef_e_t_blt, ef_e_t_mzl, ef_e_t_tsuki |
| [mother_gun](https://dashgl.github.io/psz-asset-viewer/enemies/mother_gun/) | shot_mother | Generic basic placeholder | atk_gu_g_ed, atk_gu_g_lp, atk_gu_g_st, atk_sa_s, atk_sb_s, tec_a, tec_t_ed, tec_t_lp, tec_t_st | ef_e_c_granz, ef_e_c_sdd, ef_e_t_blt, ef_e_t_mzl, ef_e_t_tsuki |
| [mother_sword](https://dashgl.github.io/psz-asset-viewer/enemies/mother_sword/) | blade_mother | Generic basic placeholder | atk_gu_a_ed, atk_gu_a_lp, atk_gu_a_st, atk_sa_s, atk_sb_s, tec_a, tec_t_ed, tec_t_lp, tec_t_st | ef_e_c_granz, ef_e_c_sdd, ef_e_t_blt, ef_e_t_mzl, ef_e_t_tsuki |
| [mother_tech](https://dashgl.github.io/psz-asset-viewer/enemies/mother_tech/) | force_mother | Generic basic placeholder | atk_gu_g_ed, atk_gu_g_lp, atk_gu_g_st, atk_sa_s, atk_sb_s, tec_a, tec_t_ed, tec_t_lp, tec_t_st | ef_e_c_granz, ef_e_c_sdd, ef_e_t_blt, ef_e_t_mzl, ef_e_t_tsuki |
| [orangutan](https://dashgl.github.io/psz-asset-viewer/enemies/orangutan/) | froutang | Authored 3 attacks | — | ef_e_c_sdd, ef_e_l_ebul, ef_e_r_gun, ef_e_r_stt |
| [orangutan_rare](https://dashgl.github.io/psz-asset-viewer/enemies/orangutan_rare/) | frunaked (rig orangutan) | Authored 3 attacks | — | ef_e_c_sdd, ef_e_l_ebul, ef_e_r_gun, ef_e_r_stt |
| [quad](https://dashgl.github.io/psz-asset-viewer/enemies/quad/) | izhirak_s6 | Authored 2 attacks | — | ef_com_exp02, ef_com_explosion, ef_e_c_mdd, ef_e_l_ebul, ef_e_r_flsh, ef_e_r_flshb, ef_e_r_stt |
| [quad_rare](https://dashgl.github.io/psz-asset-viewer/enemies/quad_rare/) | azherowa_b2 (rig quad) | Authored 2 attacks | — | ef_com_exp02, ef_com_explosion, ef_e_c_mdd, ef_e_l_ebul, ef_e_r_flsh, ef_e_r_flshb, ef_e_r_stt |
| [rabbit](https://dashgl.github.io/psz-asset-viewer/enemies/rabbit/) | usanny | Generic basic placeholder | — | ef_e_c_sdd, ef_e_s_stt, ef_e_s_wbr |
| [rabbit_rare](https://dashgl.github.io/psz-asset-viewer/enemies/rabbit_rare/) | usanimere (rig rabbit) | Generic basic placeholder | — | ef_e_c_sdd, ef_e_s_stt, ef_e_s_wbr |
| [rappy](https://dashgl.github.io/psz-asset-viewer/enemies/rappy/) | rappy | Generic basic placeholder | — | ef_e_c_rstt, ef_e_c_sdd |
| [rappy_blue](https://dashgl.github.io/psz-asset-viewer/enemies/rappy_blue/) | ar_rappy (rig rappy) | Generic basic placeholder | — | ef_e_c_rstt, ef_e_c_sdd |
| [rappy_red](https://dashgl.github.io/psz-asset-viewer/enemies/rappy_red/) | rab_rappy (rig rappy) | Generic basic placeholder | — | ef_e_c_rstt, ef_e_c_sdd |
| [roc](https://dashgl.github.io/psz-asset-viewer/enemies/roc/) | pelcatraz | Authored 3 attacks | — | ef_e_c_sdd, ef_e_w_bspin, ef_enm_b_snc |
| [roc_rare](https://dashgl.github.io/psz-asset-viewer/enemies/roc_rare/) | pelcatobur (rig roc) | Authored 3 attacks | — | ef_e_c_sdd, ef_e_w_bspin, ef_enm_b_snc |
| [seal](https://dashgl.github.io/psz-asset-viewer/enemies/seal/) | hypao | Authored 2 attacks | — | ef_c_stt_w, ef_e_c_sdd, ef_e_w_ele |
| [seal_rare](https://dashgl.github.io/psz-asset-viewer/enemies/seal_rare/) | vespao (rig seal) | Authored 2 attacks | — | ef_c_stt_w, ef_e_c_sdd, ef_e_w_ele |
| [shooter](https://dashgl.github.io/psz-asset-viewer/enemies/shooter/) | korse | Authored 2 attacks | — | ef_com_exp02, ef_com_explosion, ef_e_c_mdd, ef_e_l_ebul, ef_e_l_stt |
| [shooter_leader](https://dashgl.github.io/psz-asset-viewer/enemies/shooter_leader/) | akorse | Authored 2 attacks | — | ef_com_exp02, ef_com_explosion, ef_e_c_mdd, ef_e_l_ebul, ef_e_l_stt |
| [shrimp](https://dashgl.github.io/psz-asset-viewer/enemies/shrimp/) | bolix | Authored 1 attacks | — | ef_e_c_sdd |
| [shrimp_rare](https://dashgl.github.io/psz-asset-viewer/enemies/shrimp_rare/) | goldix (rig shrimp) | Authored 1 attacks | — | ef_e_c_sdd |
| [snake](https://dashgl.github.io/psz-asset-viewer/enemies/snake/) | garapython | Authored 2 attacks | — | ef_e_c_sdd, ef_e_m_stt |
| [snake_rare](https://dashgl.github.io/psz-asset-viewer/enemies/snake_rare/) | garahadan (rig snake) | Authored 2 attacks | — | ef_e_c_sdd, ef_e_m_stt |
| [swordman](https://dashgl.github.io/psz-asset-viewer/enemies/swordman/) | arkzein | Generic basic placeholder | atk_pu, atk_sw, atk_th_ed, atk_th_st, atk_th_sw | ef_e_d_spin1, ef_e_d_spin2, ef_e_d_stt, ef_e_d_swd |
| [swordman_b](https://dashgl.github.io/psz-asset-viewer/enemies/swordman_b/) | zaphobos | Generic basic placeholder | atk_pu, atk_sw, atk_th_ed, atk_th_st, atk_th_sw | ef_e_d_spin1, ef_e_d_spin2, ef_e_d_stt, ef_e_d_swd |
| [swordman_rare](https://dashgl.github.io/psz-asset-viewer/enemies/swordman_rare/) | arkzein_r | Generic basic placeholder | atk_pu, atk_sw, atk_th_ed, atk_th_st, atk_th_sw | ef_e_d_spin1, ef_e_d_spin2, ef_e_d_stt, ef_e_d_swd |
| [swordman_rare_b](https://dashgl.github.io/psz-asset-viewer/enemies/swordman_rare_b/) | zaphobos_dyna | Generic basic placeholder | atk_pu, atk_sw, atk_th_ed, atk_th_st, atk_th_sw | ef_e_d_spin1, ef_e_d_spin2, ef_e_d_stt, ef_e_d_swd |
| [tank](https://dashgl.github.io/psz-asset-viewer/enemies/tank/) | phobos | Generic basic placeholder | atk_bz, atk_mi, atk_sh | ef_com_exp02, ef_com_explosion, ef_e_c_mdd, ef_e_l_arbd, ef_e_l_mine, ef_e_l_sgun, ef_e_l_stt |
| [tank_rare](https://dashgl.github.io/psz-asset-viewer/enemies/tank_rare/) | phobos_dyna | Generic basic placeholder | atk_bz, atk_mi, atk_sh | ef_com_exp02, ef_com_explosion, ef_e_c_mdd, ef_e_l_arbd, ef_e_l_mine, ef_e_l_sgun, ef_e_l_stt |
| [tiger](https://dashgl.github.io/psz-asset-viewer/enemies/tiger/) | kapantha | Generic basic placeholder | — | ef_e_c_sdd, ef_e_c_stt_c |
| [vulture](https://dashgl.github.io/psz-asset-viewer/enemies/vulture/) | vulkure | Generic basic placeholder | — | ef_e_c_sdd, ef_e_m_stt |
| [wolf](https://dashgl.github.io/psz-asset-viewer/enemies/wolf/) | reyhound | Generic basic placeholder | — | ef_e_c_sdd, ef_e_s_stt, ef_e_s_wbr |

**Not covered by this viewer:** local `chaos_sorcerer`, `poison_lily`, `shinowa`, `sinow_beat`, and `sinow_gold` have no matching model page. They require their own asset/reference audit.

**Coverage limits:** Model inventories are not attack event tables. Range, release frames, hit volumes, status probabilities, invulnerability and exact clip meanings still need recorded gameplay, saved user observations, or decoded behavior evidence. No runtime definitions were changed by this audit.

### Helion implementation checkpoint

The October 7 viewer audit above is a pre-implementation snapshot. Helion and
Blaze Helion now use `lunging_melee`, with `atk` close claws and `atkb` distant
spin-lunge. Imported durations are 1.3167 s and 0.9000 s. Inspecting all eight
poses per clip confirmed that `atkb` embeds about 16 source units of forward
`Point_Spine01` translation; its instance-local animation now preserves height
and rotation while collision-driven movement supplies planar travel.

Initial tuning: claws through 2.5 m, lunge to 7 m, active windows 30–60% and
15–70% respectively. The lunge commits direction/range, sweeps one contact, stops
at walls/floor edges, and cannot damage during preparation or recovery.
Blaze shares this verified rig mapping; elemental differences remain unverified.

Validation: 4,843 Godot checks and 698 web tests passed (4 web skips), plus
TypeScript, spec build, code-graph and orphan checks. Both real-rig Coliseum
probes passed claws, lunge, dodge at impact, wall blocking, weapon contact,
enemy damage, and room clear using disposable saves. The pure tests also cover
interruption/death, slow-frame sweep, floor gating, and shared-animation safety.
Repeat with `PSZ_ENEMY_RUNTIME_CHECK=1 PSZ_COLISEUM_ENEMY=helion` (or
`blaze_helion`) and the existing Coliseum probe in a disposable project.

Next user checkpoint: Helion's close claw readability, distant spin alignment,
dodge opportunity and recovery duration. After feedback/tuning, proceed to bats.

### Automated first-pass decisions — October 7

The web combat room tests player weapons against dummies. Its enemy-room sibling
and the Godot Coliseum now share explicit conditional scenarios in
`data/combat_scenarios.json`. Expectations are authored independently of the
attack table. Tests enter pursuit and observe ordinary AI; they do not select an
attack or force ATTACKING. Overlapping bands allow the appropriate weighted set.

- 27 scenario templates expand to 49 enemy cases across Helion/Blaze Helion,
  Hypao/Vespao, Rohjade/Rohcrysta, Garapython/Garahadan, Korse/Akorse and
  Froutang/Frunaked. All 49 passed with actual rigs in the Coliseum.
- The Godot unit runner repeats every case over eight seeds (392 checks). The
  web enemy-room FSM repeats its 41 applicable cases over eight seeds; freeze,
  dormancy, entrance and stun gates are explicitly Godot-only.
- Helion cases cover close/distant choice, either side of the claw/lunge split,
  maximum range, cooldown, hurt, recovery, freeze, dormancy, entrance and stun's
  no-attack phase. No-attack checks observe six physics frames; they do not imply
  the enemy can never attack after moving closer or its gate expires.
- Existing execution probes separately check timing, damage, dodge, wall contact,
  weapon hits and room clear. Decision tests do not verify every clip or effect.

Full suites: 5,235 Godot checks and 739 web tests passed (4 web skips), with
TypeScript, spec build, code-health and orphan checks passing. Saved live results:
[`combat-scenario-results.json`](combat-scenario-results.json).

Run an individual live decision pass in a disposable project with
`PSZ_COMBAT_SCENARIOS=1 PSZ_COLISEUM_ENEMY=helion` and
`res://scripts/tools/coliseum_probe.tscn`. Per-run JSON is written to that test
project's user-data directory as `combat-scenarios-<enemy>.json`. Add
`PSZ_ENEMY_RUNTIME_CHECK=1` to also run the existing supported family execution
check. Each newly implemented family should add scenarios before a user feel pass;
placeholder families are not silently treated as validated.


### Helion pursuit correction — October 8

User playtest: stt/run were absent or hard to see; Helion should aggressively
punish backing away to heal with repeated atkb attacks. Both Helion variants now
play the stationary harmless stt display on target acquisition, run during active
pursuit at all ranges (including beyond 7 m and while cooling down), and use
0.35–0.65 s post-attack recovery. The existing 1.5 s cooldown still gates attacks;
claw/lunge bands, committed facing, hit windows, dodge and wall checks are unchanged.
No healing-input detection was added. These are explicit gameplay choices; stt's
original DS trigger remains unverified.

The Godot runtime now honors authored fsm.loaf_duration_min/max, matching the web
sim. Only Helion/Blaze currently override these fields; other enemies keep their
2.5–4 s default. Tests cover display hold, run at far/near distances during cooldown,
eight seeded recovery samples per variant, and ordinary live AI displaying, running,
then starting two lunges as the target retreats. Both imported rigs also pass the
existing claws/lunge/dodge/wall, weapon-contact and room-clear checks.

Validation: 6,855 Godot checks and 874 web tests pass (4 skipped), TypeScript and
Astro builds, code-graph and orphan checks. The Bats + Helion mixed encounter also
passes participation and last-kill exit checks.

Reference follow-up: psz-re's current checkout was up to date. Its lion identity,
animation-event structure and effect attachments provide clues but do not establish
Helion's attack-selection rules. The supplied https://psp2i.dev/rozalin/pszm-decomp
returned HTTP 404 on both the repository page and Gitea API on October 8; HTTPS
clone requested credentials. No claims about that project's AI coverage can be
made until an accessible URL or checkout is available.

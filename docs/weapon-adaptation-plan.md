# All-weapon adaptation: checkpoint and test handoff

Status: adapting one gender–weapon pair at a time. The approved HUmar/saber prototype remains opt-in; broader campaign behavior has not been enabled. See PR #791 for the persistent checklist and the current **Resume here** record.

## Spec pages

- `/states/weapon-animation-mappings/`: all 16 weapon families plus unarmed, both genders; exact PSO IDs, inspected GLB clip inventory/hashes, source gaps and class overrides.
- `/states/weapon-state-transitions/`: UML-style locomotion, combo, reaction and context diagrams. Raw sources: `spec/src/diagrams/weapon-*.mmd`.
- `/states/weapon-adaptation-plan/`: P00–P05 shared work, A01–A17 individual adaptation plans, W01–W10 test protocol.

The pages are linked from the spec States index. Their source files are under `spec/src/pages/states/`. `spec/src/data/weapon-animation-adaptations.json` is a dated local asset audit, not a runtime profile. Refresh that audit when assets change; do not infer a missing female index from the male sequence.

## Current runnable fixture

Male — Saber is the approved reference. Female — Saber now uses HUmarl with native `pwsa` idle/attacks/dodge/defeat and female PSO saber clips 327–342. Normal walk uses the existing female general-walk bake (412). Female saber is owner-approved at `cd946912`. Male sword is owner-approved at `87fcf2bf`; female sword is owner-approved at `5bd1c1e3`. Male daggers are owner-approved at `e0ec8124`; female daggers are implemented and await playtest. The launcher accepts `--gender male|female` and `--weapon saber|sword|daggers`; both genders are supported for saber, sword and daggers.

From this worktree on this Mac:

```sh
cd /Users/kion/Projects/psz-godot-pr-791
export GODOT=/Users/kion/Applications/Godot.app/Contents/MacOS/Godot
python3 scripts/tools/run_humar_saber.py
```

Variants:

```sh
python3 scripts/tools/run_humar_saber.py --gender female
python3 scripts/tools/run_humar_saber.py --gender female --check --group
python3 scripts/tools/run_humar_saber.py --group
python3 scripts/tools/run_humar_saber.py --check
python3 scripts/tools/run_humar_saber.py --check --group
python3 scripts/tools/run_humar_saber.py --check --rendered
```

Restart the wrapper to reset the encounter. Its project/user directory isolates the fixture from campaign saves. Capture the exact `git rev-parse HEAD`, Godot version, local modifications and pack SHA before testing. A moving branch name alone is not a reproducible test reference.

## Clean setup / assets still needing publication

Follow `BUILD.md` and populate assets before importing. The current local prototype additionally uses the named charge and cursor WAV files, which must be included in the next asset-pack publication. A successful local test is not proof that the published pack contains them.

```sh
bash scripts/tools/fetch_assets_dev.sh
mkdir -p assets/sfx/common
cp web/public/assets/psobb_sfx/common/common_017.wav assets/sfx/common/
cp web/public/assets/psobb_sfx/common/common_060.wav assets/sfx/common/
"$GODOT" --headless --editor --path . --import
```

The fetch script must supply `assets/player/animations/pso_humar_saber.glb`; see `docs/humar-saber-prototype.md` for rebuild provenance if absent. Keep these SEGA-derived binary assets in the asset pipeline, not the source commit. For click-free exported playback, include the raw cursor WAV used for the PCM edge fade or publish a pre-softened imported cue; the current runtime gracefully falls back to ordinary playback if the raw source is absent.

## Approved saber reference

- PSZ relaxed idle and three native attacks; general normal walk, PSO saber caution/run/ready/reactions.
- Cursor-driven caution; 500 ms retreat hold before running; no proximity-only entry.
- 250 ms vulnerable first-attack preparation, with 80 ms pose blends.
- Normal and strong share a continuation window; palette circles replace ground rings.
- Mistimed early/late press: finish swing, then 250 ms stationary exposed recovery.
- Deliberate no-input stop: movement available after swing; attacks and guard locked for 300 ms.
- Full combo: 350 ms stationary ready recovery with deterministic frontal guard.
- Small strong-charge weapon sparks; subtle contact effect and impact sound only after HP loss; stronger accepted generic flinch.
- Softened lock-cursor sample, lower cue volume and suppression of same-target dropout repeats under 350 ms.

These are saber reference values, not final balance numbers for every weapon. The accuracy bypass and guaranteed guard must become explicit reviewed policies before campaign rollout. Keep ranged accuracy, bosses, multi-hit contact budgets and technique casting separate until P03 is complete.

## Resume record template

Copy this into **Resume here** in the PR description before leaving:

| Field | Value |
|---|---|
| Tester / date | |
| Commit / dirty changes | |
| Asset-pack SHA / extra local files | |
| Godot / platform / input | |
| Profile / avatar / weapon ID | e.g. A01-M / HUmar / saber |
| Scenario | solo / group / boss / export |
| Last completed test | Wxx |
| Next exact test | Wxx plus action to perform |
| Failure / blocker | test ID, expected vs actual, reproduction |
| Evidence | screenshot/video/log path or link |

Check a profile/gender row only after W01–W10 and its family-specific acceptance checks pass. For partial completion, record individual W IDs here and leave the row unchecked. Mark blocked profiles as **BLOCKED: reason**, not as passed. When code/assets change, mark affected completed rows for retest and preserve the previous revision/result in the record.

## Merge and release gates

1. Checkpoint and publish the approved prototype source; the PR checklist must reference that exact revision.
2. Resolve source/gender/role inventory and ship a selectable inspection fixture.
3. Extract the shared controller/profile API without changing the saber reference.
4. Implement and validate each enabled weapon/gender profile using its real hit/release schedule.
5. Publish matching animation/audio assets; validate a clean checkout and exported build.
6. Run campaign, status, boss, equipment-swap and input regressions. Original PR broad-regression failures remain open until independently resolved or classified.
7. Enable only reviewed profiles. Keep an explicit rollout/rollback gate; do not remove the prototype restriction as a shortcut to “all weapons supported.”

## Female saber asset provenance

Rebuild with `cd web && node scripts/bake-retarget.mjs --female-saber`, then import with Godot. The recipe targets `pc_010_000.glb` and selects only `pso_f_sa_*` from `data/retarget/Humar_body.glb`, producing `assets/player/animations/pso_female_saber.glb`. This local binary still needs asset-pack publication. The female profile fails visibly if its imported library is absent; it does not substitute the male profile.

Female saber local artifact SHA-256: `8452245239a43caa569d84dd214b6c6c9e8e209c6b20f1d464064329a1f5a54e`. Focused solo, three-Booma and rendered checks passed on Godot 4.5.1; male solo regression passed. Existing exit resource-leak warnings remain. Owner approved Female — Saber at `cd946912`.

## Male — Sword playtest

Run `python3 scripts/tools/run_humar_saber.py --weapon sword` (add `--group` for four Boomas, allowing the three-target cap to be tested). Rebuild the local library with `cd web && node scripts/bake-retarget.mjs --male-sword`, then import with Godot.

| Role | Explicit source |
| --- | --- |
| Relaxed idle / attacks 1–3 | PSZ `pmsw_wait`, `pmsw_atk1/2/3` |
| Normal walk | Existing general male PSO walk 200, `pmsa_walk` |
| Caution / ready / block | PSO 112 / 117 / 118, `pso_sw_walk_ready/wait/block` |
| Run | PSO saber run 111, baked as `pso_sw_run`; shared donor per owner reference |
| Light / heavy / fall / get up | PSO 122 / 120 / 123 / 121 |
| Dodge / defeated hold | Native PSZ `pmsw_esc_f`, `pmsw_dam_d_lp` |

Sword contacts use the decoded PSZ fractions 0.3191 / 0.3261 / 0.44 of the original swing, with held recoveries 180 / 200 / 280 ms. Normal and strong share the approved 55–95% continuation window. Range, three-target cap, damage, knockback and 60-degree chain turn limits remain sword-specific. Strong contact plays the sword swing cue. The shared short contact spark/sound and flinch remain as in the approved saber reference.

Focused checks cover all eight mixed combos, recovery outcomes, cursor caution, guard/reactions, exact contact onset, once-only delivery and a four-enemy test of the three-target limit. Female saber regression passed. Owner playtest and asset publication remain pending.

Local sword library SHA-256: `28e4347ddb314de8fa44e6284ffbc6a18930ee2a4d90c345a72ba11350fd6c60`.

Male sword carry grip: PSO run, caution and ready now use fixed per-pose forearm-space corrections that point the tip upward at the calibration pose while retaining animation sway. Grip changes blend over 80 ms; native PSZ attack/reaction/idle grips remain unchanged. Headless group and rendered checks verify upward carry direction and restoration of all three native attack grips.

## Female — Sword playtest

Run `python3 scripts/tools/run_humar_saber.py --weapon sword --gender female` (HUmarl). Add `--group` for four Boomas. Bake with `cd web && node scripts/bake-retarget.mjs --female-sword`, then import with Godot.

| Role | Explicit source |
| --- | --- |
| Relaxed idle / three attacks | Native `pwsw_wait`, `pwsw_atk1/2/3` |
| Normal walk | Female general walk 412, existing `pwsa_walk` |
| Caution / ready / block | PSO 343 / 348 / 349 |
| Run | Shared female saber run 342, baked as `pso_f_sw_run` |
| Light / heavy / fall / get up | PSO 353 / 351 / 354 / 352 |
| Dodge / defeated hold | Native `pwsw_esc_f`, `pwsw_dam_d_lp` |

Previously unlabeled clips 348/349/350/353/355 were rendered and inspected as ready/block/walk/light damage/photon-blast poses before adding labels. Native attacks remain authoritative; source 350 is inventoried but normal walk retains the approved general female walk. The female body has its own calibrated carry grips rather than reusing male angles. Sword contact fractions, recovery holds, target cap and turn limits match the approved male reference. Solo rendered, four-enemy group and male-sword regression checks pass. Owner playtest and asset-pack publication remain pending.

Local female sword library SHA-256: `21c6262b40766800e8fd16b1678a621c279bdaf5abd1b2191b362d8dbf8d6251`.

## Male — Daggers playtest

Run `python3 scripts/tools/run_humar_saber.py --weapon daggers` (HUmar), with optional `--group` for three Boomas. Bake with `cd web && node scripts/bake-retarget.mjs --male-daggers`, then import with Godot. Female daggers are now available with `--gender female`.

| Role | Explicit source |
| --- | --- |
| Relaxed idle / attacks | Native `pmda_wait`, `pmda_atk1/2/3` |
| Normal walk | General male walk 200, existing `pmsa_walk` |
| Caution / ready / block | PSO 125 / 130 / 131 |
| Run | Shared male saber run 111, baked as `pso_da_run` (explicit donor; no mapped dedicated dagger run) |
| Light / heavy / fall / get up | PSO 135 / 133 / 136 / 134 |
| Dodge / defeated hold | Native `pmda_esc_f`, `pmda_dam_d_lp` |

Preserve the decoded native hit schedule from `original_attack_timing.json`: 2/1/3 contacts, at [0.1556, 0.3333] / [0.2895] / [0.2075, 0.4151, 0.5849] of the original motion. These records take precedence over the old generic 2/2/3 hit-count defaults. Recovery holds are 100/120/180 ms; the approved normal/strong continuation window remains shared. Each impact consumes one target, with a 120-degree chain turn limit. Prototype reach is tuned to 2.6, horizontal cone 38 degrees, vertical tolerance 0.9 and vertical cone 45 degrees; targeting and contact share the same configuration. Every contact of a strong swing retains 1.5× power plus strong impact feedback and extended flinch, including all three contacts of the finisher. The windup cue plays once per swing. An 80 ms per-enemy feedback throttle prevents sound/particle bursts when a slow frame catches up multiple contacts. Damage contacts are never throttled.

Focused checks verify both hand attachments, authored contact onset, no repeat contact, single-target cap, strong feedback on every impact, all mixed combos and recovery outcomes. Group and rendered solo checks pass; female sword regression passes. Owner playtest and asset publication are pending.

Local male dagger library SHA-256: `a94743d033da4ab10f893857c7e64541b0e8809e7511921fffef52e382f5b30c`.

Male dagger visual: the fixture uses the native PSZ Ein Dagger (`wdac01_1_r`) mesh, native scale and tint in both hands. The equipped `dagger` resource and all combat stats remain unchanged. The shared registry resources are not mutated.

The interactive male dagger fixture includes a left-grip adjustment panel: local X/Y/Z rotations in 180°, 90° and 5° increments, Reset, Copy angles, and Save. Enemies start frozen while adjusting; toggle to resume combat. Save persists the exact basis in the ignored local `.godot/dagger-left-grip.json`; automated checks ignore this personal override. Once accepted, promote the saved basis into the attachment defaults.

Owner-saved left dagger grip promoted into the default: basis columns `(0,0,-1)`, `(0,-1,0)`, `(1,0,0)`, retaining native scale. Reset in the live panel now returns to this calibrated default.

Dagger reach checks cover an offset target at (0.8, 0, 2.2), agreement with the lock cursor, and rejection of targets behind or at distance 4. Strong third-swing power is verified against normal with identical damage variance.

## Female — Daggers playtest

Run `python3 scripts/tools/run_humar_saber.py --weapon daggers --gender female` (HUmarl). Add `--group` for three Boomas. Bake with `cd web && node scripts/bake-retarget.mjs --female-daggers`, then import with Godot.

| Role | Explicit source |
| --- | --- |
| Relaxed idle / attacks 1–3 | Native `pwda_wait`, `pwda_atk1/2/3` |
| Normal walk | General female walk 412, existing `pwsa_walk` |
| Caution / ready / block | PSO 356 / 357 / 358 |
| Run | Shared female saber run 342, baked as `pso_f_da_run` |
| Light / heavy / fall / get up | PSO 361 / 359 / 362 / 360 |
| Photon blast inventory | PSO 363 |
| Dodge / defeated hold / casting | Native `pwda_esc_f`, `pwda_dam_d_lp`, `pwda_tec` |

The shorter female source sequence 356–363 was rendered and inspected before labeling; it is not a fixed offset of the male dagger block. Missing female PSO attacks/casting are not invented: attacks and casting explicitly use native clips. Female contacts use the approved dagger profile's 2/1/3 normalized timing schedule, holds and continuation window against the female native motion lengths. Reach, targeting, strong feedback on every contact and the PSZ Ein Dagger models retain the approved male settings. Both attachment grips use the owner-calibrated defaults.

Group, rendered solo and male-dagger regression checks passed. Owner playtest and asset-pack publication remain pending. The grip panel is available; uncheck Freeze enemies for combat. Female adjustments save separately to `.godot/dagger-female-left-grip.json`, leaving the male override untouched.

Local female dagger library SHA-256: `bfa43ab82232ff75c1a4122ddb84b01c787f614ef7990a3535af76acb707387b`.

Shared successful-block feedback: a 300 ms blue-white particle burst plus a 320 ms camera-facing cyan guard flash at chest height toward the attacker, emitted only after guard acceptance. Rear/rejected blocks emit nothing. All adapted weapon profiles share it; focused checks verify emission and cleanup.

Guard flash v2 is visible through overlapping enemy geometry at chest height. The fixture window title identifies this revision; the grip panel includes Preview block to demonstrate the effect without requiring a gameplay block. Rendered checks verify emission and cleanup.

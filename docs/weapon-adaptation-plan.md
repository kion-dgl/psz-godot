# All-weapon adaptation: checkpoint and test handoff

Status: adapting one gender–weapon pair at a time. The approved HUmar/saber prototype remains opt-in; broader campaign behavior has not been enabled. See PR #791 for the persistent checklist and the current **Resume here** record.

## Spec pages

- `/states/weapon-animation-mappings/`: all 16 weapon families plus unarmed, both genders; exact PSO IDs, inspected GLB clip inventory/hashes, source gaps and class overrides.
- `/states/weapon-state-transitions/`: UML-style locomotion, combo, reaction and context diagrams. Raw sources: `spec/src/diagrams/weapon-*.mmd`.
- `/states/weapon-adaptation-plan/`: P00–P05 shared work, A01–A17 individual adaptation plans, W01–W10 test protocol.

The pages are linked from the spec States index. Their source files are under `spec/src/pages/states/`. `spec/src/data/weapon-animation-adaptations.json` is a dated local asset audit, not a runtime profile. Refresh that audit when assets change; do not infer a missing female index from the male sequence.

## Current runnable fixture

Male — Saber is the approved reference. Female — Saber now uses HUmarl with native `pwsa` idle/attacks/dodge/defeat and female PSO saber clips 327–342. Normal walk uses the existing female general-walk bake (412). Female owner playtest is pending; all other pairs remain unimplemented. The launcher accepts `--gender male|female`, but no weapon or arbitrary class selection.

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

Female saber local artifact SHA-256: `8452245239a43caa569d84dd214b6c6c9e8e209c6b20f1d464064329a1f5a54e`. Focused solo, three-Booma and rendered checks passed on Godot 4.5.1; male solo regression passed. Existing exit resource-leak warnings remain. Next action: owner playtest Female — Saber; do not check it off from automated results alone.

# HUmar saber combat prototype (#790)

This opt-in Coliseum experiment combines PSZ idle and saber attacks with PSO locomotion, readiness and reactions on the current PSZ HUmar VRM. It tests approach, commitment, defense and recovery at fixed starting stats. It does not change campaign balance or status effects (#789).

## Run

Populate the current game assets following BUILD.md (the new library is mirrored with the assets). To rebuild the library locally when changing the retarget, use the existing `data/retarget/Humar_body.glb` source:

```sh
cd web
node scripts/bake-retarget.mjs --humar-saber
```

From the repository root, import the new library once and launch:

```sh
godot --headless --editor --path . --import
python3 scripts/tools/run_humar_saber.py
python3 scripts/tools/run_humar_saber.py --group
```

The launcher invokes `res://scripts/tools/humar_saber_probe.tscn` inside an isolated temporary project. Launch through the wrapper, which supplies the required save-isolation settings. Restart it to reset the encounter. The fixture uses a level-one HUmar with starter saber and level-one PSO Booma, or three Boomas with `--group`. Fixture opponents award no EXP, keeping player stats fixed during group fights. Movement, attack and dodge use the existing controls. Caution engages when the visible targeting cursor acquires a living enemy during approach or lateral movement; proximity alone does not engage it. Retreat keeps caution for 500 ms, including after the cursor drops, then transitions directly to running. Reacquiring a target cancels the retreat countdown; stopping or entering combat resets elapsed retreat time. With no prior cursor engagement, ordinary walk-to-run progression applies. Standing always uses native `pmsa_wait`; proximity alone never selects weapon-ready. All three attacks use native `pmsa_atk1`–`pmsa_atk3`; the PSO swings remain in the library for inspection only.

Automatic frontal guard is a provisional rule for review: while idle, walking, or in the earned finisher-ready cooldown, a melee hit from within a 60-degree half-angle plays block and is absorbed. Attack preparation, active swings, failed-combo recovery, stopped-combo attack cooldown, running, rolling and damage recovery do not guard. Guard commits for the block animation. This is not a claim about PSO's original stat-based guard algorithm. Existing PSZ dodge remains unchanged; its native clip and the defeated hold are retained as fallbacks alongside the 15 PSO clips.

## Animation inventory

`data/retarget/pso_animation_map.json` maps all 15 source clips:

| Source | Action |
|---|---|
| 097 | Caution walk |
| 098 | Technique cast |
| 099–101 | Three saber attacks |
| 102 | Ready idle |
| 103 | Block |
| 104 | Walk |
| 105 | Heavy damage reaction |
| 106 | Get up |
| 107 | Light damage reaction |
| 108 | Fall down |
| 109 | Button interaction |
| 110 | Photon Blast |
| 111 | Run |

The baker reuses the existing PSO→PSZ retarget pipeline and writes only `assets/player/animations/pso_humar_saber.glb` in prototype mode. It fails if any source clip is missing. Horizontal root translation is removed from every prototype clip; vertical pose is retained. The game body owns locomotion, keeping the visible rig and hit geometry together. Existing weapon libraries are retained. Utility clips are included even when the encounter does not call them. The earlier retarget notes incorrectly placed caution/cast at 112–113; those are sword clips.

## Review

The three PSZ swings retain native motion speed, followed by held recovery poses of 0.14, 0.16 and 0.22 seconds. The queued next swing waits for this recovery; damage can still interrupt it. Normal walking uses the existing general `pmsa_walk` clip instead of saber source 104; caution walk 097 and run 111 remain unchanged. Connected physical hits from this fixture bypass the accuracy roll while retaining reach, facing, defense and immunity checks. Contact fractions (40%, 40%, 45% of the motion, excluding added recovery) are retained as an initial playtest baseline for the native swings, not visually calibrated contact markers. These fractions and the chain window (55–95%) are explicit provisional tuning, not recovered PSO timings. A shrinking circle on each attack palette icon uses the same chain window as input: pale countdown, green for valid input, gold for a queued follow-up. It disappears on fumble, interruption and the final swing. Ground timing/charge rings are disabled in this fixture. Check saber contact alignment, foot planting, attack recovery, blocking commitment and whether avoiding retaliation feels understandable. Record failures before expanding to other weapons or classes.

```sh
python3 scripts/tools/run_humar_saber.py --check
python3 scripts/tools/run_humar_saber.py --check --group
```

The live probe checks the real Coliseum/VRM, complete library, attachment, caution range, frontal guard, rear-hit rejection, attack commitment, chaining and interruption/recovery. `humar_saber_tests.gd` adds guard direction boundaries to the ordinary test runner. Render the probe with `--check --rendered`; `PSZ_BOSS_SCREENSHOTS=/absolute/directory` captures its visual checkpoint.

Owner playtesting remains required. The Combat and Character grades are unchanged. The normative prototype contract is `/states/humar-saber-prototype/`.

## Bake provenance

The prototype exports directly from the original HUmar skeleton, independent of mutable weapon libraries. Verified repeated bake hashes:

- `data/retarget/Humar_body.glb`: `953d5d6f11fe8af8155740e2c697414af4e5879d0619b2c09dd597694a455b26`
- `assets/player/pc_000/pc_000_000.glb`: `b9ec7af4eea5a081cc60826d0046a96e8f9607d3ca5114f396f3511b3e8be865`
- `assets/player/animations/pso_humar_saber.glb`: `623ffc194db77f10df11bf96fbfa7cca83c75d6a60c2cc66dd658ead816774a0`

## Mixed attacks and audio

Normal and strong inputs share the same chain window and full step duration in this fixture. Strong attacks use their existing animation windup for the charge tell, with no additional 400 ms delay. SE_PL_BIGCHARGE (`common_060.wav`) plays at windup start; the saber swing sound follows at contact. Charge visuals end at contact or interruption. SE_PL_LOCKCURSOR (`common_017.wav`) plays once on acquiring or changing the primary enemy cursor, never every frame or on losing a target. Reacquiring the same enemy after a dropout shorter than 350 ms stays silent; changing enemies still cues immediately. Cursor audio is reduced by 5 dB and uses cached 5 ms edge fades to suppress the source sample's initial spike. The fade decodes the source WAV if the imported resource is compressed; builds without that source fall back to the normal cue.

The two sounds must be imported under `assets/sfx/common/`. For local testing, copy them from `web/public/assets/psobb_sfx/common/` (populated by the asset fetch script) and reimport. They are asset-pack content and must join the next pack publication before a distributed build uses this revision.

## Contact feedback

Strong windup emits eight small weapon-local sparks without whole-body glow. Successful hits emit a brief four-spark contact burst (seven warm sparks for strong hits) and the existing saber impact sound, quieter for normal attacks. Strong hits extend an already-accepted generic enemy flinch to 0.45 seconds; immunity, death and enemies without generic hurt reactions are respected. Effects require actual HP loss and clean themselves up. This is a prototype visual treatment, not an exact recreation of Portable 2.

## Retreat and earned readiness

Both normal and strong first attacks share a 250 ms weapon-ready preparation, with an 80 ms blend into the pose and into the first swing. Finisher-ready also blends in and returns smoothly to relaxed idle. It is committed and vulnerable, with no chain input until the swing begins. A completed three-step combo enters a 350 ms ready stance that blocks frontal melee; a mistimed early or late press causes an unguarded, stationary 250 ms recovery after the swing. These committed recoveries cannot be canceled by attacking or dodging. Deliberately stopping by providing no follow-up releases movement immediately at swing completion, but locks both attack types and guard for 300 ms. Damage clears the pending phase, so no delayed swing can resume after interruption. This playtest uses guaranteed frontal guard versus no guard during the respective cooldowns, not a probabilistic bonus. Ordinary idle/walking guard remains available after cooldown expiry.

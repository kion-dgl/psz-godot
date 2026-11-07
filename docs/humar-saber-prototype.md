# HUmar saber combat prototype (#790)

This opt-in Coliseum experiment uses PSO saber motion on the current PSZ HUmar VRM. It tests approach, commitment, defense and recovery at fixed starting stats. It does not change campaign balance or status effects (#789).

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

The launcher invokes `res://scripts/tools/humar_saber_probe.tscn` inside an isolated temporary project. Launch through the wrapper, which supplies the required save-isolation settings. Restart it to reset the encounter. The fixture uses a level-one HUmar with starter saber and level-one PSO Booma, or three Boomas with `--group`. Fixture opponents award no EXP, keeping player stats fixed during group fights. Movement, attack and dodge use the existing controls. Within six metres of a living enemy, walking remains cautious. Outside that range, the normal walk-to-run transition returns.

Automatic frontal guard is a provisional rule for review: while idle or walking, a melee hit from within a 60-degree half-angle plays block and is absorbed. Attacking, running, rolling and recovering do not guard. Guard commits for the block animation. This is not a claim about PSO's original stat-based guard algorithm. Existing PSZ dodge remains unchanged; its native clip and the defeated hold are retained as fallbacks alongside the 15 PSO clips.

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

The first two swings use their source durations; the third is substantially longer. Contact fractions (40%, 40%, 45%) and the chain window (55–95%) are explicit provisional tuning, not recovered PSO timings. A timing ring uses the same chain window as input. Check saber contact alignment, foot planting, attack recovery, blocking commitment and whether avoiding retaliation feels understandable. Record failures before expanding to other weapons or classes.

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

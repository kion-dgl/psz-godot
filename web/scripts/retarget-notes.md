# PSO -> PSZ Animation Retargeting Notes

## Model Overview

### PSZ (Phantasy Star Zero)
- **12 bones** total (simple skeleton)
- **Scale**: ~1.5 units tall (game units)
- **Bone naming**: `NNN_Name` format (e.g., `010_Hip`, `060_RArm01`)
- **Rest pose approach**: Complex multi-axis local rotations. Hip has -90 Y, spine has (90, -80, 180), arms have ~135 degree compound rotations
- **Bone orientation**: Local X-axis generally points along the bone (positions like `(0.27, 0, 0)` for arm segments, `(0.32, 0, 0)` for leg segments)
- **Root bone** (`000_Root`): Identity quaternion at origin

### PSO (Phantasy Star Online)
- **64 bones** (bone_000 to bone_063, plus bone_000_1, bone_000_2)
- **Scale**: ~16 units tall (roughly 10x PSZ)
- **Bone naming**: `bone_NNN` format (numbered, no semantic names)
- **Rest pose approach**: Primarily Z-axis rotations for pre-rotation. Hip is -91 Z, spine is +91 Z (cancels hip), arms are ~-83 Z, legs are ~-94 Z
- **Bone orientation**: Local X-axis points along bones (positions like `(2.5, 0, 0)` for arm segments, `(3.95, 0, 0)` for leg segments)
- **Root bone** (`bone_000`): Identity quaternion at origin
- Has extra bones for fingers, toes, accessories, etc. that PSZ doesn't have

## Bone Mappings (12 mapped bones)

| PSO Bone | PSZ Bone | Body Part |
|----------|----------|-----------|
| bone_000 | 000_Root | Root |
| bone_002 | 010_Hip | Hip/Pelvis |
| bone_024 | 020_Spine | Spine/Chest |
| bone_028 | 030_LArm01 | Left Upper Arm |
| bone_029 | 040_LArm02 | Left Lower Arm |
| bone_041 | 060_RArm01 | Right Upper Arm |
| bone_042 | 070_RArm02 | Right Lower Arm |
| bone_056 | 090_Head | Head |
| bone_004 | 100_LLeg01 | Left Upper Leg |
| bone_005 | 110_LLeg02 | Left Lower Leg |
| bone_013 | 120_RLeg01 | Right Upper Leg |
| bone_014 | 130_RLeg02 | Right Lower Leg |

## PSO Bone Hierarchy (mapped bones in context)

```
bone_000 (root)
  bone_001 (position offset to hip height)
    bone_002 (hip) — Z rotation -91°
      bone_003 → bone_004 (LLeg01) → bone_005 (LLeg02) → bone_006..011 (foot/toes)
      bone_012 → bone_013 (RLeg01) → bone_014 (RLeg02) → bone_015..020 (foot/toes)
      bone_024 (spine) — Z rotation +91° (cancels hip rotation)
        bone_025 (chest/upper spine)
          bone_026 → bone_027 → bone_028 (LArm01) → bone_029 (LArm02) → bone_030..037 (hand/fingers)
          bone_039 → bone_040 → bone_041 (RArm01) → bone_042 (RArm02) → bone_043..051 (hand/fingers)
          bone_055 → bone_056 (Head) → bone_057..059 (face)
```

Note: PSO has intermediate bones between mapped bones (e.g., bone_003 between hip and LLeg01, bone_027 between spine chain and arms). These intermediate bones have their own rotations that contribute to the world-space orientation.

## PSZ Bone Hierarchy

```
000_Root
  010_Hip — Y rotation -90°
    120_RLeg01 → 130_RLeg02
    020_Spine (complex compound rotation)
      060_RArm01 → 070_RArm02
      090_Head
      030_LArm01 → 040_LArm02
    100_LLeg01 → 110_LLeg02
```

## Key Differences

### 1. Pre-rotation Axes
- **PSO**: Almost exclusively uses Z-axis rotation for bone pre-rotations (the "old school" approach)
- **PSZ**: Uses complex multi-axis compound rotations (more modern approach with arbitrary rest orientations)
- This means PSO's local rotation space is very different from PSZ's local rotation space for corresponding bones

### 2. Intermediate Bones
PSO has bones between mapped positions that PSZ doesn't:
- `bone_001` between root and hip (just a position offset)
- `bone_003` / `bone_012` between hip and legs (with -90/+90 X rotations and 5-6° Z)
- `bone_025` between spine and everything above (89.6° Z)
- `bone_026`/`bone_027` and `bone_039`/`bone_040` between chest and arms (with 90° Y rotation)
- `bone_055` between chest and head

These intermediate bones accumulate rotations that affect the world-space orientation of mapped bones.

### 3. World-Space Rest Orientations (the core problem)

Comparing world-space euler angles at rest for each mapped pair:

| Body Part | PSO World Euler | PSZ World Euler | Difference |
|-----------|----------------|-----------------|------------|
| Root | (0, 0, 0) | (0, 0, 0) | Same |
| Hip | (0, 0, -91) | (0, -90, 0) | Different axes |
| Spine | (0, 0, 0) | (170, 0, -90) | Very different |
| LArm01 | (-83, 90, 0) | (3.5, -2.3, -44) | Very different |
| RArm01 | (-83, 90, 0) | (3.5, 2.3, -136) | Very different |
| Head | (0, 0, 91) | (-180, 0, -90) | Very different |
| LLeg01 | (-90, 85, -4) | (-175, 0, 90) | Very different |
| RLeg01 | (90, 86, 176) | (-175, 0, 90) | Very different |

The world-space rest orientations are fundamentally different for every bone pair except root. This means:
- A "swing forward" rotation in PSO world space is NOT the same axis as "swing forward" in PSZ world space
- Simple local or world quaternion remapping won't work correctly

### 4. Animation Structure
- PSO animations contain **position, rotation (quaternion), and scale** tracks per bone per keyframe
- Animations are **relative to rest pose** — zeroing out rest rotations breaks the model
- Only **rotation tracks** should be transferred (position and scale are skeleton-specific)

## Retargeting Approaches Tried

### Approach 1: Direct Copy (failed)
Just rename bone tracks. Result: completely twisted/mutilated model because local coordinate frames are totally different.

### Approach 2: Local Rest-Pose Delta (partially worked)
`pszLocal = pszRest * inv(psoRest) * psoAnim`
Result: character stands up, arms/legs move, but swing directions are wrong (legs waddle sideways instead of forward/back). The local rest delta doesn't account for the different parent chain orientations.

### Approach 3: World-Space Delta (had a bug, now fixed)
Original (buggy) implementation extracted a LEFT (world-frame) delta but applied it on the RIGHT (bone-frame):
```
worldDelta = psoWorld * inv(psoWorldRest)     // LEFT extraction
pszWorldAnimated = pszWorldRest * worldDelta  // RIGHT application (BUG!)
```
This mismatch caused dampened/subtle movements. For arm bones the error was up to 170°.

### Approach 4: Conjugation (current, correct)
Re-express the local animation delta from PSO's bone coordinate frame to PSZ's:

```
localDelta = inv(psoLocalRest) * psoLocalAnim     // delta in PSO bone frame
F = inv(pszWorldRest) * psoWorldRest               // frame correction PSO -> PSZ
pszDelta = F * localDelta * inv(F)                 // conjugate to PSZ's frame
pszLocal = pszLocalRest * pszDelta
```

Optimized form (precompute per bone, 2 quat multiplies per keyframe):
```
prefix = pszLocalRest * F * inv(psoLocalRest)
suffix = inv(F)
pszLocal = prefix * psoLocalAnim * suffix
```

Verified via `retarget-test.mjs`: this produces identical results to the corrected world-frame approach (left-left), with 0.0° difference across all bones and keyframes.

## Mapped PSO Animations (Humar)

Animations are grouped per weapon. The pattern repeats: each weapon set starts with attacks, then idle/block/walk/damage/utility/run/tech.

### Saber (indices 99–113)

| Index | Name | Description |
|-------|------|-------------|
| 099 | pso_sa_atk1 | Saber Attack 1 |
| 100 | pso_sa_atk2 | Saber Attack 2 |
| 101 | pso_sa_atk3 | Saber Attack 3 |
| 102 | pso_sa_wait | Saber Idle Ready |
| 103 | pso_sa_block | Saber Block |
| 104 | pso_sa_walk | Saber Walk |
| 105 | pso_sa_dam_h | Saber Damage (flip back) |
| 106 | pso_sa_dam_d_wa | Saber Get Back Up |
| 107 | pso_sa_dam_n | Saber Damage (light) |
| 108 | pso_sa_dam_d | Saber Damage (fall down) |
| 109 | pso_sa_press | Saber Press Button |
| 110 | pso_sa_pb | Saber Photon Blast |
| 111 | pso_sa_run | Saber Run |
| 112 | pso_sa_walk_ready | Saber Walk Ready |
| 113 | pso_sa_tec | Saber Cast Tech |

**Note:** Index 114 likely starts the sword weapon set following the same pattern.

## Remaining Issues

1. **PSO has 3 skins**: The GLB has `bone_000`, `bone_000_1`, `bone_000_2` suggesting multiple skin/skeleton variants. Currently using the first one.

2. **Animation sets to map**: Sword (114+), Dagger, Spear, Claw, Shield, Handgun, Rifle, Machinegun, Grenade, Rod, Wand, Slicer — each likely follows the same 15-animation pattern as saber.

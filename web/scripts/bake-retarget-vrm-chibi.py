#!/usr/bin/env python3
"""Bake PSO animations onto stock VRM models' J_Bip_* rigs.

Python sibling of bake-retarget-vrm.mjs (the PSO→VRM bake that drives the
item-shop NPC). Supports two targets, selected by argv (default: example):

- example (assets/npcs/vrm_example/) — standard VRoid Studio export
  (VRM 1.0, "example"). Commit-safe: it's the user's own model.
- chibi (assets/npcs/vrm_chibi/) — chibi_model_2.0.vrm (VRM 0.x),
  Redistribution_Prohibited: GITIGNORED, local-only experiment.

Rest poses are captured from each skin's inverseBindMatrices (what three.js
skeleton.pose() restores), NOT the glTF node TRS — in Humar_body.glb those
two poses differ, and conjugating against the TRS pose was the root cause of
the first bake's crossed legs / backward bow / drifting root.

Offsets are PER MODEL (see MODELS notes): neutral keyframes conjugate to the
target's OWN rest, so the tuned rest must read as natural standing — facing
matching the PSO clip's bind yaw, feet planted, arms hanging. VRM 1.0 rests
face +Z (same as PSO — only the clip's own −15° bind yaw needs compensating),
while VRM 0.x rests face −Z (needs the extra 180° flip, which also mirrors
the local-z direction of the arm/leg offsets).

Usage: python3 web/scripts/bake-retarget-vrm-chibi.py [example|chibi]
"""

import json
import math
import os
import struct

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PSO_PATH = os.path.join(REPO_ROOT, "data/retarget/Humar_body.glb")

# PSO bone -> VRM bone — verbatim from bake-retarget-vrm.mjs
# (BONE_MAPPINGS_VRM). bone_000 -> Root: VRM keeps an origin-rooted Root
# bone above the hips, so root motion lands there rather than on the hips.
BONE_MAPPINGS_VRM = {
    "bone_000": "Root",
    "bone_002": "J_Bip_C_Hips",
    "bone_024": "J_Bip_C_Chest",
    "bone_025": "J_Bip_C_UpperChest",
    "bone_028": "J_Bip_L_UpperArm",
    "bone_029": "J_Bip_L_LowerArm",
    "bone_041": "J_Bip_R_UpperArm",
    "bone_042": "J_Bip_R_LowerArm",
    "bone_056": "J_Bip_C_Head",
    "bone_004": "J_Bip_L_UpperLeg",
    "bone_005": "J_Bip_L_LowerLeg",
    "bone_013": "J_Bip_R_UpperLeg",
    "bone_014": "J_Bip_R_LowerLeg",
}

# Per-model paths, clip suffix, and tuned rest offsets. Derived by rest-pose
# FK against the PSO idle reference frame (facing −14.9°, foot spread
# 0.10h, arms hang): neutral keyframes conjugate to the target's OWN rest,
# so the rest stance must read as a natural standing pose first.
MODELS = {
    # Standard VRoid Studio export (VRM 1.0). VRM 1.0 rests face +Z like the
    # PSO assets, so only the PSO clip's own −14.9° bind yaw compensates —
    # and without the VRM 0.x 180° flip, the local-z arm direction mirrors:
    # arms-down is L z−90 / R z+90 (the chibi's signs would point them at
    # the sky). Feet plant at 0.095h spread natively — no leg or chest trim.
    "example": {
        "target": os.path.join(REPO_ROOT, "assets/npcs/vrm_example/vrm_example.glb"),
        "out": os.path.join(REPO_ROOT, "assets/npcs/vrm_example/npc_idles_vrm.glb"),
        # _vex (not _vrm): the item-shop lib already owns pso_f_emote_bow_vrm /
        # pso_f_emote_wave_vrm and sits earlier in CityNPC's ANIM_SOURCES —
        # a shared suffix would hand the example rig item-shop-tuned clips.
        "suffix": "_vex",
        "offsets": {
            "Root": {"x": 0, "y": -14.9, "z": 0},
            "J_Bip_L_UpperArm": {"x": 0, "y": 0, "z": -90},
            "J_Bip_R_UpperArm": {"x": 0, "y": 0, "z": 90},
        },
    },
    # chibi_model_2.0.vrm (VRM 0.x) — local-only, Redistribution_Prohibited:
    # - Root y:180 — VRM 0.x rest faces -Z while PSO assets face +Z; without
    #   it every clip plays on a character turned backwards.
    # - UpperArm z ±90 — T-pose arms down to hang at the sides; under the
    #   180° flip the local-z signs mirror vs the example model.
    # - UpperLeg z ±5 — the chibi's own rest crosses its feet; widens the
    #   stance toward PSO's proportional spread.
    # - UpperChest x14.7/z−0.4 — posture lean carried from the item-shop rig.
    "chibi": {
        "target": os.path.join(REPO_ROOT, "assets/npcs/vrm_chibi/vrm_chibi.glb"),
        "out": os.path.join(REPO_ROOT, "assets/npcs/vrm_chibi/npc_idles_vrm.glb"),
        "suffix": "_chibi",
        "offsets": {
            "Root": {"x": -0.2, "y": 198, "z": 0},
            "J_Bip_C_UpperChest": {"x": 14.7, "y": 0, "z": -0.4},
            "J_Bip_L_UpperArm": {"x": 0, "y": 0, "z": 90},
            "J_Bip_R_UpperArm": {"x": 0, "y": 0, "z": -90},
            "J_Bip_L_UpperLeg": {"x": 0, "y": 0, "z": -5},
            "J_Bip_R_UpperLeg": {"x": 0, "y": 0, "z": 5},
        },
    },
}

# Bound late (in __main__) from MODELS so both bakes share the code below.
TARGET_PATH = None
OUT_PATH = None
BAKED_OFFSETS = None
SUFFIX = None

# PSO-frame copy disabled: copying the PSO arm bone's world frame
# (X-along-bone) onto a VRM rig (-Y-along-bone) lands the arms skyward on
# these proportions. The own-rest + z±90 offsets above replace it.
ARM_CORRECTION_PSO_BONES = []

ANIMS = [
    (335, "pso_f_sa_stand"),  # counter-clerk idle
    (421, "plymotiondata_421"),  # storage-close reaction
    (429, "pso_f_emote_bow"),  # quest-accept bow
    # showcase set — identities confirmed by FK probe + browser capture
    # (plymotiondata_NNN index kept here as the source-of-truth reference)
    (417, "pso_f_emote_wave"),  # held one-hand wave
    (433, "pso_f_emote_wave2"),  # alternating-hands wave with hip sway
    (216, "pso_f_emote_raise"),  # both hands half-up, then right hand held high
    (427, "pso_f_emote_cheer"),  # both hands climb to head height, held
    (316, "pso_f_sit_floor"),  # drops to seated on the floor and scoots
    (109, "pso_sa_press"),  # saber-set "press button" — counter clerk reach
    (104, "pso_sa_walk"),  # saber-set walk (carries root motion)
    (111, "pso_sa_run"),  # saber-set run (carries root motion)
]


# ── quaternion helpers (glTF layout: x, y, z, w) ────────────────────────────

def q_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def q_conj(q):
    return (-q[0], -q[1], -q[2], q[3])


def q_norm(q):
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    return tuple(c / n for c in q)


def v_add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def q_rotate(q, v):
    qv = (v[0], v[1], v[2], 0.0)
    t = q_mul(q_mul(q, qv), q_conj(q))
    return (t[0], t[1], t[2])


# ── GLB I/O ──────────────────────────────────────────────────────────────────

def load_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"glTF":
        raise ValueError(f"not a GLB: {path}")
    json_len, _ = struct.unpack("<II", data[12:20])
    gltf = json.loads(data[20 : 20 + json_len])
    off = 20 + json_len
    bin_len, bin_type = struct.unpack("<II", data[off : off + 8])
    bin_chunk = data[off + 8 : off + 8 + bin_len] if bin_type == 0x004E4942 else b""
    return gltf, bin_chunk


def pad4(buf):
    while len(buf) % 4:
        buf += b"\x00"
    return buf


def write_glb(path, gltf, bin_chunk):
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "
    bin_chunk = pad4(bin_chunk)
    total = 12 + 8 + len(json_bytes) + (8 + len(bin_chunk) if bin_chunk else 0)
    out = struct.pack("<III", 0x46546C67, 2, total)
    out += struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes
    if bin_chunk:
        out += struct.pack("<II", len(bin_chunk), 0x004E4942) + bin_chunk
    with open(path, "wb") as f:
        f.write(out)


def read_accessor(gltf, bin_chunk, idx):
    acc = gltf["accessors"][idx]
    assert acc["componentType"] == 5126, f"expected float32 accessor: {acc['type']}"
    n = acc["count"]
    ncomp = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[acc["type"]]
    bv = gltf["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    fmt = "<" + "f" * (n * ncomp)
    vals = struct.unpack_from(fmt, bin_chunk, base)
    if ncomp == 1:
        return list(vals)
    return [list(vals[i : i + ncomp]) for i in range(0, len(vals), ncomp)]


# ── rest-pose capture from inverseBindMatrices ───────────────────────────────
# three.js's Skeleton.pose() (what bake-retarget-vrm.mjs rests on) rebuilds
# each bone's local TRS from the skin's inverseBindMatrices — and in
# Humar_body.glb that bind pose DIFFERS from the nodes' JSON TRS (the TRS
# hold a saved mesh pose; the IBM hold the canonical PSO bind: legs -94°Z,
# arms -83°Z, hip -91°Z per retarget-notes.md). Capturing the raw node TRS
# here was the root cause of the chibi's crossed legs / backward bow:
# every conjugation factor F ran on the wrong frames.

def mat4_invert(m):
    # column-major 16-tuple -> inverse (column-major)
    a00, a01, a02, a03 = m[0], m[4], m[8], m[12]
    a10, a11, a12, a13 = m[1], m[5], m[9], m[13]
    a20, a21, a22, a23 = m[2], m[6], m[10], m[14]
    a30, a31, a32, a33 = m[3], m[7], m[11], m[15]
    b00 = a00 * a11 - a01 * a10
    b01 = a00 * a12 - a02 * a10
    b02 = a00 * a13 - a03 * a10
    b03 = a01 * a12 - a02 * a11
    b04 = a01 * a13 - a03 * a11
    b05 = a02 * a13 - a03 * a12
    b06 = a20 * a31 - a21 * a30
    b07 = a20 * a32 - a22 * a30
    b08 = a20 * a33 - a23 * a30
    b09 = a21 * a32 - a22 * a31
    b10 = a21 * a33 - a23 * a31
    b11 = a22 * a33 - a23 * a32
    det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06
    if abs(det) < 1e-12:
        raise ValueError("singular inverseBindMatrix")
    det = 1.0 / det
    out = [0.0] * 16
    out[0] = (a11 * b11 - a12 * b10 + a13 * b09) * det
    out[1] = (a12 * b08 - a10 * b11 - a13 * b07) * det
    out[2] = (a10 * b10 - a11 * b08 + a13 * b06) * det
    out[3] = (a11 * b07 - a10 * b09 - a12 * b06) * det
    out[4] = (a02 * b10 - a01 * b11 - a03 * b09) * det
    out[5] = (a00 * b11 - a02 * b08 + a03 * b07) * det
    out[6] = (a01 * b08 - a00 * b10 - a03 * b06) * det
    out[7] = (a00 * b09 - a01 * b07 + a02 * b06) * det
    out[8] = (a31 * b05 - a32 * b04 + a33 * b03) * det
    out[9] = (a32 * b02 - a30 * b05 - a33 * b01) * det
    out[10] = (a30 * b04 - a31 * b02 + a33 * b00) * det
    out[11] = (a31 * b01 - a30 * b03 - a32 * b00) * det
    out[12] = (a22 * b04 - a21 * b05 - a23 * b03) * det
    out[13] = (a20 * b05 - a22 * b02 + a23 * b01) * det
    out[14] = (a21 * b02 - a20 * b04 - a23 * b00) * det
    out[15] = (a20 * b03 - a21 * b01 + a22 * b00) * det
    return out


def mat4_mul(a, b):
    out = [0.0] * 16
    for c in range(4):
        for r in range(4):
            out[c * 4 + r] = (
                a[r] * b[c * 4] + a[4 + r] * b[c * 4 + 1]
                + a[8 + r] * b[c * 4 + 2] + a[12 + r] * b[c * 4 + 3]
            )
    return out


def mat4_quat(m):
    # upper-3x3 of a column-major mat4 -> normalized quaternion (x,y,z,w)
    m00, m01, m02 = m[0], m[4], m[8]
    m10, m11, m12 = m[1], m[5], m[9]
    m20, m21, m22 = m[2], m[6], m[10]
    tr = m00 + m11 + m22
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        q = ((m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s)
    elif m00 > m11 and m00 > m22:
        s = math.sqrt(1.0 + m00 - m11 - m22) * 2
        q = (0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s)
    elif m11 > m22:
        s = math.sqrt(1.0 + m11 - m00 - m22) * 2
        q = ((m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s)
    else:
        s = math.sqrt(1.0 + m22 - m00 - m11) * 2
        q = ((m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s)
    return q_norm(q)


class Rig:
    """Rest pose from the skin's inverseBindMatrices (three.js pose()
    semantics), with the bone->bone parent chain the conjugation walks."""

    def __init__(self, gltf, bin_chunk):
        skin = gltf["skins"][0]
        joints = skin["joints"]
        nodes = gltf["nodes"]
        parent = {}
        for i, n in enumerate(nodes):
            for c in n.get("children", []):
                parent[c] = i

        worlds = {}
        if "inverseBindMatrices" in skin:
            acc = gltf["accessors"][skin["inverseBindMatrices"]]
            bv = gltf["bufferViews"][acc["bufferView"]]
            base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            raw = struct.unpack_from("<" + "f" * (16 * acc["count"]), bin_chunk, base)
            for k, joint in enumerate(joints):
                worlds[joint] = mat4_invert(raw[k * 16 : k * 16 + 16])
        else:
            # No IBMs: fall back to composing node TRS down the joint chain.
            def compose(i, up):
                n = nodes[i]
                q = q_norm(tuple(n.get("rotation", [0.0, 0.0, 0.0, 1.0])))
                t = tuple(n.get("translation", [0.0, 0.0, 0.0]))
                # build local matrix from q/t
                w = [0.0] * 16
                x, y, z, wq = q
                xx, yy, zz = x * x, y * y, z * z
                xy, xz, yz = x * y, x * z, y * z
                wx, wy, wz = wq * x, wq * y, wq * z
                rot = [
                    1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy), 0.0,
                    2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx), 0.0,
                    2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy), 0.0,
                    t[0], t[1], t[2], 1.0,
                ]
                w = mat4_mul(up, rot)
                worlds[i] = w
                for c in n.get("children", []):
                    if c in set(joints):
                        compose(c, w)
            jset = set(joints)
            for i, n in enumerate(nodes):
                if i in jset and (parent.get(i) is None or parent[i] not in jset):
                    compose(i, [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0])

        self.local_q = {}
        self.local_t = {}
        self.parent = {}
        jset = set(joints)
        for idx, joint in enumerate(joints):
            name = nodes[joint].get("name", "")
            world = worlds[joint]
            p = parent.get(joint)
            if p is not None and p in jset:
                pw_inv = mat4_invert(worlds[p])
                local = mat4_mul(pw_inv, world)
                self.parent[name] = nodes[p].get("name", "")
            else:
                local = world
                self.parent[name] = None
            self.local_q[name] = mat4_quat(local)
            self.local_t[name] = (local[12], local[13], local[14])

    def world_q(self, bone, local_override=None):
        chain = []
        cur = bone
        while cur:
            chain.append(cur)
            cur = self.parent.get(cur)
        q = (0.0, 0.0, 0.0, 1.0)
        for name in reversed(chain):
            local = local_override[name] if local_override and name in local_override else self.local_q[name]
            q = q_mul(q, local)
        return q


# ── retarget core (conjugation, mirrors bake-retarget-vrm.mjs) ──────────────

def build_retargeted_clip(src_clip, gltf, bin_chunk, pso_gltf, pso_bin, pso_rig, tgt_rig, pos_scale):
    adjusted_local = dict(tgt_rig.local_q)

    # Arm rest-pose correction: align each target upper-arm/forearm world
    # rest orientation with PSO's before conjugating.
    for pso_bone in ARM_CORRECTION_PSO_BONES:
        tgt_bone = BONE_MAPPINGS_VRM[pso_bone]
        if tgt_bone not in adjusted_local:
            continue
        tgt_parent = tgt_rig.parent.get(tgt_bone)
        parent_world = tgt_rig.world_q(tgt_parent, adjusted_local) if tgt_parent else (0.0, 0.0, 0.0, 1.0)
        adjusted_local[tgt_bone] = q_mul(q_conj(parent_world), pso_rig.world_q(pso_bone))

    # Tuned offsets (item-shop VRM baseline) layer on top — XYZ Euler degrees,
    # converted exactly like three.js setFromEuler('XYZ').
    deg2rad = math.pi / 180.0
    for bone_name, off in BAKED_OFFSETS.items():
        base = adjusted_local.get(bone_name)
        if not base or (off["x"], off["y"], off["z"]) == (0, 0, 0):
            continue
        sx, cx = math.sin(off["x"] * deg2rad / 2), math.cos(off["x"] * deg2rad / 2)
        sy, cy = math.sin(off["y"] * deg2rad / 2), math.cos(off["y"] * deg2rad / 2)
        sz, cz = math.sin(off["z"] * deg2rad / 2), math.cos(off["z"] * deg2rad / 2)
        offset_q = q_norm((
            sx * cy * cz + cx * sy * sz,
            cx * sy * cz - sx * cy * sz,
            cx * cy * sz + sx * sy * cz,
            cx * cy * cz - sx * sy * sz,
        ))
        adjusted_local[bone_name] = q_norm(q_mul(base, offset_q))

    def tgt_world(bone):
        return tgt_rig.world_q(bone, adjusted_local)

    name_by_idx = {i: n.get("name", "") for i, n in enumerate(pso_gltf["nodes"])}
    tracks = []

    for ch in src_clip["channels"]:
        bone = name_by_idx[ch["target"]["node"]]
        mapped = BONE_MAPPINGS_VRM.get(bone)
        if not mapped or mapped not in tgt_rig.local_q:
            continue
        path_kind = ch["target"]["path"]
        sampler = src_clip["samplers"][ch["sampler"]]
        times = read_accessor(pso_gltf, pso_bin, sampler["input"])
        values = read_accessor(pso_gltf, pso_bin, sampler["output"])

        if path_kind == "rotation":
            # bone_000 (root) included: the VRM rig's Root bone carries the
            # clip's facing correction. Dropping it leaks the bind yaw.
            pso_local_rest = pso_rig.local_q[bone]
            tgt_local_rest = adjusted_local[mapped]
            f = q_mul(q_conj(tgt_world(mapped)), pso_rig.world_q(bone))
            prefix = q_mul(q_mul(tgt_local_rest, f), q_conj(pso_local_rest))
            suffix = q_conj(f)
            out = [q_norm(q_mul(q_mul(prefix, v), suffix)) for v in values]
            tracks.append((mapped, "rotation", times, out))

        elif path_kind == "translation" and bone == "bone_000":
            # Absolute formula (mjs semantics): the clip's root positions are
            # authored around the node-local origin — no bind-rest delta.
            f = q_mul(q_conj(tgt_world(mapped)), pso_rig.world_q("bone_000"))
            pos_rotation = q_conj(f)
            out = []
            for v in values:
                r = q_rotate(pos_rotation, (v[0] * pos_scale, v[1] * pos_scale, v[2] * pos_scale))
                out.append([r[0], r[1], r[2]])
            tracks.append((mapped, "translation", times, out))

    return tracks


# ── GLB assembly: strip textures, keep skeleton+mesh, write new anims ───────

def bake_library():
    gltf, bin_chunk = load_glb(TARGET_PATH)
    pso_gltf, pso_bin = load_glb(PSO_PATH)
    pso_rig = Rig(pso_gltf, pso_bin)
    # NOTE: Humar_body.glb ships three nodes named bone_000 (identity
    # dummies + the real 45°-yaw root). The world-pose transfer below FKs the
    # clip through skin 0's actual joint graph, so the duplicate names no
    # longer matter.
    tgt_rig = Rig(gltf, bin_chunk)
    missing = [b for b in BONE_MAPPINGS_VRM.values() if b not in tgt_rig.local_q]
    if missing:
        raise SystemExit(f"target rig missing mapped bones: {missing}")

    # Height normalisation from ALL skinned meshes (VRM splits face/body).
    gmin = [9e9] * 3
    gmax = [-9e9] * 3
    for mesh in gltf.get("meshes", []):
        for prim in mesh["primitives"]:
            acc = gltf["accessors"][prim["attributes"]["POSITION"]]
            for i in range(3):
                gmin[i] = min(gmin[i], acc["min"][i])
                gmax[i] = max(gmax[i], acc["max"][i])
    pso_acc = pso_gltf["accessors"][pso_gltf["meshes"][0]["primitives"][0]["attributes"]["POSITION"]]
    pso_h = pso_acc["max"][1] - pso_acc["min"][1]
    tgt_h = gmax[1] - gmin[1]
    pos_scale = tgt_h / pso_h

    node_idx = {n.get("name", ""): i for i, n in enumerate(gltf["nodes"])}
    clips = pso_gltf.get("animations", [])
    print(f"target height {tgt_h:.3f}m, PSO {pso_h:.3f}m, posScale {pos_scale:.4f}")
    baked = []
    for index, base_name in ANIMS:
        clip_name = f"plymotiondata_{index:03d}"
        src_clip = next((a for a in clips if a.get("name") == clip_name), None)
        if not src_clip:
            print(f"  !! {clip_name} not found")
            continue
        tracks = build_retargeted_clip(src_clip, gltf, bin_chunk, pso_gltf, pso_bin, pso_rig, tgt_rig, pos_scale)
        out_name = base_name + SUFFIX
        baked.append((out_name, tracks))
        print(f"  {clip_name} -> {out_name} ({len(tracks)} tracks)")

    keep_accessors = set()
    for mesh in gltf.get("meshes", []):
        for prim in mesh["primitives"]:
            keep_accessors.update(prim["attributes"].values())
            if "indices" in prim:
                keep_accessors.add(prim["indices"])
            # Morph targets (VRoid blendshapes) carry their own accessor
            # references — three.js computeBounds reads them and hard-fails
            # on dangling indices.
            for target in prim.get("targets", []):
                keep_accessors.update(target.values())
            prim.pop("material", None)
    for skin in gltf.get("skins", []):
        if "inverseBindMatrices" in skin:
            keep_accessors.add(skin["inverseBindMatrices"])

    new_bin = bytearray()
    new_views = []
    new_accessors = []
    acc_remap = {}

    NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
    CSIZE = {5126: 4, 5123: 2, 5125: 4, 5121: 1}

    def append_bytes(data):
        view_idx = len(new_views)
        new_views.append({"buffer": 0, "byteOffset": len(new_bin), "byteLength": len(data)})
        new_bin.extend(pad4(data))
        return view_idx

    def add_accessor(data, acc_type, count):
        new_accessors.append(
            {"bufferView": append_bytes(data), "componentType": 5126, "count": count, "type": acc_type}
        )
        return len(new_accessors) - 1

    for old_idx in sorted(keep_accessors):
        acc = dict(gltf["accessors"][old_idx])
        bv = gltf["bufferViews"][acc["bufferView"]]
        start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        length = acc["count"] * NCOMP[acc["type"]] * CSIZE[acc["componentType"]]
        data = bytes(bin_chunk[start : start + length])
        acc["bufferView"] = append_bytes(data)
        acc.pop("byteOffset", None)
        acc_remap[old_idx] = len(new_accessors)
        new_accessors.append(acc)

    for mesh in gltf.get("meshes", []):
        for prim in mesh["primitives"]:
            prim["attributes"] = {k: acc_remap[v] for k, v in prim["attributes"].items()}
            if "indices" in prim:
                prim["indices"] = acc_remap[prim["indices"]]
            if "targets" in prim:
                prim["targets"] = [{k: acc_remap[v] for k, v in t.items()} for t in prim["targets"]]
    for skin in gltf.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = acc_remap[skin["inverseBindMatrices"]]

    animations = []
    for clip_name, tracks in baked:
        samplers = []
        channels = []
        for tgt_bone, path, times, values in tracks:
            n = len(times)
            in_idx = add_accessor(struct.pack(f"<{n}f", *times), "SCALAR", n)
            if path == "rotation":
                out_idx = add_accessor(struct.pack(f"<{4 * n}f", *[c for v in values for c in v]), "VEC4", n)
            else:
                out_idx = add_accessor(struct.pack(f"<{3 * n}f", *[c for v in values for c in v]), "VEC3", n)
            samplers.append({"input": in_idx, "output": out_idx, "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": node_idx[tgt_bone], "path": path}})
        animations.append({"name": clip_name, "channels": channels, "samplers": samplers})

    gltf["animations"] = animations
    for key in ("images", "textures", "materials"):
        gltf.pop(key, None)
    gltf.pop("extensions", None)  # drop VRM ext blocks referencing stripped materials
    gltf.pop("extensionsRequired", None)
    gltf.pop("extensionsUsed", None)
    gltf["bufferViews"] = new_views
    gltf["accessors"] = new_accessors
    gltf["buffers"][0]["byteLength"] = len(new_bin)
    write_glb(OUT_PATH, gltf, bytes(new_bin))
    print(f"wrote {os.path.relpath(OUT_PATH, REPO_ROOT)} ({os.path.getsize(OUT_PATH) / 1024:.1f} KB)")


if __name__ == "__main__":
    import sys

    key = sys.argv[1] if len(sys.argv) > 1 else "example"
    if key not in MODELS:
        raise SystemExit(f"unknown model {key!r}; pick one of {sorted(MODELS)}")
    cfg = MODELS[key]
    TARGET_PATH = cfg["target"]
    OUT_PATH = cfg["out"]
    BAKED_OFFSETS = cfg["offsets"]
    SUFFIX = cfg["suffix"]
    print(f"baking model: {key}")
    bake_library()

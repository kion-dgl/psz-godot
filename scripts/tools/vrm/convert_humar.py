#!/usr/bin/env python3
"""Native PSZ humanoid VRM conversion. See docs/character-vrm-policy.md.
Use convert_players.py for the complete playable roster; no asset upload.

Preserves a legacy-bind compatibility profile in glTF extras for native PSZ
animations. The portable VRM itself contains a T-pose and an embedded texture.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import struct

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "assets/player/pc_000/pc_000_000.glb"
TEXTURE = ROOT / "assets/player/pc_000/textures/pc_000_000.png"
OUTPUT = ROOT / "assets/player/vrm_poc/humar.vrm"
BONES = {
    "hips": "010_Hip", "spine": "020_Spine", "head": "090_Head",
    "leftUpperArm": "030_LArm01", "leftLowerArm": "040_LArm02",
    "rightUpperArm": "060_RArm01", "rightLowerArm": "070_RArm02",
    "leftUpperLeg": "100_LLeg01", "leftLowerLeg": "110_LLeg02",
    "rightUpperLeg": "120_RLeg01", "rightLowerLeg": "130_RLeg02",
}
# Local +X is the original limb axis. HUmar's distal vertex clusters begin
# around x=.277 at the wrist and x=.39 at the boot/ankle (metres).
ENDPOINTS = {
    "leftHand": ("040_LArm02", 0.28, 0.27),
    "rightHand": ("070_RArm02", 0.28, 0.27),
    "leftFoot": ("110_LLeg02", 0.40, 0.38),
    "rightFoot": ("130_RLeg02", 0.40, 0.38),
}
DTYPES = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    data = path.read_bytes()
    magic, version, size = struct.unpack_from("<4sII", data)
    assert (magic, version, size) == (b"glTF", 2, len(data))
    size, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A
    doc = json.loads(data[20:20 + size])
    count, kind = struct.unpack_from("<II", data, 20 + size)
    assert kind == 0x004E4942
    return doc, bytearray(data[28 + size:28 + size + count])


def accessor(doc, blob, index):
    a = doc["accessors"][index]
    view = doc["bufferViews"][a["bufferView"]]
    dtype = np.dtype(DTYPES[a["componentType"]])
    width = WIDTHS[a["type"]]
    offset = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = view.get("byteStride", dtype.itemsize * width)
    return np.ndarray((a["count"], width), dtype=dtype, buffer=blob,
                      offset=offset, strides=(stride, dtype.itemsize)).copy()


def append_view(doc, blob, data):
    blob.extend(b"\0" * (-len(blob) % 4))
    index = len(doc["bufferViews"])
    doc["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)})
    blob.extend(data)
    return index


def append_accessor(doc, blob, array, kind, component=5126, bounds=False):
    array = np.asarray(array, dtype=DTYPES[component])
    view = append_view(doc, blob, array.tobytes())
    entry = {"bufferView": view, "componentType": component, "count": len(array), "type": kind}
    if bounds:
        entry.update(min=array.min(axis=0).tolist(), max=array.max(axis=0).tolist())
    index = len(doc["accessors"])
    doc["accessors"].append(entry)
    return index


def matrices(values):
    return values.reshape((-1, 4, 4)).transpose(0, 2, 1)


def flat_matrices(values):
    return np.asarray(values).transpose(0, 2, 1).reshape((-1, 16))


def translation(x=0, y=0, z=0):
    result = np.eye(4)
    result[:3, 3] = [x, y, z]
    return result


def align_axis(rotation, target):
    """Rotate a bone's +X axis to target, keeping its existing axial roll."""
    a, b = rotation[:, 0], np.asarray(target, dtype=float)
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
    cross, dot = np.cross(a, b), np.dot(a, b)
    if dot < -0.999999:
        axis = rotation[:, 1]
        delta = 2 * np.outer(axis, axis) - np.eye(3)
    else:
        x, y, z = cross
        skew = np.array([[0, -z, y], [z, 0, -x], [-y, x, 0]])
        delta = np.eye(3) + skew + skew @ skew / max(1 + dot, 1e-10)
    return delta @ rotation


def skin_vertices(positions, joints, weights, transforms):
    vertices = np.column_stack([positions, np.ones(len(positions))])
    result = np.zeros((len(positions), 4))
    for slot in range(4):
        result += np.einsum("nij,nj->ni", transforms[joints[:, slot]], vertices) * weights[:, slot, None]
    return result[:, :3]


def write_glb(path, doc, blob):
    doc["buffers"] = [{"byteLength": len(blob)}]
    encoded = json.dumps(doc, separators=(",", ":"), ensure_ascii=True).encode()
    encoded += b" " * (-len(encoded) % 4)
    blob += b"\0" * (-len(blob) % 4)
    result = struct.pack("<4sII", b"glTF", 2, 28 + len(encoded) + len(blob))
    result += struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
    result += struct.pack("<II", len(blob), 0x004E4942) + blob
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(result)


def convert(output=OUTPUT, source=SOURCE, texture=TEXTURE):
    model = source.parent.name
    doc, blob = read_glb(source)
    assert len(doc["skins"]) == 1 and len(doc["meshes"]) == 1, "Expected one native humanoid mesh/skin"
    skin = doc["skins"][0]
    assert len(skin["joints"]) == 12, "Expected the original 12-bone PSZ rig"
    primitive = doc["meshes"][0]["primitives"][0]
    attrs = primitive["attributes"]
    assert all(p["attributes"] == attrs for p in doc["meshes"][0]["primitives"]), "Expected shared vertex stream"
    original_position = attrs["POSITION"]
    positions = accessor(doc, blob, original_position)
    joints = accessor(doc, blob, attrs["JOINTS_0"])
    weights = accessor(doc, blob, attrs["WEIGHTS_0"]).astype(float) / 255.0
    # Reposing a blended vertex needs a different solve. This PoC deliberately
    # requires the source's rigid weights rather than silently approximating it.
    assert np.all(np.count_nonzero(weights, axis=1) == 1)
    assert np.allclose(weights.sum(axis=1), 1)
    old_bind = list(np.linalg.inv(matrices(accessor(doc, blob, skin["inverseBindMatrices"]))))
    names = {n.get("name"): i for i, n in enumerate(doc["nodes"])}
    source_nodes = copy.deepcopy(doc["nodes"])
    counts = {}
    for role, (parent_name, offset, cutoff) in ENDPOINTS.items():
        parent = names[parent_name]
        parent_joint = skin["joints"].index(parent)
        child = len(doc["nodes"])
        name = "PSZ_" + role
        doc["nodes"].append({"name": name, "translation": [offset, 0, 0]})
        source_nodes.append({"name": name, "translation": [offset, 0, 0]})
        doc["nodes"][parent].setdefault("children", []).append(child)
        source_nodes[parent].setdefault("children", []).append(child)
        inverse = np.linalg.inv(old_bind[parent_joint])
        local = np.einsum("ij,nj->ni", inverse, np.column_stack([positions, np.ones(len(positions))]))
        selected = (joints == parent_joint) & (weights > 0) & (local[:, :1] >= cutoff)
        joints[selected] = len(skin["joints"])
        counts[role] = int(np.count_nonzero(selected))
        assert counts[role] > 0
        skin["joints"].append(child)
        old_bind.append(old_bind[parent_joint] @ translation(offset))
        names[name] = child
    old_bind = np.asarray(old_bind)
    attrs["JOINTS_0"] = append_accessor(doc, blob, joints, "VEC4", 5121)
    legacy_ibm = append_accessor(doc, blob, flat_matrices(np.linalg.inv(old_bind)), "MAT4")
    parents = {child: i for i, node in enumerate(doc["nodes"]) for child in node.get("children", [])}
    joint_for_node = {node: i for i, node in enumerate(skin["joints"])}
    # HUmar already faces VRM 1.0's +Z direction. Preserve its handedness.
    facing = np.eye(4)
    canonical = {}
    pending = set(skin["joints"])
    while pending:
        for node in sorted(pending):
            parent = parents.get(node)
            if parent in pending:
                continue
            old = old_bind[joint_for_node[node]]
            mat = facing @ old
            name = doc["nodes"][node]["name"]
            if parent in canonical:
                relative = np.linalg.inv(old_bind[joint_for_node[parent]]) @ old
                mat[:3, 3] = (canonical[parent] @ np.append(relative[:3, 3], 1))[:3]
            axis = None
            if "Arm" in name or "Hand" in name:
                axis = [1 if ("LArm" in name or "leftHand" in name) else -1, 0, 0]
            elif "Leg" in name or "Foot" in name:
                axis = [0, -1, 0]
            elif name in ("020_Spine", "090_Head"):
                axis = [0, 1, 0]
            if axis is not None:
                mat[:3, :3] = align_axis(mat[:3, :3], axis)
            canonical[node] = mat
            pending.remove(node)
    new_bind = np.asarray([canonical[n] for n in skin["joints"]])
    posed = skin_vertices(positions, joints, weights, new_bind @ np.linalg.inv(old_bind))
    ground = float(posed[:, 1].min())
    new_bind[:, 1, 3] -= ground
    posed[:, 1] -= ground
    canonical = dict(zip(skin["joints"], new_bind))
    for node, world in canonical.items():
        parent_world = canonical.get(parents.get(node), np.eye(4))
        local = np.linalg.inv(parent_world) @ world
        item = doc["nodes"][node]
        for key in ("translation", "rotation", "scale"):
            item.pop(key, None)
        item["matrix"] = local.T.flatten().tolist()
    attrs["POSITION"] = append_accessor(doc, blob, posed, "VEC3", bounds=True)
    skin["inverseBindMatrices"] = append_accessor(doc, blob, flat_matrices(np.linalg.inv(new_bind)), "MAT4")
    # The legacy profile swaps only rest data/accessors back. No original GLB
    # is needed at runtime; the VRM remains a self-contained compatibility asset.
    doc.setdefault("extras", {})["pszLegacyRig"] = {
        "version": 1, "model": model, "nodes": source_nodes,
        "positionAccessor": original_position, "inverseBindMatrices": legacy_ibm,
        "sourceSha256": hashlib.sha256(source.read_bytes()).hexdigest(),
    }
    image = append_view(doc, blob, texture.read_bytes())
    doc["images"] = [{"bufferView": image, "mimeType": "image/png", "name": model + " default appearance"}]
    doc["samplers"] = [{"magFilter": 9728, "minFilter": 9728, "wrapS": 10497, "wrapT": 10497}]
    doc["textures"] = [{"sampler": 0, "source": 0}]
    for material in doc["materials"]:
        material["pbrMetallicRoughness"] = {"baseColorTexture": {"index": 0}, "metallicFactor": 0, "roughnessFactor": 1}
        material["extensions"] = {"KHR_materials_unlit": {}}
    for part in doc["meshes"][0]["primitives"]:
        part["attributes"] = copy.deepcopy(attrs)
        part.pop("extensions", None)
    doc["extensionsUsed"] = ["KHR_materials_unlit", "VRMC_vrm"]
    human = {role: {"node": names[name]} for role, name in BONES.items()}
    human.update({role: {"node": names["PSZ_" + role]} for role in ENDPOINTS})
    doc["extensions"] = {"VRMC_vrm": {"specVersion": "1.0", "humanoid": {"humanBones": human}, "meta": {
        "name": model + " — PSZ humanoid", "version": "0.1",
        "authors": ["SEGA (original character and model)"],
        "copyrightInformation": "Original Phantasy Star Zero assets © SEGA. Conversion grants no additional rights.",
        "licenseUrl": "https://vrm.dev/licenses/1.0/", "avatarPermission": "onlySeparatelyLicensedPerson",
        "allowRedistribution": False, "modification": "prohibited",
        "thirdPartyLicenses": "Local conversion experiment. Original game asset rights remain with SEGA; no relicensing is asserted."}}}
    doc.pop("animations", None)
    write_glb(output, doc, blob)
    report = {"output": str(output), "weightedEndpointVertices": counts,
              "humanoidBones": len(human), "vertices": len(positions), "groundOffset": ground,
              "bytes": output.stat().st_size, "sha256": hashlib.sha256(output.read_bytes()).hexdigest()}
    print(json.dumps(report, indent=2))
    return doc, blob, report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    convert(parser.parse_args().output)

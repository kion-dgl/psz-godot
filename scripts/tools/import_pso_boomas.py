#!/usr/bin/env python3
"""Import the user-supplied PSO Booma ZIPs locally, baking units into skinned GLBs.

No Blender, storage credentials, upload or runtime model_scale required.
Scales positions, node/matrix translations, animation translations (including
cubic tangents), and inverse-bind translations together; normals/rotations and
animation times are unchanged. Embedded textures stay byte-identical.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[2]
MODELS = {'booma': 'pso_booma', 'gobooma': 'pso_gobooma', 'gigabooma': 'pso_gigobooma'}
CLIPS = {'appear': 'spawn', 'atackl': 'atk_l', 'atackr': 'atk_r', 'damage': 'dam',
         'dead': 'ded', 'deadb': 'ded_b', 'leader': 'leader', 'mihari': 'mihari',
         'run': 'run', 'stund': 'stun', 'wakeup': 'wakeup', 'walk': 'wlk'}


def bake(raw, scale):
    magic, version, length = struct.unpack_from('<III', raw)
    if (magic, version, length) != (0x46546C67, 2, len(raw)):
        raise ValueError('Expected a GLB 2.0 file')
    size, kind = struct.unpack_from('<II', raw, 12)
    if kind != 0x4E4F534A:
        raise ValueError('Expected a JSON chunk')
    doc = json.loads(raw[20:20 + size])
    offset = 20 + size
    binary_size, kind = struct.unpack_from('<II', raw, offset)
    if kind != 0x004E4942 or len(doc['buffers']) != 1:
        raise ValueError('Expected one embedded binary buffer')
    binary = bytearray(raw[offset + 8:offset + 8 + binary_size])
    scaled = set()

    def scale_accessor(index, matrix=False):
        if index in scaled:
            return
        scaled.add(index)
        accessor = doc['accessors'][index]
        expected = 'MAT4' if matrix else 'VEC3'
        if accessor['componentType'] != 5126 or accessor['type'] != expected or 'sparse' in accessor:
            raise ValueError('Unsupported position/bind accessor')
        view = doc['bufferViews'][accessor['bufferView']]
        count = 16 if matrix else 3
        start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
        stride = view.get('byteStride', count * 4)
        components = (12, 13, 14) if matrix else range(3)
        for row in range(accessor['count']):
            for component in components:
                address = start + row * stride + component * 4
                value = struct.unpack_from('<f', binary, address)[0]
                struct.pack_into('<f', binary, address, value * scale)
        for bound in ('min', 'max'):
            if bound in accessor:
                for component in components:
                    accessor[bound][component] *= scale

    for mesh in doc.get('meshes', []):
        for primitive in mesh['primitives']:
            scale_accessor(primitive['attributes']['POSITION'])
            for target in primitive.get('targets', []):
                if 'POSITION' in target:
                    scale_accessor(target['POSITION'])
    for node in doc['nodes']:
        if 'translation' in node:
            node['translation'] = [v * scale for v in node['translation']]
        if 'matrix' in node:
            for i in (12, 13, 14):
                node['matrix'][i] *= scale
    for skin in doc.get('skins', []):
        if 'inverseBindMatrices' in skin:
            scale_accessor(skin['inverseBindMatrices'], matrix=True)
    mapping = {}
    for animation in doc.get('animations', []):
        original = animation['name']
        token = original.split('_', 1)[0]
        animation['name'] = CLIPS[token]
        animation.setdefault('extras', {})['source_animation'] = original
        mapping[original] = animation['name']
        for channel in animation['channels']:
            if channel['target']['path'] == 'translation':
                scale_accessor(animation['samplers'][channel['sampler']]['output'])
    doc.setdefault('asset', {}).setdefault('extras', {})['baked_unit_scale'] = scale
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    binary += b'\0' * (-len(binary) % 4)
    result = (struct.pack('<III', magic, version, 28 + len(encoded) + len(binary))
              + struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
              + struct.pack('<II', len(binary), 0x004E4942) + binary)
    return result, mapping


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archives', type=Path, required=True)
    parser.add_argument('--scale', type=float, default=0.089)
    args = parser.parse_args()
    if not 0 < args.scale < 1:
        parser.error('--scale must be between 0 and 1')
    report = {'scale': args.scale, 'storage': 'local only; not uploaded', 'models': {}}
    for archive_name, model_id in MODELS.items():
        source = args.archives / ('ene_' + archive_name + '.zip')
        with zipfile.ZipFile(source) as archive:
            glbs = [n for n in archive.namelist() if n.lower().endswith('.glb')]
            if len(glbs) != 1:
                raise ValueError(f'{source}: expected exactly one GLB')
            raw = archive.read(glbs[0])
        result, clips = bake(raw, args.scale)
        output = ROOT / 'assets/enemies' / model_id / (model_id + '.glb')
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(result)
        report['models'][model_id] = {'archive': source.name, 'archive_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                                      'source_glb_sha256': hashlib.sha256(raw).hexdigest(),
                                      'output': str(output.relative_to(ROOT)), 'output_sha256': hashlib.sha256(result).hexdigest(),
                                      'animation_names': clips}
        print(output)
    (ROOT / 'data/re_reference/pso_booma_import.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()

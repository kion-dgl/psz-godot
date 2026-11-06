#!/usr/bin/env python3
"""Verify native skinning equivalence, material preservation and texture coverage."""
import numpy as np
from convert_humar import ROOT, accessor, matrices, read_glb, skin_vertices


def check(source, converted):
    original, old_blob = read_glb(source)
    doc, blob = read_glb(converted)
    old_skin, skin = original['skins'][0], doc['skins'][0]
    old_attrs = original['meshes'][0]['primitives'][0]['attributes']
    attrs = doc['meshes'][0]['primitives'][0]['attributes']
    profile = doc['extras']['pszLegacyRig']
    vertices = accessor(original, old_blob, old_attrs['POSITION'])
    restored = accessor(doc, blob, profile['positionAccessor'])
    np.testing.assert_array_equal(vertices, restored)
    old_joints = accessor(original, old_blob, old_attrs['JOINTS_0'])
    joints = accessor(doc, blob, attrs['JOINTS_0'])
    weights = accessor(original, old_blob, old_attrs['WEIGHTS_0']) / 255.0
    np.testing.assert_array_equal(weights, accessor(doc, blob, attrs['WEIGHTS_0']) / 255.0)
    inverse = matrices(accessor(doc, blob, profile['inverseBindMatrices']))
    old_inverse = matrices(accessor(original, old_blob, old_skin['inverseBindMatrices']))
    np.testing.assert_allclose(inverse[:len(old_inverse)], old_inverse, atol=1e-6)
    # Independent arbitrary bone poses, with the new endpoints following their
    # native parent. This catches incorrect bind matrices or reassigned weights
    # even if all animated original bone poses still match.
    rng = np.random.default_rng(773)
    for _ in range(8):
        poses = np.linalg.inv(old_inverse).copy()
        poses[:, :3, 3] += rng.uniform(-0.5, 0.5, (len(poses), 3))
        for pose in poses:
            q, _ = np.linalg.qr(rng.normal(size=(3, 3)))
            pose[:3, :3] = q
        expanded = list(poses)
        nodes = profile['nodes']
        for index in range(len(poses), len(skin['joints'])):
            node = skin['joints'][index]
            parent = next(i for i, item in enumerate(nodes) if node in item.get('children', []))
            local = np.eye(4)
            local[:3, 3] = nodes[node]['translation']
            expanded.append(poses[skin['joints'].index(parent)] @ local)
        expected = skin_vertices(vertices, old_joints, weights, poses @ old_inverse)
        actual = skin_vertices(restored, joints, weights, np.asarray(expanded) @ inverse)
        np.testing.assert_allclose(actual, expected, atol=2e-6)
    assert len(original['meshes'][0]['primitives']) == len(doc['meshes'][0]['primitives'])
    for old, new in zip(original['materials'], doc['materials']):
        assert old.get('doubleSided', False) == new.get('doubleSided', False)
    for hair in range(3):
        for skin_tone in range(3):
            for body in range(5):
                name = f'{source.parent.name}_{hair}{skin_tone}{body}.png'
                assert (source.parent / 'textures' / name).is_file(), name


if __name__ == '__main__':
    paths = sorted(ROOT.glob('assets/player/pc_*/*.vrm'))
    assert len(paths) == 56, f'Expected complete playable roster, found {len(paths)}'
    for path in paths:
        check(path.with_name(path.stem + '_000.glb'), path)
    print('PASS: 56 native skinning comparisons (8 poses each), surface materials, 2520 appearance textures')
